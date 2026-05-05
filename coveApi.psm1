#Requires -Version 7.4
# coveApi.psm1 - v1.1.0
# Cove Data Protection API: authentication, device enumeration, per-device queries, parallel execution.
#
# Quick start:
#   Initialize-CoveApi                                        # optional - defaults to production URLs
#   Connect-CoveApi -Username $u -Password $p
#   $devices = Get-CoveDevices -Columns @('AU', 'B4', ...)
#   $results = Invoke-CoveParallel -Items $devices -ThrottleLimit 20 -ScriptBlock {
#       param($device)
#       Get-CoveDeviceErrors -AccountId $device.AccountId
#   }

$script:version       = "1.1.0"
$script:apiUrl        = "https://api.backup.management/jsonapi"
$script:reportingUrl  = "https://api.backup.management/reporting_api"
$script:visa          = $null
$script:partnerId     = 0
$script:modulePath    = Join-Path $PSScriptRoot 'coveApi.psm1'
$script:httpClient    = [System.Net.Http.HttpClient]::new()
$script:httpClient.Timeout = [TimeSpan]::FromSeconds(30)
$script:endpointCache = [System.Collections.Concurrent.ConcurrentDictionary[int,object]]::new()

# ============================================================
# Private helpers
# ============================================================

function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$MaxAttempts  = 3,
        [int]$BaseDelaySec = 2,
        [int]$MaxDelaySec  = 16
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $Action
        } catch {
            if ($attempt -ge $MaxAttempts) { throw }
            $delay = [Math]::Min($BaseDelaySec * [Math]::Pow(2, $attempt - 1), $MaxDelaySec)
            Write-Verbose "Attempt $attempt failed. Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

# ============================================================
# Plugin / data-source maps
# ============================================================

$script:pluginSrcMap = @{
    'FileSystem'       = 'D01'
    'VssSystemState'   = 'D02'
    'LinuxSystemState' = 'D02'
    'NetworkShares'    = 'D06'
    'VMWare'           = 'D08'
    'Oracle'           = 'D12'
    'MySql'            = 'D15'
    'HyperV'           = 'D14'
    'VssExchange'      = 'D04'
    'VssSql'           = 'D10'
    '1'                = 'D01'
    '4'                = 'D04'
    '6'                = 'D06'
    '7'                = 'D02'
    '8'                = 'D08'
    '10'               = 'D10'
    '12'               = 'D12'
    '14'               = 'D14'
    '15'               = 'D15'
    '18'               = 'D02'
}

$script:dCodeNames = @{
    'D01' = 'Files and Folders'
    'D02' = 'System State'
    'D04' = 'Exchange Stores'
    'D06' = 'Network Shares'
    'D08' = 'VMware'
    'D10' = 'MS SQL'
    'D11' = 'SharePoint'
    'D12' = 'Oracle'
    'D14' = 'Hyper-V'
    'D15' = 'MySQL'
}

# ============================================================
# Initialization
# ============================================================

function Initialize-CoveApi {
    param(
        [string]$ApiUrl       = "https://api.backup.management/jsonapi",
        [string]$ReportingUrl = "https://api.backup.management/reporting_api"
    )
    $script:apiUrl       = $ApiUrl
    $script:reportingUrl = $ReportingUrl
}

# Restores session state from an existing visa without re-authenticating.
# Used by Invoke-CoveParallel to initialize module state inside thread jobs.
function Set-CoveSession {
    param(
        [Parameter(Mandatory)][string]$Visa,
        [Parameter(Mandatory)][long]$PartnerId
    )
    $script:visa      = $Visa
    $script:partnerId = $PartnerId
}

# ============================================================
# Authentication
# ============================================================

function Connect-CoveApi {
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password
    )
    $body = @{
        jsonrpc = '2.0'; id = 'jsonrpc'; method = 'Login'
        params  = @{ username = $Username; password = $Password }
    } | ConvertTo-Json -Depth 5 -Compress

    $params = @{
        Uri         = $script:apiUrl
        Method      = 'Post'
        Body        = $body
        ContentType = 'application/json'
        TimeoutSec  = 30
        ErrorAction = 'Stop'
    }

    $resp = Invoke-RestMethod @params
    if (-not $resp.visa)                    { throw "Cove login returned no visa token" }
    if (-not $resp.result.result.PartnerId) { throw "Cove login returned no PartnerId - check credentials" }

    $script:visa      = $resp.visa
    $script:partnerId = [long]$resp.result.result.PartnerId

    return [PSCustomObject]@{
        Visa      = $script:visa
        PartnerId = $script:partnerId
    }
}

function Get-CoveVisa      { return $script:visa }
function Get-CovePartnerId { return $script:partnerId }

# ============================================================
# Core JSON-RPC
# ============================================================

function Invoke-CoveJsonrpc {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][hashtable]$Params,
        [string]$Visa = $script:visa
    )
    $body = [ordered]@{
        jsonrpc = '2.0'
        id      = 'jsonrpc'
        visa    = $Visa
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 10 -Compress

    $params = @{
        Uri         = $script:apiUrl
        Method      = 'Post'
        ContentType = 'application/json'
        Body        = $body
        TimeoutSec  = 30
    }
    return Invoke-RestMethod @params
}

# ============================================================
# Parallel execution
# ============================================================

# Runs a caller-provided script block against each item in parallel. The module
# state (visa, partner ID, API URLs) is pre-initialized in each thread job, so
# any module function can be called directly from within the script block.
#
# The script block receives one argument: the current item.
#
# Example:
#   $results = Invoke-CoveParallel -Items $devices -ThrottleLimit 20 -ScriptBlock {
#       param($device)
#       Get-CoveDeviceErrors -AccountId $device.AccountId
#   }
function Invoke-CoveParallel {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$ThrottleLimit = 20
    )

    $modPath      = $script:modulePath
    $apiUrl       = $script:apiUrl
    $reportingUrl = $script:reportingUrl
    $visa         = $script:visa
    $partnerId    = $script:partnerId

    $jobs    = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $Items) {
        while (($jobs | Where-Object State -eq 'Running').Count -ge $ThrottleLimit) {
            $done = @($jobs | Where-Object { $_.State -in 'Completed', 'Failed', 'Stopped' })
            if ($done.Count -gt 0) {
                foreach ($j in $done) {
                    $results.Add((Receive-Job $j -Wait -ErrorAction SilentlyContinue))
                    Remove-Job $j
                    [void]$jobs.Remove($j)
                }
            } else {
                Start-Sleep -Milliseconds 100
            }
        }

        $job = Start-ThreadJob -ScriptBlock {
            param($i)
            Import-Module $using:modPath
            Initialize-CoveApi -ApiUrl $using:apiUrl -ReportingUrl $using:reportingUrl
            Set-CoveSession -Visa $using:visa -PartnerId $using:partnerId
            & $using:ScriptBlock $i
        } -ArgumentList $item

        [void]$jobs.Add($job)
    }

    foreach ($job in @($jobs)) {
        $results.Add((Receive-Job $job -Wait -ErrorAction SilentlyContinue))
        Remove-Job $job
    }

    return $results.ToArray()
}

# ============================================================
# Partner
# ============================================================

# Returns MainColor and ProductName from the partner web branding archive.
# Returns $null on failure.
function Get-CovePartnerBranding {
    param([string]$Visa = $script:visa)
    try {
        $resp      = Invoke-CoveJsonrpc -Method 'GetPartnerWebBranding' -Params @{ partnerId = $script:partnerId } -Visa $Visa
        $bytes     = [Convert]::FromBase64String($resp.result.webBrandingArchive.Content)
        $ms        = [System.IO.MemoryStream]::new($bytes)
        $zip       = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
        $lessEntry = $zip.GetEntry('css/brand.less')
        $less      = [System.IO.StreamReader]::new($lessEntry.Open()).ReadToEnd()
        $zip.Dispose(); $ms.Dispose()

        $colorMatch = [regex]::Match($less, '@mainColor\s*:\s*(#[0-9a-fA-F]{3,8})')
        $nameMatch  = [regex]::Match($less, "@brandNavBarText\s*:\s*'([^']+)'")
        return [PSCustomObject]@{
            MainColor   = if ($colorMatch.Success) { $colorMatch.Groups[1].Value } else { $null }
            ProductName = if ($nameMatch.Success)  { $nameMatch.Groups[1].Value }  else { $null }
        }
    } catch {
        Write-Verbose "GetPartnerWebBranding failed: $_"
        return $null
    }
}

# ============================================================
# Device enumeration
# ============================================================

# Fetches all devices via EnumerateAccountStatistics.
# $Columns: the list of column codes to request (e.g. 'AU', 'B4', 'AO', ...).
# See Cove API documentation for available column codes.
function Get-CoveDevices {
    param(
        [Parameter(Mandatory)][string[]]$Columns,
        [string]$Visa      = $script:visa,
        [long]$PartnerId   = $script:partnerId,
        [int]$RecordsCount = 10000
    )
    $body = @{
        jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
        method  = 'EnumerateAccountStatistics'
        params  = @{ query = @{ PartnerId = $PartnerId; RecordsCount = $RecordsCount; Columns = $Columns } }
    } | ConvertTo-Json -Depth 10 -Compress

    $params = @{
        Uri         = $script:apiUrl
        Method      = 'Post'
        Body        = $body
        ContentType = 'application/json'
        TimeoutSec  = 60
        ErrorAction = 'Stop'
    }
    $resp = Invoke-RestMethod @params
    return $resp.result.result
}

# ============================================================
# Per-device account info
# ============================================================

# Returns Name, Token, and RepservUrl for a device account.
# RepservUrl is derived from EnumerateAccountRemoteAccessEndpoints.
# Both API calls are issued simultaneously via HttpClient async tasks.
# Results are cached in module scope - repeated calls for the same AccountId
# within the same session (or thread job) return immediately from cache.
# Returns $null if the account cannot be resolved.
function Get-CoveAccountInfo {
    param(
        [Parameter(Mandatory)][int]$AccountId,
        [string]$Visa = $script:visa
    )

    if ($script:endpointCache.ContainsKey($AccountId)) {
        return $script:endpointCache[$AccountId]
    }

    try {
        $infoBody = @{
            jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
            method  = 'GetAccountInfoById'
            params  = @{ accountId = $AccountId }
        } | ConvertTo-Json -Depth 5 -Compress

        $epBody = @{
            jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
            method  = 'EnumerateAccountRemoteAccessEndpoints'
            params  = @{ accountId = $AccountId }
        } | ConvertTo-Json -Depth 5 -Compress

        $c1 = [System.Net.Http.StringContent]::new($infoBody, [Text.Encoding]::UTF8, 'application/json')
        $c2 = [System.Net.Http.StringContent]::new($epBody,   [Text.Encoding]::UTF8, 'application/json')

        $t1 = $script:httpClient.PostAsync($script:apiUrl, $c1)
        $t2 = $script:httpClient.PostAsync($script:apiUrl, $c2)

        [System.Threading.Tasks.Task]::WhenAll($t1, $t2) | Out-Null

        $infoResp = $t1.Result.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        $epResp   = $t2.Result.Content.ReadAsStringAsync().Result | ConvertFrom-Json

        $info = $infoResp.result.result
        if (-not $info) { return $null }

        $repservUrl = $null
        $endpoints  = $epResp.result.result
        if ($endpoints -and $endpoints.Count -gt 0) {
            $webRcgUri  = [Uri]$endpoints[0].WebRcgUrl
            $repservUrl = "$($webRcgUri.Scheme)://$($webRcgUri.Host)/repserv_json"
        }

        $result = @{ Name = $info.Name; Token = $info.Token; RepservUrl = $repservUrl }
        [void]$script:endpointCache.TryAdd($AccountId, $result)
        return $result
    } catch { return $null }
}

# ============================================================
# Device errors
# ============================================================

# Returns error history for a device. FetchFailed=$true indicates a connectivity failure.
# LatestSession: top errors from the most recent session.
# History: top errors across all sessions in the last 90 days.
# SourceErrors: top errors per datasource from the most recent failing session per plugin.
function Get-CoveDeviceErrors {
    param(
        [Parameter(Mandatory)][int]$AccountId,
        [string]$Visa        = $script:visa,
        [int]$TopN           = 5,
        [hashtable]$Endpoint = $null
    )

    $empty     = [PSCustomObject]@{ LatestSession=@(); LatestMore=0; History=@(); HistoryMore=0; LastSessionId=0; SourceErrors=@(); FetchFailed=$false }
    $emptyFail = [PSCustomObject]@{ LatestSession=@(); LatestMore=0; History=@(); HistoryMore=0; LastSessionId=0; SourceErrors=@(); FetchFailed=$true  }

    try {
        if (-not $Endpoint) { $Endpoint = Get-CoveAccountInfo -AccountId $AccountId -Visa $Visa }
        if (-not $Endpoint -or -not $Endpoint.RepservUrl) { return $emptyFail }

        $cutoff  = [long]((Get-Date).AddDays(-90) - [DateTime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc)).TotalSeconds
        $qParams = @{
            Uri         = $Endpoint.RepservUrl
            Method      = 'Post'
            ContentType = 'application/json'
            TimeoutSec  = 10
            Body        = @{
                jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
                method  = 'QueryErrors'
                params  = @{
                    accountId = $AccountId
                    account   = $Endpoint.Name
                    sessionId = 0
                    query     = "Time >= $cutoff"
                    orderBy   = 'Time DESC'
                    groupId   = 0
                    token     = $Endpoint.Token
                }
            } | ConvertTo-Json -Depth 5 -Compress
        }

        $errResponse = Invoke-RestMethod @qParams
        if ($errResponse.error) { return $emptyFail }

        $allErrors = @($errResponse.result.result)
        if ($allErrors.Count -eq 0) { return $empty }

        $maxSession    = ($allErrors | Measure-Object -Property SessionId -Maximum).Maximum
        $latestRaw     = $allErrors | Where-Object { $_.SessionId -eq $maxSession }
        $latestGroups  = @($latestRaw | Group-Object { "$($_.Code)|$($_.Text)|$($_.Filename)" } | Sort-Object { ($_.Group | Measure-Object -Property Count -Sum).Sum } -Descending)
        $latestMore    = [Math]::Max(0, $latestGroups.Count - $TopN)
        $latestSession = $latestGroups | Select-Object -First $TopN | ForEach-Object {
            $top = $_.Group | Sort-Object Time -Descending | Select-Object -First 1
            [PSCustomObject]@{ Code=$top.Code; Text=$top.Text; Filename=$top.Filename; Seen=($_.Group | Measure-Object -Property Count -Sum).Sum; LatestTime=$top.Time }
        }

        $historyGroups = @($allErrors | Group-Object { "$($_.Code)|$($_.Text)|$($_.Filename)" } | Sort-Object { ($_.Group | Measure-Object -Property Count -Sum).Sum } -Descending)
        $historyMore   = [Math]::Max(0, $historyGroups.Count - $TopN)
        $history       = $historyGroups | Select-Object -First $TopN | ForEach-Object {
            $top = $_.Group | Sort-Object Time -Descending | Select-Object -First 1
            [PSCustomObject]@{ Code=$top.Code; Text=$top.Text; Filename=$top.Filename; Seen=($_.Group | Measure-Object -Property Count -Sum).Sum; LatestTime=$top.Time }
        }

        $sourceErrors = @()
        try {
            $ssCutoff = [long]((Get-Date).AddDays(-7) - [DateTime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc)).TotalSeconds
            $ssParams = @{
                Uri         = $Endpoint.RepservUrl
                Method      = 'Post'
                ContentType = 'application/json'
                TimeoutSec  = 10
                Body        = @{
                    jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
                    method  = 'QuerySessions'
                    params  = @{
                        accountId = $AccountId
                        account   = $Endpoint.Name
                        token     = $Endpoint.Token
                        query     = '(Status == 2 or Status == 3 or Status == 6 or Status == 8) and BackupStartTime >= ' + $ssCutoff
                        orderBy   = 'BackupStartTime DESC'
                    }
                } | ConvertTo-Json -Depth 5 -Compress
            }
            $ssResp = Invoke-RestMethod @ssParams
            if (-not $ssResp.error) {
                $failingSessions = @($ssResp.result.result)
                $byPlugin = $failingSessions | Group-Object { [string]$_.PluginId } | ForEach-Object {
                    $_.Group | Sort-Object { [long]$_.BackupStartTime } -Descending | Select-Object -First 1
                }
                foreach ($sess in $byPlugin) {
                    $plugin = [string]$sess.PluginId
                    if (-not $script:pluginSrcMap.ContainsKey($plugin)) { continue }
                    $dCode   = $script:pluginSrcMap[$plugin]
                    $srcName = if ($script:dCodeNames.ContainsKey($dCode)) { $script:dCodeNames[$dCode] } else { $dCode }
                    $sessId  = [int]$sess.Id
                    $sqParams = @{
                        Uri         = $Endpoint.RepservUrl
                        Method      = 'Post'
                        ContentType = 'application/json'
                        TimeoutSec  = 10
                        Body        = @{
                            jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
                            method  = 'QueryErrors'
                            params  = @{
                                accountId = $AccountId
                                account   = $Endpoint.Name
                                sessionId = $sessId
                                query     = "SessionId == $sessId"
                                groupId   = 0
                                token     = $Endpoint.Token
                            }
                        } | ConvertTo-Json -Depth 5 -Compress
                    }
                    $sqResp = Invoke-RestMethod @sqParams
                    if ($sqResp.error) { continue }
                    $sessErrs = @($sqResp.result.result)
                    if ($sessErrs.Count -eq 0) { continue }
                    $grps    = @($sessErrs | Group-Object { "$($_.Code)|$($_.Text)|$($_.Filename)" } | Sort-Object { ($_.Group | Measure-Object -Property Count -Sum).Sum } -Descending)
                    if ($grps.Count -eq 0) { continue }
                    $srcMore = [Math]::Max(0, $grps.Count - $TopN)
                    $srcErrs = $grps | Select-Object -First $TopN | ForEach-Object {
                        $top = $_.Group | Sort-Object Time -Descending | Select-Object -First 1
                        [PSCustomObject]@{ Code=$top.Code; Text=$top.Text; Filename=$top.Filename; Seen=($_.Group | Measure-Object -Property Count -Sum).Sum; LatestTime=$top.Time }
                    }
                    if (@($srcErrs).Count -eq 0) { continue }
                    $sourceErrors += [PSCustomObject]@{ Name=$srcName; Errors=@($srcErrs); MoreCount=$srcMore }
                }
            }
        } catch { }

        return [PSCustomObject]@{
            LatestSession = @($latestSession)
            LatestMore    = $latestMore
            History       = @($history)
            HistoryMore   = $historyMore
            LastSessionId = if ($maxSession) { [int]$maxSession } else { 0 }
            SourceErrors  = $sourceErrors
            FetchFailed   = $false
        }
    } catch { return $emptyFail }
}

# ============================================================
# M365 errors
# ============================================================

# Returns M365 error history for a device across Exchange, OneDrive, SharePoint, and Teams.
# $ActiveSources: concatenated 3-char datasource codes (e.g. 'D19D20') to limit which M365
#   sources are queried. Pass empty string to query all four.
# FetchFailed=$true indicates a connectivity or token failure.
function Get-CoveM365Errors {
    param(
        [Parameter(Mandatory)][int]$AccountId,
        [string]$Visa          = $script:visa,
        [string]$ActiveSources = '',
        [int]$TopN             = 5,
        [string]$AccountToken  = $null
    )

    $empty     = [PSCustomObject]@{ LatestSession=@(); LatestMore=0; History=@(); HistoryMore=0; LastSessionId=0; SourceErrors=@(); FetchFailed=$false }
    $emptyFail = [PSCustomObject]@{ LatestSession=@(); LatestMore=0; History=@(); HistoryMore=0; LastSessionId=0; SourceErrors=@(); FetchFailed=$true  }

    $dsTypeMap = [ordered]@{ 'D19'='Exchange'; 'D20'='OneDrive'; 'D05'='SharePoint'; 'D23'='Teams' }
    $dsNameMap = @{ 'D19'='M365 Exchange'; 'D20'='M365 OneDrive'; 'D05'='M365 SharePoint'; 'D23'='M365 Teams' }

    $activeDsIds = @()
    if ($ActiveSources) {
        for ($i = 0; $i -lt $ActiveSources.Length; $i += 3) {
            $activeDsIds += $ActiveSources.Substring($i, [Math]::Min(3, $ActiveSources.Length - $i))
        }
    }
    $activeDs = if ($activeDsIds.Count -gt 0) {
        $dsTypeMap.GetEnumerator() | Where-Object { $activeDsIds -contains $_.Key }
    } else { $dsTypeMap.GetEnumerator() }
    if (-not $activeDs) { return $empty }

    try {
        $currentVisa = $Visa
        if (-not $AccountToken) {
            $infoParams = @{
                Uri         = $script:apiUrl
                Method      = 'Post'
                ContentType = 'application/json'
                TimeoutSec  = 15
                Body        = @{
                    jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
                    method  = 'GetAccountInfoById'
                    params  = @{ accountId = $AccountId }
                } | ConvertTo-Json -Depth 5 -Compress
            }
            $infoResponse = Invoke-RestMethod @infoParams
            $AccountToken = $infoResponse.result.result.Token
            $currentVisa  = if ($infoResponse.visa) { $infoResponse.visa } else { $Visa }
        }
        if (-not $AccountToken) { return $emptyFail }

        $reportingHeaders = @{ Authorization = "Bearer $currentVisa" }
        $cutoffTs         = [long]((Get-Date).AddDays(-90) - [DateTime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc)).TotalSeconds
        $allErrors        = @()
        $m365SrcErrors    = @()

        foreach ($ds in $activeDs) {
            $dsType  = $ds.Value
            $errBody = @{
                jsonrpc = '2.0'; id = 'jsonrpc'
                method  = 'EnumerateSessionErrors'
                params  = @{
                    accountToken   = $AccountToken
                    dataSourceType = $dsType
                    filter         = @{ SessionType = 'Backup'; TimestampFrom = $cutoffTs }
                    range          = @{ Offset = 0; Size = 50 }
                }
            } | ConvertTo-Json -Depth 10 -Compress

            try {
                $errParams = @{
                    Uri         = $script:reportingUrl
                    Method      = 'Post'
                    Body        = $errBody
                    ContentType = 'application/json'
                    Headers     = $reportingHeaders
                    TimeoutSec  = 10
                }
                $response = Invoke-RestMethod @errParams
                if ($response.visa) {
                    $currentVisa      = $response.visa
                    $reportingHeaders = @{ Authorization = "Bearer $currentVisa" }
                }
                if ($response.error) { continue }

                $dsResults  = @($response.result.result)
                if ($dsResults.Count -eq 0) { continue }

                $maxSession = ($dsResults | Measure-Object -Property SessionId -Maximum).Maximum
                $latestRaw  = $dsResults | Where-Object { $_.SessionId -eq $maxSession }

                foreach ($err in $latestRaw) {
                    $desc     = try { $err.Description | ConvertFrom-Json } catch { $null }
                    $descText = if ($desc -and $desc.description) { $desc.description } elseif ($err.Description) { $err.Description } else { '(unknown error)' }
                    if ($descText.Length -gt 200) { $descText = $descText.Substring(0, 197) + '...' }

                    $parts = @()
                    if ($err.Item) { $parts += $err.Item }
                    if ($desc -and $desc.path -and $desc.path -ne '/' -and $desc.path -ne '') { $parts += $desc.path }

                    $allErrors += [PSCustomObject]@{
                        Code       = ''
                        Text       = $descText
                        Filename   = $parts -join ' - '
                        Seen       = [int]$err.Count
                        LatestTime = [long]$err.Timestamp
                        DataSource = $dsType
                    }
                }

                if ($latestRaw.Count -gt 0) {
                    $dsGrps = @($latestRaw | Group-Object { "$($_.Description)|$($_.Item)" } | Sort-Object { ($_.Group | Measure-Object -Property Count -Sum).Sum } -Descending)
                    $dsMore = [Math]::Max(0, $dsGrps.Count - $TopN)
                    $dsErrs = $dsGrps | Select-Object -First $TopN | ForEach-Object {
                        $topE = $_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1
                        $dsc  = try { $topE.Description | ConvertFrom-Json } catch { $null }
                        $txt  = if ($dsc -and $dsc.description) { $dsc.description } elseif ($topE.Description) { $topE.Description } else { '(unknown error)' }
                        if ($txt.Length -gt 200) { $txt = $txt.Substring(0, 197) + '...' }
                        $pts  = @()
                        if ($topE.Item) { $pts += $topE.Item }
                        if ($dsc -and $dsc.path -and $dsc.path -ne '/' -and $dsc.path -ne '') { $pts += $dsc.path }
                        [PSCustomObject]@{ Code=''; Text=$txt; Filename=($pts -join ' - '); Seen=[int]$topE.Count; LatestTime=[long]$topE.Timestamp }
                    }
                    if (@($dsErrs).Count -eq 0) { continue }
                    $dCodeKey = ($dsTypeMap.GetEnumerator() | Where-Object { $_.Value -eq $dsType } | Select-Object -First 1).Key
                    $srcName  = if ($dCodeKey -and $dsNameMap.ContainsKey($dCodeKey)) { $dsNameMap[$dCodeKey] } else { $dsType }
                    $m365SrcErrors += [PSCustomObject]@{ Name=$srcName; Errors=@($dsErrs); MoreCount=$dsMore }
                }
            } catch {
                Write-Verbose "M365 error fetch failed for ${dsType}: $($_.Exception.Message)"
            }
        }

        if ($allErrors.Count -eq 0) { return $empty }

        $groups        = @($allErrors | Group-Object { "$($_.Text)|$($_.Filename)" } | Sort-Object { ($_.Group | Measure-Object -Property Seen -Sum).Sum } -Descending)
        $latestMore    = [Math]::Max(0, $groups.Count - $TopN)
        $latestSession = $groups | Select-Object -First $TopN | ForEach-Object {
            $top = $_.Group | Sort-Object LatestTime -Descending | Select-Object -First 1
            [PSCustomObject]@{ Code=''; Text=$top.Text; Filename=$top.Filename; Seen=($_.Group | Measure-Object -Property Seen -Sum).Sum; LatestTime=$top.LatestTime; DataSource=$top.DataSource }
        }

        return [PSCustomObject]@{
            LatestSession = @($latestSession)
            LatestMore    = $latestMore
            History       = @()
            HistoryMore   = 0
            LastSessionId = 0
            SourceErrors  = $m365SrcErrors
            FetchFailed   = $false
        }
    } catch { return $emptyFail }
}

# ============================================================
# Session progress
# ============================================================

# Returns progress of the most recent or currently active backup session for a device.
# FetchFailed=$true if the repserv endpoint is unreachable.
function Get-CoveSessionProgress {
    param(
        [Parameter(Mandatory)][int]$AccountId,
        [string]$Visa        = $script:visa,
        [hashtable]$Endpoint = $null
    )

    $empty = [PSCustomObject]@{
        FetchFailed=     $true
        PercentComplete= 0
        ProcessedSize=   0
        SelectedSize=    0
        ChangedSize=     0
        ProcessedCount=  0
        SelectedCount=   0
        SentSize=        0
        SessionId=       0
        Status=          ''
    }

    try {
        if (-not $Endpoint) { $Endpoint = Get-CoveAccountInfo -AccountId $AccountId -Visa $Visa }
        if (-not $Endpoint -or -not $Endpoint.RepservUrl) { return $empty }

        $qParams = @{
            Uri         = $Endpoint.RepservUrl
            Method      = 'Post'
            ContentType = 'application/json'
            TimeoutSec  = 5
            Body        = @{
                jsonrpc = '2.0'; id = 'jsonrpc'
                method  = 'QuerySessions'
                params  = @{
                    accountId = $AccountId
                    account   = $Endpoint.Name
                    token     = $Endpoint.Token
                    visa      = $Visa
                    query     = '(Type & 1) == 1'
                    orderBy   = 'BackupStartTime DESC'
                    range     = @{ Offset = 0; Size = 10 }
                }
            } | ConvertTo-Json -Depth 5 -Compress
        }

        $sResponse = Invoke-RestMethod @qParams
        if ($sResponse.error) { return $empty }
        $sessions = @($sResponse.result.result)
        if (-not $sessions) { return $empty }

        $activeSessions = @($sessions | Where-Object { [long]$_.EndTime -eq 0 })
        if ($activeSessions.Count -eq 0) { $activeSessions = @($sessions | Select-Object -First 1) }

        $sel     = ($activeSessions | Measure-Object -Property SelectedSize   -Sum).Sum
        $proc    = ($activeSessions | Measure-Object -Property ProcessedSize  -Sum).Sum
        $changed = ($activeSessions | Measure-Object -Property ChangedSize    -Sum).Sum
        $sent    = ($activeSessions | Measure-Object -Property SentSize       -Sum).Sum
        $procCnt = ($activeSessions | Measure-Object -Property ProcessedCount -Sum).Sum
        $selCnt  = ($activeSessions | Measure-Object -Property SelectedCount  -Sum).Sum

        $pct = if ($changed -gt 0) { [int][Math]::Min(100, [Math]::Round($proc / $changed * 100)) } `
               elseif ($sel -gt 0) { [int][Math]::Round($proc / $sel * 100) } `
               else { 0 }

        $refId = ($activeSessions | Measure-Object -Property Id -Maximum).Maximum

        return [PSCustomObject]@{
            FetchFailed     = $false
            PercentComplete = $pct
            ProcessedSize   = [long]$proc
            SelectedSize    = [long]$sel
            ChangedSize     = [long]$changed
            ProcessedCount  = [long]$procCnt
            SelectedCount   = [long]$selCnt
            SentSize        = [long]$sent
            SessionId       = [int]$refId
            Status          = "$($activeSessions[0].Status)"
        }
    } catch { return $empty }
}

# ============================================================
# Session history
# ============================================================

# Returns a list of session objects for a device.
# Each object: SrcCode (string), StartTimeUnix (long), EndTimeUnix (long),
#   Status (int, normalized), SelectedSize (long, bytes).
# Status codes: 1=InProgress, 2=Failed, 3=Aborted, 5=Success, 6=Interrupted,
#   7=NotStarted, 8=CompletedWithErrors, 9=InProgressWithFaults, 10=OverQuota,
#   12=Restarted, 13=Blocked.
# Returns $null if the endpoint is unreachable or returns no sessions.
function Get-CoveSessions {
    param(
        [Parameter(Mandatory)][int]$AccountId,
        [string]$Visa        = $script:visa,
        [long]$StartTime     = 0,
        [long]$EndTime       = 0,
        [hashtable]$Endpoint = $null
    )

    try {
        if (-not $Endpoint) { $Endpoint = Get-CoveAccountInfo -AccountId $AccountId -Visa $Visa }
        if (-not $Endpoint -or -not $Endpoint.RepservUrl) { return $null }

        $queryParts = @('(Type & 1) == 1')
        if ($StartTime -gt 0) { $queryParts += "BackupStartTime >= $StartTime" }
        if ($EndTime   -gt 0) { $queryParts += "BackupStartTime <= $EndTime"   }
        $query = $queryParts -join ' and '

        $qParams = @{
            Uri         = $Endpoint.RepservUrl
            Method      = 'Post'
            ContentType = 'application/json'
            TimeoutSec  = 15
            Body        = @{
                jsonrpc = '2.0'; id = 'jsonrpc'
                method  = 'QuerySessions'
                params  = @{
                    accountId = $AccountId
                    account   = $Endpoint.Name
                    token     = $Endpoint.Token
                    visa      = $Visa
                    query     = $query
                    orderBy   = 'BackupStartTime DESC'
                    range     = @{ Offset = 0; Size = 500 }
                }
            } | ConvertTo-Json -Depth 5 -Compress
        }

        $sResp = $null
        foreach ($delay in @(0, 3, 6)) {
            if ($delay -gt 0) { Start-Sleep -Seconds $delay }
            try {
                $sResp = Invoke-RestMethod @qParams
                if (-not $sResp.error) { break }
                $sResp = $null
            } catch { $sResp = $null }
        }
        if (-not $sResp) { return $null }

        $rawSessions = @($sResp.result.result)
        if (-not $rawSessions -or $rawSessions.Count -eq 0) { return $null }

        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($sess in $rawSessions) {
            $plugin = if ($null -ne $sess.PSObject.Properties['Plugin']) { [string]$sess.Plugin } else { [string]$sess.PluginId }
            if (-not $script:pluginSrcMap.ContainsKey($plugin)) { continue }
            $srcCode = $script:pluginSrcMap[$plugin]
            $errCnt  = [int]$sess.ErrorsCount
            $st      = [string]$sess.Status
            $status  = switch ($st) {
                'Completed'            { if ($errCnt -gt 0) { 8 } else { 5 } }
                'CompletedWithErrors'  { 8  }
                '5'                    { if ($errCnt -gt 0) { 8 } else { 5 } }
                '8'                    { 8  }
                'Failed'               { 2  }
                '2'                    { 2  }
                'Aborted'              { 3  }
                '3'                    { 3  }
                'Interrupted'          { 6  }
                '6'                    { 6  }
                'InProgress'           { 1  }
                '1'                    { 1  }
                'InProgressWithFaults' { 9  }
                '9'                    { 9  }
                'NotStarted'           { 7  }
                '7'                    { 7  }
                'OverQuota'            { 10 }
                '10'                   { 10 }
                'Restarted'            { 12 }
                '12'                   { 12 }
                'Blocked'              { 13 }
                '13'                   { 13 }
                default                { 0  }
            }
            if ($status -eq 0) { continue }
            $result.Add([PSCustomObject]@{
                SrcCode       = $srcCode
                StartTimeUnix = [long]$sess.StartTime
                EndTimeUnix   = [long]$sess.EndTime
                Status        = $status
                SelectedSize  = [long]$sess.SelectedSize
            })
        }
        return $result
    } catch { return $null }
}

# ============================================================
# Device write
# ============================================================

# Writes a value to a Cove device custom column. Pass Value = '' to clear.
function Set-CoveDeviceCustomColumn {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][long]$DeviceId,
        [Parameter(Mandatory)][int]$ColumnId,
        [string]$Value = '',
        [string]$Visa  = $script:visa
    )
    if (-not $PSCmdlet.ShouldProcess("Device $DeviceId", "Set custom column $ColumnId = '$Value'")) { return }

    $body = @{
        jsonrpc = '2.0'; id = 'jsonrpc'; visa = $Visa
        method  = 'UpdateAccountCustomColumnValues'
        params  = @{ accountId = $DeviceId; values = @(, @($ColumnId, $Value)) }
    } | ConvertTo-Json -Depth 10 -Compress

    $params = @{
        Uri         = $script:apiUrl
        Method      = 'Post'
        Body        = $body
        ContentType = 'application/json'
        TimeoutSec  = 15
        ErrorAction = 'Stop'
    }
    $resp = Invoke-RestMethod @params
    if ($resp.error) { throw "Cove error: $($resp.error.message)" }
}

Export-ModuleMember -Function `
    Initialize-CoveApi, Set-CoveSession, `
    Connect-CoveApi, Get-CoveVisa, Get-CovePartnerId, `
    Invoke-CoveJsonrpc, Invoke-CoveParallel, `
    Get-CovePartnerBranding, `
    Get-CoveDevices, `
    Get-CoveAccountInfo, `
    Get-CoveDeviceErrors, Get-CoveM365Errors, `
    Get-CoveSessionProgress, Get-CoveSessions, `
    Set-CoveDeviceCustomColumn
