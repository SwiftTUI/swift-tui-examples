#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '[install_swift_toolchain_ci] %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: Scripts/install_swift_toolchain_ci.sh <swift-version-file>

Installs swiftly if needed, then installs and selects the Swift toolchain named
by <swift-version-file>. Intended for GitHub Actions example lanes.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

version_file=${1:-}
if [[ -z "$version_file" ]]; then
  usage >&2
  exit 1
fi
if [[ ! -f "$version_file" ]]; then
  fail "missing Swift version file: $version_file"
fi

swift_version="$(tr -d '[:space:]' < "$version_file")"
if [[ -z "$swift_version" ]]; then
  fail "empty Swift version file: $version_file"
fi

swiftly_version="${SWIFTLY_VERSION:-1.1.3}"
host_os="${SWIFTTUI_EXAMPLES_CI_HOST_OS:-$(uname -s)}"
host_arch="${SWIFTTUI_EXAMPLES_CI_HOST_ARCH:-$(uname -m)}"

install_swiftly_linux() {
  local tmpdir swiftly_archive
  tmpdir="$(mktemp -d)"
  trap "rm -rf $(printf '%q' "$tmpdir")" EXIT

  (
    cd "$tmpdir"
    swiftly_archive="swiftly-${swiftly_version}-${host_arch}.tar.gz"
    curl -fsSLO "https://download.swift.org/swiftly/linux/${swiftly_archive}"
    tar -zxf "$swiftly_archive"
    ./swiftly init --skip-install --quiet-shell-followup --assume-yes
  )
}

install_swiftly_macos() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap "rm -rf $(printf '%q' "$tmpdir")" EXIT

  (
    cd "$tmpdir"
    curl -fsSLO https://download.swift.org/swiftly/darwin/swiftly.pkg
    installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
    "$HOME/.swiftly/bin/swiftly" init --skip-install --quiet-shell-followup --assume-yes
  )
}

install_swiftly() {
  case "$host_os" in
    Linux)
      install_swiftly_linux
      ;;
    Darwin)
      install_swiftly_macos
      ;;
    *)
      fail "unsupported host OS: $host_os"
      ;;
  esac
}

case "$host_os" in
  Linux)
    export SWIFTLY_HOME_DIR="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
    export SWIFTLY_BIN_DIR="${SWIFTLY_BIN_DIR:-$HOME/.local/bin}"
    mkdir -p "$SWIFTLY_BIN_DIR"
    export PATH="$SWIFTLY_BIN_DIR:$PATH"
    ;;
  Darwin)
    export SWIFTLY_HOME_DIR="${SWIFTLY_HOME_DIR:-$HOME/.swiftly}"
    export SWIFTLY_BIN_DIR="${SWIFTLY_BIN_DIR:-$HOME/.swiftly/bin}"
    export PATH="$SWIFTLY_BIN_DIR:$PATH"
    ;;
  *)
    fail "unsupported host OS: $host_os"
    ;;
esac

if ! command -v swiftly >/dev/null 2>&1 || [[ ! -f "${SWIFTLY_HOME_DIR}/env.sh" ]]; then
  install_swiftly
fi

. "${SWIFTLY_HOME_DIR}/env.sh"
hash -r

install_toolchain() {
  swiftly install --use --assume-yes "$swift_version"
}

toolchain_ready() {
  swiftly run swift --version
}

clear_cached_toolchain() {
  printf '[install_swift_toolchain_ci] clearing cached Swift %s before retry\n' "$swift_version" >&2
  if ! swiftly uninstall "$swift_version" --assume-yes; then
    printf '[install_swift_toolchain_ci] uninstall of Swift %s failed; swiftly state is inconsistent\n' \
      "$swift_version" >&2
  fi
}

# A restored CI cache can record toolchains that are not on disk. On macOS
# swiftly keeps its registry in SWIFTLY_HOME_DIR but installs toolchains into
# ~/Library/Developer/Toolchains, which the lanes do not cache — so a cache hit
# can carry a registry with no payload behind it. swiftly then reports the
# toolchain as already installed and fails to select it, and a targeted
# uninstall cannot always repair that. Drop the whole swiftly state and
# reinstall so the registry is rebuilt from reality.
reset_swiftly_state() {
  printf '[install_swift_toolchain_ci] swiftly state is unusable; reinstalling swiftly from scratch\n' >&2
  rm -rf "$SWIFTLY_HOME_DIR"
  rm -f "$SWIFTLY_BIN_DIR/swiftly"
  install_swiftly
  . "${SWIFTLY_HOME_DIR}/env.sh"
  hash -r
}

if ! install_toolchain || ! toolchain_ready; then
  clear_cached_toolchain
  if ! install_toolchain || ! toolchain_ready; then
    reset_swiftly_state
    install_toolchain
    toolchain_ready
  fi
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$SWIFTLY_BIN_DIR" >> "$GITHUB_PATH"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SWIFTLY_HOME_DIR=$SWIFTLY_HOME_DIR" >> "$GITHUB_ENV"
  echo "SWIFTLY_BIN_DIR=$SWIFTLY_BIN_DIR" >> "$GITHUB_ENV"
fi
