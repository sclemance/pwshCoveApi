#Requires -Version 7.4
# Tests Get-CoveAccountInfo: verifies HttpClient async fetch and endpoint cache.
# Picks the first device from EnumerateAccountStatistics if -AccountId is not supplied.
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
    Write-Host "No -AccountId supplied, picking first device from EnumerateAccountStatistics..." -ForegroundColor Cyan
    $devices   = Get-CoveDevices -Columns @('AU', 'AB')
    if (-not $devices -or $devices.Count -eq 0) { throw "No devices returned" }
    $AccountId = [int]$devices[0].AccountId
    Write-Host "  Using AccountId: $AccountId ($($devices[0].Name))" -ForegroundColor Gray
}

# First call - hits the API
Write-Host "First call (expect API fetch)..." -ForegroundColor Cyan
$sw1  = [System.Diagnostics.Stopwatch]::StartNew()
$info = Get-CoveAccountInfo -AccountId $AccountId
$sw1.Stop()

if (-not $info) { Write-Host "[FAIL] Get-CoveAccountInfo returned null" -ForegroundColor Red; exit 1 }
Write-Host "  Name:       $($info.Name)"       -ForegroundColor Green
Write-Host "  RepservUrl: $($info.RepservUrl)"  -ForegroundColor Green
Write-Host "  Elapsed:    $($sw1.ElapsedMilliseconds) ms" -ForegroundColor Green

# Second call - must be a cache hit
Write-Host "Second call (expect cache hit)..." -ForegroundColor Cyan
$sw2   = [System.Diagnostics.Stopwatch]::StartNew()
$info2 = Get-CoveAccountInfo -AccountId $AccountId
$sw2.Stop()

Write-Host "  Elapsed: $($sw2.ElapsedMilliseconds) ms" -ForegroundColor Green

if ($info2.Name -ne $info.Name -or $info2.RepservUrl -ne $info.RepservUrl) {
    Write-Host "[FAIL] Cache returned different data" -ForegroundColor Red; exit 1
}
if ($sw2.ElapsedMilliseconds -gt 50) {
    Write-Host "  [WARN] Cache hit took $($sw2.ElapsedMilliseconds) ms - expected < 50 ms" -ForegroundColor Yellow
} else {
    Write-Host "  Cache hit confirmed (<50 ms)" -ForegroundColor Green
}

Write-Host "Get-CoveAccountInfo OK" -ForegroundColor Green
