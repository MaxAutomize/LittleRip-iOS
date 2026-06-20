#!/bin/bash
# LittleRip weekly refresh — rebuilds and reinstalls both iOS and macOS apps
# Runs every Friday at noon via launchd

set -e

# Device-specific values (UDID) are sourced from local-env.sh, which is gitignored.
# See local-env.example.sh. Copy it to local-env.sh and fill in your device UDID.
[ -f "$(dirname "$0")/local-env.sh" ] && . "$(dirname "$0")/local-env.sh"

# ─── iOS app ───
echo "🔨 Building LittleRip iOS..."
cd /Users/maxrippley/Desktop/LittleRip
xcodegen generate >/dev/null 2>&1
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build >/tmp/littlerip-ios-refresh.log 2>&1

IOS_APP=$(find ~/Library/Developer/Xcode/DerivedData/LittleRip-*/Build/Products/Debug-iphoneos/LittleRip.app -maxdepth 0 -type d 2>/dev/null | grep -v Index.noindex | head -1)

if [ -n "$IOS_APP" ] && [ -d "$IOS_APP" ] && [ -f "$IOS_APP/Info.plist" ]; then
  if [ -z "$IOS_DEVICE_UDID" ]; then
    echo "⚠️  No IOS_DEVICE_UDID set — copy local-env.example.sh to local-env.sh"
  else
    echo "📦 Installing iOS app..."
    xcrun devicectl device install app \
      --device "$IOS_DEVICE_UDID" \
      "$IOS_APP" >/dev/null 2>&1 || echo "⚠️  iOS install failed — phone may be locked"
    echo "✅ iOS app refreshed."
  fi
else
  echo "❌ iOS build failed. Check /tmp/littlerip-ios-refresh.log"
fi

# ─── macOS app ───
echo "🔨 Building LittleRip macOS..."
cd /Users/maxrippley/Desktop/LittleRipMac
xcodegen generate >/dev/null 2>&1
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=72CK386HNT \
  build >/tmp/littlerip-mac-refresh.log 2>&1

# Find the macOS build by checking for the actual binary (not the iOS app)
MAC_APP=""
for app in $(find ~/Library/Developer/Xcode/DerivedData -name "LittleRip.app" -path "*/Products/Debug/LittleRip.app" -not -path "*/iphoneos*" -not -path "*/iphonesimulator*" -not -path "*/Index.noindex*" -maxdepth 8 2>/dev/null); do
  if [ -f "$app/Contents/MacOS/LittleRip" ]; then
    MAC_APP="$app"
    break
  fi
done

if [ -n "$MAC_APP" ] && [ -d "$MAC_APP" ]; then
  echo "📦 Installing macOS app..."
  pkill -f "/Applications/LittleRip.app" 2>/dev/null || true
  sleep 1
  rm -rf /Applications/LittleRip.app
  cp -R "$MAC_APP" /Applications/LittleRip.app
  echo "✅ macOS app refreshed at /Applications/LittleRip.app"
  open /Applications/LittleRip.app
else
  echo "❌ macOS build failed. Check /tmp/littlerip-mac-refresh.log"
fi

echo "Done! Both apps valid for 7 more days."