#!/usr/bin/env bash
set -euo pipefail

# Runs the AndroidGallery connected journey on one emulator or device and
# prints a verdict. The run is red when the device is missing, when the APK
# lacks the Swift host or JNI libraries, when the app crashes, when a test
# fails, or when the journey test does not execute. Test XML, screenshots,
# logcat and the tested revisions are kept for a green run and a red run alike.
#
# The Gradle plugin skips the Swift cross-build when the NDK or the Swift
# Android SDK is absent, and the app then builds without its host library.
# This script therefore checks the toolchain first and the APK payload after
# the build. It never skips a step.

script_name=android_connected_journey
repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
gallery_dir="$repo_root/AndroidGallery"

app_id="org.swifttui.gallery.android"
journey_test="publicHostRendersInteractsRetainsSemanticsAndAlpha"
fixture_argument="swifttuiJourneyFailFixture"
ndk_version="30.0.16248370"
swift_sdk_artifact="swift-6.4.0-RELEASE_android"
required_libraries="libswift_tui_app_host.so libswift_tui_jni.so libswiftCore.so libc++_shared.so"

abi="arm64-v8a"
api="36"
serial=""
artifacts=""
failing_fixture=0
keep_device=0

usage() {
  cat <<'EOF'
Usage: Scripts/android_connected_journey.sh [options]

  --abi <abi>          ABI to run: arm64-v8a (default) or x86_64. The device
                       and the APK must both carry it.
  --api <level>        API level of the emulator system image (default 36).
  --serial <serial>    Use this running device or emulator. Without it the
                       script creates, boots and deletes a clean emulator.
  --artifacts <dir>    Directory for the retained artifacts (default
                       AndroidGallery/app/build/journey-artifacts/<UTC time>).
  --failing-fixture    Ask the verdict fixture test to fail. The run must end
                       red; use it to prove the verdict.
  --keep-device        Leave the emulator that this script booted running.
  -h, --help           Show this text.

Timeouts, in seconds (environment):
  SWIFTTUI_ANDROID_JOURNEY_BOOT_TIMEOUT_SECONDS     emulator boot       (300)
  SWIFTTUI_ANDROID_JOURNEY_BUILD_IDLE_SECONDS       build silence bound (600)
  SWIFTTUI_ANDROID_JOURNEY_BUILD_TIMEOUT_SECONDS    build wall clock    (2400)
  SWIFTTUI_ANDROID_JOURNEY_TEST_IDLE_SECONDS        test silence bound  (300)
  SWIFTTUI_ANDROID_JOURNEY_TEST_TIMEOUT_SECONDS     test wall clock     (900)
  SWIFTTUI_ANDROID_JOURNEY_CLEANUP_TIMEOUT_SECONDS  emulator shutdown   (60)
EOF
}

note() {
  printf '[%s] %s\n' "$script_name" "$*"
}

# A failure before the journey can start. Nothing useful is left to collect.
abort() {
  printf '[%s] FAIL: %s\n' "$script_name" "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --abi) [ "$#" -ge 2 ] || abort "--abi needs a value"; abi=$2; shift 2 ;;
    --api) [ "$#" -ge 2 ] || abort "--api needs a value"; api=$2; shift 2 ;;
    --serial) [ "$#" -ge 2 ] || abort "--serial needs a value"; serial=$2; shift 2 ;;
    --artifacts) [ "$#" -ge 2 ] || abort "--artifacts needs a value"; artifacts=$2; shift 2 ;;
    --failing-fixture) failing_fixture=1; shift ;;
    --keep-device) keep_device=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; abort "unknown option: $1" ;;
  esac
done

case "$abi" in
  arm64-v8a | x86_64) ;;
  *) abort "unsupported ABI '$abi' (expected arm64-v8a or x86_64)" ;;
esac
case "$api" in
  "" | *[!0-9]*) abort "--api must be a number, got '$api'" ;;
esac

boot_timeout=${SWIFTTUI_ANDROID_JOURNEY_BOOT_TIMEOUT_SECONDS:-300}
build_idle=${SWIFTTUI_ANDROID_JOURNEY_BUILD_IDLE_SECONDS:-600}
build_timeout=${SWIFTTUI_ANDROID_JOURNEY_BUILD_TIMEOUT_SECONDS:-2400}
test_idle=${SWIFTTUI_ANDROID_JOURNEY_TEST_IDLE_SECONDS:-300}
test_timeout=${SWIFTTUI_ANDROID_JOURNEY_TEST_TIMEOUT_SECONDS:-900}
cleanup_timeout=${SWIFTTUI_ANDROID_JOURNEY_CLEANUP_TIMEOUT_SECONDS:-60}
for bound in "$boot_timeout" "$build_idle" "$build_timeout" "$test_idle" "$test_timeout" "$cleanup_timeout"; do
  case "$bound" in
    "" | *[!0-9]* | 0) abort "every timeout must be a positive number of seconds, got '$bound'" ;;
  esac
done

# --- toolchain -------------------------------------------------------------

case "$(uname -s)" in
  Darwin)
    default_android_home="$HOME/Library/Android/sdk"
    default_swift_sdks="$HOME/Library/org.swift.swiftpm/swift-sdks"
    ;;
  *)
    default_android_home="$HOME/Android/Sdk"
    default_swift_sdks="$HOME/.swiftpm/swift-sdks"
    ;;
esac

android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$default_android_home}}
export ANDROID_HOME="$android_home"
adb="$android_home/platform-tools/adb"
emulator_bin="$android_home/emulator/emulator"
avdmanager="$android_home/cmdline-tools/latest/bin/avdmanager"
ndk_dir=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$android_home/ndk/$ndk_version}}
swift_sdk_bundle=${SWIFT_ANDROID_SDK_BUNDLE:-$default_swift_sdks/$swift_sdk_artifact.artifactbundle}
system_image_dir="$android_home/system-images/android-$api/google_apis/$abi"

swiftly_bin=""
for candidate in "${SWIFTLY_BIN_DIR:-}" "$HOME/.swiftly/bin" "$HOME/.local/bin"; do
  if [ -n "$candidate" ] && [ -x "$candidate/swiftly" ]; then
    swiftly_bin="$candidate/swiftly"
    break
  fi
done
if [ -z "$swiftly_bin" ]; then
  swiftly_bin=$(command -v swiftly || true)
fi

java_bin=""
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  java_bin="$JAVA_HOME/bin/java"
else
  java_bin=$(command -v java || true)
fi

[ -d "$android_home" ] || abort "Android SDK not found at $android_home (set ANDROID_HOME)"
[ -x "$adb" ] || abort "adb not found at $adb (install the SDK package platform-tools)"
[ -n "$java_bin" ] || abort "no JDK found (set JAVA_HOME or put java on PATH)"
command -v python3 >/dev/null 2>&1 || abort "python3 not found; it reads the test results"
command -v unzip >/dev/null 2>&1 || abort "unzip not found; it inspects the APK"
[ -n "$swiftly_bin" ] || abort "swiftly not found (set SWIFTLY_BIN_DIR); the app needs it to build the Swift host"
[ -d "$ndk_dir" ] || abort "Android NDK $ndk_version not found at $ndk_dir (set ANDROID_NDK_HOME)"
[ -d "$swift_sdk_bundle" ] || abort "Swift Android SDK not found at $swift_sdk_bundle (set SWIFT_ANDROID_SDK_BUNDLE)"
[ -x "$gallery_dir/gradlew" ] || abort "Gradle wrapper not found in $gallery_dir"
if [ -z "$serial" ]; then
  [ -x "$emulator_bin" ] || abort "emulator not found at $emulator_bin (install the SDK package emulator, or pass --serial)"
  [ -x "$avdmanager" ] || abort "avdmanager not found at $avdmanager (install the SDK command-line tools, or pass --serial)"
  [ -d "$system_image_dir" ] ||
    abort "system image not installed: sdkmanager 'system-images;android-$api;google_apis;$abi'"
fi

if [ -z "$artifacts" ]; then
  artifacts="$gallery_dir/app/build/journey-artifacts/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$artifacts"
artifacts="$(CDPATH= cd -- "$artifacts" && pwd)"
note "artifacts: $artifacts"

# --- verdict bookkeeping ---------------------------------------------------

failures=""
add_failure() {
  printf '[%s] FAIL: %s\n' "$script_name" "$1" >&2
  failures="$failures$1
"
}

# --- device ----------------------------------------------------------------

booted_here=0
serial_is_ours=0
emulator_pid=""
avd_name=""

device_prop() {
  "$adb" -s "$serial" shell getprop "$1" 2>/dev/null | tr -d '\r' || true
}

port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# An emulator that is still starting holds no port yet and is not in
# `adb devices`, so the command lines of running emulators count too.
port_claimed_by_process() {
  ps -Ao command | grep -Eq -- "-port $1( |\$)"
}

free_emulator_port() {
  candidate=5554
  while [ "$candidate" -le 5680 ]; do
    if ! "$adb" devices | grep -q "^emulator-${candidate}[[:space:]]" &&
      ! port_claimed_by_process "$candidate" &&
      ! port_in_use "$candidate" && ! port_in_use "$((candidate + 1))"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate=$((candidate + 2))
  done
  return 1
}

cleanup() {
  status=$?
  trap - EXIT
  if [ "$booted_here" -eq 1 ] && [ "$keep_device" -eq 0 ]; then
    note "shutting down the emulator that this script started"
    # Ask through the console only when the serial is known to be this
    # script's emulator; otherwise the request could stop someone else's.
    if [ "$serial_is_ours" -eq 1 ]; then
      "$adb" -s "$serial" emu kill >/dev/null 2>&1 || true
    else
      kill "$emulator_pid" 2>/dev/null || true
    fi
    deadline=$(($(date +%s) + cleanup_timeout))
    while kill -0 "$emulator_pid" 2>/dev/null; do
      if [ "$(date +%s)" -ge "$deadline" ]; then
        note "emulator ignored the shutdown request for ${cleanup_timeout}s; killing it"
        kill -9 "$emulator_pid" 2>/dev/null || true
        break
      fi
      sleep 1
    done
    "$avdmanager" delete avd -n "$avd_name" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -z "$serial" ]; then
  avd_name="swifttui-journey-$$"
  port=$(free_emulator_port) || abort "no free emulator console port between 5554 and 5680"
  serial="emulator-$port"
  note "creating a clean emulator ($avd_name, API $api, $abi) as $serial"
  if ! printf 'no\n' | "$avdmanager" create avd --force -n "$avd_name" \
    -k "system-images;android-$api;google_apis;$abi" -d pixel_7 >"$artifacts/avd-create.log" 2>&1; then
    tail -n 20 "$artifacts/avd-create.log" >&2 || true
    abort "could not create the emulator; see $artifacts/avd-create.log"
  fi
  nohup "$emulator_bin" -avd "$avd_name" -port "$port" \
    -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
    -memory 4096 -gpu swiftshader_indirect -camera-back none -camera-front none \
    >"$artifacts/emulator.log" 2>&1 &
  emulator_pid=$!
  booted_here=1

  deadline=$(($(date +%s) + boot_timeout))
  while :; do
    if ! kill -0 "$emulator_pid" 2>/dev/null; then
      tail -n 20 "$artifacts/emulator.log" >&2 || true
      abort "the emulator exited while booting; see $artifacts/emulator.log"
    fi
    if [ "$(device_prop sys.boot_completed)" = "1" ] &&
      "$adb" -s "$serial" shell pm path android >/dev/null 2>&1; then
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      tail -n 20 "$artifacts/emulator.log" >&2 || true
      abort "the emulator did not finish booting within ${boot_timeout}s; see $artifacts/emulator.log"
    fi
    sleep 2
  done
  # Two emulators that start at the same moment can pick the same port. Then
  # the serial belongs to the other one, and this run would test the wrong
  # device.
  running_avd=$("$adb" -s "$serial" emu avd name 2>/dev/null | head -n 1 | tr -d '\r' || true)
  [ "$running_avd" = "$avd_name" ] ||
    abort "$serial is the emulator '$running_avd', not the '$avd_name' that this script started"
  serial_is_ours=1
  note "$serial booted"
else
  state=$("$adb" -s "$serial" get-state 2>/dev/null | tr -d '\r' || true)
  [ "$state" = "device" ] || abort "device $serial is not online (adb state: ${state:-absent})"
  # A device that this script did not create can hold an earlier install.
  "$adb" -s "$serial" uninstall "$app_id" >/dev/null 2>&1 || true
  "$adb" -s "$serial" uninstall "$app_id.test" >/dev/null 2>&1 || true
fi
export ANDROID_SERIAL="$serial"

device_abis=$(device_prop ro.product.cpu.abilist)
case ",$device_abis," in
  *",$abi,"*) ;;
  *) abort "device $serial runs [$device_abis], which does not include $abi" ;;
esac

for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  "$adb" -s "$serial" shell settings put global "$scale" 0 >/dev/null 2>&1 || true
done
"$adb" -s "$serial" shell input keyevent 82 >/dev/null 2>&1 || true
"$adb" -s "$serial" logcat -G 16M >/dev/null 2>&1 || true

# --- revisions -------------------------------------------------------------

gradle_value() {
  # First double-quoted capture group of the first line that matches $1 in $2.
  sed -n -E "s/$1/\\1/p" "$2" | head -n 1
}

{
  printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'examples_revision=%s\n' "$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)"
  if [ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]; then
    printf 'examples_worktree=modified\n'
  else
    printf 'examples_worktree=clean\n'
  fi
  printf 'android_host_aar=%s\n' \
    "$(gradle_value '.*"(sh\.swifttui:android-host:[^"]+)".*' "$gallery_dir/app/build.gradle.kts")"
  printf 'android_plugin=%s\n' \
    "$(gradle_value '.*id\("sh\.swifttui\.android"\) version "([^"]+)".*' "$gallery_dir/app/build.gradle.kts")"
  printf 'android_gradle_plugin=%s\n' \
    "$(gradle_value '.*id\("com\.android\.application"\) version "([^"]+)".*' "$gallery_dir/build.gradle.kts")"
  printf 'ndk=%s\n' "$ndk_dir"
  printf 'swift_android_sdk=%s\n' "$swift_sdk_bundle"
  printf 'swift=%s\n' "$("$swiftly_bin" run +6.4.0 swift --version 2>/dev/null | head -n 1 || echo unknown)"
  printf 'java=%s\n' "$("$java_bin" -version 2>&1 | head -n 1)"
  printf 'requested_abi=%s\n' "$abi"
  printf 'device_serial=%s\n' "$serial"
  printf 'device_created_by_script=%s\n' "$booted_here"
  printf 'device_android_release=%s\n' "$(device_prop ro.build.version.release)"
  printf 'device_api=%s\n' "$(device_prop ro.build.version.sdk)"
  printf 'device_abis=%s\n' "$device_abis"
  printf 'device_fingerprint=%s\n' "$(device_prop ro.build.fingerprint)"
  printf 'device_ime=%s\n' \
    "$("$adb" -s "$serial" shell settings get secure default_input_method 2>/dev/null | tr -d '\r' || true)"
  printf 'failing_fixture=%s\n' "$failing_fixture"
} >"$artifacts/revisions.txt"

# --- bounded steps ---------------------------------------------------------

step_timeout_seconds=$build_idle
step_absolute_timeout_seconds=$build_timeout
step_busy_grace_seconds=$((build_idle / 2))
step_timeout_kill_grace_seconds=10
step_output_probe_ticks=25
step_busy_min_cpu_percent=25
step_watchdog_deadline_seconds=0
# shellcheck source=Scripts/lib/step_watchdog.sh
. "$repo_root/Scripts/lib/step_watchdog.sh"

# run_step <title> <log name> <silence bound> <wall-clock bound> <command...>
run_step() {
  title=$1
  log_file="$artifacts/$2"
  step_timeout_seconds=$3
  step_absolute_timeout_seconds=$4
  step_busy_grace_seconds=$(($3 / 2))
  shift 4
  status_file="$log_file.status"
  timeout_file="$log_file.timeout"

  note "==> $title"
  if (
    cd "$gallery_dir" &&
      run_logged_command "$log_file" "$status_file" "$timeout_file" "$@"
  ); then
    rm -f "$status_file" "$timeout_file"
    return 0
  fi

  if [ -f "$timeout_file" ]; then
    add_failure "$title timed out ($(cat "$timeout_file"))"
  else
    add_failure "$title failed (exit $(read_step_exit_code "$status_file"))"
  fi
  rm -f "$status_file" "$timeout_file"
  return 1
}

# --- build and payload -----------------------------------------------------

apk="$gallery_dir/app/build/outputs/apk/debug/app-debug.apk"
payload_ok=0
if run_step "Build the app and its test APK" gradle-build.log "$build_idle" "$build_timeout" \
  ./gradlew --console=plain :app:assembleDebug :app:assembleDebugAndroidTest; then
  if [ ! -f "$apk" ]; then
    add_failure "the build produced no APK at $apk"
  else
    unzip -Z1 "$apk" >"$artifacts/apk-entries.txt"
    missing=""
    for library in $required_libraries; do
      if ! grep -Fxq "lib/$abi/$library" "$artifacts/apk-entries.txt"; then
        missing="$missing $library"
      fi
    done
    if [ -n "$missing" ]; then
      add_failure "the APK lacks these $abi libraries:$missing"
    else
      payload_ok=1
      printf 'apk_sha256=%s\n' "$(shasum -a 256 "$apk" | cut -d ' ' -f 1)" >>"$artifacts/revisions.txt"
    fi
  fi
fi

# --- journey ---------------------------------------------------------------

results_dir="$gallery_dir/app/build/outputs/androidTest-results/connected"
additional_output_dir="$gallery_dir/app/build/outputs/connected_android_test_additional_output"
if [ "$payload_ok" -eq 1 ]; then
  # Results of an earlier run must not stand in for this one.
  rm -rf "$results_dir" "$additional_output_dir"
  "$adb" -s "$serial" logcat -c >/dev/null 2>&1 || true

  set -- ./gradlew --console=plain :app:connectedDebugAndroidTest
  if [ "$failing_fixture" -eq 1 ]; then
    set -- "$@" "-Pandroid.testInstrumentationRunnerArguments.$fixture_argument=true"
  fi
  run_step "Run the connected journey on $serial" gradle-journey.log "$test_idle" "$test_timeout" "$@" || true

  # --- artifacts -----------------------------------------------------------

  "$adb" -s "$serial" logcat -d -v threadtime >"$artifacts/logcat.txt" 2>/dev/null || true
  "$adb" -s "$serial" exec-out screencap -p >"$artifacts/device-final.png" 2>/dev/null || true
  if [ -d "$results_dir" ]; then
    mkdir -p "$artifacts/test-results"
    find "$results_dir" -name '*.xml' -exec cp {} "$artifacts/test-results/" \;
  fi
  if [ -d "$additional_output_dir" ]; then
    mkdir -p "$artifacts/test-output"
    cp -R "$additional_output_dir/." "$artifacts/test-output/"
  fi

  # --- verdict -------------------------------------------------------------

  python3 - "$artifacts/test-results" "$journey_test" >"$artifacts/test-summary.txt" <<'PY'
import glob
import os
import sys
import xml.etree.ElementTree as ET

directory, journey = sys.argv[1], sys.argv[2]
counts = {"passed": 0, "failed": 0, "skipped": 0}
journey_state = "missing"
unreadable = 0
for path in sorted(glob.glob(os.path.join(directory, "*.xml"))):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        unreadable += 1
        continue
    for case in root.iter("testcase"):
        if case.find("failure") is not None or case.find("error") is not None:
            state = "failed"
        elif case.find("skipped") is not None:
            state = "skipped"
        else:
            state = "passed"
        counts[state] += 1
        if case.get("name") == journey:
            journey_state = state
print("executed=%d" % (counts["passed"] + counts["failed"]))
print("passed=%d" % counts["passed"])
print("failed=%d" % counts["failed"])
print("skipped=%d" % counts["skipped"])
print("unreadable_files=%d" % unreadable)
print("journey=%s" % journey_state)
PY
  summary_value() {
    sed -n "s/^$1=//p" "$artifacts/test-summary.txt"
  }
  executed=$(summary_value executed)
  failed=$(summary_value failed)
  journey_state=$(summary_value journey)
  note "tests: executed=$executed failed=$failed skipped=$(summary_value skipped) journey=$journey_state"

  if [ "$executed" -eq 0 ]; then
    add_failure "no test executed"
  fi
  if [ "$failed" -gt 0 ]; then
    add_failure "$failed test(s) failed"
  fi
  if [ "$(summary_value unreadable_files)" -gt 0 ]; then
    add_failure "a test result file could not be read"
  fi
  if [ "$journey_state" != "passed" ]; then
    add_failure "the journey test $journey_test did not pass (state: $journey_state)"
  fi
  # A Java crash names the process on the line after FATAL EXCEPTION; a native
  # crash names it in the tombstone header.
  if grep -Eq "Process: $app_id(,|$)|>>> $app_id <<<" "$artifacts/logcat.txt" 2>/dev/null; then
    add_failure "the app process crashed; see logcat.txt"
  fi
fi

if [ -z "$failures" ]; then
  printf 'PASS\n' >"$artifacts/verdict.txt"
  note "VERDICT: PASS"
  exit 0
fi

{
  printf 'FAIL\n'
  printf '%s' "$failures"
} >"$artifacts/verdict.txt"
note "VERDICT: FAIL"
printf '%s' "$failures" | sed "s/^/[$script_name]   - /" >&2
exit 1
