#!/bin/bash
# Build and package SheetSync as a DMG

set -e

# Configuration
APP_NAME="sheetsync"  # App bundle name
DIST_DIR=".build/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_NAME="sheetsync"  # DMG name
VERSION=$(grep -A1 "CFBundleShortVersionString" SheetSync/App/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
DMG_FILE="${DIST_DIR}/${DMG_NAME}-${VERSION}.dmg"
VOLUME_NAME="sheetsync ${VERSION}"

echo "Building sheetsync v${VERSION}..."

# Quit existing app if running
pkill -x sheetsync 2>/dev/null || true

# Clean previous dist builds (keep .build/release and .build/debug)
rm -rf "${DIST_DIR}"

# Backup real Secrets.swift and replace with placeholder for release build
# This ensures the DMG doesn't contain developer's OAuth client ID
SECRETS_FILE="SheetSync/Config/Secrets.swift"
SECRETS_BACKUP=""
if [ -f "${SECRETS_FILE}" ]; then
    echo "Removing OAuth credentials from release build..."
    SECRETS_BACKUP=$(mktemp)
    cp "${SECRETS_FILE}" "${SECRETS_BACKUP}"

    # Create placeholder Secrets.swift for release
    cat > "${SECRETS_FILE}" << 'SECRETS_EOF'
import Foundation

/// OAuth credentials - users must add their own Client ID in Settings
/// See README.md for setup instructions
enum Secrets {
    static let googleClientId = "YOUR_CLIENT_ID.apps.googleusercontent.com"

    static var googleRedirectScheme: String {
        let prefix = googleClientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    static var googleRedirectURI: String {
        "\(googleRedirectScheme):/oauth2callback"
    }
}
SECRETS_EOF
fi

# Build release
echo "Compiling release build..."
swift build -c release

# Restore real Secrets.swift after build
if [ -n "${SECRETS_BACKUP}" ] && [ -f "${SECRETS_BACKUP}" ]; then
    echo "Restoring development credentials..."
    mv "${SECRETS_BACKUP}" "${SECRETS_FILE}"
fi

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
DMG_TEMP="${DIST_DIR}/dmg_temp"
mkdir -p "${DMG_TEMP}"

# Copy app to temporary directory
cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

# Create Applications symlink
ln -s /Applications "${DMG_TEMP}/Applications"

# Create a styled DMG background (optional, simple text file)
cat > "${DMG_TEMP}/.DS_Store_instructions.txt" << EOF
To install sheetsync:
1. Drag sheetsync.app to the Applications folder
2. Eject this disk image
3. Launch sheetsync from your Applications folder
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

# Upload to GitHub Release
if command -v gh &> /dev/null; then
    echo ""
    echo "Creating GitHub release v${VERSION}..."

    # Check if release already exists
    if gh release view "v${VERSION}" &> /dev/null; then
        echo "Release v${VERSION} already exists. Updating..."
        gh release upload "v${VERSION}" "${DMG_FILE}" --clobber
    else
        # Create new release
        gh release create "v${VERSION}" "${DMG_FILE}" \
            --title "sheetsync v${VERSION}" \
            --notes "## sheetsync v${VERSION}

### Installation
1. Download \`sheetsync-${VERSION}.dmg\`
2. Open the DMG and drag sheetsync to Applications
3. Launch sheetsync from Applications
4. Go to Settings → Developer Settings and add your Google OAuth Client ID
5. Sign in with Google and start syncing!

### Setup
You need a Google OAuth Client ID to use this app. See [README](https://github.com/mhadifilms/sheetsync#2-create-google-oauth-credentials) for setup instructions.

### Changes
- Initial release
"
    fi

    RELEASE_URL=$(gh release view "v${VERSION}" --json url -q .url)
    echo "✅ Released to GitHub: ${RELEASE_URL}"
else
    echo ""
    echo "To upload to GitHub, install gh CLI and run:"
    echo "  gh release create v${VERSION} ${DMG_FILE} --title 'sheetsync v${VERSION}'"
fi

echo ""
echo "To test the app: open ${APP_BUNDLE}"
echo "To test the DMG: open ${DMG_FILE}"
