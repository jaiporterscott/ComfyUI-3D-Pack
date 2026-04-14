#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ComfyUI + 3D Pipeline - Full Windows Installer
    Installs Python 3.11, Git, VS 2022 Build Tools, ComfyUI, and 20 custom
    nodes for a complete text-to-3D pipeline using PyTorch 2.7.0 + CUDA 12.8.

.DESCRIPTION
    Run as Administrator:
      Right-click PowerShell -> Run as Administrator
      Set-ExecutionPolicy Bypass -Scope Process -Force
      .\install-comfyui-3d-pipeline.ps1

    Install into existing ComfyUI (e.g. StabilityMatrix):
      .\install-comfyui-3d-pipeline.ps1 -InstallDir "E:\StabilityMatrix\Packages\ComfyUI" -SkipComfyUI

    Optional flags:
      -InstallDir "D:\ComfyUI"   Custom install location
      -SkipComfyUI               Don't clone ComfyUI (use existing install)
      -SkipCUDA                  Skip CUDA toolkit prompt
      -SkipPython                Skip Python install
      -SkipVS                    Skip VS Build Tools
      -SkipGit                   Skip Git install

.NOTES
    Requires: Windows 10/11, NVIDIA GPU (driver 528+), Internet, Admin rights
    Uses: PyTorch 2.7.0 + cu126, official ComfyUI-3D-Pack repo
    Install time: 30-90 minutes depending on internet speed
#>

param(
    [string]$InstallDir = "$env:USERPROFILE\ComfyUI",
    [switch]$SkipComfyUI,
    [switch]$SkipCUDA,
    [switch]$SkipPython,
    [switch]$SkipVS,
    [switch]$SkipGit
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# =====================================================================
# Configuration - Official 3D-Pack stack (known working)
# =====================================================================
$PYTHON_VERSION    = "3.11.9"
$PYTHON_URL        = "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-amd64.exe"
$GIT_URL           = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe"
$VS_BUILDTOOLS_URL = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
$DOWNLOADS_DIR     = "$env:TEMP\comfyui-installer"

# PyTorch stack (matches official ComfyUI-3D-Pack)
$TORCH_VERSION     = "2.7.0"
$TORCHVISION_VER   = "0.22.0"
$TORCHAUDIO_VER    = "2.7.0"
$XFORMERS_VER      = "0.0.30"
$CU_TAG            = "cu126"
$TORCH_INDEX       = "https://download.pytorch.org/whl/$CU_TAG"
$PYG_LINKS         = "https://data.pyg.org/whl/torch-$TORCH_VERSION+$CU_TAG.html"

# =====================================================================
# Helper functions
# =====================================================================
function Write-Step { param([string]$msg) Write-Host "`n========================================" -ForegroundColor Cyan; Write-Host "  $msg" -ForegroundColor Cyan; Write-Host "========================================" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }

function Download-File {
    param([string]$Url, [string]$OutFile)
    if (Test-Path $OutFile) { Write-OK "Already downloaded: $(Split-Path $OutFile -Leaf)"; return }
    Write-Host "  Downloading $(Split-Path $OutFile -Leaf)..."
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    Write-OK "Downloaded"
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Detect existing venv (StabilityMatrix uses its own)
function Find-Venv {
    # Check common venv locations
    $candidates = @(
        "$InstallDir\venv",
        "$InstallDir\.venv",
        "$InstallDir\python_embeded"  # StabilityMatrix embedded Python
    )
    foreach ($c in $candidates) {
        if (Test-Path "$c\Scripts\python.exe") { return $c }
    }
    return $null
}

# =====================================================================
# Pre-flight
# =====================================================================
Write-Step "Pre-flight checks"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as Administrator"; exit 1
}

$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
if (-not $gpu) { Write-Err "No NVIDIA GPU detected."; exit 1 }
Write-OK "GPU: $($gpu.Name)"

New-Item -ItemType Directory -Path $DOWNLOADS_DIR -Force | Out-Null
Write-OK "Install dir: $InstallDir"

# =====================================================================
# 1. Git
# =====================================================================
if (-not $SkipGit) {
    Write-Step "1/6 Git"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-OK "Git already installed: $(git --version)"
    } else {
        $inst = "$DOWNLOADS_DIR\git-installer.exe"
        Download-File $GIT_URL $inst
        Start-Process -FilePath $inst -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS" -Wait
        Refresh-Path
        Write-OK "Git installed"
    }
} else { Write-Step "1/6 Skipping Git" }

# =====================================================================
# 2. Python 3.11
# =====================================================================
if (-not $SkipPython) {
    Write-Step "2/6 Python $PYTHON_VERSION"
    $pyVer = try { & python --version 2>&1 } catch { "" }
    if ($pyVer -match "3\.11") {
        Write-OK "Python 3.11 already installed"
    } else {
        $inst = "$DOWNLOADS_DIR\python-$PYTHON_VERSION-amd64.exe"
        Download-File $PYTHON_URL $inst
        Start-Process -FilePath $inst -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1" -Wait
        Refresh-Path
        Write-OK "Python $PYTHON_VERSION installed"
    }
} else { Write-Step "2/6 Skipping Python" }

# =====================================================================
# 3. VS 2022 Build Tools
# =====================================================================
if (-not $SkipVS) {
    Write-Step "3/6 VS 2022 Build Tools"
    $vsExists = (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools") -or
                (Test-Path "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\MSVC")
    if ($vsExists) {
        Write-OK "VS Build Tools already installed"
    } else {
        $inst = "$DOWNLOADS_DIR\vs_BuildTools.exe"
        Download-File $VS_BUILDTOOLS_URL $inst
        Write-Host "  Installing (10-20 min)..."
        Start-Process -FilePath $inst -ArgumentList "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" -Wait
        Write-OK "VS Build Tools installed"
    }
} else { Write-Step "3/6 Skipping VS Build Tools" }

# =====================================================================
# 4. CUDA Toolkit
# =====================================================================
if (-not $SkipCUDA) {
    Write-Step "4/6 CUDA Toolkit"
    $cudaFound = $false
    # Check for any CUDA 12.x
    foreach ($v in @("v12.8","v12.6","v12.4","v12.1")) {
        $p = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\$v"
        if (Test-Path "$p\bin\nvcc.exe") { Write-OK "CUDA found: $p"; $cudaFound = $true; break }
    }
    if (-not $cudaFound) {
        # Check if nvcc is in PATH
        if (Get-Command nvcc -ErrorAction SilentlyContinue) {
            Write-OK "CUDA found in PATH: $(nvcc --version | Select-String 'release')"
            $cudaFound = $true
        }
    }
    if (-not $cudaFound) {
        Write-Warn "No CUDA 12.x toolkit detected."
        Write-Warn "Download CUDA 12.8 from: https://developer.nvidia.com/cuda-12-8-0-download-archive"
        Write-Warn "Run installer with default options, then re-run this script."
        Write-Host ""
        Read-Host "  Press Enter after installing CUDA, or Ctrl+C to exit"
        Refresh-Path
    }
} else { Write-Step "4/6 Skipping CUDA" }

# =====================================================================
# 5. Environment + Developer Mode
# =====================================================================
Write-Step "5/6 Environment"
Refresh-Path

# Enable Developer Mode (required by TRELLIS2 for symlinks without Admin)
$devMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
if (-not $devMode -or $devMode.AllowDevelopmentWithoutDevLicense -ne 1) {
    Write-Host "  Enabling Developer Mode (needed by TRELLIS2 for symlinks)..."
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1" 2>&1 | Out-Null
    Write-OK "Developer Mode enabled"
} else {
    Write-OK "Developer Mode already enabled"
}

Write-OK "Environment ready"

# =====================================================================
# 6. ComfyUI + Nodes + Dependencies
# =====================================================================
Write-Step "6/6 ComfyUI + 3D Pipeline"

# --- Clone or detect ComfyUI ---
if (-not $SkipComfyUI) {
    if (-not (Test-Path "$InstallDir\.git") -and -not (Test-Path "$InstallDir\main.py")) {
        Write-Host "  Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git $InstallDir
    } else {
        Write-OK "ComfyUI already exists at $InstallDir"
    }
}

if (-not (Test-Path "$InstallDir\main.py")) {
    Write-Err "ComfyUI not found at $InstallDir. Use -InstallDir to specify location."
    exit 1
}

Set-Location $InstallDir

# --- Find or create venv ---
$existingVenv = Find-Venv
if ($existingVenv) {
    $VENV_DIR = $existingVenv
    Write-OK "Using existing venv: $VENV_DIR"
} else {
    $VENV_DIR = "$InstallDir\venv"
    Write-Host "  Creating Python 3.11 venv..."
    python -m venv $VENV_DIR
    Write-OK "Created venv: $VENV_DIR"
}

$python = "$VENV_DIR\Scripts\python.exe"
# Always use "python -m pip" instead of pip.exe directly to avoid
# "Failed to canonicalize script path" errors on StabilityMatrix venvs

# --- When SkipComfyUI is set, skip PyTorch/ComfyUI/xformers (already installed) ---
if (-not $SkipComfyUI) {
    # --- Upgrade pip ---
    & $python -m pip install --upgrade pip setuptools wheel 2>&1 | Out-Null
    Write-OK "pip upgraded"

    # --- PyTorch 2.7.0 + cu126 ---
    Write-Host "  Installing PyTorch $TORCH_VERSION + $CU_TAG..."
    & $python -m pip install "torch==$TORCH_VERSION" "torchvision==$TORCHVISION_VER" "torchaudio==$TORCHAUDIO_VER" --index-url $TORCH_INDEX
    Write-OK "PyTorch installed"

    # --- ComfyUI requirements ---
    if (Test-Path "$InstallDir\requirements.txt") {
        Write-Host "  Installing ComfyUI requirements..."
        & $python -m pip install -r "$InstallDir\requirements.txt" 2>&1 | Out-Null
        Write-OK "ComfyUI requirements installed"
    }

    # --- xformers ---
    Write-Host "  Installing xformers $XFORMERS_VER..."
    & $python -m pip install "xformers==$XFORMERS_VER" --index-url $TORCH_INDEX
    Write-OK "xformers installed"
} else {
    Write-OK "Skipping PyTorch/ComfyUI/xformers (existing install)"
}

# ===========================================================
# Clone all custom nodes
# ===========================================================
$nodesDir = "$InstallDir\custom_nodes"
if (-not (Test-Path $nodesDir)) { New-Item -ItemType Directory -Path $nodesDir -Force | Out-Null }
Set-Location $nodesDir

$nodes = @(
    # 3D Generation & Processing
    @{ Name = "ComfyUI-3D-Pack";               Url = "https://github.com/MrForExample/ComfyUI-3D-Pack.git" },
    @{ Name = "ComfyUI-TRELLIS2";              Url = "https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2.git" },
    @{ Name = "ComfyUI-GeometryPack";          Url = "https://github.com/PozzettiAndrea/ComfyUI-GeometryPack.git" },

    # Rigging & Animation
    @{ Name = "ComfyUI-UniRig";                Url = "https://github.com/PozzettiAndrea/ComfyUI-UniRig.git" },
    @{ Name = "ComfyUI-MotionCapture";         Url = "https://github.com/PozzettiAndrea/ComfyUI-MotionCapture.git" },
    @{ Name = "ComfyUI-Frame-Interpolation";   Url = "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" },

    # Body & Character
    @{ Name = "ComfyUI-SAM3DBody";             Url = "https://github.com/PozzettiAndrea/ComfyUI-SAM3DBody.git" },

    # Texturing & PBR
    @{ Name = "ComfyUI-TextureAlchemy";        Url = "https://github.com/amtarr/ComfyUI-TextureAlchemy.git" },
    @{ Name = "COMFYUI-PBRFusion4";            Url = "https://github.com/Night1099/COMFYUI-PBRFusion4.git" },

    # ControlNet & Pose
    @{ Name = "comfyui_controlnet_aux";        Url = "https://github.com/Fannovel16/comfyui_controlnet_aux.git" },
    @{ Name = "ComfyUI_IPAdapter_plus";        Url = "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git" },

    # Segmentation
    @{ Name = "ComfyUI-segment-anything-2";    Url = "https://github.com/kijai/ComfyUI-segment-anything-2.git" },
    @{ Name = "comfyui_segment_anything";      Url = "https://github.com/storyicon/comfyui_segment_anything.git" },
    @{ Name = "rembg-comfyui-node";            Url = "https://github.com/Jcd1230/rembg-comfyui-node.git" },

    # Upscaling
    @{ Name = "ComfyUI_UltimateSDUpscale";     Url = "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"; Recursive = $true },

    # Essential Workflow
    @{ Name = "ComfyUI-Impact-Pack";           Url = "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" },
    @{ Name = "ComfyUI-KJNodes";               Url = "https://github.com/kijai/ComfyUI-KJNodes.git" },
    @{ Name = "ComfyUI-Manager";               Url = "https://github.com/Comfy-Org/ComfyUI-Manager.git" },
    @{ Name = "ComfyUI-VideoHelperSuite";      Url = "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" }
)

Write-Host "  Cloning custom nodes..."
$newlyCloned = @()
foreach ($node in $nodes) {
    $nodePath = "$nodesDir\$($node.Name)"
    if (Test-Path $nodePath) {
        Write-OK "$($node.Name) exists"
    } else {
        $gitArgs = @("clone")
        if ($node.Branch) { $gitArgs += "-b"; $gitArgs += $node.Branch }
        if ($node.Recursive) { $gitArgs += "--recursive" }
        $gitArgs += $node.Url
        $gitArgs += $nodePath
        Write-Host "  Cloning $($node.Name)..."
        $ErrorActionPreference = "Continue"
        & git @gitArgs 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
        $newlyCloned += $node.Name
    }
}
if ($newlyCloned.Count -gt 0) {
    Write-OK "$($newlyCloned.Count) new nodes cloned"
} else {
    Write-OK "All nodes already present"
}

# ===========================================================
# Shared dependencies (only installs what's missing)
# ===========================================================
Write-Host "`n  Installing shared dependencies (skipping already installed)..."

$sharedDeps = @(
    @{ Pkgs = @("cumm-cu126", "spconv-cu126"); Label = "spconv + cumm" },
    @{ Pkgs = @("torch-scatter", "torch-cluster"); Extra = "--find-links $PYG_LINKS"; Label = "torch-scatter + torch-cluster" },
    @{ Pkgs = @("scipy>=1.15.0"); Label = "scipy" },
    @{ Pkgs = @("gpytoolbox"); Extra = "--no-build-isolation"; Label = "gpytoolbox" },
    @{ Pkgs = @("rembg[gpu]"); Label = "rembg[gpu]" },
    @{ Pkgs = @("insightface"); Label = "insightface" }
)

foreach ($dep in $sharedDeps) {
    $allInstalled = $true
    foreach ($pkg in $dep.Pkgs) {
        $checkName = ($pkg -replace '[>=<\[\]].*','')  # strip version/extras
        $check = & $python -c "import importlib; importlib.import_module('$checkName'.replace('-','_'))" 2>&1
        if ($LASTEXITCODE -ne 0) { $allInstalled = $false; break }
    }
    if ($allInstalled) {
        Write-OK "$($dep.Label) already installed"
    } else {
        Write-Host "  Installing $($dep.Label)..."
        $cmd = @("-m", "pip", "install") + $dep.Pkgs
        if ($dep.Extra) { $cmd += ($dep.Extra -split ' ') }
        & $python @cmd 2>&1 | Out-Null
        Write-OK "$($dep.Label)"
    }
}

# ===========================================================
# Install requirements for NEW nodes only (skip existing)
# ===========================================================
if ($newlyCloned.Count -eq 0) {
    Write-Host "`n  No new nodes to install requirements for."
} else {
    Write-Host "`n  Installing requirements for $($newlyCloned.Count) new node(s)..."

    $i = 1
    foreach ($nodeDir in $newlyCloned) {
        $nodePath = "$nodesDir\$nodeDir"
        if (Test-Path $nodePath) {
            Write-Host "  [$i/$($newlyCloned.Count)] $nodeDir..."
            if (Test-Path "$nodePath\requirements.txt") {
                & $python -m pip install -r "$nodePath\requirements.txt" 2>&1 | Out-Null
            }
            if (Test-Path "$nodePath\install.py") {
                Set-Location $nodePath
                & $python install.py 2>&1 | Out-Null
                Set-Location $nodesDir
            }
            Write-OK $nodeDir
        }
        $i++
    }
}

# ===========================================================
# Create launch script
# ===========================================================
$launchScript = @"
@echo off
title ComfyUI - 3D Pipeline
echo Starting ComfyUI...
cd /d "$InstallDir"
call "$VENV_DIR\Scripts\activate.bat"
python main.py --listen 0.0.0.0 --port 8188
pause
"@
Set-Content -Path "$InstallDir\run_comfyui.bat" -Value $launchScript

# Desktop shortcut
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\ComfyUI 3D Pipeline.lnk")
    $shortcut.TargetPath = "$InstallDir\run_comfyui.bat"
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = "ComfyUI with 3D Pipeline nodes"
    $shortcut.Save()
    Write-OK "Desktop shortcut created"
} catch { Write-Warn "Could not create desktop shortcut" }

# =====================================================================
# Done!
# =====================================================================
Set-Location $InstallDir

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Location:  $InstallDir" -ForegroundColor White
Write-Host "  Venv:      $VENV_DIR" -ForegroundColor White
Write-Host "  PyTorch:   $TORCH_VERSION + $CU_TAG" -ForegroundColor White
Write-Host "  Python:    3.11" -ForegroundColor White
Write-Host "  Launch:    $InstallDir\run_comfyui.bat" -ForegroundColor White
Write-Host "  URL:       http://localhost:8188" -ForegroundColor White
Write-Host ""
Write-Host "  20 nodes installed:" -ForegroundColor Cyan
Write-Host "    3D:        3D-Pack, TRELLIS2, GeometryPack"
Write-Host "    Rigging:   UniRig, MotionCapture, Frame-Interpolation"
Write-Host "    Body:      SAM3DBody"
Write-Host "    Textures:  TextureAlchemy, PBRFusion4"
Write-Host "    Control:   controlnet_aux, IPAdapter+"
Write-Host "    Segment:   SAM2, GroundingDino, rembg"
Write-Host "    Upscale:   UltimateSDUpscale"
Write-Host "    Core:      Impact-Pack, KJNodes, Manager, VideoHelper"
Write-Host ""
Write-Host "  Next: download models to $InstallDir\models\" -ForegroundColor Yellow
Write-Host ""
