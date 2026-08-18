#!/bin/bash
# Build a distributable DMG for MeiPDF. Depends on Scripts/build-app.sh having
# produced MeiPDF.app. The resulting DMG is written to Distribution/.
#
# Env:
#   MEIPDF_VERSION   version string (default: resolved via Scripts/version.sh)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "Scripts/version.sh"

VERSION="$(resolve_version)"
export MEIPDF_VERSION="$VERSION"
DMG_NAME="Distribution/MeiPDF-${VERSION}.dmg"
STAGE=".dmgstage"

# Ensure the app bundle exists and is up to date (also re-resolves VERSION for the app).
bash Scripts/build-app.sh

echo "==> Building DMG $DMG_NAME (version $VERSION)"
mkdir -p "$(dirname "$DMG_NAME")"
rm -rf "$STAGE" "$DMG_NAME"
mkdir -p "$STAGE"

cp -R MeiPDF.app "$STAGE/MeiPDF.app"
# Drag-to-Applications shortcut.
ln -s /Applications "$STAGE/Applications"

# Self-use helper: a double-clickable script that strips Gatekeeper quarantine so an
# ad-hoc (unsigned) build can launch, plus a short README. Harmless when the app is
# Developer-ID-signed and notarized. These live in Distribution/Installer/.
if [ -f Distribution/Installer/install.command ]; then
  cp Distribution/Installer/install.command "$STAGE/install.command"
  chmod +x "$STAGE/install.command"
fi
[ -f Distribution/Installer/README.txt ] && cp Distribution/Installer/README.txt "$STAGE/README.txt"

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
