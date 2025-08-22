#!/bin/bash

# Installation script for unwarp emergency tool
# This must be run with sudo

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run with sudo"
    echo "Usage: sudo ./install.sh"
    exit 1
fi

# Check if binary exists
if [ ! -f "unwarp" ]; then
    echo "Error: unwarp binary not found!"
    echo "Please run ./build.sh first"
    exit 1
fi

echo "Installing unwarp emergency tool..."

# Create hidden directory if it doesn't exist
INSTALL_DIR="/usr/local/libexec"
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# Copy binary to hidden location
echo "Installing to: $INSTALL_DIR/.unwarp"
cp unwarp "$INSTALL_DIR/.unwarp"

# Set proper ownership and permissions
echo "Setting ownership to root:wheel..."
chown root:wheel "$INSTALL_DIR/.unwarp"

echo "Setting setuid permissions (4755)..."
chmod 4755 "$INSTALL_DIR/.unwarp"

# Verify installation
if [ -f "$INSTALL_DIR/.unwarp" ]; then
    echo ""
    echo "✓ Installation complete!"
    echo ""
    echo "The emergency tool is installed at:"
    echo "  $INSTALL_DIR/.unwarp"
    echo ""
    echo "To use in an emergency:"
    echo "  $INSTALL_DIR/.unwarp --liveincident"
    echo ""
    echo "This tool requires Touch ID authentication and will:"
    echo "  - Disconnect WARP"
    echo "  - Kill all WARP processes"
    echo "  - Flush DNS cache"
    echo "  - Reset network routes"
    echo "  - Schedule automatic WARP reconnection"
    echo ""
    echo "⚠️  IMPORTANT: Document this location in your incident playbooks only!"
    echo "⚠️  This tool should remain hidden from normal users."
else
    echo "Error: Installation failed!"
    exit 1
fi