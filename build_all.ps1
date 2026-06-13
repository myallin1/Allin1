# build_all.ps1 - Allin1 Super App
Set-Location "C:\Projects\all in one"
$env:PATH = "C:\Program Files\nodejs;" + $env:PATH
$FIREBASE = "C:\Users\nijja\AppData\Roaming\npm\firebase.cmd"

function Build-WebTarget {
  param(
    [string]$Label,
    [string]$TargetFile,
    [string]$OutputDir,
    [string]$ManifestName,
    [string]$ManifestShortName
  )

  Write-Host "[BUILD] $Label" -ForegroundColor Cyan

  if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Recurse -Force
  }

  flutter build web --release --target=$TargetFile
  if ($LASTEXITCODE -ne 0) {
    Write-Host "$Label build failed" -ForegroundColor Red
    exit 1
  }

  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
  Copy-Item "build\web\*" $OutputDir -Recurse -Force

  $mainJs = Join-Path $OutputDir "main.dart.js"
  if (-not (Test-Path $mainJs)) {
    Write-Host "$Label output is invalid: missing main.dart.js in $OutputDir" -ForegroundColor Red
    exit 1
  }

  $manifestPath = Join-Path $OutputDir "manifest.json"
  if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw
    $manifest = $manifest -replace '"name":\s*"[^"]*"', "`"name`": `"$ManifestName`""
    $manifest = $manifest -replace '"short_name":\s*"[^"]*"', "`"short_name`": `"$ManifestShortName`""
    $manifest | Set-Content $manifestPath
  }

  Write-Host "$Label OK -> $OutputDir" -ForegroundColor Green
}

Write-Host "=== ALLIN1 FULL BUILD ===" -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) { exit 1 }

flutter pub get
if ($LASTEXITCODE -ne 0) { exit 1 }

Build-WebTarget `
  -Label "CUSTOMER" `
  -TargetFile "lib/main_customer.dart" `
  -OutputDir "build/web_customer" `
  -ManifestName "Allin1 - Order and Ride" `
  -ManifestShortName "Allin1"

Build-WebTarget `
  -Label "HERO" `
  -TargetFile "lib/main_hero.dart" `
  -OutputDir "build/web_hero" `
  -ManifestName "Allin1 Hero" `
  -ManifestShortName "Hero"

Build-WebTarget `
  -Label "SELLER" `
  -TargetFile "lib/main_seller.dart" `
  -OutputDir "build/web_seller" `
  -ManifestName "Allin1 Grow" `
  -ManifestShortName "Grow"

Build-WebTarget `
  -Label "ADMIN" `
  -TargetFile "lib/main_admin.dart" `
  -OutputDir "build/web_admin" `
  -ManifestName "Allin1 HQ" `
  -ManifestShortName "HQ"

Write-Host "[DEPLOY] Firebase Hosting" -ForegroundColor Cyan
& $FIREBASE deploy --only hosting --project erode-super-app

Write-Host "Customer -> https://my-allin1.web.app" -ForegroundColor Green
Write-Host "Hero     -> https://hero-allin1.web.app" -ForegroundColor Blue
Write-Host "Seller   -> https://grow-allin1.web.app" -ForegroundColor Magenta
Write-Host "Admin    -> https://hq-allin1.web.app" -ForegroundColor Red
