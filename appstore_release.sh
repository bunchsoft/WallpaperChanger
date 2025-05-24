#!/bin/bash

# Script to build, sign, and submit WallpaperChanger.app to the App Store
#
# Usage:
#   ./appstore_release.sh             # Build, sign, and increment version number
#   ./appstore_release.sh --no-increment  # Build and sign without incrementing version

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== WallpaperChanger App Store Submission Script ===${NC}"

# Parse command line arguments
INCREMENT_VERSION=false
for arg in "$@"; do
    case $arg in
        --increment)
            INCREMENT_VERSION=true
            shift
            ;;
    esac
done

# App details
APP_NAME="WallpaperChanger"
APP_BUNDLE="./build/${APP_NAME}.app"
BUNDLE_ID="software.bunch.WallpaperChanger"  # Should match Info.plist
INFO_PLIST="Sources/${APP_NAME}/Info.plist"

# Extract current version
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
echo -e "${YELLOW}Current version: $CURRENT_VERSION${NC}"

# Conditionally increment version number
if [ "$INCREMENT_VERSION" = true ]; then
    echo -e "${YELLOW}Incrementing version number...${NC}"
    
    # Parse version components
    IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
    MAJOR=${VERSION_PARTS[0]}
    MINOR=${VERSION_PARTS[1]}
    PATCH=${VERSION_PARTS[2]}

    # Increment patch version
    PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
    echo -e "${YELLOW}New version: $NEW_VERSION${NC}"

    # Update Info.plist with new version
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST"
    echo -e "${GREEN}Version updated to $NEW_VERSION${NC}"
else
    echo -e "${YELLOW}Skipping version increment${NC}"
    NEW_VERSION=$CURRENT_VERSION
fi

# Step 1: Build the app using the existing build script
echo -e "${YELLOW}Step 1: Building the app...${NC}"
# Set CI environment variable to skip prompts in build_app.sh
export CI=true
echo -e "${YELLOW}CI environment variable set to: $CI${NC}"
./build_app.sh

# Check if build was successful
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}Error: App build failed. The app bundle was not created.${NC}"
    exit 1
fi

echo -e "${GREEN}App built successfully!${NC}"

# Step 2: Code signing
echo -e "${YELLOW}Step 2: Signing the app...${NC}"

# Auto-detect 3rd Party Mac Developer Application certificate
echo -e "${YELLOW}Auto-detecting 3rd Party Mac Developer Application certificate...${NC}"
echo -e "${YELLOW}Available certificates:${NC}"
security find-identity -v | grep "3rd Party Mac Developer Application"
# Extract just the certificate name inside the quotes
CERT_LINE=$(security find-identity -v | grep "3rd Party Mac Developer Application" | head -1)
SIGNING_IDENTITY=$(echo "$CERT_LINE" | sed -n 's/.*"3rd Party Mac Developer Application: \(.*\)".*/\1/p')
echo -e "${YELLOW}Extracted certificate name: $SIGNING_IDENTITY${NC}"

# Validate signing identity
if [ -z "$SIGNING_IDENTITY" ]; then
    echo -e "${RED}Error: No 3rd Party Mac Developer Application certificate found in your keychain.${NC}"
    echo -e "${YELLOW}This certificate is required for App Store submission.${NC}"
    echo -e "${YELLOW}Please ensure you have a valid 3rd Party Mac Developer Application certificate installed.${NC}"
    exit 1
fi

echo -e "${GREEN}Found certificate: $SIGNING_IDENTITY${NC}"

# Check if the identity exists
if ! security find-identity -v | grep -q "$SIGNING_IDENTITY"; then
    echo -e "${RED}Warning: The signing identity '$SIGNING_IDENTITY' was not found in your keychain.${NC}"
    echo -e "${YELLOW}Do you want to continue anyway? (y/n)${NC}"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Signing aborted.${NC}"
        exit 1
    fi
fi

# Sign the app with entitlements
echo -e "${YELLOW}Signing app with identity: 3rd Party Mac Developer Application: $SIGNING_IDENTITY${NC}"
echo -e "${YELLOW}Applying entitlements from: Sources/${APP_NAME}/${APP_NAME}.entitlements${NC}"
codesign --force --options runtime --entitlements "Sources/${APP_NAME}/${APP_NAME}.entitlements" --sign "3rd Party Mac Developer Application: $SIGNING_IDENTITY" "$APP_BUNDLE" --deep

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: App signing failed.${NC}"
    exit 1
fi

echo -e "${GREEN}App signed successfully!${NC}"

# Step 3: Create a .pkg installer for App Store submission
echo -e "${YELLOW}Step 3: Creating .pkg installer for App Store...${NC}"

# Create a temporary directory for productbuild
TEMP_DIR=$(mktemp -d)
PKG_PATH="./build/${APP_NAME}.pkg"

# Find 3rd Party Mac Developer Installer certificate for pkg signing
echo -e "${YELLOW}Looking for 3rd Party Mac Developer Installer certificate...${NC}"
security find-identity -v | grep "3rd Party Mac Developer Installer"
INSTALLER_CERT_LINE=$(security find-identity -v | grep "3rd Party Mac Developer Installer" | head -1)
INSTALLER_IDENTITY=$(echo "$INSTALLER_CERT_LINE" | sed -n 's/.*"3rd Party Mac Developer Installer: \(.*\)".*/\1/p')

if [ -z "$INSTALLER_IDENTITY" ]; then
    echo -e "${RED}Error: No 3rd Party Mac Developer Installer certificate found.${NC}"
    echo -e "${YELLOW}This certificate is required for App Store submission.${NC}"
    echo -e "${YELLOW}Please ensure you have a valid 3rd Party Mac Developer Installer certificate installed.${NC}"
    exit 1
else
    echo -e "${GREEN}Found installer certificate: $INSTALLER_IDENTITY${NC}"
    # Use productbuild to create the signed installer package
    productbuild --component "$APP_BUNDLE" /Applications --sign "3rd Party Mac Developer Installer: $INSTALLER_IDENTITY" "$PKG_PATH"
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create .pkg installer.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}.pkg installer created successfully at $PKG_PATH${NC}"
