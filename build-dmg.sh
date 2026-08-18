#!/bin/bash
# Build a distributable DMG for MeiPDF. Depends on build-app.sh having produced MeiPDF.app.
set -e
cd "$(dirname "$0")"

# Ensure the app bundle exists and is up to date.
bash build-app.sh

# Read the version from Info.plist.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG_NAME="MeiPDF-${VERSION}.dmg"
STAGE=".dmgstage"

echo "==> Building DMG $DMG_NAME (version $VERSION)"
rm -rf "$STAGE" "$DMG_NAME"
mkdir -p "$STAGE"

cp -R MeiPDF.app "$STAGE/MeiPDF.app"
# Drag-to-Applications shortcut.
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "MeiPDF ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG_NAME"

# Ad-hoc sign the DMG (optional; for distribution use a Developer ID + notarization).
if command -v codesign >/dev/null 2>&1; then
    codesign --sign - "$DMG_NAME" 2>/dev/null || echo "  (dmg codesign skipped)"
fi

rm -rf "$STAGE"
echo "==> Built $DMG_NAME"
echo "    分发: $DMG_NAME"
