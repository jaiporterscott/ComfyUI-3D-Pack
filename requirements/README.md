# ComfyUI-3D-Pack Requirements

## Quick Start

```bash
# Auto-detect CUDA version and install everything:
python requirements/install_requirements.py

# Or specify manually:
python requirements/install_requirements.py --cuda 13
python requirements/install_requirements.py --cuda 12
```

## Files

| File | CUDA | Platform | Description |
|------|------|----------|-------------|
| `base.txt` | Any | Any | CUDA-independent packages (numpy, trimesh, diffusers, etc.) |
| `cuda12x.txt` | 12.1-12.8 | Any | PyTorch 2.9.1+cu126, prebuilt spconv/cumm/xformers |
| `cuda13x.txt` | 13.0+ | Linux | PyTorch 2.9.1+cu130, cu126 spconv/cumm (ABI compatible) |
| `cuda13x_windows.txt` | 13.0+ | Windows | Same as cuda13x but xformers excluded (build from source) |
| `build_from_source.txt` | Any | Any | Reference list of extensions compiled by install.py |
| `install_requirements.py` | Any | Any | Auto-detect script |

## CUDA 13.x Dual CUDA Setup

CUDA 13.x is fully supported with a "dual CUDA" approach:

- **PyTorch, torch-scatter**: use `cu130` wheels (native CUDA 13 support)
- **spconv, cumm**: use `cu126` prebuilt wheels (ABI forward-compatible with CUDA 13.x driver)
- **xformers**: prebuilt on Linux; build from source on Windows

### Windows + CUDA 13.x

After installing requirements, build xformers manually:

```bash
pip install -v --no-build-isolation git+https://github.com/facebookresearch/xformers.git@main#egg=xformers
```

Requires Visual Studio 2022 Build Tools with `/Zc:preprocessor` flag.

### Optional: CUDA 12.8 Toolkit

For building CUDA extensions from source (pytorch3d, nvdiffrast, etc.), having CUDA 12.8 installed alongside 13.x is recommended. The installer auto-detects it.

- Windows: https://developer.nvidia.com/cuda-12-8-0-download-archive
- Linux: `sudo apt install cuda-toolkit-12-8`
