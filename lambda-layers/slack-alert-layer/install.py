#!/usr/bin/env python
"""Install dependencies for Lambda layer."""

import subprocess
import sys
from pathlib import Path

# Lambda Layer target directory
layer_dir = Path(__file__).parent / "python" / "lib" / "python3.12" / "site-packages"

# Ensure directory exists
layer_dir.mkdir(parents=True, exist_ok=True)

print(f"Installing requests to: {layer_dir}")

# Install requests
result = subprocess.run(
    [
        sys.executable,
        "-m",
        "pip",
        "install",
        "requests==2.32.5",
        "-t",
        str(layer_dir),
        "--no-cache-dir"
    ],
    capture_output=True,
    text=True
)

print(result.stdout)
if result.stderr:
    print("STDERR:", result.stderr)

if result.returncode == 0:
    print("✅ Lambda Layer dependencies installed successfully!")
    print(f"   Path: {layer_dir}")
    print(f"   Contents: {list(layer_dir.iterdir())}")
else:
    print(f"❌ Installation failed with return code {result.returncode}")
    sys.exit(1)
