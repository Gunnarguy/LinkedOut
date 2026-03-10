#!/bin/zsh
# Build LinkedOut and deploy directly to your iPhone — no Xcode Run button needed.
# Usage: ./deploy-to-phone.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE_ID="B1483F12-4FFD-5534-BA30-29FF48070549"  # Gunnar's Hand Extension (iPhone 16 Pro Max)

echo "🔨 Building for device..."
xcodebuild -project "$PROJECT_DIR/LinkedOut.xcodeproj" \
    -scheme LinkedOut \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    build 2>&1 | grep -E "BUILD|error:" | tail -5

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/LinkedOut-*/Build/Products/Debug-iphoneos -name "LinkedOut.app" -maxdepth 1 2>/dev/null | head -1)

if [[ -z "$APP_PATH" ]]; then
    echo "❌ Build failed — no .app found"
    exit 1
fi

echo "📲 Installing to iPhone..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "🚀 Launching..."
xcrun devicectl device process launch --device "$DEVICE_ID" Gunndamental.LinkedOut

echo "✅ Done!"
