#Requires -Version 7.4
# Tests Get-CoveDeviceErrors and Get-CoveM365Errors end-to-end against a real device.
# Prints a summary of what was returned so results can be eyeballed.
param(
    [string]$Username,
    [string]$Password,
    [int]$AccountId = 0
)

$credFile = Join-Path $PSScriptRoot 'credentials.ps1'
if (-not $Username -or -not $Password) {
    if (Test-Path $credFile) { . $credFile }
    if (-not $Username) { $Username = $testUsername }
    if (-not $Password) { $Password = $testPassword }
    if ($AccountId -eq 0 -and $testAccountId) { $AccountId = $testAccountId }
}
if (-not $Username -or -not $Password) { throw "Provide -Username/-Password or populate tests/credentials.ps1" }

Import-Module (Join-Path $PSScriptRoot '../coveApi.psm1') -Force

Connect-CoveApi -Username $Username -Password $Password | Out-Null

if ($AccountId -eq 0) {
    Write-Host "No -AccountId supplied, picking first device..." -ForegroundColor Cyan
    $devices   = Get-CoveDevices -Columns @('AU', 'AB')
    if (-not $devices -or $devices.Count -eq 0) { throw "No devices returned" }
    $AccountId = [int]$devices[0].AccountId
    Write-Host "  Using AccountId: $AccountId ($($devices[0].Name))" -ForegroundColor Gray
}

# Fetch endpoint once - reused by both calls via cache
Write-Host "Resolving endpoint for AccountId $AccountId..." -ForegroundColor Cyan
$endpoint = Get-CoveAccountInfo -AccountId $AccountId
if (-not $endpoint) {
    Write-Host "[FAIL] Could not resolve endpoint" -ForegroundColor Red; exit 1
}
Write-Host "  $($endpoint.Name) -> $($endpoint.RepservUrl)" -ForegroundColor Gray

# Device errors
Write-Host "Fetching device errors..." -ForegroundColor Cyan
$errors = Get-CoveDeviceErrors -AccountId $AccountId -Endpoint $endpoint

if ($errors.FetchFailed) {
    Write-Host "  [WARN] FetchFailed=true - repserv may be unreachable" -ForegroundColor Yellow
} else {
    Write-Host "  LatestSession: $($errors.LatestSession.Count) errors (+$($errors.LatestMore) more)" -ForegroundColor Green
    Write-Host "  History:       $($errors.History.Count) errors (+$($errors.HistoryMore) more)"       -ForegroundColor Green
    Write-Host "  SourceErrors:  $($errors.SourceErrors.Count) sources"                                -ForegroundColor Green
    Write-Host "  LastSessionId: $($errors.LastSessionId)"                                             -ForegroundColor Green

    if ($errors.LatestSession.Count -gt 0) {
        Write-Host "  --- Latest session errors ---" -ForegroundColor Gray
        foreach ($e in $errors.LatestSession) {
            Write-Host "    [$($e.Code)] $($e.Text) (seen $($e.Seen)x)" -ForegroundColor Gray
        }
    }
}

# M365 errors
Write-Host "Fetching M365 errors..." -ForegroundColor Cyan
$m365 = Get-CoveM365Errors -AccountId $AccountId

if ($m365.FetchFailed) {
    Write-Host "  [WARN] FetchFailed=true - may not be an M365 device" -ForegroundColor Yellow
} else {
    Write-Host "  LatestSession: $($m365.LatestSession.Count) errors (+$($m365.LatestMore) more)" -ForegroundColor Green
    Write-Host "  SourceErrors:  $($m365.SourceErrors.Count) sources"                             -ForegroundColor Green

    if ($m365.LatestSession.Count -gt 0) {
        Write-Host "  --- Latest M365 errors ---" -ForegroundColor Gray
        foreach ($e in $m365.LatestSession) {
            Write-Host "    [$($e.DataSource)] $($e.Text) (seen $($e.Seen)x)" -ForegroundColor Gray
        }
    }
}

Write-Host "Device errors test complete" -ForegroundColor Green
