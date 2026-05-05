#!/bin/bash
# Build, sign with the stable cert, and deploy to /Applications.
# Run this instead of manually invoking xcodebuild.

set -e

CERT_NAME="LatexSnap Dev"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DEST="/Applications/LatexSnap.app"

# Ensure the signing certificate exists
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
    echo "Signing certificate not found. Run ./setup_signing.sh first."
    exit 1
fi

echo "→ Building..."
cd "$PROJECT_DIR"
xcodebuild \
    -project LatexSnap.xcodeproj \
    -scheme LatexSnap \
    -configuration Debug \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | grep -E "error:|warning: |BUILD SUCCEEDED|BUILD FAILED" \
               | grep -v "appintents\|stub executor\|hardened runtime\|provisioning"

BUILD_DIR=$(xcodebuild \
    -project LatexSnap.xcodeproj \
    -scheme LatexSnap \
    -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk '/^ *BUILT_PRODUCTS_DIR =/{print $3; exit}')

echo "→ Stopping running instance..."
pkill -x LatexSnap 2>/dev/null || true
sleep 0.4

echo "→ Copying to /Applications..."
rm -rf "$APP_DEST"
cp -R "$BUILD_DIR/LatexSnap.app" "$APP_DEST"

echo "→ Signing with '$CERT_NAME'..."
codesign --force --deep --options runtime --sign "$CERT_NAME" "$APP_DEST"

echo ""
echo "✓ Done. Launch /Applications/LatexSnap.app"
echo ""
echo "  First run after a fresh install: grant Screen Recording when prompted."
echo "  (You only need to do this once — the stable cert means it persists.)"
