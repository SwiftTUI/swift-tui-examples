#!/usr/bin/env bash
set -euo pipefail

swift_version="$(tr -d '[:space:]' < .swift-version)"
swiftly_home="${SWIFTLY_HOME_DIR:-$HOME/.swiftly}"
swiftly_bin="${SWIFTLY_BIN_DIR:-$swiftly_home/bin}"
export SWIFTLY_HOME_DIR="$swiftly_home"
export SWIFTLY_BIN_DIR="$swiftly_bin"
export PATH="$swiftly_bin:$PATH"

if [[ ! -x "$swiftly_bin/swiftly" || ! -f "$swiftly_home/env.sh" ]]; then
  temporary_directory="$(mktemp -d)"
  trap 'rm -rf "$temporary_directory"' EXIT
  (
    cd "$temporary_directory"
    curl -fsSLO https://download.swift.org/swiftly/darwin/swiftly.pkg
    installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
    "$swiftly_bin/swiftly" init \
      --skip-install \
      --quiet-shell-followup \
      --assume-yes
  )
fi

. "$swiftly_home/env.sh"
swiftly install --use --assume-yes "$swift_version"
swiftly run swift --version

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$swiftly_bin" >> "$GITHUB_PATH"
fi
