#!/bin/bash
# LittleRip weekly refresh — rebuilds/reinstalls LittleRip iOS + WebDriverAgent
# Keeps free Apple Developer signed apps fresh before the 7-day expiry.

set -e

[ -f "$(dirname "$0")/local-env.sh" ] && . "$(dirname "$0")/local-env.sh"

IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-B479D7DF-EF99-58E9-93CD-CB993DDBAD18}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-72CK386HNT}"
WDA_PROJECT_DIR="${WDA_PROJECT_DIR:-/Users/maxrippley/Developer/WebDriverAgent}"
WDA_BUNDLE_ID="${WDA_BUNDLE_ID:-com.maxautomize.WebDriverAgentRunner}"

install_app() {
  local app_path="$1"
  local app_name="$2"

  if [ -z "$IOS_DEVICE_UDID" ]; then
    echo "⚠️  No IOS_DEVICE_UDID set."
    return 0
  fi

  if [ -d "$app_path" ]; then
    echo "📦 Installing $app_name..."
    xcrun devicectl device install app \
      --device "$IOS_DEVICE_UDID" \
      "$app_path" >/tmp/${app_name}-install.log 2>&1 || {
        echo "⚠️  $app_name install failed. Check /tmp/${app_name}-install.log for the real devicectl error."
        return 0
      }
    echo "✅ $app_name refreshed."
  else
    echo "❌ $app_name app bundle not found: $app_path"
  fi
}

# ─── LittleRip iOS app + widget ───
echo "🔨 Building LittleRip iOS..."
cd /Users/maxrippley/Desktop/LittleRip
xcodegen generate >/dev/null 2>&1
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build >/tmp/littlerip-ios-refresh.log 2>&1 || {
    echo "❌ LittleRip iOS build failed. Check /tmp/littlerip-ios-refresh.log"
    exit 1
  }

IOS_APP=$(find ~/Library/Developer/Xcode/DerivedData/LittleRip-*/Build/Products/Debug-iphoneos/LittleRip.app -maxdepth 0 -type d 2>/dev/null | grep -v Index.noindex | head -1)
install_app "$IOS_APP" "littlerip-ios"

# ─── WebDriverAgent for iphone_* tools ───
echo "🔨 Building WebDriverAgent..."
if [ ! -d "$WDA_PROJECT_DIR/.git" ]; then
  mkdir -p "$(dirname "$WDA_PROJECT_DIR")"
  git clone --depth 1 https://github.com/appium/WebDriverAgent.git "$WDA_PROJECT_DIR"
fi

cd "$WDA_PROJECT_DIR"
git pull --ff-only >/tmp/wda-git-refresh.log 2>&1 || true
xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$WDA_BUNDLE_ID" \
  -allowProvisioningUpdates \
  build >/tmp/wda-refresh.log 2>&1 || {
    echo "❌ WebDriverAgent build failed. Check /tmp/wda-refresh.log"
    exit 1
  }

WDA_APP=$(find ~/Library/Developer/Xcode/DerivedData/WebDriverAgent-*/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app -maxdepth 0 -type d 2>/dev/null | head -1)
install_app "$WDA_APP" "webdriveragent"

echo "Done! LittleRip + WebDriverAgent should be valid for 7 more days."
