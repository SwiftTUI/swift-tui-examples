#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
framework_root=${SWIFTTUI_CHECKOUT:-}
swiftpm_scratch=${SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH:-}
runtime_tmpdir=
mrkdwn_package_path="$repo_root/mrkdwn"
skip_bun_install=0
failures=""

usage() {
  cat <<'EOF'
Usage: Scripts/check_examples_focused_tests.sh [--skip-bun-install]

Runs the example packages' focused behavior tests. The main examples gate
(`Scripts/check_examples.sh`) is build-first and keeps these slower test suites
separate so CI and pre-tag lanes can choose the right contract explicitly.

Set SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH to reuse one sequential SwiftPM scratch
directory across the example package tests. Do not share that directory across
parallel checks.
When SWIFTTUI_CHECKOUT is set, mrkdwn runs from a disposable package root whose
SwiftTUI dependency points at that exact checkout; the public manifest is not
modified.
EOF
}

add_failure() {
  title=$1
  if [ -z "$failures" ]; then
    failures=$title
  else
    failures=$failures'
'$title
  fi
}

for argument in "$@"; do
  case "$argument" in
    --skip-bun-install)
      skip_bun_install=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      >&2 echo "Unknown argument: $argument"
      >&2 echo ""
      usage
      exit 1
      ;;
  esac
done

require_command() {
  name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    >&2 echo "Missing required command: $name"
    exit 1
  fi
}

require_checkout() {
  path=$1
  label=$2
  if [ ! -d "$path" ]; then
    >&2 echo "Missing $label checkout: $path"
    exit 1
  fi
}

cleanup_runtime_tmpdir() {
  if [ -n "$runtime_tmpdir" ] && [ -d "$runtime_tmpdir" ]; then
    rm -rf -- "$runtime_tmpdir"
  fi
}

trap cleanup_runtime_tmpdir EXIT
trap 'cleanup_runtime_tmpdir; exit 129' HUP
trap 'cleanup_runtime_tmpdir; exit 130' INT
trap 'cleanup_runtime_tmpdir; exit 143' TERM

ensure_runtime_tmpdir() {
  if [ -z "$runtime_tmpdir" ]; then
    runtime_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-examples-focused.XXXXXX")
  fi
}

prepare_mrkdwn_package() {
  if [ -z "$framework_root" ]; then
    return
  fi

  ensure_runtime_tmpdir
  localized_root="$runtime_tmpdir/mrkdwn"
  mkdir -p "$localized_root"
  cp "$repo_root/mrkdwn/Package.swift" \
    "$repo_root/mrkdwn/Package.resolved" \
    "$repo_root/mrkdwn/default-theme.toml" \
    "$localized_root/"
  cp -R "$repo_root/mrkdwn/Sources" "$repo_root/mrkdwn/Tests" "$localized_root/"
  python3 "$repo_root/mrkdwn/Scripts/check_manifest_contract.py" \
    --localize-manifest \
    "$repo_root/mrkdwn/Package.swift" \
    "$localized_root/Package.swift" \
    "$framework_root"
  mrkdwn_package_path=$localized_root
}

require_command swiftly
require_command bun
require_command python3
ensure_runtime_tmpdir
if [ -n "$framework_root" ]; then
  require_checkout "$framework_root" "swift-tui"
  prepare_mrkdwn_package
fi

run_swift() {
  if [ -n "$swiftpm_scratch" ]; then
    swiftly run swift "$@" --scratch-path "$swiftpm_scratch"
  else
    swiftly run swift "$@"
  fi
}

run_mrkdwn_manifest_contract() {
  ensure_runtime_tmpdir
  dump_file="$runtime_tmpdir/mrkdwn-dump-package.json"
  status=0
  if ! swiftly run swift package \
    --package-path "$mrkdwn_package_path" \
    dump-package >"$dump_file"; then
    status=1
  elif [ -n "$framework_root" ]; then
    if ! python3 "$repo_root/mrkdwn/Scripts/check_manifest_contract.py" \
      --overlay "$framework_root" "$dump_file" "$mrkdwn_package_path"; then
      status=1
    fi
  elif ! python3 "$repo_root/mrkdwn/Scripts/check_manifest_contract.py" \
    "$dump_file" "$mrkdwn_package_path"; then
    status=1
  fi
  rm -f "$dump_file"
  return "$status"
}

run_mrkdwn_tests() {
  run_mrkdwn_manifest_contract || return 1
  export MRKDWN_REAL_PTY_TESTS=1
  run_swift test --package-path "$mrkdwn_package_path"
}

run_step() {
  title=$1
  workdir=$2
  shift 2

  echo ""
  echo "==> $title"

  if (
    cd "$workdir" &&
    "$@"
  ); then
    echo "PASS: $title"
  else
    >&2 echo "FAIL: $title"
    add_failure "$title"
  fi
}

echo ""
echo "### Focused SwiftPM behavior tests"

for package_path in \
  "sextant" \
  "terminal-runner" \
  "gallery" \
  "gifcat" \
  "gifeditor" \
  "git-viz" \
  "layouts" \
  "terminal-workspace" \
  "WebHostExample"; do
  run_step \
    "Test $package_path" \
    "$repo_root" \
    run_swift test --package-path "$package_path"
done

run_step \
  "Test mrkdwn" \
  "$repo_root" \
  run_mrkdwn_tests

echo ""
echo "### Focused browser behavior tests"

if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
  run_step \
    "Install Bun workspace dependencies" \
    "$repo_root" \
    bun install --frozen-lockfile
fi

run_step \
  "Test WebExample" \
  "$repo_root" \
  bun test --cwd WebExample

echo ""
if [ -z "$failures" ]; then
  echo "All focused example tests succeeded."
  exit 0
fi

>&2 echo "Focused example test failures:"
OLD_IFS=$IFS
IFS='
'
for failure in $failures; do
  >&2 echo "  - $failure"
done
IFS=$OLD_IFS

exit 1
