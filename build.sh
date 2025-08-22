#!/bin/bash

# Build script for unwarp emergency tool
# This compiles the Objective-C program with necessary frameworks

set -e

# Accept version as first parameter (optional)
VERSION="${1:-dev}"

echo "Building unwarp emergency tool (version: $VERSION)..."

# Check if source file exists
if [ ! -f "unwarp.m" ]; then
    echo "Error: unwarp.m not found!"
    exit 1
fi

# Compile with clang, linking Foundation and LocalAuthentication frameworks
clang -framework Foundation \
      -framework LocalAuthentication \
      -framework Security \
      -framework SystemConfiguration \
      -fobjc-arc \
      -O2 \
      -DUNWARP_VERSION="\"$VERSION\"" \
      -Weverything \
      -Wno-padded \
      -Wno-gnu-statement-expression \
      -Wno-poison-system-directories \
      -Wno-declaration-after-statement \
      -o unwarp \
      unwarp.m

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Binary created: ./unwarp"
    echo ""
    echo "To install, run: sudo ./install.sh"
else
    echo "Build failed!"
    exit 1
fi