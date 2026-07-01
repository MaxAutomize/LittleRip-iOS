#!/bin/bash
# LittleRip refresh checker — runs at login and every 6 hours via launchd.
# Refreshes before free Apple Developer signing hits the 7-day expiry.
# IMPORTANT: checks embedded.mobileprovision expiration, not app bundle mtime.

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

NEEDS_REFRESH=false
REFRESH_WITHIN=172800 # 2 days remaining; free profiles last 7 days
NOW=$(date +%s)

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

profile_expiration_epoch() {
  local bundle_path="$1"
  local profile="$bundle_path/embedded.mobileprovision"
  local tmp exp_iso exp_epoch

  [ -f "$profile" ] || return 1

  tmp=$(mktemp /tmp/littlerip-profile.XXXXXX.plist)
  if ! security cms -D -i "$profile" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi

  exp_iso=$(plutil -extract ExpirationDate raw -o - "$tmp" 2>/dev/null || true)
  rm -f "$tmp"
  [ -n "$exp_iso" ] || return 1

  exp_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$exp_iso" +%s 2>/dev/null || true)
  [ -n "$exp_epoch" ] || return 1
  echo "$exp_epoch"
}

check_profile_expiration() {
  local label="$1"
  local bundle_path="$2"
  local exp_epoch remaining exp_display

  if [ -z "$bundle_path" ] || [ ! -d "$bundle_path" ]; then
    NEEDS_REFRESH=true
    echo "$label not found, refreshing..."
    return
  fi

  if ! exp_epoch=$(profile_expiration_epoch "$bundle_path"); then
    NEEDS_REFRESH=true
    echo "$label provisioning profile missing/unreadable, refreshing..."
    return
  fi

  remaining=$(( exp_epoch - NOW ))
  exp_display=$(date -r "$exp_epoch" "+%Y-%m-%d %H:%M:%S %Z")

  if [ "$remaining" -le 0 ]; then
    NEEDS_REFRESH=true
    echo "$label provisioning profile expired at $exp_display, refreshing..."
  elif [ "$remaining" -le "$REFRESH_WITHIN" ]; then
    NEEDS_REFRESH=true
    echo "$label provisioning profile expires soon ($exp_display), refreshing..."
  else
    echo "$label provisioning profile is fresh until $exp_display."
  fi
}

IOS_APP=$(newest_bundle "*/LittleRip-*/Build/Products/Debug-iphoneos/LittleRip.app")
WIDGET_APP=""
[ -n "$IOS_APP" ] && WIDGET_APP="$IOS_APP/PlugIns/LittleRipWidgetExtension.appex"
WDA_APP=$(newest_bundle "*/WebDriverAgent-*/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app")

check_profile_expiration "LittleRip iOS app" "$IOS_APP"
check_profile_expiration "LittleRip widget extension" "$WIDGET_APP"
check_profile_expiration "WebDriverAgent" "$WDA_APP"

if [ "$NEEDS_REFRESH" = true ]; then
  echo "Running refresh.sh..."
  exec "$(dirname "$0")/refresh.sh"
else
  echo "LittleRip iOS app + widget + WebDriverAgent signing are fresh; no refresh needed."
fi
