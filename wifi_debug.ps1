# ================================================================
# wifi_debug.ps1 — Wireless ADB helper (Aug 17 2026)
# ================================================================
# Nizam: "yennoda 2 phones la cable disconnect agite iruku athan
# problem so ipaye wifi debugging um one step panni vachuklam"
#
# Cable debugging keeps dropping mid-`flutter run`, which kills the hot
# reload session and forces a fresh Gradle build every time. This sets
# up ADB over Wi-Fi once, then reconnects both phones with one command.
#
# USAGE
#   .\wifi_debug.ps1 pair      -> first-time setup for a NEW phone
#   .\wifi_debug.ps1 connect   -> reconnect saved phones (the daily one)
#   .\wifi_debug.ps1 list      -> show what's currently attached
#   .\wifi_debug.ps1 forget    -> clear saved phones
#
# Saved phone addresses live in wifi_debug_devices.txt next to this
# script (gitignored-friendly: it holds only LAN IPs, no secrets).
# ================================================================

param(
    [Parameter(Position = 0)]
    [ValidateSet('pair', 'connect', 'list', 'forget')]
    [string]$Action = 'connect'
)

$ErrorActionPreference = 'Stop'
$deviceFile = Join-Path $PSScriptRoot 'wifi_debug_devices.txt'

function Assert-Adb {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Write-Host "adb not found on PATH." -ForegroundColor Red
        Write-Host "It ships with Android Studio. Add this to PATH:" -ForegroundColor Yellow
        Write-Host "  $env:LOCALAPPDATA\Android\Sdk\platform-tools" -ForegroundColor Yellow
        exit 1
    }
}

function Show-Devices {
    Write-Host ""
    Write-Host "Attached devices:" -ForegroundColor Cyan
    adb devices -l
    Write-Host ""
    Write-Host "Run the seller app on one of them with:" -ForegroundColor DarkGray
    Write-Host "  flutter run -d <device-id> -t lib/main_seller.dart --flavor seller" -ForegroundColor DarkGray
}

Assert-Adb

switch ($Action) {

    'list' { Show-Devices }

    'forget' {
        if (Test-Path $deviceFile) { Remove-Item $deviceFile }
        Write-Host "Saved phones cleared." -ForegroundColor Green
    }

    'pair' {
        # Android 11+ path: no cable needed at all, not even once.
        Write-Host ""
        Write-Host "=== ON THE PHONE ===" -ForegroundColor Cyan
        Write-Host "  1. Settings -> Developer options -> Wireless debugging -> ON"
        Write-Host "  2. Tap 'Pair device with pairing code'"
        Write-Host "  3. Leave that popup OPEN - it shows an IP:PORT and a 6-digit code"
        Write-Host ""
        Write-Host "The PAIRING port and the CONNECT port are DIFFERENT." -ForegroundColor Yellow
        Write-Host "The popup shows the pairing one; the main Wireless debugging" -ForegroundColor Yellow
        Write-Host "screen shows the connect one. You need both." -ForegroundColor Yellow
        Write-Host ""

        $pairAddr = Read-Host "Pairing IP:PORT (from the popup)"
        $pairCode = Read-Host "6-digit pairing code"

        adb pair $pairAddr $pairCode
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Pairing failed. Check the phone and PC are on the SAME Wi-Fi." -ForegroundColor Red
            exit 1
        }

        Write-Host ""
        $connAddr = Read-Host "Now the CONNECT IP:PORT (main Wireless debugging screen)"
        adb connect $connAddr
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Connect failed." -ForegroundColor Red
            exit 1
        }

        # Remember it so 'connect' can reuse it tomorrow.
        $existing = @()
        if (Test-Path $deviceFile) { $existing = Get-Content $deviceFile }
        if ($existing -notcontains $connAddr) {
            Add-Content -Path $deviceFile -Value $connAddr
        }

        Write-Host ""
        Write-Host "Paired and saved: $connAddr" -ForegroundColor Green
        Write-Host "From now on just run:  .\wifi_debug.ps1 connect" -ForegroundColor Green
        Show-Devices
    }

    'connect' {
        if (-not (Test-Path $deviceFile)) {
            Write-Host "No saved phones yet. Run this first:" -ForegroundColor Yellow
            Write-Host "  .\wifi_debug.ps1 pair" -ForegroundColor Yellow
            exit 0
        }

        $addrs = Get-Content $deviceFile | Where-Object { $_.Trim() -ne '' }
        foreach ($addr in $addrs) {
            Write-Host "Connecting $addr ..." -ForegroundColor Cyan
            adb connect $addr
        }

        Write-Host ""
        Write-Host "If a phone says 'failed to connect', its PORT CHANGED." -ForegroundColor Yellow
        Write-Host "Android picks a new port every time Wireless debugging is" -ForegroundColor Yellow
        Write-Host "toggled off/on or the phone reboots. Re-run 'pair' for it." -ForegroundColor Yellow
        Show-Devices
    }
}
