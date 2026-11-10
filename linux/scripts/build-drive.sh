#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
gcc -O2 -Wall -o build/drive tools/drive.c $(pkg-config --cflags --libs libei-1.0 libsystemd)
