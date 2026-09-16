#!/bin/bash
# Manual LittleRip iOS reset backend.
# This file is intentionally invoked by the Pi littlerip_ios_reset tool (or
# refresh.sh as a manual compatibility entrypoint). It never schedules itself.

set -Eeuo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SUPERVISOR_SCRIPT="$SCRIPT_DIR/littlerip-process-supervisor.py"
DEFAULT_PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${LITTLERIP_PROJECT_DIR:-$DEFAULT_PROJECT_DIR}"

# local-env.sh is gitignored and may contain private device overrides. Source it
# without printing it; no credential or account automation is performed here.
if [[ "${LITTLERIP_SOURCE_LOCAL_ENV:-1}" == "1" && -f "$PROJECT_DIR/local-env.sh" ]]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/local-env.sh"
fi
PROJECT_DIR="${LITTLERIP_PROJECT_DIR:-$PROJECT_DIR}"

IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-72CK386HNT}"
APP_BUNDLE_ID="${LITTLERIP_APP_BUNDLE_ID:-com.maxautomize.LittleRip}"
WIDGET_BUNDLE_ID="${LITTLERIP_WIDGET_BUNDLE_ID:-com.maxautomize.LittleRip.LittleRipWidgetExtension}"
PROFILE_DIR="${LITTLERIP_PROFILE_DIR:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles}"
STATE_DIR="${LITTLERIP_STATE_DIR:-$HOME/Library/Application Support/LittleRipRefresh}"
BUILD_DIR="${LITTLERIP_BUILD_DIR:-$STATE_DIR/builds}"
LOG_DIR="${LITTLERIP_LOG_DIR:-$STATE_DIR/logs}"

# Command names are overridable only to make the transaction mockable in local
# regression tests. Normal runs use the signed-in user's Xcode toolchain.
XCODEGEN_BIN="${XCODEGEN_BIN:-xcodegen}"
XCODEBUILD_BIN="${XCODEBUILD_BIN:-xcodebuild}"
XCRUN_BIN="${XCRUN_BIN:-xcrun}"
SECURITY_BIN="${SECURITY_BIN:-security}"
CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
DEFAULTS_BIN="${DEFAULTS_BIN:-defaults}"
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"

PREFLIGHT_TIMEOUT_SECONDS="${LITTLERIP_PREFLIGHT_TIMEOUT_SECONDS:-45}"
GENERATE_TIMEOUT_SECONDS="${LITTLERIP_GENERATE_TIMEOUT_SECONDS:-120}"
BUILD_TIMEOUT_SECONDS="${LITTLERIP_BUILD_TIMEOUT_SECONDS:-1200}"
DEVICE_TIMEOUT_SECONDS="${LITTLERIP_DEVICE_TIMEOUT_SECONDS:-90}"
VERIFY_TIMEOUT_SECONDS="${LITTLERIP_VERIFY_TIMEOUT_SECONDS:-90}"
INSTALL_TIMEOUT_SECONDS="${LITTLERIP_INSTALL_TIMEOUT_SECONDS:-180}"
LAUNCH_TIMEOUT_SECONDS="${LITTLERIP_LAUNCH_TIMEOUT_SECONDS:-90}"
MIN_PROFILE_REMAINING_SECONDS="${LITTLERIP_MIN_PROFILE_REMAINING_SECONDS:-3600}"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
LOCK_DIR="$STATE_DIR/reset.lock"
ACTIVE_RUNNER_PID_FILE="$LOCK_DIR/active-runner.pid"
LOG_PATH="$LOG_DIR/reset-$RUN_ID.log"
PROFILE_BACKUP_DIR=""
RESTORE_QUARANTINED_PROFILES=1
TEMP_FILES=()
CANCEL_REQUESTED=0
ACTIVE_RUNNER_PID=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cancel_active_runner() {
  local pid="${ACTIVE_RUNNER_PID:-}"
  if [[ -z "$pid" && -f "$ACTIVE_RUNNER_PID_FILE" ]]; then
    pid="$(cat "$ACTIVE_RUNNER_PID_FILE" 2>/dev/null || printf '')"
  fi
  if [[ -n "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
}

handle_signal() {
  CANCEL_REQUESTED=1
  cancel_active_runner
}

abort_if_cancelled() {
  if [[ "$CANCEL_REQUESTED" == "1" ]]; then
    exit 130
  fi
}

if [[ "$#" -ne 0 ]]; then
  fail "This manual reset accepts no arguments; invoke the Pi littlerip_ios_reset tool."
fi
[[ -f "$SUPERVISOR_SCRIPT" ]] || fail "Process supervisor is missing: $SUPERVISOR_SCRIPT"

restore_quarantined_profiles() {
  local file base
  [[ -n "$PROFILE_BACKUP_DIR" && -d "$PROFILE_BACKUP_DIR" ]] || return 0
  mkdir -p "$PROFILE_DIR"
  for file in "$PROFILE_BACKUP_DIR"/*.mobileprovision; do
    [[ -e "$file" ]] || continue
    base="$(basename "$file")"
    # Never replace a profile Xcode may have created during this attempt.
    if [[ ! -e "$PROFILE_DIR/$base" ]]; then
      mv "$file" "$PROFILE_DIR/$base"
    else
      rm -f "$file"
    fi
  done
  rm -rf "$PROFILE_BACKUP_DIR"
  PROFILE_BACKUP_DIR=""
}

stop_active_runner() {
  local pid="${ACTIVE_RUNNER_PID:-}"
  if [[ -z "$pid" && -f "$ACTIVE_RUNNER_PID_FILE" ]]; then
    pid="$(cat "$ACTIVE_RUNNER_PID_FILE" 2>/dev/null || printf '')"
  fi
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  ACTIVE_RUNNER_PID=""
  rm -f "$ACTIVE_RUNNER_PID_FILE"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM HUP
  # Do not restore profiles or release the lock until the active supervisor
  # (and its entire stage process group) has stopped and been reaped.
  stop_active_runner
  if [[ "$RESTORE_QUARANTINED_PROFILES" == "1" ]]; then
    restore_quarantined_profiles || true
  elif [[ -n "$PROFILE_BACKUP_DIR" ]]; then
    rm -rf "$PROFILE_BACKUP_DIR"
    PROFILE_BACKUP_DIR=""
  fi
  local temp_file
  if (( ${#TEMP_FILES[@]} > 0 )); then
    for temp_file in "${TEMP_FILES[@]}"; do
      rm -f "$temp_file"
    done
  fi
  rm -rf "$LOCK_DIR"
  exit "$status"
}

mkdir -p "$STATE_DIR" "$BUILD_DIR" "$LOG_DIR"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  owner='unknown'
  [[ -f "$LOCK_DIR/pid" ]] && owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || printf unknown)"
  fail "Another LittleRip iOS reset is already running (lock owner: $owner). Wait for it to finish; no second build was started."
fi
printf '%s\n' "$$" >"$LOCK_DIR/pid"
printf '%s\n' "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$LOG_PATH"
chmod 600 "$LOG_PATH"
trap cleanup EXIT
trap 'handle_signal' INT TERM HUP

run_bounded() {
  local seconds="$1"
  shift
  # exec is important: when run in the background below, the tracked PID is
  # the Python supervisor itself, not an intermediate Bash process.
  exec "$PYTHON_BIN" "$SUPERVISOR_SCRIPT" "$seconds" "$@"
}

run_bounded_wait() {
  local timeout_seconds="$1"
  shift
  local runner_pid status=0
  run_bounded "$timeout_seconds" "$@" &
  runner_pid=$!
  ACTIVE_RUNNER_PID="$runner_pid"
  printf '%s\n' "$runner_pid" >"$ACTIVE_RUNNER_PID_FILE"
  if wait "$runner_pid"; then
    status=0
  else
    status=$?
  fi
  # Bash can return from wait when its own TERM trap runs. Wait again until the
  # supervisor has actually reaped the stage group before clearing the PID.
  if [[ "$CANCEL_REQUESTED" == "1" ]] && kill -0 "$runner_pid" 2>/dev/null; then
    wait "$runner_pid" 2>/dev/null || true
  fi
  ACTIVE_RUNNER_PID=""
  rm -f "$ACTIVE_RUNNER_PID_FILE"
  if [[ "$CANCEL_REQUESTED" == "1" && "$status" == "0" ]]; then
    status=130
  fi
  return "$status"
}

run_stage() {
  local label="$1"
  local timeout_seconds="$2"
  shift 2
  local status
  abort_if_cancelled
  printf 'stage=%s\n' "$label" | tee -a "$LOG_PATH"
  if run_bounded_wait "$timeout_seconds" "$@" >>"$LOG_PATH" 2>&1; then
    printf 'stage=%s status=ok\n' "$label" | tee -a "$LOG_PATH"
    return 0
  else
    status=$?
  fi
  printf 'stage=%s status=failed code=%s\n' "$label" "$status" | tee -a "$LOG_PATH" >&2
  tail -80 "$LOG_PATH" >&2 || true
  return "$status"
}

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "Required command is unavailable: $name"
}

printf 'LittleRip iOS reset started (manual, foreground-only)\n'
printf 'log_path=%s\n' "$LOG_PATH"

[[ -d "$PROJECT_DIR/LittleRip.xcodeproj" ]] || fail "LittleRip.xcodeproj was not found at $PROJECT_DIR"
[[ -n "$IOS_DEVICE_UDID" ]] || fail "IOS_DEVICE_UDID is not configured. Set it in the gitignored local-env.sh; no device action was attempted."
cd "$PROJECT_DIR"

require_command "$XCODEGEN_BIN"
require_command "$XCODEBUILD_BIN"
require_command "$XCRUN_BIN"
require_command "$SECURITY_BIN"
require_command "$CODESIGN_BIN"
require_command "$DEFAULTS_BIN"
require_command "$PYTHON_BIN"

# Read-only account metadata check. This intentionally does not sign in, touch
# Keychain credentials, or attempt password/2FA automation.
account_plist="$(mktemp /tmp/littlerip-xcode-account.plist.XXXXXX)"
account_err="$(mktemp /tmp/littlerip-xcode-account.err.XXXXXX)"
TEMP_FILES+=("$account_plist" "$account_err")
account_status=0
run_bounded_wait "$PREFLIGHT_TIMEOUT_SECONDS" "$DEFAULTS_BIN" export com.apple.dt.Xcode - >"$account_plist" 2>"$account_err" || account_status=$?
abort_if_cancelled
if (( account_status != 0 )); then
  rm -f "$account_plist" "$account_err"
  fail "Could not inspect Xcode Apple Account metadata. Open Xcode → Settings → Apple Accounts and sign in if needed."
fi
if ! "$PYTHON_BIN" - "$account_plist" <<'PY'
import plistlib
import sys
try:
    with open(sys.argv[1], "rb") as fh:
        data = plistlib.load(fh)
    accounts = data.get("DVTDeveloperAccountManagerAppleIDLists")
    present = bool(accounts) if isinstance(accounts, (dict, list)) else False
except Exception:
    present = False
sys.exit(0 if present else 1)
PY
then
  rm -f "$account_plist" "$account_err"
  fail "No Xcode Apple Account is available. Sign in under Xcode → Settings → Apple Accounts, then retry; no build or install was attempted."
fi
rm -f "$account_plist" "$account_err"
TEMP_FILES=()
printf 'preflight=xcode-account-present\n'

if ! run_stage "device-preflight" "$DEVICE_TIMEOUT_SECONDS" "$XCRUN_BIN" devicectl device info details --device "$IOS_DEVICE_UDID"; then
  fail "The iPhone is not available to devicectl. Unlock it, keep it connected and paired, then retry; no install was attempted."
fi

if ! run_stage "generate-project" "$GENERATE_TIMEOUT_SECONDS" "$XCODEGEN_BIN" generate; then
  fail "XcodeGen could not generate the project. See $LOG_PATH"
fi

if ! run_stage "signing-preflight" "$PREFLIGHT_TIMEOUT_SECONDS" "$XCODEBUILD_BIN" \
  -project "$PROJECT_DIR/LittleRip.xcodeproj" \
  -scheme LittleRip \
  -destination generic/platform=iOS \
  -showBuildSettings \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic; then
  fail "Xcode signing/project preflight failed. Check Xcode account, team selection, and $LOG_PATH"
fi

# Move only cached profiles belonging to LittleRip out of Xcode's cache. They
# are restored automatically if any later stage fails. This nudges Xcode to ask
# Apple for a current profile without deleting unrelated profiles.
quarantine_cached_profiles() {
  local file decoded app_id base moved=0
  [[ -d "$PROFILE_DIR" ]] || return 0
  PROFILE_BACKUP_DIR="$(mktemp -d "$STATE_DIR/profile-backup.XXXXXX")"
  for file in "$PROFILE_DIR"/*.mobileprovision; do
    [[ -e "$file" ]] || continue
    decoded="$(mktemp /tmp/littlerip-profile.plist.XXXXXX)"
    if run_bounded_wait "$VERIFY_TIMEOUT_SECONDS" "$SECURITY_BIN" cms -D -i "$file" >"$decoded" 2>>"$LOG_PATH"; then
      app_id="$($PYTHON_BIN - "$decoded" <<'PY'
import plistlib
import sys
try:
    with open(sys.argv[1], "rb") as fh:
        data = plistlib.load(fh)
    print((data.get("Entitlements") or {}).get("application-identifier", ""))
except Exception:
    print("")
PY
)"
      case "$app_id" in
        "$DEVELOPMENT_TEAM.$APP_BUNDLE_ID"|"$DEVELOPMENT_TEAM.$WIDGET_BUNDLE_ID")
          base="$(basename "$file")"
          mv "$file" "$PROFILE_BACKUP_DIR/$base"
          moved=$((moved + 1))
          ;;
      esac
    fi
    rm -f "$decoded"
  done
  if [[ "$moved" == "0" ]]; then
    rm -rf "$PROFILE_BACKUP_DIR"
    PROFILE_BACKUP_DIR=""
    printf 'profile-cache=no-target-profiles\n'
  else
    printf 'profile-cache=quarantined-target-profiles count=%s\n' "$moved"
  fi
}
quarantine_cached_profiles
abort_if_cancelled

BUILD_ATTEMPT="$BUILD_DIR/$RUN_ID"
if ! run_stage "build-signed-app-and-widget" "$BUILD_TIMEOUT_SECONDS" "$XCODEBUILD_BIN" \
  -project "$PROJECT_DIR/LittleRip.xcodeproj" \
  -scheme LittleRip \
  -derivedDataPath "$BUILD_ATTEMPT" \
  -destination generic/platform=iOS \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build; then
  fail "Signed LittleRip build failed. The installed app was not changed. Sign in or resolve the Xcode error, then retry; see $LOG_PATH"
fi

IOS_APP="$BUILD_ATTEMPT/Build/Products/Debug-iphoneos/LittleRip.app"
WIDGET_APP="$IOS_APP/PlugIns/LittleRipWidgetExtension.appex"
[[ -d "$IOS_APP" ]] || fail "The signed build did not produce LittleRip.app; the installed app was not changed. See $LOG_PATH"
[[ -d "$WIDGET_APP" ]] || fail "The signed build did not embed LittleRipWidgetExtension.appex; the installed app was not changed. See $LOG_PATH"

profile_metadata() {
  local label="$1"
  local bundle_path="$2"
  local expected_id="$3"
  local profile="$bundle_path/embedded.mobileprovision"
  local decoded metadata uuid app_id epoch expiry remaining
  [[ -f "$profile" ]] || fail "$label has no embedded.mobileprovision; the installed app was not changed. See $LOG_PATH"
  decoded="$(mktemp /tmp/littlerip-profile.plist.XXXXXX)"
  if ! run_bounded_wait "$VERIFY_TIMEOUT_SECONDS" "$SECURITY_BIN" cms -D -i "$profile" >"$decoded" 2>>"$LOG_PATH"; then
    rm -f "$decoded"
    fail "$label embedded provisioning profile could not be decoded; the installed app was not changed. See $LOG_PATH"
  fi
  metadata="$($PYTHON_BIN - "$decoded" <<'PY'
import datetime
import plistlib
import sys

try:
    with open(sys.argv[1], "rb") as fh:
        data = plistlib.load(fh)
    entitlements = data.get("Entitlements") or {}
    uuid = str(data.get("UUID", ""))
    app_id = str(entitlements.get("application-identifier", ""))
    exp = data.get("ExpirationDate")
    if isinstance(exp, datetime.datetime):
        dt = exp
    elif isinstance(exp, str):
        text = exp.strip().replace("Z", "+00:00")
        dt = datetime.datetime.fromisoformat(text)
    else:
        raise ValueError("missing ExpirationDate")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    dt = dt.astimezone(datetime.timezone.utc)
    print(f"{uuid}\t{app_id}\t{int(dt.timestamp())}\t{dt.strftime('%Y-%m-%dT%H:%M:%SZ')}")
except Exception as exc:
    print(f"ERROR: {exc}", file=sys.stderr)
    sys.exit(1)
PY
)" || {
    rm -f "$decoded"
    fail "$label embedded provisioning profile is unreadable; the installed app was not changed. See $LOG_PATH"
  }
  rm -f "$decoded"
  IFS=$'\t' read -r uuid app_id epoch expiry <<<"$metadata"
  [[ "$app_id" == "$expected_id" ]] || fail "$label profile application identifier is $app_id, expected $expected_id; the installed app was not changed. See $LOG_PATH"
  remaining=$((epoch - $(date +%s)))
  (( remaining >= MIN_PROFILE_REMAINING_SECONDS )) || fail "$label profile expires too soon at $expiry; the installed app was not changed. See $LOG_PATH"
  printf '%s\t%s\t%s\t%s\n' "$uuid" "$app_id" "$epoch" "$expiry"
}

APP_METADATA="$(profile_metadata "LittleRip app" "$IOS_APP" "$DEVELOPMENT_TEAM.$APP_BUNDLE_ID")"
WIDGET_METADATA="$(profile_metadata "LittleRip widget extension" "$WIDGET_APP" "$DEVELOPMENT_TEAM.$WIDGET_BUNDLE_ID")"
IFS=$'\t' read -r APP_PROFILE_UUID APP_PROFILE_ID APP_PROFILE_EPOCH APP_PROFILE_EXPIRY <<<"$APP_METADATA"
IFS=$'\t' read -r WIDGET_PROFILE_UUID WIDGET_PROFILE_ID WIDGET_PROFILE_EPOCH WIDGET_PROFILE_EXPIRY <<<"$WIDGET_METADATA"

if ! run_stage "codesign-app" "$VERIFY_TIMEOUT_SECONDS" "$CODESIGN_BIN" --verify --deep --strict "$IOS_APP"; then
  fail "LittleRip app code-signature verification failed; the installed app was not changed. See $LOG_PATH"
fi
if ! run_stage "codesign-widget" "$VERIFY_TIMEOUT_SECONDS" "$CODESIGN_BIN" --verify --deep --strict "$WIDGET_APP"; then
  fail "LittleRip widget code-signature verification failed; the installed app was not changed. See $LOG_PATH"
fi

# devicectl install app updates the existing app in place. There is no
# uninstall, erase, or data-wipe operation in this transaction.
if ! run_stage "install-in-place" "$INSTALL_TIMEOUT_SECONDS" "$XCRUN_BIN" devicectl device install app --device "$IOS_DEVICE_UDID" "$IOS_APP"; then
  fail "In-place install failed; no uninstall or data wipe was attempted. Unlock/reconnect the iPhone and retry; see $LOG_PATH"
fi

if ! run_stage "launch-and-verify" "$LAUNCH_TIMEOUT_SECONDS" "$XCRUN_BIN" devicectl device process launch --device "$IOS_DEVICE_UDID" --terminate-existing "$APP_BUNDLE_ID"; then
  fail "The app installed in place but launch verification failed. Trust the Apple Development profile or unlock/reconnect the iPhone, then retry; see $LOG_PATH"
fi

abort_if_cancelled
mkdir -p "$STATE_DIR/stamps"
cat >"$STATE_DIR/stamps/last-success.env" <<EOF
APP_PROFILE_UUID="$APP_PROFILE_UUID"
APP_PROFILE_EXPIRES_AT="$APP_PROFILE_EXPIRY"
WIDGET_PROFILE_UUID="$WIDGET_PROFILE_UUID"
WIDGET_PROFILE_EXPIRES_AT="$WIDGET_PROFILE_EXPIRY"
COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
chmod 600 "$STATE_DIR/stamps/last-success.env"
# Keep the cache mutation reversible even after a successful transaction. The
# fresh profile is embedded in the built app and Xcode will quarantine the
# cached target profiles again on the next manual reset.

printf 'SUCCESS: LittleRip iOS reset completed\n'
printf 'app_embedded_profile_expires=%s\n' "$APP_PROFILE_EXPIRY"
printf 'widget_embedded_profile_expires=%s\n' "$WIDGET_PROFILE_EXPIRY"
printf 'installed_in_place=true\n'
printf 'launch_verified=true\n'
printf 'warning=Apple controls profile lifetime; this result does not promise seven days.\n'
printf 'log_path=%s\n' "$LOG_PATH"
