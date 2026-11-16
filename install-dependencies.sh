#!/usr/bin/env bash

# Install build and runtime dependencies

set -euo pipefail

echo "Updating package lists..."
sudo apt update || { echo "Failed to update package lists"; exit 1; }

# Install only missing packages
REQUIRED_PACKAGES=(
    "build-essential"    # C toolchain and build utilities
    "nasm"               # 16/32-bit assembler
    "python3"            # ROM image builder script
    "qemu-system-x86"    # System emulator
    "qemu-utils"         # Disk image utility
    "flashrom"           # Hardware flash programmer
    "xxd"                # Hex dump utility
)

for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -s "$PACKAGE" &> /dev/null; then
        echo "$PACKAGE is already installed. Skipping..."
    else
        echo "Installing $PACKAGE..."
        sudo apt install -y "$PACKAGE" || { echo "Failed to install $PACKAGE"; exit 1; }
    fi
done

# Verify installed tools

echo "Verifying installation..."
REQUIRED_COMMANDS=("nasm" "make" "python3" "qemu-system-i386" "flashrom")
MISSING_COMMANDS=()

for CMD in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$CMD" &> /dev/null; then
        MISSING_COMMANDS+=("$CMD")
    fi
done

if [ ${#MISSING_COMMANDS[@]} -eq 0 ]; then
    echo "Tools setup completed successfully! All dependencies are installed."
else
    echo "Tools setup verification failed! Missing commands: ${MISSING_COMMANDS[*]}"
    exit 1
fi

echo "Installation complete."
