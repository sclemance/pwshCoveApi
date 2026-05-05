#Requires -Version 7.4
# Tests Connect-CoveApi and Get-CovePartnerBranding.
param(
    [string]$Username,
    [string]$Password
)

$credFile = Join-Path $PSScriptRoot 'credentials.ps1'
if (-not $Username -or -not $Password) {
    if (Test-Path $credFile) { . $credFile }
    if (-not $Username) { $Username = $testUsername }
    if (-not $Password) { $Password = $testPassword }
}
if (-not $Username -or -not $Password) { throw "Provide -Username/-Password or populate tests/credentials.ps1" }

Import-Module (Join-Path $PSScriptRoot '../coveApi.psm1') -Force

Write-Host "Connecting..." -ForegroundColor Cyan
$session = Connect-CoveApi -Username $Username -Password $Password

if (-not $session.Visa)      { Write-Host "[FAIL] No visa returned"      -ForegroundColor Red; exit 1 }
if ($session.PartnerId -le 0) { Write-Host "[FAIL] No PartnerId returned" -ForegroundColor Red; exit 1 }

Write-Host "  Visa:      $($session.Visa.Substring(0, 20))..." -ForegroundColor Green
Write-Host "  PartnerId: $($session.PartnerId)"                -ForegroundColor Green

Write-Host "Fetching partner branding..." -ForegroundColor Cyan
$branding = Get-CovePartnerBranding
if ($branding) {
    Write-Host "  ProductName: $($branding.ProductName)" -ForegroundColor Green
    Write-Host "  MainColor:   $($branding.MainColor)"   -ForegroundColor Green
} else {
    Write-Host "  [WARN] Branding returned null (non-fatal)" -ForegroundColor Yellow
}

Write-Host "Auth OK" -ForegroundColor Green
