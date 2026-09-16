#!/bin/bash
# Mocked regression tests for the manual LittleRip reset transaction.
# No Xcode project, Apple account, device, install, or launch is touched.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/scripts/littlerip-ios-reset.sh"
TMP="$(mktemp -d /tmp/littlerip-ios-reset-test.XXXXXX)"
MOCK_BIN="$TMP/bin"
PROJECT="$TMP/project"
STATE="$TMP/state"
PROFILES="$TMP/profiles"
EVENTS="$TMP/events.log"
OUT="$TMP/output.log"
mkdir -p "$MOCK_BIN" "$PROJECT/LittleRip.xcodeproj" "$STATE" "$PROFILES"
trap 'rm -rf "$TMP"' EXIT

FUTURE="$(date -u -v+6d '+%Y-%m-%dT%H:%M:%SZ')"
SHORT="$(date -u -v+30M '+%Y-%m-%dT%H:%M:%SZ')"
PAST="$(date -u -v-1d '+%Y-%m-%dT%H:%M:%SZ')"
BUILD_ACTIVE_MARKER="$TMP/build.active"
BUILD_DESCENDANT_PID_FILE="$TMP/build.descendant.pid"
BUILD_DELAYED_MARKER="$TMP/build.delayed"

cat >"$MOCK_BIN/defaults" <<'MOCK'
#!/bin/bash
cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>DVTDeveloperAccountManagerAppleIDLists</key>
<dict><key>test@example.invalid</key><dict/></dict>
</dict></plist>
PLIST
MOCK

cat >"$MOCK_BIN/security" <<'MOCK'
#!/bin/bash
set -eu
profile=""
while (($#)); do
  if [[ "$1" == "-i" ]]; then profile="$2"; shift 2; else shift; fi
done
cat "$profile"
MOCK

cat >"$MOCK_BIN/xcodegen" <<'MOCK'
#!/bin/bash
set -eu
printf 'xcodegen %s\n' "$*" >>"$MOCK_EVENTS"
[[ "${FAIL_GENERATE:-0}" == "1" ]] && exit 19
exit 0
MOCK

cat >"$MOCK_BIN/xcodebuild" <<'MOCK'
#!/bin/bash
set -eu
printf 'xcodebuild %s\n' "$*" >>"$MOCK_EVENTS"
if [[ "$*" == *"-showBuildSettings"* ]]; then
  [[ "${FAIL_SIGNING:-0}" == "1" ]] && exit 18
  exit 0
fi
[[ "${FAIL_BUILD:-0}" == "1" ]] && exit 17
if [[ "${BUILD_IGNORE_TERM:-0}" == "1" ]]; then
  trap '' TERM INT HUP
fi
if [[ -n "${BUILD_ACTIVE_MARKER:-}" ]]; then
  printf '%s\n' "$$" >"$BUILD_ACTIVE_MARKER"
  done_marker="${BUILD_ACTIVE_MARKER}.done"
  if [[ -n "${BUILD_DESCENDANT_PID_FILE:-}" ]]; then
    (
      trap '' TERM INT HUP
      while [[ ! -f "$done_marker" ]]; do sleep 0.05; done
      printf 'orphan-survived\n' >"${BUILD_DELAYED_MARKER:?}"
    ) &
    printf '%s\n' "$!" >"$BUILD_DESCENDANT_PID_FILE"
  fi
fi
if [[ -n "${BUILD_SLEEP:-}" ]]; then sleep "$BUILD_SLEEP"; fi
if [[ -n "${BUILD_ACTIVE_MARKER:-}" ]]; then touch "${BUILD_ACTIVE_MARKER}.done"; fi
out=""
previous=""
for arg in "$@"; do
  if [[ "$previous" == "-derivedDataPath" ]]; then out="$arg"; fi
  previous="$arg"
done
[[ -n "$out" ]]
app="$out/Build/Products/Debug-iphoneos/LittleRip.app"
widget="$app/PlugIns/LittleRipWidgetExtension.appex"
mkdir -p "$widget"
printf 'fake app\n' >"$app/Info.plist"
cat >"$app/embedded.mobileprovision" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>UUID</key><string>APP-NEW-UUID</string>
<key>ExpirationDate</key><string>${PROFILE_EXPIRATION:?}</string>
<key>Entitlements</key><dict><key>application-identifier</key><string>72CK386HNT.com.maxautomize.LittleRip</string></dict>
</dict></plist>
PLIST
cat >"$widget/embedded.mobileprovision" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>UUID</key><string>WIDGET-NEW-UUID</string>
<key>ExpirationDate</key><string>${PROFILE_EXPIRATION:?}</string>
<key>Entitlements</key><dict><key>application-identifier</key><string>72CK386HNT.com.maxautomize.LittleRip.LittleRipWidgetExtension</string></dict>
</dict></plist>
PLIST
MOCK

cat >"$MOCK_BIN/codesign" <<'MOCK'
#!/bin/bash
set -eu
printf 'codesign %s\n' "$*" >>"$MOCK_EVENTS"
[[ "${FAIL_CODESIGN:-0}" == "1" ]] && exit 16
exit 0
MOCK

cat >"$MOCK_BIN/xcrun" <<'MOCK'
#!/bin/bash
set -eu
printf 'xcrun %s\n' "$*" >>"$MOCK_EVENTS"
case "$*" in
  *"device info details"*) [[ "${FAIL_DEVICE:-0}" != "1" ]] ;;
  *"device install app"*) [[ "${FAIL_INSTALL:-0}" != "1" ]] ;;
  *"device process launch"*) [[ "${FAIL_LAUNCH:-0}" != "1" ]] ;;
  *) : ;;
esac
MOCK
chmod 755 "$MOCK_BIN"/*

write_cached_profiles() {
  mkdir -p "$PROFILES"
  cat >"$PROFILES/cached-littlerip.mobileprovision" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>UUID</key><string>OLD-UUID</string><key>Entitlements</key><dict><key>application-identifier</key><string>72CK386HNT.com.maxautomize.LittleRip</string></dict></dict></plist>
PLIST
  cat >"$PROFILES/unrelated.mobileprovision" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>UUID</key><string>OTHER-UUID</string><key>Entitlements</key><dict><key>application-identifier</key><string>OTHERTEAM.com.example.Other</string></dict></dict></plist>
PLIST
}

reset_fixture() {
  rm -rf "$STATE" "$PROFILES"
  mkdir -p "$STATE" "$PROFILES"
  rm -f "$BUILD_ACTIVE_MARKER" "$BUILD_ACTIVE_MARKER.done" "$BUILD_DESCENDANT_PID_FILE" "$BUILD_DELAYED_MARKER"
  : >"$EVENTS"
  write_cached_profiles
}

run_backend() {
  env \
    "PATH=$MOCK_BIN:$PATH" \
    "MOCK_EVENTS=$EVENTS" \
    "LITTLERIP_SOURCE_LOCAL_ENV=0" \
    "LITTLERIP_PROJECT_DIR=$PROJECT" \
    "LITTLERIP_STATE_DIR=$STATE" \
    "LITTLERIP_PROFILE_DIR=$PROFILES" \
    "IOS_DEVICE_UDID=TEST-UDID" \
    "DEVELOPMENT_TEAM=72CK386HNT" \
    "PROFILE_EXPIRATION=${PROFILE_EXPIRATION:-$FUTURE}" \
    "XCODEGEN_BIN=$MOCK_BIN/xcodegen" \
    "XCODEBUILD_BIN=$MOCK_BIN/xcodebuild" \
    "XCRUN_BIN=$MOCK_BIN/xcrun" \
    "SECURITY_BIN=$MOCK_BIN/security" \
    "CODESIGN_BIN=$MOCK_BIN/codesign" \
    "DEFAULTS_BIN=$MOCK_BIN/defaults" \
    "BUILD_ACTIVE_MARKER=$BUILD_ACTIVE_MARKER" \
    "BUILD_DESCENDANT_PID_FILE=$BUILD_DESCENDANT_PID_FILE" \
    "BUILD_DELAYED_MARKER=$BUILD_DELAYED_MARKER" \
    "BUILD_IGNORE_TERM=${BUILD_IGNORE_TERM:-0}" \
    "$@" \
    "$BACKEND"
}

assert_contains() {
  grep -Fq -- "$1" "$2" || { printf 'missing expected text: %s\n' "$1" >&2; cat "$2" >&2; exit 1; }
}
assert_not_contains() {
  ! grep -Fq -- "$1" "$2" || { printf 'unexpected text: %s\n' "$1" >&2; cat "$2" >&2; exit 1; }
}

assert_process_not_running() {
  local pid="$1" state
  for _ in {1..80}; do
    state="$(ps -o state= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
    # A killed orphan can briefly be a zombie while launchd reaps it. It is no
    # longer an executing descendant, and must never get a delayed marker.
    [[ -z "$state" || "$state" == Z* ]] && return 0
    sleep 0.05
  done
  printf 'process remained live after cancellation: %s (%s)\n' "$pid" "$state" >&2
  ps -o pid,ppid,pgid,sid,state,command -p "$pid" >&2 || true
  exit 1
}

# Success: exact app/widget expiry is reported, install+launch happen, and the
# unrelated cached profile remains untouched.
reset_fixture
run_backend >"$OUT" 2>&1
assert_contains "SUCCESS: LittleRip iOS reset completed" "$OUT"
assert_contains "app_embedded_profile_expires=$FUTURE" "$OUT"
assert_contains "widget_embedded_profile_expires=$FUTURE" "$OUT"
assert_contains "installed_in_place=true" "$OUT"
assert_contains "launch_verified=true" "$OUT"
grep -Fq 'device install app' "$EVENTS"
grep -Fq 'device process launch' "$EVENTS"
test -f "$PROFILES/unrelated.mobileprovision"
test -f "$PROFILES/cached-littlerip.mobileprovision"

# Short/expired embedded profiles stop before install or launch.
reset_fixture
if PROFILE_EXPIRATION="$PAST" run_backend >"$OUT" 2>&1; then
  echo 'expiry case unexpectedly succeeded' >&2
  exit 1
fi
assert_contains 'profile expires too soon' "$OUT"
assert_not_contains 'device install app' "$EVENTS"
assert_not_contains 'device process launch' "$EVENTS"

# A still-positive but too-short profile is also refused by the one-hour safety
# threshold rather than being presented as a seven-day renewal.
reset_fixture
if PROFILE_EXPIRATION="$SHORT" run_backend >"$OUT" 2>&1; then
  echo 'short-positive expiry case unexpectedly succeeded' >&2
  exit 1
fi
assert_contains 'profile expires too soon' "$OUT"
assert_not_contains 'device install app' "$EVENTS"

# Build failure preserves the old cached target profile and never touches the
# installed app.
reset_fixture
if run_backend FAIL_BUILD=1 >"$OUT" 2>&1; then
  echo 'build failure case unexpectedly succeeded' >&2
  exit 1
fi
assert_contains 'Signed LittleRip build failed' "$OUT"
test -f "$PROFILES/cached-littlerip.mobileprovision"
assert_not_contains 'device install app' "$EVENTS"

# Install and launch failures are surfaced separately and do not get reported
# as a successful reset.
reset_fixture
if run_backend FAIL_INSTALL=1 >"$OUT" 2>&1; then exit 1; fi
assert_contains 'In-place install failed' "$OUT"
assert_not_contains 'device process launch' "$EVENTS"
reset_fixture
if run_backend FAIL_LAUNCH=1 >"$OUT" 2>&1; then exit 1; fi
assert_contains 'launch verification failed' "$OUT"

reset_fixture
if run_backend FAIL_CODESIGN=1 >"$OUT" 2>&1; then exit 1; fi
assert_contains 'code-signature verification failed' "$OUT"
assert_not_contains 'device install app' "$EVENTS"

# A second invocation fails closed on the atomic lock while the first one is in
# progress; only the first invocation may install/launch.
reset_fixture
run_backend BUILD_SLEEP=2 >"$TMP/first.log" 2>&1 &
first_pid=$!
for _ in {1..40}; do [[ -d "$STATE/reset.lock" ]] && break; sleep 0.05; done
test -d "$STATE/reset.lock"
if run_backend >"$OUT" 2>&1; then
  echo 'concurrency case unexpectedly allowed a second reset' >&2
  exit 1
fi
assert_contains 'already running' "$OUT"
wait "$first_pid"

# A timeout during the active child is bounded, kills the descendant group, and
# restores the profile cache before releasing the lock.
reset_fixture
start_epoch="$(date +%s)"
if run_backend BUILD_SLEEP=20 LITTLERIP_BUILD_TIMEOUT_SECONDS=1 >"$OUT" 2>&1; then
  echo 'timeout case unexpectedly succeeded' >&2
  exit 1
fi
elapsed=$(( $(date +%s) - start_epoch ))
[ "$elapsed" -le 8 ]
assert_contains 'Signed LittleRip build failed' "$OUT"
test -f "$PROFILES/cached-littlerip.mobileprovision"
assert_not_contains 'device install app' "$EVENTS"
assert_not_contains 'device process launch' "$EVENTS"
sleep 0.5
test ! -e "$BUILD_DELAYED_MARKER"

# Direct TERM cancellation waits for a genuinely active build and its stubborn
# descendant. No delayed marker may appear after the backend has returned.
reset_fixture
rm -f "$BUILD_ACTIVE_MARKER" "$BUILD_ACTIVE_MARKER.done" "$BUILD_DESCENDANT_PID_FILE" "$BUILD_DELAYED_MARKER"
run_backend BUILD_SLEEP=20 >"$TMP/cancel.log" 2>&1 &
cancel_pid=$!
for _ in {1..160}; do
  [[ -f "$BUILD_ACTIVE_MARKER" && -s "$BUILD_DESCENDANT_PID_FILE" ]] && break
  sleep 0.05
done
test -f "$BUILD_ACTIVE_MARKER"
test -s "$BUILD_DESCENDANT_PID_FILE"
cancel_backend_pid="$(cat "$STATE/reset.lock/pid")"
descendant_pid="$(cat "$BUILD_DESCENDANT_PID_FILE")"
start_epoch="$(date +%s)"
kill -TERM "$cancel_backend_pid"
if wait "$cancel_pid"; then
  echo 'cancellation case unexpectedly succeeded' >&2
  exit 1
fi
elapsed=$(( $(date +%s) - start_epoch ))
[ "$elapsed" -le 8 ]
for _ in {1..120}; do [[ ! -d "$STATE/reset.lock" ]] && break; sleep 0.05; done
test ! -d "$STATE/reset.lock"
test -f "$PROFILES/cached-littlerip.mobileprovision"
assert_not_contains 'device install app' "$EVENTS"
assert_not_contains 'device process launch' "$EVENTS"
sleep 0.5
test ! -e "$BUILD_DELAYED_MARKER"
assert_process_not_running "$descendant_pid"

# Simulate Pi's actual execCommand cancellation: it kills only its direct
# child, which is the backend after env execs it. The backend must forward TERM
# into the supervisor-owned process group and return with killed=true.
reset_fixture
rm -f "$BUILD_ACTIVE_MARKER" "$BUILD_ACTIVE_MARKER.done" "$BUILD_DESCENDANT_PID_FILE" "$BUILD_DELAYED_MARKER"
PI_TEST_BACKEND="$BACKEND" \
PI_TEST_BIN="$MOCK_BIN" \
PI_TEST_PATH="$PATH" \
PI_TEST_EVENTS="$EVENTS" \
PI_TEST_PROJECT="$PROJECT" \
PI_TEST_STATE="$STATE" \
PI_TEST_PROFILES="$PROFILES" \
PI_TEST_ACTIVE="$BUILD_ACTIVE_MARKER" \
PI_TEST_DESC_PID="$BUILD_DESCENDANT_PID_FILE" \
PI_TEST_DELAYED="$BUILD_DELAYED_MARKER" \
PI_TEST_EXPIRATION="$FUTURE" \
node --input-type=module <<'JS'
import { existsSync } from 'node:fs';
import { execCommand } from '/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/dist/core/exec.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const env = process.env;
const vars = {
  PATH: `${env.PI_TEST_BIN}:${env.PI_TEST_PATH}`,
  MOCK_EVENTS: env.PI_TEST_EVENTS,
  LITTLERIP_SOURCE_LOCAL_ENV: '0',
  LITTLERIP_PROJECT_DIR: env.PI_TEST_PROJECT,
  LITTLERIP_STATE_DIR: env.PI_TEST_STATE,
  LITTLERIP_PROFILE_DIR: env.PI_TEST_PROFILES,
  IOS_DEVICE_UDID: 'TEST-UDID',
  DEVELOPMENT_TEAM: '72CK386HNT',
  PROFILE_EXPIRATION: env.PI_TEST_EXPIRATION,
  XCODEGEN_BIN: `${env.PI_TEST_BIN}/xcodegen`,
  XCODEBUILD_BIN: `${env.PI_TEST_BIN}/xcodebuild`,
  XCRUN_BIN: `${env.PI_TEST_BIN}/xcrun`,
  SECURITY_BIN: `${env.PI_TEST_BIN}/security`,
  CODESIGN_BIN: `${env.PI_TEST_BIN}/codesign`,
  DEFAULTS_BIN: `${env.PI_TEST_BIN}/defaults`,
  BUILD_SLEEP: '20',
  BUILD_ACTIVE_MARKER: env.PI_TEST_ACTIVE,
  BUILD_DESCENDANT_PID_FILE: env.PI_TEST_DESC_PID,
  BUILD_DELAYED_MARKER: env.PI_TEST_DELAYED,
};
const args = Object.entries(vars).map(([key, value]) => `${key}=${value}`);
const controller = new AbortController();
const pending = execCommand('/usr/bin/env', [...args, env.PI_TEST_BACKEND], env.PI_TEST_PROJECT, { signal: controller.signal });
for (let i = 0; i < 160 && !existsSync(env.PI_TEST_ACTIVE); i++) await sleep(50);
if (!existsSync(env.PI_TEST_ACTIVE)) throw new Error('mock build never became active');
controller.abort();
const result = await pending;
if (!result.killed) throw new Error(`Pi exec did not report killed=true: ${JSON.stringify(result)}`);
if (existsSync(env.PI_TEST_DELAYED)) throw new Error('delayed descendant marker already exists');
console.log('Pi exec cancellation simulation: PASS');
JS
for _ in {1..120}; do [[ ! -d "$STATE/reset.lock" ]] && break; sleep 0.05; done
test ! -d "$STATE/reset.lock"
test -f "$PROFILES/cached-littlerip.mobileprovision"
assert_not_contains 'device install app' "$EVENTS"
assert_not_contains 'device process launch' "$EVENTS"
sleep 0.5
test ! -e "$BUILD_DELAYED_MARKER"
pi_descendant_pid="$(cat "$BUILD_DESCENDANT_PID_FILE")"
assert_process_not_running "$pi_descendant_pid"

# Repeat the installed Pi exec cancellation with a root build process that
# ignores TERM as well as its descendant. Escalation must happen within the
# supervisor grace period rather than waiting for the stage timeout.
reset_fixture
rm -f "$BUILD_ACTIVE_MARKER" "$BUILD_ACTIVE_MARKER.done" "$BUILD_DESCENDANT_PID_FILE" "$BUILD_DELAYED_MARKER"
PI_TEST_BACKEND="$BACKEND" \
PI_TEST_BIN="$MOCK_BIN" \
PI_TEST_PATH="$PATH" \
PI_TEST_EVENTS="$EVENTS" \
PI_TEST_PROJECT="$PROJECT" \
PI_TEST_STATE="$STATE" \
PI_TEST_PROFILES="$PROFILES" \
PI_TEST_ACTIVE="$BUILD_ACTIVE_MARKER" \
PI_TEST_DESC_PID="$BUILD_DESCENDANT_PID_FILE" \
PI_TEST_DELAYED="$BUILD_DELAYED_MARKER" \
PI_TEST_EXPIRATION="$FUTURE" \
node --input-type=module <<'JS'
import { existsSync } from 'node:fs';
import { execCommand } from '/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/dist/core/exec.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const env = process.env;
const vars = {
  PATH: `${env.PI_TEST_BIN}:${env.PI_TEST_PATH}`,
  MOCK_EVENTS: env.PI_TEST_EVENTS,
  LITTLERIP_SOURCE_LOCAL_ENV: '0',
  LITTLERIP_PROJECT_DIR: env.PI_TEST_PROJECT,
  LITTLERIP_STATE_DIR: env.PI_TEST_STATE,
  LITTLERIP_PROFILE_DIR: env.PI_TEST_PROFILES,
  IOS_DEVICE_UDID: 'TEST-UDID',
  DEVELOPMENT_TEAM: '72CK386HNT',
  PROFILE_EXPIRATION: env.PI_TEST_EXPIRATION,
  XCODEGEN_BIN: `${env.PI_TEST_BIN}/xcodegen`,
  XCODEBUILD_BIN: `${env.PI_TEST_BIN}/xcodebuild`,
  XCRUN_BIN: `${env.PI_TEST_BIN}/xcrun`,
  SECURITY_BIN: `${env.PI_TEST_BIN}/security`,
  CODESIGN_BIN: `${env.PI_TEST_BIN}/codesign`,
  DEFAULTS_BIN: `${env.PI_TEST_BIN}/defaults`,
  BUILD_SLEEP: '20',
  BUILD_IGNORE_TERM: '1',
  BUILD_ACTIVE_MARKER: env.PI_TEST_ACTIVE,
  BUILD_DESCENDANT_PID_FILE: env.PI_TEST_DESC_PID,
  BUILD_DELAYED_MARKER: env.PI_TEST_DELAYED,
};
const args = Object.entries(vars).map(([key, value]) => `${key}=${value}`);
const controller = new AbortController();
const pending = execCommand('/usr/bin/env', [...args, env.PI_TEST_BACKEND], env.PI_TEST_PROJECT, { signal: controller.signal });
for (let i = 0; i < 160 && !existsSync(env.PI_TEST_ACTIVE); i++) await sleep(50);
if (!existsSync(env.PI_TEST_ACTIVE)) throw new Error('root-ignore mock build never became active');
const abortAt = performance.now();
controller.abort();
const result = await pending;
const elapsed = performance.now() - abortAt;
if (!result.killed) throw new Error(`Pi root-ignore exec did not report killed=true: ${JSON.stringify(result)}`);
if (elapsed >= 5000) throw new Error(`root-ignore cancellation exceeded 5s: ${elapsed.toFixed(0)}ms`);
console.log(`Pi exec root-ignore cancellation simulation: PASS (${elapsed.toFixed(0)}ms)`);
JS
for _ in {1..120}; do [[ ! -d "$STATE/reset.lock" ]] && break; sleep 0.05; done
test ! -d "$STATE/reset.lock"
test -f "$PROFILES/cached-littlerip.mobileprovision"
assert_not_contains 'device install app' "$EVENTS"
assert_not_contains 'device process launch' "$EVENTS"
sleep 0.5
test ! -e "$BUILD_DELAYED_MARKER"
root_descendant_pid="$(cat "$BUILD_DESCENDANT_PID_FILE")"
assert_process_not_running "$root_descendant_pid"

echo 'ios-reset mocked regression tests: PASS (expiry, short-positive threshold, build/install/launch/codesign failures, lock, timeout, direct TERM, Pi exec cancellation, root-ignore cancellation)'
