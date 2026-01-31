#!/bin/bash
# Build and package SheetSync as a DMG

set -e

# Configuration
APP_NAME="SheetSync"
APP_BUNDLE="build/${APP_NAME}.app"
DMG_NAME="SheetSync"
VERSION=$(grep -A1 "CFBundleShortVersionString" SheetSync/App/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
DMG_FILE="build/${DMG_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"

echo "Building ${APP_NAME} v${VERSION}..."

# Quit existing app if running
pkill -x sheetsync 2>/dev/null || true

# Clean previous builds
rm -rf build/

# Build release
echo "Compiling release build..."
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp .build/release/sheetsync "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
cp SheetSync/App/Info.plist "${APP_BUNDLE}/Contents/"

# Copy entitlements (for reference, not used in unsigned build)
cp SheetSync/App/GSheetSync.entitlements "${APP_BUNDLE}/Contents/"

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Try to extract icon from Assets.xcassets (if actool is available)
if command -v actool &> /dev/null; then
    echo "Extracting app icon..."
    actool SheetSync/Resources/Assets.xcassets \
        --compile "${APP_BUNDLE}/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /tmp/partial.plist \
        2>/dev/null || echo "Note: Could not extract icon assets"
fi

# Create DMG
echo "Creating DMG..."

# Create temporary directory for DMG contents
DMG_TEMP="build/dmg_temp"
mkdir -p "${DMG_TEMP}"

# Copy app to temporary directory
cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

# Create Applications symlink
ln -s /Applications "${DMG_TEMP}/Applications"

# Create a styled DMG background (optional, simple text file)
cat > "${DMG_TEMP}/.DS_Store_instructions.txt" << EOF
To install ${APP_NAME}:
1. Drag ${APP_NAME}.app to the Applications folder
2. Eject this disk image
3. Launch ${APP_NAME} from your Applications folder
EOF

# Remove any existing DMG
rm -f "${DMG_FILE}"

# Create DMG using hdiutil
echo "Packaging DMG..."
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_FILE}"

# Clean up temporary directory
rm -rf "${DMG_TEMP}"

# Calculate DMG size
DMG_SIZE=$(du -h "${DMG_FILE}" | cut -f1)

echo ""
echo "✅ Build complete!"
echo "   App Bundle: ${APP_BUNDLE}"
echo "   DMG: ${DMG_FILE} (${DMG_SIZE})"
echo ""
echo "To test the app: open ${APP_BUNDLE}"
echo "To test the DMG: open ${DMG_FILE}"
