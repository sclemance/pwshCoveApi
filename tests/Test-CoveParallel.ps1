#Requires -Version 7.4
# Tests Invoke-CoveParallel: verifies module state is initialized in thread jobs
# and that results are collected correctly. Uses Get-CoveDevices as the data source
# and a lightweight script block to avoid hammering the repserv endpoints.
param(
    [string]$Username,
    [string]$Password,
    [int]$DeviceLimit   = 10,
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

# Verify module state is accessible inside thread jobs by calling Get-CovePartnerId
# and Get-CoveVisa from within the script block. If Invoke-CoveParallel fails to
# initialize the session, these return 0 / $null.
Write-Host "Running Invoke-CoveParallel (ThrottleLimit $ThrottleLimit)..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$results = Invoke-CoveParallel -Items $devices -ThrottleLimit $ThrottleLimit -ScriptBlock {
    param($device)
    [PSCustomObject]@{
        AccountId = $device.AccountId
        Name      = $device.Name
        PartnerId = Get-CovePartnerId   # non-zero only if session state was initialized
        HasVisa   = -not [string]::IsNullOrEmpty((Get-CoveVisa))
    }
}

$sw.Stop()
Write-Host "  Elapsed: $($sw.ElapsedMilliseconds) ms" -ForegroundColor Gray

$failures = @()

if ($results.Count -ne $devices.Count) {
    $failures += "Expected $($devices.Count) results, got $($results.Count)"
}

foreach ($r in $results) {
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
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Host "[FAIL] $f" -ForegroundColor Red }
    exit 1
}

Write-Host "  All $($results.Count) jobs returned correct session state" -ForegroundColor Green
Write-Host "Invoke-CoveParallel OK" -ForegroundColor Green
