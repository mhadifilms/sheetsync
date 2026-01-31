#!/bin/bash
# Build script for SheetSync

set -e

# Quit existing app if running
pkill -x sheetsync 2>/dev/null || true

echo "Building SheetSync..."

# Build release
swift build -c release

# Create app bundle structure
mkdir -p build/SheetSync.app/Contents/MacOS
mkdir -p build/SheetSync.app/Contents/Resources

# Copy executable
cp .build/release/sheetsync build/SheetSync.app/Contents/MacOS/

# Copy Info.plist
cp SheetSync/App/Info.plist build/SheetSync.app/Contents/

# Create PkgInfo
echo -n "APPL????" > build/SheetSync.app/Contents/PkgInfo

echo "Build complete: build/SheetSync.app"
echo ""
echo "To run: open build/SheetSync.app"
