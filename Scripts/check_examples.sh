#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
framework_root=${SWIFTTUI_CHECKOUT:-}
web_root=${SWIFTTUI_WEB_CHECKOUT:-}
swiftpm_scratch=${SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH:-}
xcode_derived_data=${SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA:-}

skip_clean=0
skip_bun_install=0
suite=all
failures=""

usage() {
  cat <<'EOF'
Usage: Scripts/check_examples.sh [--linux-only|--macos-only|--web-only] [--skip-clean] [--skip-bun-install]

Builds and tests the SwiftTUI example packages from this repository. By default
the examples resolve public SwiftTUI release tags and web package release
tarballs; no sibling checkouts are required.

Set SWIFTTUI_CHECKOUT or SWIFTTUI_WEB_CHECKOUT only when deliberately testing
against local sibling checkouts. The default public gate does not use them.
Set SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH to reuse one sequential SwiftPM scratch
directory across the example package builds. Do not share that directory across
parallel check runs.
Set SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA to reuse an Xcode DerivedData path for
the macOS app build.
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
    --linux-only)
      suite=linux
      ;;
    --macos-only|--mac-only)
      suite=macos
      ;;
    --web-only)
      suite=web
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

run_linux_suite() {
  [ "$suite" = "all" ] || [ "$suite" = "linux" ]
}

run_macos_suite() {
  [ "$suite" = "all" ] || [ "$suite" = "macos" ]
}

run_web_suite() {
  [ "$suite" = "all" ] || [ "$suite" = "web" ]
}

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
if run_linux_suite; then
  require_command python3
fi
if run_web_suite; then
  require_command bun
fi
if run_macos_suite; then
  require_command xcodebuild
fi
if [ -n "$framework_root" ]; then
  require_checkout "$framework_root" "swift-tui"
fi
if run_web_suite && [ -n "$web_root" ]; then
  require_checkout "$web_root" "swift-tui-web"
fi

run_swift() {
  if should_use_swiftpm_scratch "$@"; then
    swiftly run swift "$@" --scratch-path "$swiftpm_scratch"
  else
    swiftly run swift "$@"
  fi
}

should_use_swiftpm_scratch() {
  if [ -z "$swiftpm_scratch" ] || [ "$#" -eq 0 ]; then
    return 1
  fi

  case "$1" in
    build|test)
      return 0
      ;;
    package)
      shift
      if [ "$#" -eq 0 ] || [ "$1" != "clean" ]; then
        return 1
      fi
      shift
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--package-path" ]; then
          return 0
        fi
        shift
      done
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

swiftpm_binary_path() {
  package_path=$1
  configuration=$2
  product=$3

  if [ -n "$swiftpm_scratch" ]; then
    printf '%s/%s/%s\n' "$swiftpm_scratch" "$configuration" "$product"
  else
    printf '%s/%s/.build/%s/%s\n' "$repo_root" "$package_path" "$configuration" "$product"
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

print_section() {
  echo ""
  echo "### $1"
}

run_xcodebuild_swiftui_example() {
  set -- \
    xcodebuild \
    -project SwiftUIExample/SwiftUIExample.xcodeproj \
    -scheme SwiftUIExample \
    -configuration Debug \
    -destination generic/platform=macOS

  if [ -n "$xcode_derived_data" ]; then
    set -- "$@" -derivedDataPath "$xcode_derived_data"
  fi

  set -- "$@" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    SWIFT_SUPPRESS_WARNINGS=NO

  if [ "$skip_clean" -eq 0 ]; then
    set -- "$@" clean build
  else
    set -- "$@" build
  fi

  "$@"
}

run_linux_examples() {
  if [ "$skip_clean" -eq 0 ]; then
    if [ -n "$framework_root" ]; then
      run_step \
        "Clean SwiftTUI framework package" \
        "$framework_root" \
        run_swift package clean
    fi

    for package_path in \
      "minimal" \
      "equatable-demo" \
      "terminal-runner" \
      "argparse" \
      "file-previewer" \
      "gallery" \
      "gifcat" \
      "gifeditor" \
      "gitviz" \
      "terminal-workspace" \
      "three-hosts-demo" \
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

  print_section "Linux build-only coverage"

  for package_path in \
    "minimal" \
    "equatable-demo" \
    "terminal-runner" \
    "argparse" \
    "file-previewer" \
    "gifcat" \
    "gifeditor" \
    "gitviz" \
    "terminal-workspace" \
    "three-hosts-demo"; do
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
      --binary "$(swiftpm_binary_path gallery debug gallery-demo)" \
      --count 20

  run_step \
    "Stack safety gallery (release)" \
    "$repo_root" \
    python3 Scripts/stack_safety_harness.py \
      --binary "$(swiftpm_binary_path gallery release gallery-demo)" \
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

  print_section "Linux focused smoke tests"

  run_step \
    "Test WebHostExample" \
    "$repo_root" \
    run_swift test --package-path WebHostExample

  run_step \
    "Test three-hosts-demo" \
    "$repo_root" \
    run_swift test --package-path three-hosts-demo

  # The gallery exercises the full app shell (lazy-tab capture-host seam,
  # toolbar strip, command palette). Its test suite is the only coverage of
  # seam-hosted interactivity end to end; build-only checks cannot catch a
  # stranded action handler. The default suite is deterministic
  # (GALLERY_RUNTIME_TESTS-gated PTY/timing tests stay opt-in).
  run_step \
    "Test gallery" \
    "$repo_root" \
    run_swift test --package-path gallery
}

run_macos_examples() {
  if [ "$skip_clean" -eq 0 ]; then
    if [ -n "$framework_root" ]; then
      run_step \
        "Clean SwiftTUI framework package" \
        "$framework_root" \
        run_swift package clean
    fi

    run_step \
      "Clean SwiftUIExample/TerminalApp" \
      "$repo_root" \
      run_swift package clean --package-path SwiftUIExample/TerminalApp

    run_step \
      "Clean LayoutsSwiftUI" \
      "$repo_root" \
      run_swift package clean --package-path LayoutsSwiftUI
  fi

  print_section "macOS build-only coverage"

  run_step \
    "Build SwiftUIExample/TerminalApp" \
    "$repo_root" \
    run_swift build --package-path SwiftUIExample/TerminalApp

  run_step \
    "Build LayoutsSwiftUI" \
    "$repo_root" \
    run_swift build --package-path LayoutsSwiftUI

  run_step \
    "Build SwiftUIExample macOS app" \
    "$repo_root" \
    run_xcodebuild_swiftui_example
}

run_web_examples() {
  print_section "Web build-only coverage"

  if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
    run_step \
      "Install Bun workspace dependencies" \
      "$repo_root" \
      bun install --frozen-lockfile
  fi

  run_step \
    "Build WebExample web demo" \
    "$repo_root/WebExample" \
    bun run build

  if [ -n "$web_root" ]; then
    run_step \
      "Build local swift-tui-web host with WebExampleApp" \
      "$web_root/packages/web" \
      bun run build -- --package-path "$repo_root/WebExample/TerminalApp" --app WebExampleApp
  fi
}

run_step \
  "Check CI Swift toolchain setup" \
  "$repo_root" \
  Scripts/install_swift_toolchain_ci_test.sh

run_step \
  "Check examples CI workflow" \
  "$repo_root" \
  Scripts/check_examples_ci_workflow.sh

if run_linux_suite; then
  run_linux_examples
fi

if run_macos_suite; then
  run_macos_examples
fi

if run_web_suite; then
  run_web_examples
fi

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
