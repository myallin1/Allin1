# ================================================================
# deploy_web.ps1 — build + deploy the web apps, safely
#
# Two things this exists to prevent, both of which bit us for real:
#
# 1. STALE build\web.
#    Hero and Customer both build into the SAME build\web folder. The
#    second build has to delete the first one's files before writing
#    its own, and Windows refuses to delete assets\assets\videos\
#    intro.mp4 while anything (Explorer's video thumbnailer, an
#    antivirus scan, a leftover dart.exe) has a handle on it. The build
#    then dies with errno 183 "file already exists" or errno 5 "access
#    is denied". Wiping build\web first means there is nothing to
#    delete, so the race cannot happen.
#
# 2. DEPLOYING A FAILED BUILD.
#    The old command list ran `firebase deploy` on the next line
#    regardless of whether the build had succeeded, so broken/partial
#    output kept going live and looked like an app bug. Every deploy
#    here is gated on the build's exit code.
#
# 3. DEPLOYING ONE APP'S CODE TO ANOTHER APP'S URL.
#    All four apps compile into the SAME build\web folder. If the
#    customer build fails while hero's output is still sitting there,
#    an ungated `firebase deploy --only hosting:customer` publishes
#    HERO's code to the customer URL. Wiping the folder first and
#    gating on exit code makes that impossible.
#
# Which app is which is decided by two paired values that are written
# out literally below — the entry point (-t lib/main_X.dart) and the
# hosting target (--only hosting:X). They are never derived or guessed.
#
# Usage:
#   .\deploy_web.ps1                 # all four apps (hero, customer, seller, admin)
#   .\deploy_web.ps1 -Only admin     # one app
#   .\deploy_web.ps1 -NoDeploy       # build only, don't publish
# ================================================================

param(
    [switch]$NoDeploy,
    [ValidateSet('default', 'all', 'hero', 'customer', 'admin', 'seller')]
    [string]$Only = 'all'
)

# The single source of truth for entry-point <-> hosting-target pairing.
$apps = @(
    @{ Name = 'HERO';     Entry = 'lib/main_hero.dart';     Target = 'hero' }
    @{ Name = 'CUSTOMER'; Entry = 'lib/main_customer.dart'; Target = 'customer' }
    @{ Name = 'ADMIN';    Entry = 'lib/main_admin.dart';    Target = 'admin' }
    @{ Name = 'SELLER';   Entry = 'lib/main_seller.dart';   Target = 'seller' }
)

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

function Step-BuildNumber {
    # Bumps the +N build number in pubspec.yaml's `version:` line.
    #
    # This is what makes the in-app UPDATE button possible. Flutter
    # writes that number into build/web/version.json, and
    # web_version_checker.dart decides "a new build is live" by seeing
    # that number change. If it never changes, every deploy looks
    # identical to the running app and no update is ever offered.
    #
    # Doing it here rather than by hand for the same reason the
    # build\web wipe is here: anything that has to be remembered every
    # single time eventually gets forgotten.
    $path = 'pubspec.yaml'
    $lines = Get-Content $path
    $updated = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
            $semver = $Matches[1]
            $build = [int]$Matches[2] + 1
            $lines[$i] = "version: $semver+$build"
            Write-Host "  version -> $semver+$build" -ForegroundColor DarkCyan
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        Write-Host "  Could not find a 'version: x.y.z+N' line in pubspec.yaml." -ForegroundColor Yellow
        Write-Host "  Update detection needs that number to change each deploy." -ForegroundColor Yellow
        return
    }

    Set-Content -Path $path -Value $lines -Encoding UTF8
}

function Clear-BuildWeb {
    if (Test-Path build\web) {
        Remove-Item -Recurse -Force build\web -ErrorAction SilentlyContinue
    }
    if (Test-Path build\web) {
        Write-Host ""
        Write-Host "  Could not delete build\web - a program is holding a file." -ForegroundColor Yellow
        Write-Host "  Close File Explorer windows inside this project, then run:" -ForegroundColor Yellow
        Write-Host "      taskkill /F /IM dart.exe" -ForegroundColor Yellow
        Write-Host "  If it still fails, restart the computer." -ForegroundColor Yellow
        Write-Host ""
        return $false
    }
    return $true
}

function Build-And-Deploy {
    param([string]$Name, [string]$Entry, [string]$Target)

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $Name" -ForegroundColor Cyan
    Write-Host "   source : $Entry" -ForegroundColor DarkCyan
    Write-Host "   target : hosting:$Target" -ForegroundColor DarkCyan
    Write-Host "==================================================" -ForegroundColor Cyan

    if (-not (Clear-BuildWeb)) { return $false }

    # REVERTED (Aug 9 2026): --no-wasm-dry-run was added here to skip
    # the "Wasm dry run succeeded..." message's extra compile pass,
    # believing it would speed builds back up. It did the opposite —
    # this is a confirmed Flutter SDK bug (flutter/flutter#174149):
    # passing --no-wasm-dry-run doesn't skip the dry run at all, it
    # makes the build compile a FULL Wasm build in addition to the
    # normal JS build, which is far slower, not faster. That's exactly
    # what turned this build even slower after the "fix." Removed the
    # flag entirely — back to plain `flutter build web -t $Entry`. The
    # "Wasm dry run succeeded" message is cosmetic/informational only
    # (the dry run itself is cheap); it is NOT the real slowdown cause.
    # If build time is still a genuine problem, the real levers are:
    # (1) build only the flavor(s) actually changed via
    # `.\deploy_web.ps1 -Only <flavor>` instead of all 4 every time,
    # (2) investigate disk/antivirus contention on Clear-BuildWeb's
    # wipe-and-rewrite of build\web on Windows, (3) check whether the
    # Flutter/Dart SDK itself was recently upgraded to a slower version.
    # SAFE speed lever (Aug 10 2026, added instead of the reverted
    # --no-wasm-dry-run): --no-tree-shake-icons skips the pass that
    # scans every icon-font glyph reference to strip unused ones. That
    # scan is real, measurable compile time on apps with a lot of
    # Icons.* usage (this app has hundreds across 4 flavors) — skipping
    # it trades a slightly larger icon-font file (kept full, not
    # per-app-trimmed) for faster builds. Safe: it does not change
    # which icons render, only whether unused ones are pruned from the
    # font file. If bundle size ever becomes the bottleneck instead of
    # build time, remove this flag to get tree-shaking back.
    flutter build web -t $Entry --no-tree-shake-icons

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  $Name BUILD FAILED - nothing deployed." -ForegroundColor Red
        Write-Host "  Scroll up for the real error (look above the stack trace)." -ForegroundColor Red
        return $false
    }

    # All four apps build from the SAME web/ folder, so Flutter always
    # writes the one shared web/manifest.json into build/web/ — every
    # installed PWA showed the identical "NJ BAPX / Allin1" name/icon
    # label, with no way to tell customer/hero/seller/admin apart on a
    # phone's home screen. Fix: swap in this app's own manifest (see
    # web/manifests/manifest_<target>.json) right after the build,
    # overwriting the generic one before anything gets deployed.
    $manifestSource = "web\manifests\manifest_$Target.json"
    if (Test-Path $manifestSource) {
        Copy-Item -Path $manifestSource -Destination 'build\web\manifest.json' -Force
        Write-Host "  Applied $Target's own PWA manifest (distinct app name/icon)." -ForegroundColor DarkCyan
    } else {
        Write-Host "  No web\manifests\manifest_$Target.json found - using the shared manifest.json." -ForegroundColor Yellow
    }

    # These three are the ones that have actually gone missing before.
    # assets\.env matters most: flutter_dotenv fetches it over HTTP at
    # runtime, and without it the Ola Maps key reads as empty and place
    # search silently falls back to wrong results.
    $required = @(
        'build\web\manifest.json',
        'build\web\flutter_service_worker.js',
        'build\web\assets\.env'
    )
    $missing = $required | Where-Object { -not (Test-Path $_) }

    if ($missing) {
        Write-Host ""
        Write-Host "  Build succeeded but these are MISSING:" -ForegroundColor Red
        $missing | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
        Write-Host "  Not deploying an incomplete build." -ForegroundColor Red
        return $false
    }

    $count = (Get-ChildItem build\web -Recurse -File).Count
    Write-Host "  Build OK - $count files, all required files present." -ForegroundColor Green

    if ($NoDeploy) {
        Write-Host "  -NoDeploy set, skipping publish." -ForegroundColor Yellow
        return $true
    }

    firebase deploy --only "hosting:$Target"

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  ================================================" -ForegroundColor Red
        Write-Host "  $Name DEPLOY FAILED - scroll up for the real error" -ForegroundColor Red
        Write-Host "  (it's printed directly above this line, from the" -ForegroundColor Red
        Write-Host "  'firebase deploy' command itself)." -ForegroundColor Red
        Write-Host "  ================================================" -ForegroundColor Red
        return $false
    }

    Write-Host "  $Name deployed." -ForegroundColor Green
    return $true
}

# Work out which apps to run, then SHOW the plan before doing anything,
# so it is obvious up front exactly which source builds to which URL and
# nothing is being mixed up.
$selected = switch ($Only) {
    'default'  { $apps }
    'all'      { $apps }
    default    { $apps | Where-Object { $_.Target -eq $Only } }
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " PLAN" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
foreach ($app in $selected) {
    Write-Host ("  {0,-9} {1,-26} -> hosting:{2}" -f $app.Name, $app.Entry, $app.Target)
}
if ($NoDeploy) {
    Write-Host "  (build only - nothing will be published)" -ForegroundColor Yellow
}
Write-Host ""

# Bumped once for the whole run, not per app, so every app in this
# deploy reports the same version — they are the same release.
if (-not $NoDeploy) {
    Step-BuildNumber
    Write-Host ""
}

$results = [ordered]@{}
foreach ($app in $selected) {
    $results[$app.Name] = Build-And-Deploy $app.Name $app.Entry $app.Target
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
Write-Host ""
if ($results.Values -notcontains $false -and -not $NoDeploy) {
    Write-Host "  Now verify in the browser (cache-buster matters):" -ForegroundColor Cyan
    Write-Host "      https://my-allin1.web.app/assets/.env?v=2" -ForegroundColor Cyan
    Write-Host "  You should see the real .env text, not the app page." -ForegroundColor Cyan
    Write-Host ""
}
