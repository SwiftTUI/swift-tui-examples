#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
framework_root=${SWIFTTUI_CHECKOUT:-"$repo_root/../swift-tui"}
web_root=${SWIFTTUI_WEB_CHECKOUT:-"$repo_root/../swift-tui-web"}

skip_clean=0
skip_bun_install=0
failures=""

usage() {
  cat <<'EOF'
Usage: Scripts/check_examples.sh [--skip-clean] [--skip-bun-install]

Builds and tests the SwiftTUI example packages from a sibling checkout layout:
  - swift-tui-examples: this repository
  - swift-tui: framework checkout, default ../swift-tui
  - swift-tui-web: browser package checkout, default ../swift-tui-web

Set SWIFTTUI_CHECKOUT or SWIFTTUI_WEB_CHECKOUT to override the sibling paths.
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
    --skip-clean)
      skip_clean=1
      ;;
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
require_command python3
require_command xcodebuild
require_checkout "$framework_root" "swift-tui"
require_checkout "$web_root" "swift-tui-web"

run_swift() {
  swiftly run swift "$@"
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

if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
  run_step \
    "Install Bun workspace dependencies" \
    "$repo_root" \
    bun install --frozen-lockfile
fi

run_step \
  "Check examples CI workflow" \
  "$repo_root" \
  Scripts/check_examples_ci_workflow.sh

if [ "$skip_clean" -eq 0 ]; then
  run_step \
    "Clean SwiftTUI framework package" \
    "$framework_root" \
    run_swift package clean

  for package_path in \
    "argparse" \
    "file-previewer" \
    "gallery" \
    "gifcat" \
    "gifeditor" \
    "gitviz" \
    "terminal-workspace" \
    "layouts" \
    "SwiftUIExample/TerminalApp" \
    "WebExample/TerminalApp" \
    "WebHostExample"; do
    run_step \
      "Clean $package_path" \
      "$repo_root" \
      run_swift package clean --package-path "$package_path"
  done
fi

for package_path in \
  "argparse" \
  "file-previewer" \
  "gifcat" \
  "gifeditor" \
  "gitviz" \
  "terminal-workspace"; do
  run_step \
    "Build $package_path" \
    "$repo_root" \
    run_swift build --package-path "$package_path"

  run_step \
    "Build $package_path (release)" \
    "$repo_root" \
    run_swift build -c release --package-path "$package_path"
done

run_step \
  "Build gallery" \
  "$repo_root" \
  run_swift build --package-path gallery

run_step \
  "Build gallery (release)" \
  "$repo_root" \
  run_swift build -c release --package-path gallery

run_step \
  "Stack safety gallery (debug)" \
  "$repo_root" \
  python3 Scripts/stack_safety_harness.py \
    --binary gallery/.build/debug/gallery-demo \
    --count 20

run_step \
  "Stack safety gallery (release)" \
  "$repo_root" \
  python3 Scripts/stack_safety_harness.py \
    --binary gallery/.build/release/gallery-demo \
    --count 20

run_step \
  "Build layouts" \
  "$repo_root" \
  run_swift build --package-path layouts

run_step \
  "Build layouts (release)" \
  "$repo_root" \
  run_swift build -c release --package-path layouts

run_step \
  "Build SwiftUIExample/TerminalApp" \
  "$repo_root" \
  run_swift build --package-path SwiftUIExample/TerminalApp

run_step \
  "Build WebExample/TerminalApp" \
  "$repo_root" \
  run_swift build --package-path WebExample/TerminalApp

run_step \
  "Build WebHostExample" \
  "$repo_root" \
  run_swift build --package-path WebHostExample

run_step \
  "Test WebHostExample" \
  "$repo_root" \
  run_swift test --package-path WebHostExample

run_step \
  "Build SwiftTUIWebHost framework targets" \
  "$framework_root" \
  run_swift build --target SwiftTUIWebHost --target SwiftTUIWebHostCLI

run_step \
  "Build SwiftUIHost framework target" \
  "$framework_root" \
  run_swift build --target SwiftUIHost

if [ "$skip_clean" -eq 0 ]; then
  run_step \
    "Build SwiftUIExample macOS app" \
    "$repo_root" \
    xcodebuild \
      -project SwiftUIExample/SwiftUIExample.xcodeproj \
      -scheme SwiftUIExample \
      -configuration Debug \
      -destination generic/platform=macOS \
      clean build
else
  run_step \
    "Build SwiftUIExample macOS app" \
    "$repo_root" \
    xcodebuild \
      -project SwiftUIExample/SwiftUIExample.xcodeproj \
      -scheme SwiftUIExample \
      -configuration Debug \
      -destination generic/platform=macOS \
      build
fi

run_step \
  "Build WebExample web demo" \
  "$repo_root/WebExample" \
  bun run build

run_step \
  "Build swift-tui-web host with WebExampleApp" \
  "$web_root/packages/web" \
  bun run build -- --package-path "$repo_root/WebExample/TerminalApp" --app WebExampleApp

echo ""
if [ -z "$failures" ]; then
  echo "All example builds succeeded."
  exit 0
fi

>&2 echo "Example build failures:"
OLD_IFS=$IFS
IFS='
'
for failure in $failures; do
  >&2 echo "  - $failure"
done
IFS=$OLD_IFS

exit 1
