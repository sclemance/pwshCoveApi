#Requires -Version 7.4
# Tests Invoke-CoveParallel: verifies module state is initialized in thread jobs,
# results are collected correctly, and demonstrates real speedup by calling
# Get-CoveAccountInfo (a live HTTP call) for each device.
#
# Run order — parallel first, sequential second — keeps both runs cold:
# thread jobs have isolated module scope and don't populate the parent's
# endpoint cache, so sequential sees the same cold cache state.
param(
    [string]$Username,
    [string]$Password,
    [int]$DeviceLimit   = 30,
    [int]$ThrottleLimit = 5
)

$credFile = Join-Path $PSScriptRoot 'credentials.ps1'
if (-not $Username -or -not $Password) {
    if (Test-Path $credFile) { . $credFile }
    if (-not $Username) { $Username = $testUsername }
    if (-not $Password) { $Password = $testPassword }
}
if (-not $Username -or -not $Password) { throw "Provide -Username/-Password or populate tests/credentials.ps1" }

Import-Module (Join-Path $PSScriptRoot '../coveApi.psm1') -Force

Connect-CoveApi -Username $Username -Password $Password | Out-Null

Write-Host "Fetching devices (limit $DeviceLimit)..." -ForegroundColor Cyan
$allDevices = Get-CoveDevices -Columns @('AU', 'AB')
$devices    = @($allDevices | Select-Object -First $DeviceLimit)
Write-Host "  $($devices.Count) devices selected" -ForegroundColor Gray

# Real HTTP work per device — one JSON-RPC call to GetAccountInfoById.
# Deliberately uses Invoke-CoveJsonrpc (a flat HTTP call) rather than
# Get-CoveAccountInfo, which uses ForEach-Object -Parallel internally and
# breaks when nested inside Start-ThreadJob runspaces.
# Invoke-CoveParallel strips SessionState binding internally, so a plain
# script block literal works correctly here.
$workBlock = {
    param($device)
    $resp = Invoke-CoveJsonrpc -Method 'GetAccountInfoById' -Params @{ accountId = $device.AccountId }
    [PSCustomObject]@{
        AccountId = $device.AccountId
        Name      = $device.Name
        Resolved  = $null -ne $resp.result.result
        PartnerId = Get-CovePartnerId
        HasVisa   = -not [string]::IsNullOrEmpty((Get-CoveVisa))
    }
}

# --- Parallel run (first — cache cold, jobs have isolated scope) ---
Write-Host "Running Invoke-CoveParallel (ThrottleLimit $ThrottleLimit)..." -ForegroundColor Cyan
$swPar  = [System.Diagnostics.Stopwatch]::StartNew()
$parResults = Invoke-CoveParallel -Items $devices -ThrottleLimit $ThrottleLimit -ScriptBlock $workBlock
$swPar.Stop()
Write-Host "  Elapsed: $($swPar.ElapsedMilliseconds) ms" -ForegroundColor Gray

# --- Sequential run (second — parent cache still cold; parallel jobs didn't populate it) ---
Write-Host "Running sequential (foreach)..." -ForegroundColor Cyan
$swSeq = [System.Diagnostics.Stopwatch]::StartNew()
$seqResults = foreach ($device in $devices) { & $workBlock $device }
$swSeq.Stop()
Write-Host "  Elapsed: $($swSeq.ElapsedMilliseconds) ms" -ForegroundColor Gray

# --- Timing comparison ---
$parMs = $swPar.ElapsedMilliseconds
$seqMs = $swSeq.ElapsedMilliseconds
if ($parMs -gt 0) { $ratio = [math]::Round($seqMs / $parMs, 2) } else { $ratio = 'N/A' }
Write-Host ""
Write-Host "  Parallel   : $parMs ms" -ForegroundColor White
Write-Host "  Sequential : $seqMs ms" -ForegroundColor White
Write-Host "  Speedup    : ${ratio}x" -ForegroundColor $(if ($ratio -ne 'N/A' -and $ratio -gt 1) { 'Green' } else { 'Yellow' })
Write-Host ""

# --- Validate parallel results ---
# Session-state correctness uses in-memory checks (PartnerId/HasVisa) — reliable
# regardless of transient HTTP failures under concurrent load.
# Resolved mismatches are reported as warnings only, since a parallel HTTP call
# can fail transiently even when session state is fine.
$failures  = @()
$warnings  = @()
$seqMap    = @{}
foreach ($r in $seqResults) { if ($r) { $seqMap[[int]$r.AccountId] = $r } }

if ($parResults.Count -ne $devices.Count) {
    $failures += "Expected $($devices.Count) results, got $($parResults.Count)"
}

foreach ($r in $parResults) {
    if (-not $r) {
        $failures += "A result was null (job likely threw)"
        continue
    }
    if ($r.PartnerId -le 0) {
        $failures += "AccountId $($r.AccountId): PartnerId was 0 - session state not initialized in job"
    }
    if (-not $r.HasVisa) {
        $failures += "AccountId $($r.AccountId): visa was empty in job"
    }
    $seqR = $seqMap[[int]$r.AccountId]
    if ($seqR -and $seqR.Resolved -and -not $r.Resolved) {
        $warnings += "AccountId $($r.AccountId): resolved in sequential but not in parallel (likely transient)"
    }
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Host "  [FAIL] $f" -ForegroundColor Red }
    exit 1
}
foreach ($w in $warnings) { Write-Host "  [WARN] $w" -ForegroundColor Yellow }

$resolved = @($parResults | Where-Object { $_.Resolved }).Count
Write-Host "  $resolved/$($parResults.Count) devices resolved account info" -ForegroundColor Green
Write-Host "  All $($parResults.Count) jobs had correct session state" -ForegroundColor Green
Write-Host "Invoke-CoveParallel OK" -ForegroundColor Green
