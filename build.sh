#!/bin/bash

# Build script for WallpaperChanger

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building WallpaperChanger...${NC}"

# Check if Swift is installed
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed or not in your PATH.${NC}"
    echo -e "${YELLOW}Please install Swift from https://swift.org/download/ or via Xcode.${NC}"
    exit 1
fi

# Create build directory if it doesn't exist
mkdir -p .build

# Build the application
echo -e "${YELLOW}Compiling...${NC}"
swift build -c release

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build successful!${NC}"
    
    # Copy the executable to a more accessible location
    cp .build/release/WallpaperChanger ./WallpaperChanger
    
    echo -e "${GREEN}Executable copied to ./WallpaperChanger${NC}"
    echo -e "${YELLOW}You can run the application with:${NC}"
    echo -e "${GREEN}./WallpaperChanger${NC}"
    
    # Ask if user wants to run the application
    echo -e "${YELLOW}Do you want to run the application now? (y/n)${NC}"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Running WallpaperChanger...${NC}"
        ./WallpaperChanger
    fi
else
    echo -e "${RED}Build failed.${NC}"
    exit 1
fi
