#!/bin/bash
# Release workflow for MeiPDF:
#   1. build the DMG (build-dmg.sh)
#   2. create a GitHub release and upload the DMG (gh)
#   3. generate + sign the appcast (Sparkle generate_appcast) with the release download URL
#   4. stage appcast.xml at repo root (referenced by SUFeedURL)
#
# Requires: gh (authenticated), and sparkle/ed25519_private.key (gitignored).
set -e
cd "$(dirname "$0")"

REPO="tomtrije/MeiPDF"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v${VERSION}"
DMG="MeiPDF-${VERSION}.dmg"

echo "==> [1/4] Building DMG"
bash build-dmg.sh

echo "==> [2/4] Creating GitHub release ${TAG} and uploading ${DMG}"
gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "MeiPDF ${VERSION}" \
    --notes "MeiPDF ${VERSION} 发布" \
    --latest

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"

# Locate the Sparkle generate_appcast tool.
GEN=$(find .build -name generate_appcast | head -1)
if [ -z "$GEN" ]; then
    echo "!! generate_appcast not found; run 'swift package resolve' first." >&2
    exit 1
fi

echo "==> [3/4] Generating + signing appcast (download prefix: $DOWNLOAD_PREFIX)"
rm -rf Updates
mkdir -p Updates
cp "$DMG" Updates/
"$GEN" --ed-key-file sparkle/ed25519_private.key \
       --download-url-prefix "$DOWNLOAD_PREFIX" \
       Updates/

echo "==> [4/4] Staging appcast.xml at repo root"
cp Updates/appcast.xml appcast.xml

echo
echo "Done. Review appcast.xml, then:"
echo "    git add appcast.xml && git commit -m \"Release ${VERSION} appcast\" && git push"
echo "The DMG is already uploaded to the ${TAG} release."
