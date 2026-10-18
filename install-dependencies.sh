#!/usr/bin/env bash

# =============================================================================
# Update and install required packages for IPO_Boot_ROM
# =============================================================================

set -euo pipefail

echo "Updating package lists..."
sudo apt update || { echo "Failed to update package lists"; exit 1; }

# Check and install only missing packages
REQUIRED_PACKAGES=(
    "build-essential"    # make, gcc, binutils
    "nasm"               # x86 assembler
    "python3"            # ROM packaging & geometry scripts
    "qemu-system-x86"    # qemu-system-i386 for hardware emulation
    "qemu-utils"         # qemu-img for virtual disk management
    "flashrom"           # SPI/LPC/parallel flash programming tool for physical hardware
    "xxd"                # Binary and hex dump utility
)

for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -s "$PACKAGE" &> /dev/null; then
        echo "$PACKAGE is already installed. Skipping..."
    else
        echo "Installing $PACKAGE..."
        sudo apt install -y "$PACKAGE" || { echo "Failed to install $PACKAGE"; exit 1; }
    fi
done

# =============================================================================
# Verify installation
# =============================================================================

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
