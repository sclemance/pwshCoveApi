#Requires -Version 7.4
# Tests Get-CoveAccountInfo: verifies the endpoint cache delivers a dramatic
# speedup over cold API calls by running a full batch twice.
# Cold run: two JSON-RPC calls per device (GetAccountInfoById +
#   EnumerateAccountRemoteAccessEndpoints).
# Warm run: all results served from cache, no API traffic.
param(
    [string]$Username,
    [string]$Password,
    [int]$DeviceLimit = 25
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

# Use a List so null results (devices with no endpoint) are preserved and
# index-aligned with $devices for accurate cold/warm comparison.
$coldResults = [System.Collections.Generic.List[object]]::new()
$warmResults = [System.Collections.Generic.List[object]]::new()

# --- Cold run (cache empty) ---
Write-Host "Cold run ($($devices.Count) devices, cache empty)..." -ForegroundColor Cyan
$swCold = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($d in $devices) { $coldResults.Add((Get-CoveAccountInfo -AccountId $d.AccountId)) }
$swCold.Stop()
$coldMs   = $swCold.ElapsedMilliseconds
$resolved = ($coldResults | Where-Object { $_ }).Count
Write-Host "  Elapsed:  $coldMs ms" -ForegroundColor Gray
Write-Host "  Resolved: $resolved/$($devices.Count)" -ForegroundColor Gray

# --- Warm run (all cache hits) ---
Write-Host "Warm run ($($devices.Count) devices, all cache hits)..." -ForegroundColor Cyan
$swWarm = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($d in $devices) { $warmResults.Add((Get-CoveAccountInfo -AccountId $d.AccountId)) }
$swWarm.Stop()
$warmMs = $swWarm.ElapsedMilliseconds
Write-Host "  Elapsed:  $warmMs ms" -ForegroundColor Gray

# --- Comparison ---
$ratio = if ($warmMs -gt 0) { [math]::Round($coldMs / $warmMs, 0) } else { 'N/A' }
Write-Host ""
Write-Host "  Cold (API)   : $coldMs ms" -ForegroundColor White
Write-Host "  Warm (cache) : $warmMs ms" -ForegroundColor White
Write-Host "  Speedup      : ${ratio}x" -ForegroundColor $(if ($ratio -ne 'N/A' -and $ratio -gt 10) { 'Green' } else { 'Yellow' })
Write-Host ""

# --- Validate ---
$failures = @()

for ($i = 0; $i -lt $devices.Count; $i++) {
    $cold = $coldResults[$i]
    $warm = $warmResults[$i]
    if (-not $cold -and -not $warm) { continue }
    if ($cold -and -not $warm) {
        $failures += "AccountId $($devices[$i].AccountId): resolved cold but missing from warm"
    } elseif ($warm -and -not $cold) {
        $failures += "AccountId $($devices[$i].AccountId): appeared in warm but not cold (cache corruption)"
    } elseif ($cold.Name -ne $warm.Name -or $cold.RepservUrl -ne $warm.RepservUrl) {
        $failures += "AccountId $($devices[$i].AccountId): cold/warm mismatch (Name or RepservUrl differs)"
    }
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Host "  [FAIL] $f" -ForegroundColor Red }
    exit 1
}

Write-Host "  $resolved/$($devices.Count) devices resolved - cold/warm results identical" -ForegroundColor Green
Write-Host "Get-CoveAccountInfo OK" -ForegroundColor Green
