#!/bin/bash

# Script to automate the release process for WallpaperChanger

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if a version number was provided
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Please provide a version number (e.g., 1.0.0)${NC}"
    echo -e "Usage: $0 <version>"
    exit 1
fi

VERSION=$1

# Validate version format (should be like 1.0.0)
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Version should be in the format X.Y.Z (e.g., 1.0.0)${NC}"
    exit 1
fi

echo -e "${YELLOW}Creating release for version ${VERSION}...${NC}"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: Git is not installed or not in your PATH.${NC}"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo -e "${RED}Error: Not in a git repository.${NC}"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${RED}Error: You have uncommitted changes. Please commit or stash them first.${NC}"
    exit 1
fi

# Update version in Info.plist
echo -e "${YELLOW}Updating version in Info.plist...${NC}"
INFO_PLIST="Sources/WallpaperChanger/Info.plist"

if [ ! -f "$INFO_PLIST" ]; then
    echo -e "${RED}Error: Info.plist not found at $INFO_PLIST${NC}"
    exit 1
fi

# Update CFBundleVersion and CFBundleShortVersionString
# Using awk for more reliable multi-line replacements
awk -v ver="$VERSION" '
/<key>CFBundleVersion<\/key>/ { print; getline; gsub(/>.*</, ">" ver "<"); print; next }
/<key>CFBundleShortVersionString<\/key>/ { print; getline; gsub(/>.*</, ">" ver "<"); print; next }
{ print }
' "$INFO_PLIST" > "${INFO_PLIST}.tmp" && mv "${INFO_PLIST}.tmp" "$INFO_PLIST"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to update version in Info.plist${NC}"
    exit 1
fi

# Verify the changes
if ! grep -q "<string>${VERSION}</string>" "$INFO_PLIST"; then
    echo -e "${RED}Error: Failed to update version in Info.plist. Version string not found.${NC}"
    exit 1
fi

echo -e "${GREEN}Version updated in Info.plist${NC}"

# Commit the changes
echo -e "${YELLOW}Committing changes...${NC}"
git add "$INFO_PLIST"
git commit -m "Bump version to ${VERSION}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to commit changes${NC}"
    exit 1
fi

echo -e "${GREEN}Changes committed${NC}"

# Create and push tag
echo -e "${YELLOW}Creating and pushing tag v${VERSION}...${NC}"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to push tag${NC}"
    exit 1
fi

echo -e "${GREEN}Tag v${VERSION} created and pushed${NC}"
echo -e "${YELLOW}GitHub Actions will now build and create a release automatically.${NC}"
echo -e "${YELLOW}You can check the progress at:${NC}"
echo -e "${GREEN}https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:\/]\(.*\)\.git/\1/')/actions${NC}"
