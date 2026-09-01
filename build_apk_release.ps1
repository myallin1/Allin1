# ================================================================
# build_apk_release.ps1 - build + package native APKs for the
# in-app update pipeline (AppUpdateChecker / update_service.dart)
#
# WHY THIS EXISTS
# The in-app "Update Available" banner (customer + hero home screens)
# compares the installed app's pubspec version against the tag_name of
# the latest release in github.com/myallin1/Allin1-update-release, and
# downloads whichever asset is named allin1-<flavor>.apk. If either the
# tag isn't ABOVE the installed version, or the asset isn't named
# exactly that, the update banner either never appears or 404s when
# tapped - this already happened once (see the "fix(critical): native
# APK update pipeline downloads 404" commit) and is easy to repeat by
# hand, so this script does the two error-prone steps for you:
#
#   1. Bumps the X.Y.Z part of pubspec.yaml's version (not just the
#      +build number deploy_web.ps1 bumps) - AppUpdateChecker only
#      compares X.Y.Z against the release tag, so if this number never
#      moves, no release will ever look "newer" to an already-installed
#      app.
#   2. Builds each Gradle product flavor (customer/hero/admin - see
#      android/app/build.gradle.kts productFlavors) as a signed release
#      APK, then copies each into release_apks/ under the EXACT
#      filename update_service.dart expects: allin1-<flavor>.apk.
#
# This script does NOT push to GitHub for you - it prints the exact
# `gh release create` command (or manual upload steps if `gh` isn't
# installed) using the version it just bumped to, so the tag can never
# drift out of sync with the APKs sitting next to it.
#
# Usage:
#   .\build_apk_release.ps1                  # bump patch, build all 3
#   .\build_apk_release.ps1 -Only hero        # bump patch, build one
#   .\build_apk_release.ps1 -NoVersionBump    # build with version as-is
# ================================================================

param(
    [ValidateSet('all', 'customer', 'hero', 'seller', 'admin')]
    [string]$Only = 'all',
    [switch]$NoVersionBump,
    # Off by default ON PURPOSE - see the speed note below.
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# SELLER ADDED (Aug 19 2026). This list had only customer/hero/admin,
# so `.\build_apk_release.ps1` silently produced three APKs and the
# seller build was never packaged - even though update_service.dart
# already defines sellerApkUrl and expects allin1-seller.apk to exist
# in the GitHub release. Any seller tapping Update would have hit a
# 404, which is the exact failure this script was written to prevent.
$flavors = @(
    @{ Name = 'customer'; Entry = 'lib/main_customer.dart' }
    @{ Name = 'hero';     Entry = 'lib/main_hero.dart' }
    @{ Name = 'seller';   Entry = 'lib/main_seller.dart' }
    @{ Name = 'admin';    Entry = 'lib/main_admin.dart' }
)

# ── SPEED: WHY THERE IS NO `flutter clean` IN THE LOOP ──────────
# The four flavors share one Dart codebase and one Gradle project.
# Gradle keeps a SEPARATE output directory per flavor, so building
# `hero` cannot overwrite `customer` - the outputs are
# app-customer-release.apk, app-hero-release.apk, and so on, and they
# sit side by side. Nothing needs cleaning between them.
#
# Cleaning between flavors would throw away the Gradle cache, the
# compiled Kotlin, and every downloaded dependency, then rebuild all
# of it four times over. That is the single easiest way to turn a
# ~6 minute all-flavor build into a ~25 minute one, for no benefit.
#
# Pass -Clean only when something is genuinely stale (after changing
# build.gradle, bumping the Flutter SDK, or adding a plugin). It runs
# ONCE, before the loop, never inside it.
if ($Clean) {
    Write-Host "[CLEAN] flutter clean (requested)" -ForegroundColor Yellow
    flutter clean
    flutter pub get
} else {
    # pub get is cheap and catches a stale package_config.json, which
    # is what caused the phantom "undefined AppUpdateGateService"
    # analyzer errors earlier.
    flutter pub get
}
$selected = if ($Only -eq 'all') { $flavors } else { $flavors | Where-Object { $_.Name -eq $Only } }

function Step-SemverPatch {
    # Bumps the X.Y.Z part of "version: X.Y.Z+N" - this is the number
    # AppUpdateChecker actually compares against the release tag (it
    # strips the +N build suffix via PackageInfo.version). Returns the
    # new "X.Y.Z" string so the release tag can be derived from it.
    $path = 'pubspec.yaml'
    $lines = Get-Content $path
    $newSemver = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            $patch = [int]$Matches[3] + 1
            $build = [int]$Matches[4] + 1
            $newSemver = "$major.$minor.$patch"
            $lines[$i] = "version: $newSemver+$build"
            Write-Host "  pubspec version -> $newSemver+$build" -ForegroundColor DarkCyan
            break
        }
    }

    if (-not $newSemver) {
        throw "Could not find a 'version: x.y.z+N' line in pubspec.yaml - refusing to guess a release tag."
    }

    Set-Content -Path $path -Value $lines -Encoding UTF8
    return $newSemver
}

function Read-CurrentSemver {
    $line = Get-Content 'pubspec.yaml' | Where-Object { $_ -match '^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$' } | Select-Object -First 1
    if ($line -match '^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$') { return $Matches[1] }
    throw "Could not read current version from pubspec.yaml."
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " ALLIN1 - NATIVE APK RELEASE BUILD" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

if ($NoVersionBump) {
    $semver = Read-CurrentSemver
    Write-Host "  Version bump skipped - building at $semver as-is." -ForegroundColor Yellow
} else {
    $semver = Step-SemverPatch
}

$releaseDir = 'release_apks'
if (Test-Path $releaseDir) {
    Remove-Item -Recurse -Force $releaseDir
}
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

$results = [ordered]@{}

foreach ($flavor in $selected) {
    $name = $flavor.Name
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $($name.ToUpper())" -ForegroundColor Cyan
    Write-Host "   flavor : $name" -ForegroundColor DarkCyan
    Write-Host "   entry  : $($flavor.Entry)" -ForegroundColor DarkCyan
    Write-Host "==================================================" -ForegroundColor Cyan

    flutter build apk --release --flavor $name -t $flavor.Entry

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  $name BUILD FAILED - see the Flutter/Gradle error above." -ForegroundColor Red
        $results[$name] = $false
        continue
    }

    # Gradle flavor output naming convention: app-<flavor>-release.apk
    $builtApk = "build\app\outputs\flutter-apk\app-$name-release.apk"
    if (-not (Test-Path $builtApk)) {
        Write-Host "  $name build reported success but $builtApk is missing - not packaging it." -ForegroundColor Red
        $results[$name] = $false
        continue
    }

    $destApk = Join-Path $releaseDir "allin1-$name.apk"
    Copy-Item $builtApk $destApk -Force
    $sizeMb = [Math]::Round((Get-Item $destApk).Length / 1MB, 1)
    Write-Host "  $name OK -> $destApk ($sizeMb MB)" -ForegroundColor Green
    $results[$name] = $true
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
foreach ($key in $results.Keys) {
    if ($results[$key]) {
        Write-Host "  $key : OK" -ForegroundColor Green
    } else {
        Write-Host "  $key : FAILED" -ForegroundColor Red
    }
}

if ($results.Values -contains $false) {
    Write-Host ""
    Write-Host "  At least one flavor failed - fix the error above before releasing." -ForegroundColor Red
    exit 1
}

$tag = "v$semver"
$apkPaths = (Get-ChildItem $releaseDir -Filter "*.apk" | ForEach-Object { "`"$($_.FullName)`"" }) -join ' '

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " NEXT STEP - publish the release" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Tag MUST be above every already-installed app's version," -ForegroundColor Yellow
Write-Host "  or the update banner will never appear. This build used $tag." -ForegroundColor Yellow
Write-Host ""

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "  GitHub CLI found - run this to publish:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "      gh release create $tag $apkPaths ``" -ForegroundColor White
    Write-Host "        --repo myallin1/Allin1-update-release ``" -ForegroundColor White
    Write-Host "        --title `"Allin1 $tag`" ``" -ForegroundColor White
    Write-Host "        --notes `"Release $tag`"" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "  GitHub CLI (gh) not found. Publish manually:" -ForegroundColor Yellow
    Write-Host "    1. Go to https://github.com/myallin1/Allin1-update-release/releases/new" -ForegroundColor White
    Write-Host "    2. Tag: $tag  (must match or exceed pubspec version above)" -ForegroundColor White
    Write-Host "    3. Upload all 4 files from .\$releaseDir\ WITHOUT renaming them -" -ForegroundColor White
    Write-Host "       allin1-customer.apk / allin1-hero.apk / allin1-seller.apk / allin1-admin.apk" -ForegroundColor White
    Write-Host "       are the exact names update_service.dart looks for." -ForegroundColor White
    Write-Host "    4. Publish release." -ForegroundColor White
    Write-Host ""
}

Write-Host "  Don't forget to commit the pubspec.yaml version bump:" -ForegroundColor Cyan
Write-Host "      git add pubspec.yaml; git commit -m `"chore: bump version to $semver for native release`"" -ForegroundColor White
Write-Host ""
