#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

real_python="$(command -v python3)"
validator="$repo_root/mrkdwn/Scripts/check_manifest_contract.py"
fake_bin="$tmpdir/bin"
framework_root="$tmpdir/swift-tui"
web_root="$tmpdir/swift-tui-web"
wrong_framework_root="$tmpdir/wrong/swift-tui"
public_runtime_root="$tmpdir/public-runtime"
swiftly_log="$tmpdir/swiftly.log"
bun_log="$tmpdir/bun.log"
python_log="$tmpdir/python.log"
xcode_log="$tmpdir/xcodebuild.log"
scratch_path="$tmpdir/shared-swiftpm"
semantic_root="$tmpdir/semantic"
public_dump="$semantic_root/public-dump.json"
overlay_dump="$semantic_root/overlay-dump.json"
wrong_overlay_dump="$semantic_root/wrong-overlay-dump.json"
semantic_package="$semantic_root/package"
special_checkout="$semantic_root/checkouts/Swift TUI é \"quote\" \\ slash"
localized_manifest="$semantic_root/LocalizedPackage.swift"
package_root_loop="$semantic_root/package-root-loop"

mkdir -p \
  "$fake_bin" \
  "$framework_root" \
  "$web_root/packages/web" \
  "$wrong_framework_root" \
  "$public_runtime_root" \
  "$semantic_package" \
  "$special_checkout"

cat >"$public_dump" <<'EOF'
{
  "name": "mrkdwn",
  "dependencies": [
    {
      "sourceControl": [{
        "identity": "swift-tui",
        "location": {"remote": [{"urlString": "https://github.com/SwiftTUI/swift-tui.git"}]},
        "requirement": {"range": [{"lowerBound": "0.8.4", "upperBound": "0.9.0"}]}
      }]
    },
    {
      "sourceControl": [{
        "identity": "swift-markdown",
        "location": {"remote": [{"urlString": "https://github.com/swiftlang/swift-markdown.git"}]},
        "requirement": {"range": [{"lowerBound": "0.8.4", "upperBound": "0.9.0"}]}
      }]
    }
  ]
}
EOF

cat >"$overlay_dump" <<EOF
{
  "name": "mrkdwn",
  "dependencies": [
    {
      "fileSystem": [{
        "identity": "swift-tui",
        "path": "$framework_root"
      }]
    },
    {
      "sourceControl": [{
        "identity": "swift-markdown",
        "location": {"remote": [{"urlString": "https://github.com/swiftlang/swift-markdown.git"}]},
        "requirement": {"range": [{"lowerBound": "0.8.4", "upperBound": "0.9.0"}]}
      }]
    }
  ]
}
EOF

sed "s#$framework_root#$wrong_framework_root#" \
  "$overlay_dump" >"$wrong_overlay_dump"

write_semantic_lock() {
  revision_override=$1
  "$real_python" - \
    "$validator" \
    "$semantic_package/Package.resolved" \
    "$revision_override" <<'PY'
import json
import runpy
import sys

contracts = runpy.run_path(sys.argv[1])["PUBLIC_DEPENDENCIES"]
revision_override = sys.argv[3]
pins = []
for identity, contract in contracts.items():
    revision = contract["revision"]
    if identity == "swift-tui" and revision_override != "current":
        revision = revision_override
    pins.append(
        {
            "identity": identity,
            "kind": "remoteSourceControl",
            "location": contract["url"],
            "state": {
                "revision": revision,
                "version": contract["resolved"],
            },
        }
    )
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump({"pins": pins, "version": 3}, handle)
PY
}

expect_contract_failure() {
  label=$1
  shift
  error_log="$semantic_root/error.log"
  if "$real_python" "$validator" "$@" >"$semantic_root/output.log" 2>"$error_log"; then
    echo "Expected semantic validator failure: $label" >&2
    exit 1
  fi
  if ! grep -Fq "mrkdwn dependency contract failed:" "$error_log"; then
    echo "Expected reader-facing validator error: $label" >&2
    cat "$error_log" >&2
    exit 1
  fi
}

write_semantic_lock current
"$real_python" "$validator" \
  --localize-manifest \
  "$repo_root/mrkdwn/Package.swift" \
  "$localized_manifest" \
  "$special_checkout"
if ! grep -Fq 'Swift TUI é \"quote\" \\ slash")' "$localized_manifest"; then
  echo "Expected Swift-safe escaping in the localized checkout path" >&2
  cat "$localized_manifest" >&2
  exit 1
fi
if grep -Fq '\u00' "$localized_manifest"; then
  echo "Did not expect JSON-style Unicode escapes in a Swift string literal" >&2
  cat "$localized_manifest" >&2
  exit 1
fi
"$real_python" "$validator" "$public_dump" "$semantic_package" >/dev/null
"$real_python" "$validator" \
  --overlay "$framework_root" "$overlay_dump" "$semantic_package" >/dev/null
expect_contract_failure \
  "same-basename overlay path does not match the configured checkout" \
  --overlay "$framework_root" "$wrong_overlay_dump" "$semantic_package"

write_semantic_lock ""
expect_contract_failure \
  "empty direct-dependency revision" \
  "$public_dump" "$semantic_package"

write_semantic_lock 0000000000000000000000000000000000000000
expect_contract_failure \
  "mismatched direct-dependency revision" \
  "$public_dump" "$semantic_package"

printf '[]\n' >"$semantic_package/Package.resolved"
expect_contract_failure \
  "Package.resolved array root" \
  "$public_dump" "$semantic_package"

printf '\377' >"$semantic_package/Package.resolved"
expect_contract_failure \
  "invalid UTF-8 Package.resolved" \
  "$public_dump" "$semantic_package"

ln -s "$package_root_loop" "$package_root_loop"
expect_contract_failure \
  "cyclic Package.resolved root path" \
  "$public_dump" "$package_root_loop"

cat >"$fake_bin/swiftly" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_SWIFTLY_LOG"
if [[ "$*" == *" dump-package" ]]; then
  cat "$SWIFTTUI_EXAMPLES_OVERLAY_DUMP"
fi
EOF

cat >"$fake_bin/bun" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_BUN_LOG"
exit 0
EOF

cat >"$fake_bin/python3" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_PYTHON_LOG"
if [[ "${SWIFTTUI_EXAMPLES_FAIL_MANIFEST:-0}" == "1" ]] &&
  [[ "${1:-}" == */mrkdwn/Scripts/check_manifest_contract.py ]] &&
  [[ "$*" == *" --overlay "* ]]; then
  exit 23
fi
if [[ "${SWIFTTUI_EXAMPLES_SKIP_MANIFEST:-0}" == "1" ]] &&
  [[ "${1:-}" == */mrkdwn/Scripts/check_manifest_contract.py ]]; then
  exit 0
fi
if [[ "${1:-}" == */mrkdwn/Scripts/check_manifest_contract.py ]]; then
  exec "$SWIFTTUI_EXAMPLES_REAL_PYTHON" "$@"
fi
exit 0
EOF

cat >"$fake_bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWIFTTUI_EXAMPLES_XCODE_LOG"
exit 0
EOF

chmod +x "$fake_bin/swiftly" "$fake_bin/bun" "$fake_bin/python3" "$fake_bin/xcodebuild"
export SWIFTTUI_EXAMPLES_REAL_PYTHON="$real_python"
export SWIFTTUI_EXAMPLES_OVERLAY_DUMP="$overlay_dump"

run_check() {
  : >"$swiftly_log"
  PATH="$fake_bin:$PATH" \
    SWIFTTUI_CHECKOUT="$framework_root" \
    SWIFTTUI_WEB_CHECKOUT="$web_root" \
    SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
    SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
    SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
    SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
    "$repo_root/Scripts/check_examples.sh" --skip-bun-install >/dev/null
}

: >"$bun_log"
: >"$python_log"
: >"$xcode_log"
run_check

if grep -Fq -- "--scratch-path" "$swiftly_log"; then
  echo "Did not expect --scratch-path when SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH is unset" >&2
  exit 1
fi

if ! grep -Fq -- "--overlay $framework_root" "$python_log"; then
  echo "Expected the mrkdwn validator to receive the exact local checkout" >&2
  cat "$python_log" >&2
  exit 1
fi

if ! grep -Fq -- "--localize-manifest" "$python_log"; then
  echo "Expected local checkout mode to create disposable manifests" >&2
  cat "$python_log" >&2
  exit 1
fi

if ! grep -Eq -- "/csvui/Scripts/check_manifest_contract.py --localize-manifest" "$python_log"; then
  echo "Expected local checkout mode to create a disposable csvui manifest" >&2
  cat "$python_log" >&2
  exit 1
fi

if grep -Fq -- "--package-path mrkdwn" "$swiftly_log"; then
  echo "Did not expect local checkout mode to build the public mrkdwn package root" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if grep -Fq -- "--package-path csvui" "$swiftly_log"; then
  echo "Did not expect local checkout mode to build the public csvui package root" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

: >"$swiftly_log"
: >"$python_log"
PATH="$fake_bin:$PATH" \
  TMPDIR="$public_runtime_root" \
  SWIFTTUI_CHECKOUT= \
  SWIFTTUI_WEB_CHECKOUT="$web_root" \
  SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
  SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
  SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
  SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
  SWIFTTUI_EXAMPLES_OVERLAY_DUMP="$public_dump" \
  SWIFTTUI_EXAMPLES_SKIP_MANIFEST=1 \
  "$repo_root/Scripts/check_examples.sh" \
  --linux-only --skip-bun-install >/dev/null
if find "$public_runtime_root" -mindepth 1 -print -quit | grep -q .; then
  echo "Expected public-mode runtime temporary files to be removed" >&2
  find "$public_runtime_root" -mindepth 1 -maxdepth 2 -print >&2
  exit 1
fi

for gate_script in \
  "Scripts/check_examples.sh" \
  "Scripts/check_examples_focused_tests.sh"; do
  : >"$swiftly_log"
  : >"$python_log"
  gate_arguments=(--skip-bun-install)
  if [ "$gate_script" = "Scripts/check_examples.sh" ]; then
    gate_arguments=(--linux-only --skip-bun-install)
  fi
  if PATH="$fake_bin:$PATH" \
    SWIFTTUI_CHECKOUT="$framework_root" \
    SWIFTTUI_WEB_CHECKOUT="$web_root" \
    SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
    SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
    SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
    SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
    SWIFTTUI_EXAMPLES_FAIL_MANIFEST=1 \
    "$repo_root/$gate_script" "${gate_arguments[@]}" >/dev/null 2>&1; then
    echo "Expected $gate_script to fail when the mrkdwn manifest contract fails" >&2
    exit 1
  fi
done

: >"$swiftly_log"
: >"$python_log"
PATH="$fake_bin:$PATH" \
  SWIFTTUI_CHECKOUT="$framework_root" \
  SWIFTTUI_WEB_CHECKOUT="$web_root" \
  SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
  SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
  SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
  SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
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

: >"$swiftly_log"
: >"$bun_log"
: >"$python_log"
: >"$xcode_log"
PATH="$fake_bin:$PATH" \
  SWIFTTUI_CHECKOUT="$framework_root" \
  SWIFTTUI_WEB_CHECKOUT="$web_root" \
  SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
  SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
  SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
  SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
  SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH="$scratch_path" \
  "$repo_root/Scripts/check_examples_linux.sh" --skip-bun-install >/dev/null

if [ -s "$xcode_log" ]; then
  echo "Did not expect the Linux examples lane to invoke xcodebuild" >&2
  cat "$xcode_log" >&2
  exit 1
fi

if grep -Fq -- "build --target SwiftUIHost" "$swiftly_log"; then
  echo "Did not expect the Linux examples lane to build SwiftUIHost" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Fq -- "build --package-path minimal" "$swiftly_log"; then
  echo "Expected the Linux examples lane to build minimal" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Fq -- "build --package-path terminal-runner" "$swiftly_log"; then
  echo "Expected the Linux examples lane to build terminal-runner" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "build --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the Linux lane to build mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "build -c release --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the Linux lane to release-build mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "test --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the Linux lane to test mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "build --package-path .*/csvui --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the Linux lane to build csvui through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "build -c release --package-path .*/csvui --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the Linux lane to release-build csvui through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "test --package-path .*/csvui --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the Linux lane to test csvui through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

: >"$swiftly_log"
: >"$bun_log"
: >"$python_log"
: >"$xcode_log"
PATH="$fake_bin:$PATH" \
  SWIFTTUI_CHECKOUT="$framework_root" \
  SWIFTTUI_WEB_CHECKOUT="$tmpdir/missing-swift-tui-web" \
  SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
  SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
  SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
  SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
  SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH="$scratch_path" \
  "$repo_root/Scripts/check_examples_macos.sh" --skip-clean >/dev/null

if [ -s "$bun_log" ]; then
  echo "Did not expect the macOS examples lane to invoke bun" >&2
  cat "$bun_log" >&2
  exit 1
fi

if grep -Fq -- "WebExample" "$swiftly_log"; then
  echo "Did not expect the macOS examples lane to build WebExample" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if grep -Fq -- "build --target SwiftUIHost" "$swiftly_log"; then
  echo "Did not expect the macOS examples lane to run a framework-only SwiftUIHost build" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Fq -- "build --package-path LayoutsSwiftUI" "$swiftly_log"; then
  echo "Expected the macOS examples lane to build LayoutsSwiftUI" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "build --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the macOS lane to build mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "build -c release --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the macOS lane to release-build mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "test --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the macOS lane to test mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Fq -- "CODE_SIGNING_ALLOWED=NO" "$xcode_log"; then
  echo "Expected the macOS app build to disable code signing in CI" >&2
  cat "$xcode_log" >&2
  exit 1
fi

if ! grep -Fq -- "SWIFT_SUPPRESS_WARNINGS=NO" "$xcode_log"; then
  echo "Expected the macOS app build to keep package warnings visible" >&2
  cat "$xcode_log" >&2
  exit 1
fi

: >"$swiftly_log"
: >"$bun_log"
: >"$python_log"
: >"$xcode_log"
PATH="$fake_bin:$PATH" \
  SWIFTTUI_CHECKOUT="$framework_root" \
  SWIFTTUI_WEB_CHECKOUT="$web_root" \
  SWIFTTUI_EXAMPLES_SWIFTLY_LOG="$swiftly_log" \
  SWIFTTUI_EXAMPLES_BUN_LOG="$bun_log" \
  SWIFTTUI_EXAMPLES_PYTHON_LOG="$python_log" \
  SWIFTTUI_EXAMPLES_XCODE_LOG="$xcode_log" \
  SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH="$scratch_path" \
  "$repo_root/Scripts/check_examples_focused_tests.sh" --skip-bun-install >/dev/null

if [ -s "$xcode_log" ]; then
  echo "Did not expect the focused examples lane to invoke xcodebuild" >&2
  cat "$xcode_log" >&2
  exit 1
fi

missing_focused_scratch="$tmpdir/missing-focused-scratch.log"
if ! awk -v scratch="$scratch_path" '
  /run swift test/ && index($0, "--scratch-path " scratch) == 0 { print; bad = 1 }
  END { exit bad }
' "$swiftly_log" >"$missing_focused_scratch"; then
  echo "Expected shared scratch path on every focused SwiftPM test:" >&2
  cat "$missing_focused_scratch" >&2
  exit 1
fi

if ! grep -Fq -- "run swift test --package-path gallery --scratch-path $scratch_path" "$swiftly_log"; then
  echo "Expected the focused examples lane to test gallery through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Fq -- "run swift test --package-path terminal-runner --scratch-path $scratch_path" "$swiftly_log"; then
  echo "Expected the focused examples lane to test terminal-runner through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

if ! grep -Eq -- \
  "run swift test --package-path .*/mrkdwn --scratch-path $scratch_path" \
  "$swiftly_log"; then
  echo "Expected the focused examples lane to test mrkdwn through the shared scratch path" >&2
  cat "$swiftly_log" >&2
  exit 1
fi

printf '[check_examples_scratch_path_test] ok\n'
