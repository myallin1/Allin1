# deploy_all.ps1 - Build & Deploy All Apps for Allin1
Set-Location "C:\Projects\all in one"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Allin1 Multi-Site Build + Deploy     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Running clean multi-target build..." -ForegroundColor Yellow
& ".\build_all.ps1"

if ($LASTEXITCODE -ne 0) {
  Write-Host "Deployment aborted because build_all.ps1 failed." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "Deployment complete." -ForegroundColor Green
Write-Host "Customer: https://my-allin1.web.app" -ForegroundColor White
Write-Host "Hero:     https://hero-allin1.web.app" -ForegroundColor White
Write-Host "Seller:   https://grow-allin1.web.app" -ForegroundColor White
Write-Host "Admin:    https://hq-allin1.web.app" -ForegroundColor White
