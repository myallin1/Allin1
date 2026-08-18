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
    # FIX (Aug 10 2026 — root cause of "SELLER DEPLOY FAILED" printing
    # in red, then SUMMARY printing "SELLER : OK" two lines later): a
    # bare external-command call inside a PowerShell function sends its
    # stdout into the FUNCTION'S OWN return/output stream, not just the
    # console — nothing here was redirecting it. So `$results[$app.Name]
    # = Build-And-Deploy ...` was capturing an ARRAY containing every
    # line flutter/firebase printed PLUS the real $true/$false, and
    # `if ($results[$key])` in the SUMMARY loop just checks "is this a
    # non-empty array" — which is ALWAYS true, regardless of whether the
    # real value buried inside it was $false. This has silently been
    # true for every run, all along; it only became visible now because
    # this is the first genuine deploy failure to actually test it.
    # `| Out-Host` sends the command's output straight to the console
    # (identical visible behavior, real-time streaming preserved) WITHOUT
    # adding it to the function's output stream — so only the explicit
    # `return $true` / `return $false` below ever reach $results now.
    # FIX (Aug 11 2026 — Nizam's "5 to 8 sec white display" report):
    # --no-tree-shake-icons REMOVED. I added it earlier purely to speed up
    # OUR build, but measuring the output showed the real cost: it ships
    # the entire MaterialIcons font at 1.6 MB instead of tree-shaking it
    # down to the ~20 KB of glyphs this app actually uses. That 1.6 MB is
    # paid by every customer on every cold load, over mobile data, to save
    # us a few seconds at build time. Wrong trade — build time is our
    # inconvenience, download time is the customer's.
    # ================================================================
    # WIPE build\web BEFORE EVERY BUILD  (Aug 11 2026)
    # ================================================================
    # ROOT CAUSE of Nizam's "customer PWA kulla admin PWA deploy
    # aiduchu": all four flavors build into the SAME build\web folder,
    # and nothing ever cleared it between them. So the folder always held
    # the LAST SUCCESSFUL flavor's output.
    #
    # The $LASTEXITCODE guard below is supposed to stop a failed build
    # from deploying — but `flutter` on Windows is flutter.bat, and batch
    # wrappers are notoriously unreliable about propagating exit codes
    # through a pipeline. If that check ever returns 0 on a failed build,
    # every downstream safety check still PASSES (manifest present,
    # service worker present, .env present, file count > 0) because the
    # previous flavor's complete, valid build is still sitting there —
    # and the script cheerfully deploys ADMIN to the CUSTOMER target.
    #
    # Wiping first makes that impossible: after a failed build the folder
    # is empty, so the required-files check below fails loudly instead of
    # silently shipping the wrong app. Defence in depth — we do not rely
    # on the exit code alone for something this destructive.
    if (Test-Path 'build\web') {
        Remove-Item -Recurse -Force 'build\web'
        Write-Host "  Cleared build\web (prevents deploying another flavor's output)." -ForegroundColor DarkGray
    }

    # UPDATED (Aug 12 2026 — Aug 15 Erode launch hardening). Flags:
    #   --release           explicit (it is the default, but be certain).
    #   --tree-shake-icons  strips unused icon-font glyphs. NOTE: an
    #                       earlier --no-tree-shake-icons build-speed hack
    #                       was correctly reverted; do not reintroduce it,
    #                       it costs real payload size.
    #   --no-source-maps    source maps are large AND publicly served.
    #   --pwa-strategy=none stops Flutter generating flutter_service_worker.js,
    #                       which would otherwise compete with our own
    #                       web/pwa_fallback_sw.js (the cache-first worker
    #                       that makes repeat opens cost zero bytes).
    flutter build web --release -t $Entry --tree-shake-icons --no-source-maps --pwa-strategy=none | Out-Host

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
    # ================================================================
    # STAMP THE SERVICE-WORKER CACHE NAME  (Aug 11 2026)
    # ================================================================
    # Makes the cache name unique per flavor AND per deploy. Without
    # this, all four apps shared the cache name 'allin1-offline-v2', so
    # once the customer origin had cached ADMIN's main.dart.js (from the
    # wrong-flavor deploy), stale-while-revalidate kept serving it
    # forever — redeploying the correct build changed nothing, because
    # the cache name never changed and the SW never re-fetched.
    #
    # Stamping guarantees a fresh cache on every single deploy, so a
    # customer picks up new code on their FIRST launch after deploy.
    $swPath = 'build\web\pwa_fallback_sw.js'
    if (Test-Path $swPath) {
        $stamp = "allin1-$Target-$(Get-Date -Format 'yyyyMMddHHmmss')"
        (Get-Content $swPath -Raw).Replace('__ALLIN1_CACHE_VERSION__', $stamp) |
            Set-Content $swPath -NoNewline
        Write-Host "  Service-worker cache stamped: $stamp" -ForegroundColor DarkCyan
    } else {
        Write-Host "  WARNING: $swPath not found - cache not stamped." -ForegroundColor Yellow
    }

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

    # ================================================================
    # IDENTITY CHECK — is this bundle actually the flavor we think?
    # ================================================================
    # Second line of defence for the same bug. The manifest we copied in
    # above is flavor-specific, so reading it back and confirming it
    # matches $Target proves build\web really holds THIS app and not a
    # leftover. Cheap, and it turns a silent wrong-app deploy (which a
    # customer discovers, not us) into a loud refusal here.
    # SIMPLIFIED (Aug 11 2026 — my previous timestamp version false-aborted
    # a perfectly good customer build).
    #
    # The earlier check compared main.dart.js's LastWriteTime against a
    # $buildStartedAt stamp. That was over-engineered AND fragile: any
    # clock/timezone/DST quirk, or $buildStartedAt being $null for a
    # scoping reason, makes the comparison fail and blocks a valid
    # deploy. Blocking a good build is its own outage.
    #
    # It was also redundant. We now DELETE build\web before every build
    # (see the wipe above), so anything present afterwards is by
    # definition output from THIS build — freshness is guaranteed
    # structurally, not by comparing timestamps. A plain existence check
    # is therefore both simpler and strictly more reliable: if the build
    # failed, the folder is empty and this catches it.
    if (-not (Test-Path 'build\web\main.dart.js')) {
        Write-Host ""
        Write-Host "  ABORT: build\web\main.dart.js not found after build." -ForegroundColor Red
        Write-Host "  build\web was wiped before this build, so an empty/partial" -ForegroundColor Red
        Write-Host "  folder means the build did not really succeed." -ForegroundColor Red
        Write-Host "  Refusing to deploy - this is how ADMIN once shipped to the CUSTOMER URL." -ForegroundColor Red
        return $false
    }

    $count = (Get-ChildItem build\web -Recurse -File).Count
    Write-Host "  Build OK - $count files, verified as '$Target'." -ForegroundColor Green

    if ($NoDeploy) {
        Write-Host "  -NoDeploy set, skipping publish." -ForegroundColor Yellow
        return $true
    }

    # Same fix as the flutter build call above — Out-Host keeps the
    # real-time visible deploy log identical, just stops it polluting
    # this function's return value.
    firebase deploy --only "hosting:$Target" | Out-Host

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

# ================================================================
# REGENERATE THE AI'S APP KNOWLEDGE  (Aug 17 2026)
# ================================================================
# Nizam: "namma oru new update vittalum athuvum namma ai ku theriyanum".
#
# tools/gen_app_knowledge.dart reads the repository (collections, RTDB
# nodes, routes, screens, services, pubspec version) and rewrites
# lib/config/app_knowledge.dart, which is injected into every AI
# persona's system prompt.
#
# It runs HERE — before the builds, after the version bump — so it is
# structurally impossible to ship app code and stale AI knowledge in the
# same deploy. That is the entire point: a briefing somebody has to
# remember to update is a briefing that will be wrong.
#
# Non-fatal by design. If dart is missing from PATH, the deploy still
# proceeds with the previously generated file, which is out of date but
# valid. Blocking a deploy over an assistant's context would be the
# wrong trade.
Write-Host "Regenerating AI app knowledge..." -ForegroundColor Cyan
dart run tools/gen_app_knowledge.dart | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "  WARNING: could not regenerate app_knowledge.dart." -ForegroundColor Yellow
    Write-Host "  Deploy continues with the existing file (AI knowledge may be stale)." -ForegroundColor Yellow
}
Write-Host ""

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
