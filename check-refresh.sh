#!/bin/bash
# LittleRip refresh — runs at Friday noon OR at login if app is expired
# The launchd job handles the schedule; this script checks if a refresh is needed

# Check if LittleRip.iOS provisioning profile is within 1 day of expiry
# If so, force a refresh regardless of day
NEEDS_REFRESH=false

# Check iOS app age — if no build in last 6 days, refresh
IOS_APP=$(find ~/Library/Developer/Xcode/DerivedData/LittleRip-*/Build/Products/Debug-iphoneos/LittleRip.app -maxdepth 0 -type d 2>/dev/null | grep -v Index.noindex | head -1)
if [ -n "$IOS_APP" ]; then
  BUILD_AGE=$(( $(date +%s) - $(stat -f %m "$IOS_APP") ))
  if [ $BUILD_AGE -gt 518400 ]; then  # 6 days in seconds
    NEEDS_REFRESH=true
    echo "iOS app is older than 6 days, refreshing..."
  fi
else
  NEEDS_REFRESH=true
  echo "No iOS app found, refreshing..."
fi

# Check macOS app age
MAC_APP="/Applications/LittleRip.app"
if [ -d "$MAC_APP" ]; then
  MAC_AGE=$(( $(date +%s) - $(stat -f %m "$MAC_APP") ))
  if [ $MAC_AGE -gt 518400 ]; then
    NEEDS_REFRESH=true
    echo "macOS app is older than 6 days, refreshing..."
  fi
else
  NEEDS_REFRESH=true
  echo "macOS app missing, refreshing..."
fi

if [ "$NEEDS_REFRESH" = true ]; then
  exec /Users/maxrippley/Desktop/LittleRip/refresh.sh
else
  echo "Apps are fresh, no refresh needed."
fi