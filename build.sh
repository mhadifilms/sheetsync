#!/bin/bash
# Build script for GSheet Sync

set -e

# Quit existing app if running
pkill -x GSheetSync 2>/dev/null || true

echo "Building GSheet Sync..."

# Build release
swift build -c release

# Create app bundle structure
mkdir -p build/GSheetSync.app/Contents/MacOS
mkdir -p build/GSheetSync.app/Contents/Resources

# Copy executable
cp .build/release/GSheetSync build/GSheetSync.app/Contents/MacOS/

# Copy Info.plist
cp GSheetSync/App/Info.plist build/GSheetSync.app/Contents/

# Create PkgInfo
echo -n "APPL????" > build/GSheetSync.app/Contents/PkgInfo

echo "Build complete: build/GSheetSync.app"

# Open the app
open build/GSheetSync.app
