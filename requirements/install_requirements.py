#!/usr/bin/env python3
"""
ComfyUI-3D-Pack: Auto-detect CUDA version and install the correct requirements.

Usage:
    python requirements/install_requirements.py          # auto-detect
    python requirements/install_requirements.py --cuda 12  # force CUDA 12.x
    python requirements/install_requirements.py --cuda 13  # force CUDA 13.x
    python requirements/install_requirements.py --list     # just show what would be installed
"""

import subprocess
import sys
import os
import re
import platform


def detect_cuda_version():
    """Detect CUDA major version from nvcc."""
    try:
        result = subprocess.run(["nvcc", "--version"], text=True, capture_output=True)
        if result.returncode == 0:
            match = re.search(r"release (\d+)\.(\d+)", result.stdout)
            if match:
                return int(match.group(1)), int(match.group(2))
    except FileNotFoundError:
        pass
    return None


def get_requirements_file(cuda_major, is_windows):
    """Return the correct requirements file for this platform."""
    if cuda_major >= 13:
        if is_windows:
            return "cuda13x_windows.txt"
        else:
            return "cuda13x.txt"
    else:
        return "cuda12x.txt"


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Install CUDA-appropriate requirements")
    parser.add_argument("--cuda", type=int, choices=[11, 12, 13, 14],
                        help="Force CUDA major version (default: auto-detect)")
    parser.add_argument("--list", action="store_true",
                        help="Show which requirements file would be used, don't install")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show pip command but don't run it")
    args = parser.parse_args()

    req_dir = os.path.dirname(os.path.abspath(__file__))
    is_windows = platform.system() == "Windows"

    if args.cuda:
        cuda_major = args.cuda
        cuda_minor = 0
        print(f"Forced CUDA version: {cuda_major}.x")
    else:
        version = detect_cuda_version()
        if version is None:
            print("ERROR: Could not detect CUDA version (nvcc not found)")
            print("Install CUDA toolkit or use --cuda flag to specify version")
            sys.exit(1)
        cuda_major, cuda_minor = version
        print(f"Detected CUDA: {cuda_major}.{cuda_minor}")

    req_file = get_requirements_file(cuda_major, is_windows)
    req_path = os.path.join(req_dir, req_file)

    print(f"Platform: {'Windows' if is_windows else 'Linux'}")
    print(f"Requirements file: requirements/{req_file}")

    if cuda_major >= 13:
        print()
        print("=" * 60)
        print("  CUDA 13.x NOTES")
        print("=" * 60)
        print("  - PyTorch uses cu130 wheels (works with CUDA 13.0-13.x)")
        print("  - spconv/cumm use cu126 wheels (ABI forward-compatible)")
        if is_windows:
            print("  - xformers must be built from source after install:")
            print("    pip install -v --no-build-isolation \\")
            print("      git+https://github.com/facebookresearch/xformers.git@main#egg=xformers")
        print("  - CUDA 12.8 toolkit recommended alongside 13.x for building extensions")
        print("=" * 60)
        print()

    if args.list:
        print(f"\nWould install: {req_path}")
        with open(req_path) as f:
            print(f.read())
        return

    cmd = [sys.executable, "-m", "pip", "install", "-r", req_path]

    if args.dry_run:
        print(f"\nDry run - would execute:\n  {' '.join(cmd)}")
        return

    print(f"\nRunning: {' '.join(cmd)}")
    result = subprocess.run(cmd)

    if result.returncode == 0:
        print("\nBase requirements installed successfully!")
        if cuda_major >= 13 and is_windows:
            print("\nREMINDER: Build xformers from source:")
            print("  pip install -v --no-build-isolation git+https://github.com/facebookresearch/xformers.git@main#egg=xformers")
        print("\nNext: run install.py to build CUDA extensions (pytorch3d, nvdiffrast, etc.)")
    else:
        print(f"\nInstallation failed with exit code {result.returncode}")
        sys.exit(result.returncode)


if __name__ == "__main__":
    main()
