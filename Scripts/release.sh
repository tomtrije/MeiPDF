#!/bin/bash
# Local release helper (alternative to the GitHub Actions workflow).
# Builds the DMG, generates the signed Sparkle appcast, and creates/updates the
# GitHub release (uploading the DMG + appcast.xml).
#
# Requires: gh authenticated, and Secrets/ed25519_private.key (gitignored) present.
# The appcast enclosure URL points at the release download dir; SUFeedURL in Info.plist
# points at releases/latest/download/appcast.xml so every release serves the newest.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "Scripts/version.sh"

REPO="tomtrije/MeiPDF"
VERSION="$(resolve_version)"
export MEIPDF_VERSION="$VERSION"
TAG="v${VERSION}"
DMG="Distribution/MeiPDF-${VERSION}.dmg"

echo "==> [1/3] Building DMG"
bash Scripts/build-dmg.sh

echo "==> [2/3] Generating signed appcast"
if [ ! -f Secrets/ed25519_private.key ]; then
  echo "!! Secrets/ed25519_private.key missing (needed to sign the appcast)." >&2
  exit 1
fi
GEN=$(find .build -name generate_appcast | head -1)
if [ -z "$GEN" ]; then
  echo "!! generate_appcast not found; run 'swift package resolve' first." >&2
  exit 1
fi
PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
STAGE="Distribution/.caststage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"
"$GEN" --ed-key-file Secrets/ed25519_private.key \
       --download-url-prefix "$PREFIX" \
       "$STAGE/"
cp "$STAGE/appcast.xml" Distribution/appcast.xml

echo "==> [3/3] Creating/updating release ${TAG}"
FILES=("$DMG" Distribution/appcast.xml)
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "${FILES[@]}" --repo "$REPO" --clobber
else
  gh release create "$TAG" "${FILES[@]}" \
    --repo "$REPO" \
    --title "MeiPDF ${VERSION}" \
    --notes "MeiPDF ${VERSION} 发布" \
    --latest
fi
echo "Done. DMG + signed appcast uploaded to release ${TAG}."
