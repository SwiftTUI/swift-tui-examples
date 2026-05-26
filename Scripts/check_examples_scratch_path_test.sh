#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fake_bin="$tmpdir/bin"
framework_root="$tmpdir/swift-tui"
web_root="$tmpdir/swift-tui-web"
swiftly_log="$tmpdir/swiftly.log"
python_log="$tmpdir/python.log"
scratch_path="$tmpdir/shared-swiftpm"

mkdir -p "$fake_bin" "$framework_root" "$web_root/packages/web"

cat >"$fake_bin/swiftly" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_SWIFTLY_LOG"
EOF

cat >"$fake_bin/bun" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fake_bin/python3" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_PYTHON_LOG"
exit 0
EOF

cat >"$fake_bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$fake_bin/swiftly" "$fake_bin/bun" "$fake_bin/python3" "$fake_bin/xcodebuild"

run_check() {
  : >"$swiftly_log"
  PATH="$fake_bin:$PATH" \
    SWIFTTUI_CHECKOUT="$framework_root" \
    SWIFTTUI_WEB_CHECKOUT="$web_root" \
    SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
    SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
    "$repo_root/Scripts/check_examples.sh" --skip-bun-install >/dev/null
}

: >"$python_log"
run_check

if grep -Fq -- "--scratch-path" "$swiftly_log"; then
  echo "Did not expect --scratch-path when SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH is unset" >&2
  exit 1
fi

: >"$swiftly_log"
: >"$python_log"
PATH="$fake_bin:$PATH" \
  SWIFTTUI_CHECKOUT="$framework_root" \
  SWIFTTUI_WEB_CHECKOUT="$web_root" \
  SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
  SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
  SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH="$scratch_path" \
  "$repo_root/Scripts/check_examples.sh" --skip-bun-install >/dev/null

missing_scratch="$tmpdir/missing-scratch.log"
if ! awk -v scratch="$scratch_path" '
  /run swift build/ && index($0, "--scratch-path " scratch) == 0 { print; bad = 1 }
  /run swift test/ && index($0, "--scratch-path " scratch) == 0 { print; bad = 1 }
  /run swift package clean/ && /--package-path/ && index($0, "--scratch-path " scratch) == 0 { print; bad = 1 }
  END { exit bad }
' "$swiftly_log" >"$missing_scratch"; then
  echo "Expected shared scratch path on every SwiftPM build/test/package-path clean:" >&2
  cat "$missing_scratch" >&2
  exit 1
fi

if grep -F "run swift package clean --scratch-path" "$swiftly_log" >/dev/null; then
  echo "Did not expect framework-level package clean to use the examples scratch path" >&2
  exit 1
fi

if ! grep -Fq -- "--binary $scratch_path/debug/gallery-demo" "$python_log"; then
  echo "Expected debug stack-safety harness to use the shared scratch binary" >&2
  cat "$python_log" >&2
  exit 1
fi

if ! grep -Fq -- "--binary $scratch_path/release/gallery-demo" "$python_log"; then
  echo "Expected release stack-safety harness to use the shared scratch binary" >&2
  cat "$python_log" >&2
  exit 1
fi

printf '[check_examples_scratch_path_test] ok\n'
