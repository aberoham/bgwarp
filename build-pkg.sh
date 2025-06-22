#!/bin/bash
#
# Build script for creating bgwarp PKG installer
# This creates a macOS installer package suitable for JAMF deployment
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VERSION="1.0.0"
# Package identifier using GitHub username/repo convention
# Organizations can override this when building their own packages
IDENTIFIER="com.github.aberoham.bgwarp"
PACKAGE_NAME="bgwarp-${VERSION}.pkg"
SIGNED_PACKAGE_NAME="bgwarp-${VERSION}-signed.pkg"

echo -e "${GREEN}Building bgwarp PKG installer v${VERSION}${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "bgwarp.m" ]; then
    echo -e "${RED}Error: bgwarp.m not found!${NC}"
    echo "Please run this script from the bgwarp source directory"
    exit 1
fi

# Build the binary first if it doesn't exist
if [ ! -f "bgwarp" ]; then
    echo -e "${YELLOW}Binary not found, building...${NC}"
    ./build.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
fi

# Verify the binary was built
if [ ! -f "bgwarp" ]; then
    echo -e "${RED}Error: bgwarp binary still not found after build!${NC}"
    exit 1
fi

# Copy binary to payload directory
echo "Preparing package payload..."
cp bgwarp packaging/payload/usr/local/libexec/.bgwarp

# Create the package
echo "Building package..."
pkgbuild --root packaging/payload \
         --identifier "${IDENTIFIER}" \
         --version "${VERSION}" \
         --scripts packaging/scripts \
         --ownership recommended \
         "${PACKAGE_NAME}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Package created: ${PACKAGE_NAME}${NC}"
else
    echo -e "${RED}Package creation failed!${NC}"
    exit 1
fi

# Check if we should sign the package
echo ""
echo "Checking for code signing identity..."

# Look for Developer ID Installer certificates
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Installer" | head -1 | awk -F'"' '{print $2}')

if [ -n "$SIGNING_IDENTITY" ]; then
    echo -e "${GREEN}Found signing identity: ${SIGNING_IDENTITY}${NC}"
    echo "Signing package..."
    
    productsign --sign "$SIGNING_IDENTITY" \
                "${PACKAGE_NAME}" \
                "${SIGNED_PACKAGE_NAME}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Signed package created: ${SIGNED_PACKAGE_NAME}${NC}"
        
        # Verify the signature
        echo "Verifying signature..."
        pkgutil --check-signature "${SIGNED_PACKAGE_NAME}"
        
        # Calculate checksums
        echo ""
        echo "Package checksums:"
        echo -e "${YELLOW}SHA256 (unsigned):${NC} $(shasum -a 256 ${PACKAGE_NAME} | awk '{print $1}')"
        echo -e "${YELLOW}SHA256 (signed):${NC}   $(shasum -a 256 ${SIGNED_PACKAGE_NAME} | awk '{print $1}')"
    else
        echo -e "${RED}Package signing failed!${NC}"
        echo "The unsigned package is still available: ${PACKAGE_NAME}"
    fi
else
    echo -e "${YELLOW}No Developer ID Installer certificate found${NC}"
    echo "Package created without signature: ${PACKAGE_NAME}"
    echo ""
    echo "To sign this package later:"
    echo "1. Obtain a Developer ID Installer certificate from Apple Developer Program"
    echo "2. Install the certificate in your Keychain"
    echo "3. Run: productsign --sign \"Developer ID Installer: Your Company\" ${PACKAGE_NAME} ${SIGNED_PACKAGE_NAME}"
    echo ""
    echo -e "${YELLOW}SHA256:${NC} $(shasum -a 256 ${PACKAGE_NAME} | awk '{print $1}')"
fi

echo ""
echo -e "${GREEN}Package build complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Test the package on a test system"
echo "2. Upload to your JAMF distribution point"
echo "3. Create a policy in JAMF Pro to deploy to target computers"
echo ""
echo "For JAMF deployment instructions, see: packaging/JAMF_DEPLOYMENT.md"

# Clean up the payload directory (but keep the structure)
rm -f packaging/payload/usr/local/libexec/.bgwarp