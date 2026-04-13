#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ComfyUI + 3D Pipeline - Full Windows Installer
    Installs Python 3.11, Git, VS 2022 Build Tools, CUDA 13.2 + 12.8,
    ComfyUI, and 20 custom nodes for a complete text-to-3D pipeline.

.DESCRIPTION
    Run as Administrator:
      Right-click PowerShell -> Run as Administrator
      Set-ExecutionPolicy Bypass -Scope Process -Force
      .\install-comfyui-3d-pipeline.ps1

    Optional flags:
      -InstallDir "D:\ComfyUI"        # Custom install location
      -SkipCUDA                        # Skip CUDA toolkit install (if already installed)
      -SkipPython                      # Skip Python install (if 3.11 already installed)
      -SkipVS                          # Skip VS Build Tools (if already installed)
      -SkipGit                         # Skip Git install (if already installed)

.NOTES
    Requires: Windows 10/11, NVIDIA GPU, Internet connection, Admin rights
    Install time: 30-90 minutes depending on internet speed
    Disk space: ~30 GB (CUDA toolkits + Python + ComfyUI + models)
#>

param(
    [string]$InstallDir = "$env:USERPROFILE\ComfyUI",
    [switch]$SkipCUDA,
    [switch]$SkipPython,
    [switch]$SkipVS,
    [switch]$SkipGit
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Speed up Invoke-WebRequest

# =====================================================================
# Configuration
# =====================================================================
$PYTHON_VERSION   = "3.11.11"
$PYTHON_URL       = "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-amd64.exe"
$GIT_URL          = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe"
$VS_BUILDTOOLS_URL = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
$DOWNLOADS_DIR    = "$env:TEMP\comfyui-installer"
$VENV_DIR         = "$InstallDir\venv"

# CUDA paths
$CUDA_13_HOME     = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2"
$CUDA_12_HOME     = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"

# =====================================================================
# Helper functions
# =====================================================================
function Write-Step { param([string]$msg) Write-Host "`n========================================" -ForegroundColor Cyan; Write-Host "  $msg" -ForegroundColor Cyan; Write-Host "========================================" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }

function Download-File {
    param([string]$Url, [string]$OutFile)
    if (Test-Path $OutFile) {
        Write-OK "$OutFile already downloaded"
        return
    }
    Write-Host "  Downloading $Url ..."
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    Write-OK "Downloaded to $OutFile"
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# =====================================================================
# Pre-flight checks
# =====================================================================
Write-Step "Pre-flight checks"

# Check admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as Administrator"
    exit 1
}

# Check NVIDIA GPU
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
if (-not $gpu) {
    Write-Err "No NVIDIA GPU detected. This installer requires an NVIDIA GPU."
    exit 1
}
Write-OK "NVIDIA GPU found: $($gpu.Name)"

# Create directories
New-Item -ItemType Directory -Path $DOWNLOADS_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Write-OK "Install directory: $InstallDir"

# =====================================================================
# 1. Install Git
# =====================================================================
if (-not $SkipGit) {
    Write-Step "1/6 Installing Git"
    $gitCheck = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCheck) {
        Write-OK "Git already installed: $(git --version)"
    } else {
        $gitInstaller = "$DOWNLOADS_DIR\git-installer.exe"
        Download-File $GIT_URL $gitInstaller
        Write-Host "  Installing Git (silent)..."
        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS" -Wait
        Refresh-Path
        Write-OK "Git installed"
    }
} else { Write-Step "1/6 Skipping Git (--SkipGit)" }

# =====================================================================
# 2. Install Python 3.11
# =====================================================================
if (-not $SkipPython) {
    Write-Step "2/6 Installing Python $PYTHON_VERSION"
    $pyCheck = Get-Command python -ErrorAction SilentlyContinue
    $pyVer = if ($pyCheck) { & python --version 2>&1 } else { "" }
    if ($pyVer -match "3\.11") {
        Write-OK "Python 3.11 already installed: $pyVer"
    } else {
        $pyInstaller = "$DOWNLOADS_DIR\python-$PYTHON_VERSION-amd64.exe"
        Download-File $PYTHON_URL $pyInstaller
        Write-Host "  Installing Python $PYTHON_VERSION (silent)..."
        Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1" -Wait
        Refresh-Path
        Write-OK "Python $PYTHON_VERSION installed"
    }
} else { Write-Step "2/6 Skipping Python (--SkipPython)" }

# =====================================================================
# 3. Install Visual Studio 2022 Build Tools
# =====================================================================
if (-not $SkipVS) {
    Write-Step "3/6 Installing VS 2022 Build Tools (C++ workload)"
    $vsCheck = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\SxS\VS7" -ErrorAction SilentlyContinue
    $vsInstalled = Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" -ErrorAction SilentlyContinue
    $vsInstalled2 = Test-Path "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\MSVC" -ErrorAction SilentlyContinue
    if ($vsInstalled -or $vsInstalled2) {
        Write-OK "VS Build Tools already installed"
    } else {
        $vsInstaller = "$DOWNLOADS_DIR\vs_BuildTools.exe"
        Download-File $VS_BUILDTOOLS_URL $vsInstaller
        Write-Host "  Installing VS Build Tools (this may take 10-20 minutes)..."
        Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" -Wait
        Write-OK "VS 2022 Build Tools installed"
    }
} else { Write-Step "3/6 Skipping VS Build Tools (--SkipVS)" }

# =====================================================================
# 4. Install CUDA Toolkits (13.2 + 12.8)
# =====================================================================
if (-not $SkipCUDA) {
    Write-Step "4/6 Installing CUDA Toolkits"

    # Check if CUDA 13.2 is already installed
    if (Test-Path "$CUDA_13_HOME\bin\nvcc.exe") {
        Write-OK "CUDA 13.2 already installed at $CUDA_13_HOME"
    } else {
        Write-Warn "CUDA 13.2 toolkit must be downloaded from NVIDIA manually."
        Write-Warn "Download from: https://developer.nvidia.com/cuda-downloads"
        Write-Warn "Select: Windows -> x86_64 -> 11 -> exe (local)"
        Write-Warn "After downloading, run: cuda_13.2.X_windows.exe -s"
        Write-Host ""
        $response = Read-Host "  Press Enter after installing CUDA 13.2, or type 'skip' to continue without it"
        if ($response -ne "skip") {
            Refresh-Path
            if (Test-Path "$CUDA_13_HOME\bin\nvcc.exe") {
                Write-OK "CUDA 13.2 detected after install"
            } else {
                Write-Warn "CUDA 13.2 not detected - CUDA extensions may not build correctly"
            }
        }
    }

    # Check if CUDA 12.8 is already installed (dual CUDA for spconv)
    if (Test-Path "$CUDA_12_HOME\bin\nvcc.exe") {
        Write-OK "CUDA 12.8 already installed at $CUDA_12_HOME (dual CUDA ready)"
    } else {
        Write-Warn "CUDA 12.8 toolkit recommended for spconv/cumm compilation."
        Write-Warn "Download from: https://developer.nvidia.com/cuda-12-8-0-download-archive"
        Write-Warn "Install alongside CUDA 13.2 (both can coexist)."
        Write-Host ""
        $response = Read-Host "  Press Enter after installing CUDA 12.8, or type 'skip'"
    }
} else { Write-Step "4/6 Skipping CUDA (--SkipCUDA)" }

# =====================================================================
# 5. Set environment variables
# =====================================================================
Write-Step "5/6 Setting environment variables"

# CUDA 13.2 as primary
if (Test-Path $CUDA_13_HOME) {
    [Environment]::SetEnvironmentVariable("CUDA_HOME", $CUDA_13_HOME, "User")
    [Environment]::SetEnvironmentVariable("CUDA_PATH", $CUDA_13_HOME, "User")
    $env:CUDA_HOME = $CUDA_13_HOME
    $env:CUDA_PATH = $CUDA_13_HOME
    Write-OK "CUDA_HOME set to $CUDA_13_HOME"
}

# MSVC conformant preprocessor for CCCL (CUDA 13+)
$existingCxxFlags = [Environment]::GetEnvironmentVariable("CXXFLAGS", "User")
if ($existingCxxFlags -notmatch "/Zc:preprocessor") {
    $newFlags = if ($existingCxxFlags) { "$existingCxxFlags /Zc:preprocessor" } else { "/Zc:preprocessor" }
    [Environment]::SetEnvironmentVariable("CXXFLAGS", $newFlags, "User")
    $env:CXXFLAGS = $newFlags
    Write-OK "CXXFLAGS set: /Zc:preprocessor"
}

Refresh-Path

# =====================================================================
# 6. Install ComfyUI + All Custom Nodes
# =====================================================================
Write-Step "6/6 Installing ComfyUI + 3D Pipeline"

# Clone ComfyUI
if (-not (Test-Path "$InstallDir\.git")) {
    Write-Host "  Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git $InstallDir
}
Set-Location $InstallDir

# Create Python venv
if (-not (Test-Path "$VENV_DIR\Scripts\python.exe")) {
    Write-Host "  Creating Python 3.11 virtual environment..."
    python -m venv $VENV_DIR
}

# Activate venv for all subsequent commands
$pip = "$VENV_DIR\Scripts\pip.exe"
$python = "$VENV_DIR\Scripts\python.exe"

Write-Host "  Upgrading pip..."
& $python -m pip install --upgrade pip setuptools wheel

# --- PyTorch 2.9.1 + CUDA 13.0 ---
Write-Host "  Installing PyTorch 2.9.1 + cu130..."
& $pip install torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 --extra-index-url https://download.pytorch.org/whl/cu130

# --- ComfyUI requirements ---
Write-Host "  Installing ComfyUI requirements..."
& $pip install -r "$InstallDir\requirements.txt"

# --- xformers (build from source on Windows + CUDA 13) ---
Write-Host "  Building xformers from source (Windows + CUDA 13, may take 10-30 min)..."
& $pip install -v --no-build-isolation "git+https://github.com/facebookresearch/xformers.git@main#egg=xformers"
if ($LASTEXITCODE -ne 0) {
    Write-Warn "xformers build failed - trying prebuilt wheel as fallback..."
    & $pip install xformers==0.0.34 --extra-index-url https://download.pytorch.org/whl/cu130
}

# ===========================================================
# Clone all custom nodes
# ===========================================================
$nodesDir = "$InstallDir\custom_nodes"
Set-Location $nodesDir

$nodes = @(
    # 3D Generation & Processing
    @{ Name = "ComfyUI-3D-Pack";               Url = "https://github.com/jaiporterscott/ComfyUI-3D-Pack.git"; Branch = "cuda13-compat" },
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

foreach ($node in $nodes) {
    $nodePath = "$nodesDir\$($node.Name)"
    if (Test-Path $nodePath) {
        Write-OK "$($node.Name) already cloned"
    } else {
        Write-Host "  Cloning $($node.Name)..."
        $args = @("clone")
        if ($node.Branch) { $args += "-b"; $args += $node.Branch }
        if ($node.Recursive) { $args += "--recursive" }
        $args += $node.Url
        $args += $nodePath
        & git @args
    }
}

# ===========================================================
# Install shared CUDA dependencies
# ===========================================================
Write-Host "`n  Installing shared CUDA dependencies..."

# spconv/cumm (cu126, ABI forward-compatible with CUDA 13.x)
& $pip install cumm-cu126 spconv-cu126

# PyG packages
& $pip install torch-scatter torch-cluster --find-links https://data.pyg.org/whl/torch-2.9.1+cu130.html

# scipy before gpytoolbox
& $pip install "scipy>=1.15.0"
& $pip install --no-build-isolation gpytoolbox

# rembg with GPU
& $pip install "rembg[gpu]"

# insightface for IPAdapter FaceID
& $pip install insightface

# ===========================================================
# Install each node's requirements
# ===========================================================
Write-Host "`n  Installing node requirements..."

# 3D-Pack first (heaviest)
Set-Location "$nodesDir\ComfyUI-3D-Pack"
& $pip install -r requirements.txt
& $python install.py
Set-Location $nodesDir

# All other nodes
$nodeInstallOrder = @(
    "ComfyUI-Impact-Pack",
    "ComfyUI-KJNodes",
    "ComfyUI-VideoHelperSuite",
    "comfyui_controlnet_aux",
    "ComfyUI-Frame-Interpolation",
    "ComfyUI-TextureAlchemy",
    "ComfyUI-UniRig",
    "ComfyUI-TRELLIS2",
    "ComfyUI-GeometryPack",
    "ComfyUI-MotionCapture",
    "ComfyUI-SAM3DBody",
    "ComfyUI-segment-anything-2",
    "comfyui_segment_anything",
    "COMFYUI-PBRFusion4"
)

foreach ($nodeDir in $nodeInstallOrder) {
    $nodePath = "$nodesDir\$nodeDir"
    if (Test-Path "$nodePath\requirements.txt") {
        Write-Host "  Installing requirements for $nodeDir..."
        & $pip install -r "$nodePath\requirements.txt" 2>&1 | Out-Null
    }
    if (Test-Path "$nodePath\install.py") {
        Write-Host "  Running install.py for $nodeDir..."
        Set-Location $nodePath
        & $python install.py 2>&1 | Out-Null
        Set-Location $nodesDir
    }
}

# ===========================================================
# Create launch script
# ===========================================================
Write-Host "`n  Creating launch script..."

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
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = "$desktopPath\ComfyUI 3D Pipeline.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$InstallDir\run_comfyui.bat"
$shortcut.WorkingDirectory = $InstallDir
$shortcut.Description = "ComfyUI with 3D Pipeline nodes"
$shortcut.Save()

# =====================================================================
# Done!
# =====================================================================
Set-Location $InstallDir

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Install location: $InstallDir" -ForegroundColor White
Write-Host "  Python venv:      $VENV_DIR" -ForegroundColor White
Write-Host "  Launch:            $InstallDir\run_comfyui.bat" -ForegroundColor White
Write-Host "  Desktop shortcut:  ComfyUI 3D Pipeline" -ForegroundColor White
Write-Host "  URL:               http://localhost:8188" -ForegroundColor White
Write-Host ""
Write-Host "  Installed nodes (20):" -ForegroundColor Cyan
Write-Host "    3D:          3D-Pack, TRELLIS2, GeometryPack"
Write-Host "    Rigging:     UniRig, MotionCapture, Frame-Interpolation"
Write-Host "    Body:        SAM3DBody"
Write-Host "    Textures:    TextureAlchemy, PBRFusion4"
Write-Host "    ControlNet:  controlnet_aux, IPAdapter+"
Write-Host "    Segment:     SAM2, GroundingDino, rembg"
Write-Host "    Upscale:     UltimateSDUpscale"
Write-Host "    Core:        Impact-Pack, KJNodes, Manager, VideoHelper"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Download model checkpoints (Flux, SDXL, etc.) to $InstallDir\models\"
Write-Host "    2. Double-click 'ComfyUI 3D Pipeline' on your desktop"
Write-Host "    3. Open http://localhost:8188 in your browser"
Write-Host ""
