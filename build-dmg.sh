#!/bin/bash
# Build a distributable DMG for MeiPDF. Depends on build-app.sh having produced MeiPDF.app.
#
# Env:
#   MEIPDF_VERSION   version string (default: resolved via version.sh)
set -e
cd "$(dirname "$0")"
source "$(dirname "$0")/version.sh"

VERSION="$(resolve_version)"
export MEIPDF_VERSION="$VERSION"
DMG_NAME="MeiPDF-${VERSION}.dmg"
STAGE=".dmgstage"

# Ensure the app bundle exists and is up to date (also re-resolves VERSION for the app).
bash build-app.sh

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

# Ad-hoc sign the DMG. For distribution, sign the .app with a Developer ID (build-app.sh)
# and notarize the DMG instead.
if command -v codesign >/dev/null 2>&1; then
    codesign --sign - "$DMG_NAME" 2>/dev/null || echo "  (dmg codesign skipped)"
fi

rm -rf "$STAGE"
echo "==> Built $DMG_NAME"
echo "    分发: $DMG_NAME"
