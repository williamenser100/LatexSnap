#!/bin/bash
# Build Debug app and deploy that exact build to /Applications.
# Intentionally does NOT re-sign: TCC permissions are tied to code signing identity.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DEST="/Applications/LatexSnap.app"

echo "→ Clean + build Debug app (forces AppIcon / asset catalog to rebuild)..."
cd "$PROJECT_DIR"

# Bust stale actool/Xcode caches when only PNGs changed
touch "LatexSnap/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

BUILD_LOG="$(mktemp)"
cleanup() { rm -f "$BUILD_LOG"; }
trap cleanup EXIT

set +e
xcodebuild \
    -project LatexSnap.xcodeproj \
    -scheme LatexSnap \
    -configuration Debug \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

grep -E "error:|warning: |BUILD SUCCEEDED|BUILD FAILED" "$BUILD_LOG" \
    | grep -v "appintents\|stub executor\|hardened runtime\|provisioning" || true

if [[ "$BUILD_STATUS" -ne 0 ]]; then
    echo "→ xcodebuild failed (exit $BUILD_STATUS)."
    exit "$BUILD_STATUS"
fi

BUILD_DIR="$(xcodebuild \
    -project LatexSnap.xcodeproj \
    -scheme LatexSnap \
    -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk '/^ *BUILT_PRODUCTS_DIR =/{print $3; exit}')"

if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR/LatexSnap.app" ]]; then
    echo "→ error: built app not found at expected path (BUILT_PRODUCTS_DIR=$BUILD_DIR)."
    exit 1
fi

echo "→ Stopping running instance..."
pkill -x LatexSnap 2>/dev/null || true
sleep 0.4

echo "→ Copying Debug build to /Applications..."
rm -rf "$APP_DEST"
ditto "$BUILD_DIR/LatexSnap.app" "$APP_DEST"

echo "→ Removing quarantine xattr (if present)..."
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

touch "$APP_DEST"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    echo "→ Re-registering app with Launch Services..."
    "$LSREGISTER" -f "$APP_DEST" >/dev/null 2>&1 || true
fi

echo ""
echo "✓ Done. /Applications now uses the same build/signature profile as Debug."
echo "  If Screen Recording was granted to another LatexSnap entry before, reset once:"
echo "  tccutil reset ScreenCapture com.latexsnap.app"
echo ""
echo "  App icon still old in Finder/Dock? (Menu bar Ξ is separate — that is code, not AppIcon.)"
echo "    rm -rf \"\$HOME/Library/Caches/com.apple.iconservices.store\""
echo "    killall Dock; killall Finder"
echo "  Remove LatexSnap from the Dock if it is pinned, then open the app again."
