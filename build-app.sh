#!/bin/bash
# Build MeiPDF as a runnable .app bundle (no Xcode required), embedding Sparkle
# for auto-update.
set -e
cd "$(dirname "$0")"

echo "==> Building (release) with swift build"
swift build -c release --disable-sandbox

APP="MeiPDF.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/MeiPDF "$APP/Contents/MacOS/MeiPDF"
cp Resources/Info.plist "$APP/Contents/Info.plist"

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

# Ad-hoc code-sign so macOS launches it without Gatekeeper warnings.
# --deep also signs the embedded Sparkle.framework.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
fi

echo "==> Built $APP"
echo "    运行: open $APP"
