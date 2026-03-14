#!/bin/zsh
# Double-click this file to rebuild the backend + deploy the app to your iPhone.
# No terminal knowledge needed.

set -e
cd "$(dirname "$0")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  LinkedOut — One-Click Deploy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Rebuild backend (Docker) ──
echo "🐳 Rebuilding backend..."
docker compose down 2>/dev/null || true
docker compose up --build -d

echo "⏳ Waiting for backend to start..."
for i in {1..15}; do
    if curl -sf http://localhost:8443/health > /dev/null 2>&1; then
        echo "✅ Backend is healthy"
        break
    fi
    sleep 1
done

# ── 2. Build & deploy iOS app ──
DEVICE_ID="B1483F12-4FFD-5534-BA30-29FF48070549"

echo ""
echo "🔨 Building iOS app..."
xcodebuild -project LinkedOut.xcodeproj \
    -scheme LinkedOut \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    build 2>&1 | grep -E "BUILD|error:" | tail -5

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/LinkedOut-*/Build/Products/Debug-iphoneos -name "LinkedOut.app" -maxdepth 1 2>/dev/null | head -1)

if [[ -z "$APP_PATH" ]]; then
    echo "❌ Build failed"
    echo ""
    echo "Press any key to close..."
    read -k 1
    exit 1
fi

echo "📲 Installing to iPhone..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "🚀 Launching..."
xcrun devicectl device process launch --device "$DEVICE_ID" Gunndamental.LinkedOut

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Done! App is running on your phone."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press any key to close..."
read -k 1
