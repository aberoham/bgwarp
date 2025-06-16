#!/bin/bash

# Test script for bgwarp
# This helps verify the tool works correctly without affecting WARP

echo "=== bgwarp Test Script ==="
echo ""

# First, build the tool
echo "[1/3] Building the tool..."
if ./build.sh; then
    echo "✓ Build successful"
else
    echo "✗ Build failed"
    exit 1
fi

echo ""
echo "[2/3] Testing without setuid (should fail)..."
echo "Running: ./bgwarp"
echo "----------------------------------------"
./bgwarp
echo "----------------------------------------"
echo "Note: Above should show 'Error: This program must be installed with setuid root'"

echo ""
echo "[3/3] To test with proper permissions:"
echo "  1. Run: sudo ./install.sh"
echo "  2. Then run: /usr/local/libexec/.bgwarp"
echo ""
echo "The tool runs in TEST MODE by default and will:"
echo "  - Require Touch ID authentication"
echo "  - Verify setuid permissions"
echo "  - Check for required binaries"
echo "  - Show commands that would be executed"
echo "  - NOT actually disconnect WARP"
echo ""
echo "To run in live incident mode (DESTRUCTIVE):"
echo "  /usr/local/libexec/.bgwarp --liveincident"