#!/bin/bash

# Build script for bgwarp emergency tool
# This compiles the Objective-C program with necessary frameworks

set -e

echo "Building bgwarp emergency tool..."

# Check if source file exists
if [ ! -f "bgwarp.m" ]; then
    echo "Error: bgwarp.m not found!"
    exit 1
fi

# Compile with clang, linking Foundation and LocalAuthentication frameworks
clang -framework Foundation \
      -framework LocalAuthentication \
      -framework Security \
      -framework SystemConfiguration \
      -fobjc-arc \
      -O2 \
      -Weverything \
      -Wno-padded \
      -Wno-gnu-statement-expression \
      -Wno-poison-system-directories \
      -Wno-declaration-after-statement \
      -o bgwarp \
      bgwarp.m

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Binary created: ./bgwarp"
    echo ""
    echo "To install, run: sudo ./install.sh"
else
    echo "Build failed!"
    exit 1
fi