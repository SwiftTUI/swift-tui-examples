#!/usr/bin/env bash
set -euo pipefail

# Installs what Scripts/android_connected_journey.sh needs on a CI runner that
# already has a JDK, the Android SDK command-line tools and swiftly with the
# pinned Swift toolchain: the Android packages for one emulator ABI, the pinned
# NDK, and the Swift Android SDK with its NDK sysroot. A missing prerequisite
# fails the step; nothing is skipped.
#
# Usage: Scripts/install_android_journey_tools_ci.sh <abi> <api>
#
# Environment:
#   SWIFT_ANDROID_SDK_URL       artifact bundle to install with `swift sdk install`
#   SWIFT_ANDROID_SDK_CHECKSUM  its SHA-256 checksum
#   ANDROID_HOME                Android SDK root (the runner image sets it)

script_name=install_android_journey_tools_ci
ndk_version="30.0.16248370"
repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
android_swift_version="$(tr -d '[:space:]' < "$repo_root/.swift-version")"
swift_sdk_artifact="swift-${android_swift_version}-RELEASE_android"

fail() {
  printf '[%s] %s\n' "$script_name" "$1" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: Scripts/install_android_journey_tools_ci.sh <abi> <api>"
abi=$1
api=$2
case "$abi" in
  arm64-v8a | x86_64) ;;
  *) fail "unsupported ABI '$abi' (expected arm64-v8a or x86_64)" ;;
esac
case "$api" in
  "" | *[!0-9]*) fail "the API level must be a number, got '$api'" ;;
esac

android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[ -n "$android_home" ] || fail "ANDROID_HOME is not set; the runner image has no Android SDK"
sdkmanager="$android_home/cmdline-tools/latest/bin/sdkmanager"
[ -x "$sdkmanager" ] || fail "sdkmanager not found at $sdkmanager; install the Android SDK command-line tools"
command -v java >/dev/null 2>&1 || [ -x "${JAVA_HOME:-}/bin/java" ] || fail "no JDK found"

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
[ -n "$swiftly_bin" ] || fail "swiftly not found; run Scripts/install_swift_toolchain_ci.sh first"

printf '[%s] installing Android packages for %s, API %s\n' "$script_name" "$abi" "$api"
# `yes` exits on SIGPIPE when sdkmanager stops reading; that is not a failure.
set +o pipefail
yes | "$sdkmanager" --licenses >/dev/null
yes | "$sdkmanager" --install \
  "platform-tools" \
  "emulator" \
  "ndk;$ndk_version" \
  "system-images;android-$api;google_apis;$abi"
set -o pipefail

ndk_dir="$android_home/ndk/$ndk_version"
[ -d "$ndk_dir" ] || fail "sdkmanager did not install the NDK at $ndk_dir"
[ -d "$android_home/system-images/android-$api/google_apis/$abi" ] ||
  fail "sdkmanager did not install the android-$api google_apis $abi system image"

case "$(uname -s)" in
  Darwin) swift_sdks_dir="$HOME/Library/org.swift.swiftpm/swift-sdks" ;;
  *) swift_sdks_dir="$HOME/.swiftpm/swift-sdks" ;;
esac
bundle="$swift_sdks_dir/$swift_sdk_artifact.artifactbundle"

if [ ! -d "$bundle" ]; then
  [ -n "${SWIFT_ANDROID_SDK_URL:-}" ] || fail "SWIFT_ANDROID_SDK_URL is not set"
  [ -n "${SWIFT_ANDROID_SDK_CHECKSUM:-}" ] || fail "SWIFT_ANDROID_SDK_CHECKSUM is not set"
  printf '[%s] installing the Swift Android SDK\n' "$script_name"
  "$swiftly_bin" run "+$android_swift_version" swift sdk install "$SWIFT_ANDROID_SDK_URL" --checksum "$SWIFT_ANDROID_SDK_CHECKSUM"
fi
[ -d "$bundle" ] || fail "the Swift Android SDK is not at $bundle after installation"

setup_script="$bundle/swift-android/scripts/setup-android-sdk.sh"
[ -x "$setup_script" ] || fail "the Swift Android SDK has no setup script at $setup_script"
printf '[%s] linking the NDK sysroot into the Swift Android SDK\n' "$script_name"
ANDROID_NDK_HOME="$ndk_dir" "$setup_script"

printf '[%s] ok\n' "$script_name"
