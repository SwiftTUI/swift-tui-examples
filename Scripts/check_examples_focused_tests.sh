#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
framework_root=${SWIFTTUI_CHECKOUT:-"$repo_root/../swift-tui"}
swiftpm_scratch=${SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH:-}
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

require_command swiftly
require_command bun
require_checkout "$framework_root" "swift-tui"

run_swift() {
  if [ -n "$swiftpm_scratch" ]; then
    swiftly run swift "$@" --scratch-path "$swiftpm_scratch"
  else
    swiftly run swift "$@"
  fi
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
  "file-previewer" \
  "terminal-runner" \
  "gallery" \
  "gifcat" \
  "gifeditor" \
  "gitviz" \
  "layouts" \
  "terminal-workspace" \
  "WebHostExample"; do
  run_step \
    "Test $package_path" \
    "$repo_root" \
    run_swift test --package-path "$package_path"
done

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
