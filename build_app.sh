#!/bin/bash

# Build script for WallpaperChanger.app

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building WallpaperChanger.app...${NC}"

# Check if Swift is installed
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed or not in your PATH.${NC}"
    echo -e "${YELLOW}Please install Swift from https://swift.org/download/ or via Xcode.${NC}"
    exit 1
fi

# App name and bundle identifier
APP_NAME="WallpaperChanger"
BUNDLE_ID="software.bunch.WallpaperChanger"

# Build the application in release mode
echo -e "${YELLOW}Compiling...${NC}"
swift build -c release

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed.${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}"

# Create app bundle structure
echo -e "${YELLOW}Creating app bundle...${NC}"

# Define paths
APP_BUNDLE="./build/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Create directories
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/"

# Copy Info.plist
cp "Sources/${APP_NAME}/Info.plist" "${CONTENTS_DIR}/"

# Copy entitlements
cp "Sources/${APP_NAME}/${APP_NAME}.entitlements" "${CONTENTS_DIR}/"

# Create PkgInfo file
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Process and copy app icon
echo -e "${YELLOW}Processing app icon...${NC}"
ICON_PATH="assets/appicon.png"
ICONSET_DIR="${RESOURCES_DIR}/appicon.iconset"
ICNS_FILE="${RESOURCES_DIR}/appicon.icns"

# Create iconset directory
mkdir -p "${ICONSET_DIR}"

# Generate different icon sizes using sips
for size in 16 32 64 128 256 512; do
    # Standard resolution
    sips -z $size $size "${ICON_PATH}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" > /dev/null 2>&1
    
    # High resolution (2x)
    sips -z $(($size*2)) $(($size*2)) "${ICON_PATH}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" > /dev/null 2>&1
done

# Ensure we have the 1024x1024 icon (512x512@2x) required by App Store
sips -z 1024 1024 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1
echo -e "${YELLOW}Created 512x512@2x (1024x1024) icon required by App Store${NC}"

# Convert iconset to icns file
iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_FILE}"

# Clean up temporary iconset directory
rm -rf "${ICONSET_DIR}"

echo -e "${GREEN}App icon processed and added to the bundle${NC}"

# Set executable permissions
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo -e "${GREEN}App bundle created at ${APP_BUNDLE}${NC}"
echo -e "${YELLOW}You can run the application by double-clicking it in Finder${NC}"
echo -e "${YELLOW}or by running:${NC}"
echo -e "${GREEN}open ${APP_BUNDLE}${NC}"

# Only ask to run the application if not in CI environment
if [ -z "$CI" ]; then
    echo -e "${YELLOW}Do you want to run the application now? (y/n)${NC}"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Running ${APP_NAME}...${NC}"
        open "${APP_BUNDLE}"
    fi
fi
