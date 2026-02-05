#!/bin/bash
# Build script for SheetSync

set -e

# Quit existing app if running
pkill -x sheetsync 2>/dev/null || true

echo "Building SheetSync..."

# Build release
swift build -c release

# Create app bundle structure in .build/
mkdir -p .build/sheetsync.app/Contents/MacOS
mkdir -p .build/sheetsync.app/Contents/Resources

# Copy executable
cp .build/release/sheetsync .build/sheetsync.app/Contents/MacOS/

# Copy Info.plist
cp SheetSync/App/Info.plist .build/sheetsync.app/Contents/

# Create PkgInfo
echo -n "APPL????" > .build/sheetsync.app/Contents/PkgInfo

echo "Build complete: .build/sheetsync.app"
echo ""
echo "To run: open .build/sheetsync.app"
