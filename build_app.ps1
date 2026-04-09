#requires -Version 5.1
<#
.SYNOPSIS
  Same intent as build_app.sh: produce KAutomobileTracker.app via swift build (macOS only).

.NOTES
  Package.swift declares platforms [.macOS(.v14)] only. On Windows, use update_model.ps1 for
  training/export; build the SwiftUI app on a Mac (Terminal: ./build_app.sh or Xcode).
#>

$ErrorActionPreference = 'Stop'

function Test-IsWindowsPlatform {
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    return [bool]$IsWindows
  }
  return $env:OS -eq 'Windows_NT'
}

if (Test-IsWindowsPlatform) {
  Write-Host @"
KAutomobileTracker targets macOS 14+ only (see Package.swift).

On Windows you can train / export CoreML with:
  .\update_model.ps1

To build KAutomobileTracker.app, use macOS:
  ./build_app.sh
or open the package in Xcode on a Mac.
"@ -ForegroundColor Yellow
  exit 1
}

$Root = $PSScriptRoot
Set-Location -LiteralPath $Root

$swift = Get-Command swift -ErrorAction SilentlyContinue
if (-not $swift) {
  Write-Error "swift not found in PATH. Install Xcode Command Line Tools on macOS, then retry."
}

$arch = (& uname -m).Trim()
if (-not $arch) { $arch = 'arm64' }

& swift build -c release --arch $arch
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bin = Join-Path $Root ".build/${arch}-apple-macosx/release/KAutomobileTracker"
if (-not (Test-Path -LiteralPath $bin)) {
  $bin = Join-Path $Root '.build/release/KAutomobileTracker'
}
if (-not (Test-Path -LiteralPath $bin)) {
  Write-Error "Binary not found after swift build: expected under .build/"
}

$app = Join-Path $Root 'KAutomobileTracker.app'
Remove-Item -LiteralPath $app -Recurse -Force -ErrorAction SilentlyContinue

$macosDir = Join-Path $app 'Contents/MacOS'
$resDir = Join-Path $app 'Contents/Resources'
New-Item -ItemType Directory -Path $macosDir -Force | Out-Null
New-Item -ItemType Directory -Path $resDir -Force | Out-Null

Copy-Item -LiteralPath $bin -Destination (Join-Path $macosDir 'KAutomobileTracker') -Force
Copy-Item -LiteralPath (Join-Path $Root 'Sources/KAutomobileTracker/Resources/Info.plist') `
  -Destination (Join-Path $app 'Contents/Info.plist') -Force

Write-Host "Built $app"
