#!/bin/bash

# =============================================================================
# Update and install required packages for IPO_Boot_ROM
# =============================================================================

echo "Updating package lists..."
sudo apt update || { echo "Failed to update package lists"; exit 1; }

# Check and install only missing packages
REQUIRED_PACKAGES=("build-essential" "nasm" "qemu-system-x86")
for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -s $PACKAGE &> /dev/null; then
        echo "$PACKAGE is already installed. Skipping..."
    else
        echo "Installing $PACKAGE..."
        sudo apt install -y $PACKAGE || { echo "Failed to install $PACKAGE"; exit 1; }
    fi
done

# =============================================================================
# Verify installation
# =============================================================================

echo "Verifying installation..."
if command -v nasm &> /dev/null && command -v make &> /dev/null && command -v qemu-system-i386 &> /dev/null; then
    echo "Tools setup completed successfully!"
else
    echo "Tools setup verification failed!"
    exit 1
fi

echo "Installation complete."

