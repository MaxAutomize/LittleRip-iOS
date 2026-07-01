#!/bin/bash
# LittleRip weekly refresh — rebuilds/reinstalls LittleRip iOS + WebDriverAgent.
# Keeps free Apple Developer signed apps fresh before the 7-day expiry.

set -e

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

[ -f "$(dirname "$0")/local-env.sh" ] && . "$(dirname "$0")/local-env.sh"

IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-B479D7DF-EF99-58E9-93CD-CB993DDBAD18}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-72CK386HNT}"
WDA_PROJECT_DIR="${WDA_PROJECT_DIR:-/Users/maxrippley/Developer/WebDriverAgent}"
WDA_BUNDLE_ID="${WDA_BUNDLE_ID:-com.maxautomize.WebDriverAgentRunner}"

newest_bundle() {
  local path_match="$1"
  local newest=""
  local newest_mtime=0
  local p m

  while IFS= read -r -d '' p; do
    m=$(stat -f %m "$p" 2>/dev/null || echo 0)
    if [ "$m" -gt "$newest_mtime" ]; then
      newest_mtime="$m"
      newest="$p"
    fi
  done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -path "$path_match" -type d -prune -print0 2>/dev/null)

  echo "$newest"
}

print_profile_expiration() {
  local label="$1"
  local app_path="$2"
  local profile="$app_path/embedded.mobileprovision"
  local tmp exp_iso

  if [ ! -f "$profile" ]; then
    echo "⚠️  $label has no embedded.mobileprovision at $profile"
    return 0
  fi

  tmp=$(mktemp /tmp/littlerip-profile.XXXXXX.plist)
  if security cms -D -i "$profile" >"$tmp" 2>/dev/null; then
    exp_iso=$(plutil -extract ExpirationDate raw -o - "$tmp" 2>/dev/null || true)
    [ -n "$exp_iso" ] && echo "🪪 $label provisioning expires: $exp_iso"
  fi
  rm -f "$tmp"
}

install_app() {
  local app_path="$1"
  local app_name="$2"

  if [ -z "$IOS_DEVICE_UDID" ]; then
    echo "❌ No IOS_DEVICE_UDID set. Put it in local-env.sh."
    return 1
  fi

  if [ ! -d "$app_path" ]; then
    echo "❌ $app_name app bundle not found: $app_path"
    return 1
  fi

  print_profile_expiration "$app_name" "$app_path"
  echo "📦 Installing $app_name to $IOS_DEVICE_UDID..."
  if ! xcrun devicectl device install app --device "$IOS_DEVICE_UDID" "$app_path" >/tmp/${app_name}-install.log 2>&1; then
    echo "❌ $app_name install failed. Real error:"
    cat /tmp/${app_name}-install.log
    return 1
  fi

  echo "✅ $app_name refreshed/installed."
}

# ─── LittleRip iOS app + widget ───
echo "🔨 Building LittleRip iOS..."
cd /Users/maxrippley/Desktop/LittleRip
xcodegen generate >/tmp/littlerip-xcodegen-refresh.log 2>&1
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build >/tmp/littlerip-ios-refresh.log 2>&1 || {
    echo "❌ LittleRip iOS build failed. Check /tmp/littlerip-ios-refresh.log"
    tail -120 /tmp/littlerip-ios-refresh.log
    exit 1
  }

IOS_APP=$(newest_bundle "*/LittleRip-*/Build/Products/Debug-iphoneos/LittleRip.app")
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
    tail -120 /tmp/wda-refresh.log
    exit 1
  }

WDA_APP=$(newest_bundle "*/WebDriverAgent-*/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app")
install_app "$WDA_APP" "webdriveragent"

echo "Done! LittleRip + WebDriverAgent should be valid for 7 more days."
