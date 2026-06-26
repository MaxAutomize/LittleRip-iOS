#!/bin/bash
# LittleRip refresh checker — runs at login and every 6 hours via launchd.
# Refreshes before free Apple Developer signing hits the 7-day expiry.

NEEDS_REFRESH=false
MAX_AGE=518400 # 6 days

check_bundle_age() {
  local label="$1"
  local bundle_path="$2"

  if [ -n "$bundle_path" ] && [ -d "$bundle_path" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$bundle_path") ))
    if [ "$age" -gt "$MAX_AGE" ]; then
      NEEDS_REFRESH=true
      echo "$label is older than 6 days, refreshing..."
    else
      echo "$label is fresh."
    fi
  else
    NEEDS_REFRESH=true
    echo "$label not found, refreshing..."
  fi
}

IOS_APP=$(find ~/Library/Developer/Xcode/DerivedData/LittleRip-*/Build/Products/Debug-iphoneos/LittleRip.app -maxdepth 0 -type d 2>/dev/null | grep -v Index.noindex | head -1)
WDA_APP=$(find ~/Library/Developer/Xcode/DerivedData/WebDriverAgent-*/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app -maxdepth 0 -type d 2>/dev/null | head -1)

check_bundle_age "LittleRip iOS app" "$IOS_APP"
check_bundle_age "WebDriverAgent" "$WDA_APP"

if [ "$NEEDS_REFRESH" = true ]; then
  exec "$(dirname "$0")/refresh.sh"
else
  echo "LittleRip iOS app + WebDriverAgent are fresh, no refresh needed."
fi
