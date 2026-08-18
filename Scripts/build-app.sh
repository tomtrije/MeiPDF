#!/bin/bash
# Build MeiPDF as a runnable .app bundle (no Xcode required), embedding Sparkle
# for auto-update.
#
# Env:
#   MEIPDF_VERSION   version string (default: resolved via Scripts/version.sh)
#   SIGN_IDENTITY    codesign identity. If unset/'-', ad-hoc signs. Set to e.g.
#                    "Developer ID Application: <name> (TEAMID)" for distribution.
set -e
# Always operate from the project root, regardless of where this script is invoked.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "Scripts/version.sh"

VERSION="$(resolve_version)"
export MEIPDF_VERSION="$VERSION"
echo "==> Version: $VERSION"

echo "==> Building (release) with swift build"
swift build -c release --disable-sandbox

APP="MeiPDF.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/MeiPDF "$APP/Contents/MacOS/MeiPDF"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Inject the resolved version into the embedded Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# Locate the resolved Sparkle.framework (macOS slice of the XCFramework) and embed it.
SPARKLE_FW=$(find .build -path "*Sparkle.xcframework/macos-*" -name "Sparkle.framework" | head -1)
if [ -z "$SPARKLE_FW" ]; then
    echo "!! Sparkle.framework not found; run 'swift package resolve' first." >&2
    exit 1
fi
echo "==> Embedding Sparkle from $SPARKLE_FW"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# The binary links Sparkle via @rpath; add the standard app Frameworks search path so the
# embedded framework is found at runtime.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/MeiPDF" 2>/dev/null || echo "  (rpath already present)"

# Code-sign. Ad-hoc by default; with SIGN_IDENTITY set, use hardened runtime for notarization.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if command -v codesign >/dev/null 2>&1; then
  if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Ad-hoc signing $APP"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
  else
    echo "==> Signing $APP with $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime "$APP" >/dev/null 2>&1 \
      || { echo "!! codesign failed" >&2; exit 1; }
  fi
fi

echo "==> Built $APP"
echo "    运行: open $APP"
