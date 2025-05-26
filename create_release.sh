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
