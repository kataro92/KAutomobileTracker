#requires -Version 5.1
<#
.SYNOPSIS
  Same role as update_model.sh: BDD100K fine-tune -> CoreML -> per-user models folder.
  See scripts/train_bdd100k_finetune.py.

.EXAMPLE
  $env:BDD100K_DIR = "$env:USERPROFILE\datasets\bdd100k"
  .\update_model.ps1

.EXAMPLE
  .\update_model.ps1 --dry-run
  .\update_model.ps1 --epochs 50 --bundle

.NOTES
  Env: PYTHON_TRAIN, SKIP_DEPS=1, NO_INSTALL=1, BDD100K_DIR
  If activation is blocked: powershell -ExecutionPolicy Bypass -File .\update_model.ps1
#>

$ErrorActionPreference = 'Stop'

function Test-IsWindowsPlatform {
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    return [bool]$IsWindows
  }
  return $env:OS -eq 'Windows_NT'
}

function Test-LooksLikeBdd100k {
  param([string]$Path)
  # Match scripts/train_bdd100k_finetune.py discover_bdd100k_layout() (shallow + bounded deep search).
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
  $fullRoot = (Resolve-Path -LiteralPath $Path).Path
  function Test-HasMonolithicBddLabelsJson {
    param([string]$LabelsDir)
    if (-not (Test-Path -LiteralPath $LabelsDir -PathType Container)) { return $false }
    try {
      foreach ($f in [System.IO.Directory]::EnumerateFiles($LabelsDir, '*.json')) {
        $name = [System.IO.Path]::GetFileName($f)
        if ([string]::Equals($name, 'bdd100k_labels_images_train.json', [System.StringComparison]::OrdinalIgnoreCase)) {
          return $true
        }
      }
    } catch {
      return $false
    }
    return $false
  }
  $roots = @($fullRoot)
  $nameCandidates = @('bdd100k', 'bdd100k_labels', 'bdd100k_labels_release')
  foreach ($sub in $nameCandidates) {
    $child = Join-Path $fullRoot $sub
    if (Test-Path -LiteralPath $child -PathType Container) { $roots += $child }
  }
  # Common local layout: images in .data\bdd100k and labels in sibling .data\bdd100k_labels_release.
  $parent = Split-Path -Path $fullRoot -Parent
  if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) {
    foreach ($sub in $nameCandidates) {
      $sib = Join-Path $parent $sub
      if (Test-Path -LiteralPath $sib -PathType Container) { $roots += $sib }
    }
  }
  $roots = @($roots | Select-Object -Unique)
  foreach ($r in $roots) {
    foreach ($detRel in @(
        @('labels', 'det_20'),
        @('bdd100k', 'labels', 'det_20'),
        @('labels', 'bdd100k', 'det_20')
      )) {
      $det20 = $r
      foreach ($part in $detRel) { $det20 = Join-Path $det20 $part }
      $train = Join-Path $det20 'train'
      if ((Test-Path -LiteralPath $det20 -PathType Container) -and (Test-Path -LiteralPath $train -PathType Container)) {
        return $true
      }
    }
    foreach ($labelsBase in @(
        (Join-Path $r 'labels'),
        (Join-Path (Join-Path $r 'bdd100k') 'labels'),
        (Join-Path (Join-Path $r 'labels') 'bdd100k')
      )) {
      if (Test-HasMonolithicBddLabelsJson -LabelsDir $labelsBase) { return $true }
    }
  }
  $maxDepth = 16
  $maxVisits = 100000
  $visits = 0
  $q = [System.Collections.Queue]::new()
  [void]$q.Enqueue(@($fullRoot, 0))
  while ($q.Count -gt 0 -and $visits -lt $maxVisits) {
    $item = $q.Dequeue()
    $dir = [string]$item[0]
    $depth = [int]$item[1]
    $visits++
    if ($depth -gt $maxDepth) { continue }
    $leaf = Split-Path -Path $dir -Leaf
    # Folder casing varies (Det_20, TRAIN); -eq would miss on NTFS with non-lowercase names.
    if ($leaf -ieq 'det_20') {
      try {
        foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
          if ([string]::Equals([System.IO.Path]::GetFileName($sub), 'train', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
          }
        }
      } catch {
        continue
      }
    }
    if ([string]::Equals($leaf, 'labels', [System.StringComparison]::OrdinalIgnoreCase)) {
      if (Test-HasMonolithicBddLabelsJson -LabelsDir $dir) { return $true }
    }
    try {
      foreach ($child in [System.IO.Directory]::EnumerateDirectories($dir)) {
        [void]$q.Enqueue(@($child, $depth + 1))
      }
    } catch {
      continue
    }
  }
  return $false
}

function Resolve-Bdd100kDir {
  param([string]$RepoRoot)
  if ($env:BDD100K_DIR) {
    $p = $env:BDD100K_DIR.Trim()
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
      Write-Error "BDD100K_DIR is not a directory: $p"
    }
    $full = (Resolve-Path -LiteralPath $p).Path
    if (Test-LooksLikeBdd100k $full) {
      return $full
    }
    Write-Error "BDD100K_DIR does not look like BDD100K labels: $full (need ...\det_20\train or labels\bdd100k_labels_images_train.json; zips may be nested). See https://doc.bdd100k.com/"
  }
  foreach ($p in @(
      (Join-Path $RepoRoot '.data'),
      (Join-Path $RepoRoot '.data\bdd100k'),
      (Join-Path $RepoRoot 'bdd100k'),
      (Join-Path $env:USERPROFILE 'datasets\bdd100k'),
      (Join-Path $env:USERPROFILE 'bdd100k')
    )) {
    if ((Test-Path -LiteralPath $p -PathType Container) -and (Test-LooksLikeBdd100k $p)) {
      Write-Host "Using BDD100K dir: $p"
      return (Resolve-Path -LiteralPath $p).Path
    }
  }
  Write-Host "No BDD100K dataset found. Download: https://doc.bdd100k.com/download.html" -ForegroundColor Yellow
  Write-Host "Set BDD100K_DIR or place data under one of:" -ForegroundColor Yellow
  Write-Host "  $(Join-Path $RepoRoot '.data') or $(Join-Path $RepoRoot '.data\bdd100k')" -ForegroundColor Yellow
  Write-Host "  $(Join-Path $RepoRoot 'bdd100k')" -ForegroundColor Yellow
  Write-Host "  $(Join-Path $env:USERPROFILE 'datasets\bdd100k')" -ForegroundColor Yellow
  Write-Host "  $(Join-Path $env:USERPROFILE 'bdd100k')" -ForegroundColor Yellow
  exit 1
}

function Get-TrainPythonExe {
  if ($env:PYTHON_TRAIN) {
    $cmd = Get-Command $env:PYTHON_TRAIN -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Error "PYTHON_TRAIN not found: $($env:PYTHON_TRAIN)" }
    return $cmd.Path
  }
  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
      foreach ($v in @('3.12', '3.13', '3.11')) {
        $verLine = & py "-$v" -c "import sys; print(sys.version_info[0], sys.version_info[1])" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        $parts = @($verLine.Trim() -split '\s+')
        if ($parts.Count -lt 2) { continue }
        $maj = [int]$parts[0]
        $min = [int]$parts[1]
        if ($maj -eq 3 -and $min -lt 14) {
          return (& py "-$v" -c "import sys; print(sys.executable)" 2>$null).Trim()
        }
      }
    } finally {
      $ErrorActionPreference = $prevEap
    }
  }
  foreach ($name in @('python3.12', 'python3.13', 'python3.11', 'python')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    $verLine = & $cmd.Path -c "import sys; print(sys.version_info[0], sys.version_info[1])" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $parts = @($verLine.Trim() -split '\s+')
    if ($parts.Count -lt 2) { continue }
    $maj = [int]$parts[0]
    $min = [int]$parts[1]
    if ($maj -eq 3 -and $min -lt 14) {
      return $cmd.Path
    }
  }
  Write-Error @"
Need Python 3.11-3.13 (prebuilt PyTorch/SciPy wheels). Python 3.14+ often fails on SciPy.
Install from https://www.python.org/downloads/ or use the Python launcher: py -3.12
Optional: set PYTHON_TRAIN to the full path of python.exe
"@
}

function Test-VenvPythonOk {
  param([string]$VenvRoot)
  $py = $null
  if (Test-IsWindowsPlatform) {
    $py = Join-Path $VenvRoot 'Scripts\python.exe'
  }
  if (-not $py -or -not (Test-Path -LiteralPath $py)) {
    $py = Join-Path $VenvRoot 'bin\python3'
    if (-not (Test-Path -LiteralPath $py)) { $py = Join-Path $VenvRoot 'bin\python' }
  }
  if (-not (Test-Path -LiteralPath $py)) { return $false }
  $verLine = & $py -c "import sys; print(sys.version_info[0], sys.version_info[1])"
  $parts = @($verLine.Trim() -split '\s+')
  $maj = [int]$parts[0]
  $min = [int]$parts[1]
  return ($maj -eq 3 -and $min -lt 14)
}

function Enter-Venv {
  param([string]$VenvRoot)
  if (Test-IsWindowsPlatform) {
    $act = Join-Path $VenvRoot 'Scripts\Activate.ps1'
    if (-not (Test-Path -LiteralPath $act)) {
      Write-Error "Missing $act - recreate .venv-train with: python -m venv .venv-train"
    }
    . $act
    return
  }
  $bin = Join-Path $VenvRoot 'bin'
  if (-not (Test-Path -LiteralPath $bin)) {
    Write-Error "Unix venv missing bin/. On macOS/Linux use ./update_model.sh"
  }
  $env:PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
  $env:VIRTUAL_ENV = $VenvRoot
}

$Root = $PSScriptRoot
Set-Location -LiteralPath $Root

$VenvPath = Join-Path $Root '.venv-train'
$pyExe = Get-TrainPythonExe

if (Test-Path -LiteralPath $VenvPath -PathType Container) {
  if (-not (Test-VenvPythonOk $VenvPath)) {
    Write-Error "Remove incompatible venv and rerun: Remove-Item -Recurse -Force .venv-train"
  }
} else {
  Write-Host "Creating venv at $VenvPath using $pyExe"
  & $pyExe -m venv $VenvPath
}

Enter-Venv -VenvRoot $VenvPath

if (-not $env:SKIP_DEPS) {
  python -m pip install -r (Join-Path $Root 'scripts\requirements-train.txt')
}

$scriptPath = Join-Path $Root 'scripts\train_bdd100k_finetune.py'
$remaining = @()
if ($args -and $args.Count -gt 0) {
  $remaining = @($args)
}

$hasDry = ($remaining -contains '--dry-run')
$hasBdd = $false
$hasInstall = ($remaining -contains '--install')
for ($i = 0; $i -lt $remaining.Count; $i++) {
  if ($remaining[$i] -eq '--bdd100k-dir') { $hasBdd = $true; break }
  if ($remaining[$i] -like '--bdd100k-dir=*') { $hasBdd = $true; break }
}

$cmd = @('python', $scriptPath)
if (-not $hasDry) {
  if (-not $env:NO_INSTALL -and -not $hasInstall) {
    $cmd += '--install'
  }
  if (-not $hasBdd) {
    $bdd = Resolve-Bdd100kDir -RepoRoot $Root
    $cmd += '--bdd100k-dir'
    $cmd += $bdd
  }
}
$cmd += $remaining

Write-Host ($cmd -join ' ')
$exe, $argList = $cmd[0], @($cmd | Select-Object -Skip 1)
& $exe @argList
exit $LASTEXITCODE
