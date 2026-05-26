#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fake_bin="$tmpdir/bin"
swiftly_log="$tmpdir/swiftly.log"
version_root="$tmpdir/swift-tui"
mkdir -p "$fake_bin" "$version_root"
printf '6.3.1\n' >"$version_root/.swift-version"

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG"
EOF

cat >"$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
printf 'tar %s\n' "$*" >> "$SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG"
cat >swiftly <<'SWIFTLY'
#!/usr/bin/env bash
printf 'pwd=%s args=%s\n' "$PWD" "$*" >> "$SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG"
if [[ "${1:-}" == "init" ]]; then
  mkdir -p "$SWIFTLY_BIN_DIR" "$SWIFTLY_HOME_DIR"
  cp "$0" "$SWIFTLY_BIN_DIR/swiftly"
  printf 'export PATH="%s:$PATH"\n' "$SWIFTLY_BIN_DIR" >"$SWIFTLY_HOME_DIR/env.sh"
  exit 0
fi
if [[ "${1:-}" == "install" ]]; then
  exit 0
fi
if [[ "${1:-}" == "run" && "${2:-}" == "swift" && "${3:-}" == "--version" ]]; then
  printf 'Swift version 6.3.1 (fake)\n'
  exit 0
fi
exit 0
SWIFTLY
chmod +x swiftly
EOF

chmod +x "$fake_bin/curl" "$fake_bin/tar"

(
  cd "$version_root"
  : >"$swiftly_log"
  env -u SWIFTLY_HOME_DIR -u SWIFTLY_BIN_DIR \
    PATH="$fake_bin:$PATH" \
    HOME="$tmpdir/home-linux" \
    SWIFTLY_VERSION=1.1.1 \
    SWIFTTUI_EXAMPLES_CI_HOST_OS=Linux \
    SWIFTTUI_EXAMPLES_CI_HOST_ARCH=x86_64 \
    SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG="$swiftly_log" \
    "$repo_root/Scripts/install_swift_toolchain_ci.sh" .swift-version >/dev/null
)

if ! grep -Fq -- "pwd=$version_root args=install --use --assume-yes 6.3.1" "$swiftly_log"; then
  echo "Expected Linux install to return to the Swift version file directory before installing the toolchain" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

mac_home="$tmpdir/home-macos"
mac_swiftly_home="$mac_home/.swiftly"
mac_swiftly_bin="$mac_swiftly_home/bin"
mkdir -p "$mac_swiftly_home" "$mac_swiftly_bin"
printf 'export PATH="%s:$PATH"\n' "$mac_swiftly_bin" >"$mac_swiftly_home/env.sh"

cat >"$mac_swiftly_bin/swiftly" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG"
state_file="${SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG}.install_failed"
if [[ "${1:-}" == "install" && ! -f "$state_file" ]]; then
  touch "$state_file"
  exit 1
fi
if [[ "${1:-}" == "run" && "${2:-}" == "swift" && "${3:-}" == "--version" ]]; then
  printf 'Swift version 6.3.1 (fake)\n'
  exit 0
fi
exit 0
EOF
chmod +x "$mac_swiftly_bin/swiftly"

: >"$swiftly_log"
env -u SWIFTLY_HOME_DIR -u SWIFTLY_BIN_DIR \
  PATH="$mac_swiftly_bin:$PATH" \
  HOME="$mac_home" \
  SWIFTLY_VERSION=1.1.1 \
  SWIFTTUI_EXAMPLES_CI_HOST_OS=Darwin \
  SWIFTTUI_EXAMPLES_TOOLCHAIN_LOG="$swiftly_log" \
  "$repo_root/Scripts/install_swift_toolchain_ci.sh" "$version_root/.swift-version" >/dev/null

if [[ "$(grep -Fc -- 'args=install --use --assume-yes 6.3.1' "$swiftly_log")" -ne 2 ]]; then
  echo "Expected macOS install to retry once after a cached toolchain failure" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Fq -- "args=uninstall 6.3.1 --assume-yes" "$swiftly_log"; then
  echo "Expected macOS retry to clear the cached toolchain first" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

printf '[install_swift_toolchain_ci_test] ok\n'
