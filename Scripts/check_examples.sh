#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
framework_root=${SWIFTTUI_CHECKOUT:-}
swiftpm_scratch=${SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH:-}
xcode_derived_data=${SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA:-}
runtime_tmpdir=
mrkdwn_package_path="$repo_root/mrkdwn"
csvui_package_path="$repo_root/csvui"

skip_clean=0
skip_bun_install=0
release_builds=0
suite=all
failures=""
step_index=0

# Per-step silence watchdog (Scripts/lib/step_watchdog.sh, plan 2026-08-25-001
# Stage 3c). It bounds SILENCE, not wall clock: a step that keeps printing runs
# as long as it needs; a step that goes quiet for the bound is dumped (gdb
# thread backtraces when SWIFTTUI_HANG_DIAGNOSTICS=1 on Linux) and killed, and
# the gate aborts. Builds get a longer bound than tests: a whole-module release
# compile of the framework can legitimately print nothing for minutes, while
# the slowest healthy example test finishes in ~100 s. The first TIMEOUT is
# recorded and the gate continues (packages are independent); a second one
# aborts the run.
# Darwin gets a wider test bound: the macOS lane is dispatch/tag-only on a
# 60-minute cap, its runners are slower and noisier than the Linux hot path,
# and the tight Linux bound is what keeps a wedged push lane at ~5 minutes.
case "$(uname -s)" in
  Darwin) default_test_step_timeout_seconds=600 ;;
  *) default_test_step_timeout_seconds=300 ;;
esac
build_step_timeout_seconds=${SWIFTTUI_EXAMPLES_STEP_TIMEOUT_SECONDS:-600}
test_step_timeout_seconds=${SWIFTTUI_EXAMPLES_TEST_STEP_TIMEOUT_SECONDS:-$default_test_step_timeout_seconds}
step_timeout_seconds=$build_step_timeout_seconds
step_timeout_kill_grace_seconds=${SWIFTTUI_EXAMPLES_TIMEOUT_KILL_GRACE_SECONDS:-10}
# Backstop for the one case silence cannot catch: a step that livelocks while
# printing. Defaults to 4x the idle bound; 0 disables it.
step_absolute_timeout_seconds=${SWIFTTUI_EXAMPLES_STEP_ABSOLUTE_TIMEOUT_SECONDS:-$((build_step_timeout_seconds * 4))}
step_output_probe_ticks=${SWIFTTUI_EXAMPLES_STEP_OUTPUT_PROBE_TICKS:-25}

usage() {
  cat <<'EOF'
Usage: Scripts/check_examples.sh [--linux-only|--macos-only] [--skip-clean] [--skip-bun-install] [--release-builds]

Builds and tests the SwiftTUI example packages from this repository. By default
the examples resolve public SwiftTUI release tags; no sibling checkouts are
required.

This is the framework-seam gate: every package is built (debug) and the suites
that exercise SwiftTUI behaviour run — WebHostExample, mrkdwn's view/model/
journey suites, csvui's view-contract and journey suites, gallery, gifcat.
The examples' own domain-logic suites (gifeditor, sextant, git-viz,
terminal-workspace, mrkdwn compiler/links, csvui core) live in
Scripts/check_examples_focused_tests.sh, the app-logic lane.

Pass --release-builds to also build every package in release configuration
and run the release stack-safety harness. Release coverage is a tag-time
concern (the tag workflow passes it); the push lane builds debug only.

Set SWIFTTUI_CHECKOUT only when deliberately testing mrkdwn and csvui against a
local SwiftTUI checkout. Each package is copied to a disposable package root
whose SwiftTUI dependency points at that exact checkout; public manifests are
not modified.
Set SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH to reuse one sequential SwiftPM scratch
directory across the example package builds. Do not share that directory across
parallel check runs.
Set SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA to reuse an Xcode DerivedData path for
the macOS app build.
Set SWIFTTUI_EXAMPLES_LAYOUTS_TESTS=1 to run the layouts package's
LayoutsTests (85 behaviour tests). They are opt-in until their raster
expectations are repaired against the current framework (55 of 85 failed
against 0.9.9 on 2026-08-25; see the SKIP line the gate prints).

Every step runs under a silence watchdog: SWIFTTUI_EXAMPLES_STEP_TIMEOUT_SECONDS
(default 600) bounds build steps, SWIFTTUI_EXAMPLES_TEST_STEP_TIMEOUT_SECONDS
(default 300 on Linux, 600 on macOS) bounds test steps; 0 disables the
watchdog for local diagnosis.
SWIFTTUI_EXAMPLES_STEP_ABSOLUTE_TIMEOUT_SECONDS (default 4x the build bound)
backstops a step that livelocks while printing. Set SWIFTTUI_HANG_DIAGNOSTICS=1
(Linux) to capture gdb thread backtraces of the wedged process tree before it
is killed.
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
    --release-builds)
      release_builds=1
      ;;
    --linux-only)
      suite=linux
      ;;
    --macos-only|--mac-only)
      suite=macos
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

log_root=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-examples-gate.XXXXXX")

cleanup_runtime_tmpdir() {
  if [ -n "$runtime_tmpdir" ] && [ -d "$runtime_tmpdir" ]; then
    rm -rf -- "$runtime_tmpdir"
  fi
  rm -rf -- "$log_root"
}

trap cleanup_runtime_tmpdir EXIT
trap 'cleanup_runtime_tmpdir; exit 129' HUP
trap 'cleanup_runtime_tmpdir; exit 130' INT
trap 'cleanup_runtime_tmpdir; exit 143' TERM

ensure_runtime_tmpdir() {
  if [ -z "$runtime_tmpdir" ]; then
    runtime_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-examples.XXXXXX")
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

prepare_csvui_package() {
  if [ -z "$framework_root" ]; then
    return
  fi

  ensure_runtime_tmpdir
  localized_root="$runtime_tmpdir/csvui"
  mkdir -p "$localized_root"
  cp "$repo_root/csvui/Package.swift" \
    "$repo_root/csvui/Package.resolved" \
    "$repo_root/csvui/default-theme.toml" \
    "$localized_root/"
  cp -R "$repo_root/csvui/Sources" "$repo_root/csvui/Tests" "$localized_root/"
  python3 "$repo_root/csvui/Scripts/check_manifest_contract.py" \
    --localize-manifest \
    "$repo_root/csvui/Package.swift" \
    "$localized_root/Package.swift" \
    "$framework_root"
  csvui_package_path=$localized_root
}

. "$repo_root/Scripts/lib/step_watchdog.sh"
. "$repo_root/Scripts/lib/example_suites.sh"
validate_timeout_configuration

require_command swiftly
if run_linux_suite || run_macos_suite; then
  require_command python3
fi
if run_macos_suite; then
  require_command xcodebuild
fi
if [ -n "$framework_root" ]; then
  require_checkout "$framework_root" "swift-tui"
fi
if run_linux_suite || run_macos_suite; then
  ensure_runtime_tmpdir
  if [ -n "$framework_root" ]; then
    prepare_mrkdwn_package
    prepare_csvui_package
  fi
fi

run_swift() {
  if should_use_swiftpm_scratch "$@"; then
    swiftly run swift "$@" --scratch-path "$swiftpm_scratch"
  else
    swiftly run swift "$@"
  fi
}

# Proves a `swift test --filter`/`--skip` selection is non-empty before running
# it. `swift test --filter` matching nothing exits 0, so an unproven filter is
# a silent false green.
require_selected_tests() {
  package_path=$1
  label=$2
  shift 2
  if ! run_swift test list --package-path "$package_path" "$@" | grep -q .; then
    >&2 echo "No tests selected for $label in $package_path (swift test list $*); refusing to report a green run."
    return 1
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

# mrkdwn's framework-exercising suites (Scripts/lib/example_suites.sh).
# Everything else in MrkdwnTests is the app's own logic and runs in the
# app-logic lane (check_examples_focused_tests.sh) through the complementary
# `--skip` of the same regex, so the two lanes partition the package.
# Three invocations (see the note on mrkdwn_*_suites in example_suites.sh):
# the manifest contract rides on the first.
run_mrkdwn_lease_perf_tests() {
  run_mrkdwn_manifest_contract || return 1
  require_selected_tests "$mrkdwn_package_path" "mrkdwn lease + performance suites" \
    --filter "$mrkdwn_lease_perf_suites" || return 1
  run_swift test --package-path "$mrkdwn_package_path" --filter "$mrkdwn_lease_perf_suites"
}

run_mrkdwn_journey_tests() {
  require_selected_tests "$mrkdwn_package_path" "mrkdwn PTY journeys" \
    --filter "$mrkdwn_journey_suites" || return 1
  (
    MRKDWN_REAL_PTY_TESTS=1
    export MRKDWN_REAL_PTY_TESTS
    run_swift test --package-path "$mrkdwn_package_path" --filter "$mrkdwn_journey_suites"
  )
}

run_mrkdwn_view_tests() {
  require_selected_tests "$mrkdwn_package_path" "mrkdwn view suites" \
    --filter "$mrkdwn_view_suites" || return 1
  run_swift test --package-path "$mrkdwn_package_path" --filter "$mrkdwn_view_suites"
}

run_csvui_manifest_contract() {
  ensure_runtime_tmpdir
  dump_file="$runtime_tmpdir/csvui-dump-package.json"
  status=0
  if ! swiftly run swift package \
    --package-path "$csvui_package_path" \
    dump-package >"$dump_file"; then
    status=1
  elif [ -n "$framework_root" ]; then
    if ! python3 "$repo_root/csvui/Scripts/check_manifest_contract.py" \
      --overlay "$framework_root" "$dump_file" "$csvui_package_path"; then
      status=1
    fi
  elif ! python3 "$repo_root/csvui/Scripts/check_manifest_contract.py" \
    "$dump_file" "$csvui_package_path"; then
    status=1
  fi
  rm -f "$dump_file"
  return "$status"
}

# csvui's framework-exercising suites (Scripts/lib/example_suites.sh): the
# view contracts and the real-terminal journeys. The CSV core runs in the
# app-logic lane via the complementary `--skip`.
run_csvui_tests() {
  run_csvui_manifest_contract || return 1
  # The serialized PTY journeys must not share the test process with the
  # CPU-bound unit suites: a synchronous test body holds its cooperative
  # executor worker for its whole run, and on narrow CI runners (2 vCPUs,
  # pool width 2) the unit suites occupy every worker for tens of seconds,
  # so the journeys' PTY reader never gets scheduled and waits time out as
  # "wrote 0 bytes to the PTY" while the csvui process is healthy. Run the
  # view contracts first (the journeys self-skip while CSVUI_REAL_PTY_TESTS
  # is unset), then run the journeys in an invocation of their own.
  require_selected_tests "$csvui_package_path" "csvui view contracts" \
    --filter CSVUITests.CSVViewContractTests || return 1
  run_swift test --package-path "$csvui_package_path" \
    --filter CSVUITests.CSVViewContractTests || return 1
  (
    CSVUI_REAL_PTY_TESTS=1
    export CSVUI_REAL_PTY_TESTS
    # `swift test --filter` matches nothing silently; prove the journey
    # suite is still selectable before trusting a green run.
    run_swift test list --package-path "$csvui_package_path" \
      --filter CSVUIRealTerminalJourneyTests \
      | grep -q CSVUIRealTerminalJourneyTests || exit 1
    run_swift test --package-path "$csvui_package_path" \
      --filter CSVUIRealTerminalJourneyTests
  )
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

# Runs one gate step under the silence watchdog. The step's output streams
# through to the console AND to a per-step log the hang dump can reference.
# A TIMEOUT is recorded like a failure and the gate moves on — the example
# packages are independent, so the steps after a parked one still carry a
# verdict worth having — but a second TIMEOUT aborts: two parked steps mean
# the environment itself is wedged and the rest would only burn minutes.
timeout_count=0

run_step() {
  title=$1
  workdir=$2
  shift 2
  step_index=$((step_index + 1))
  log_file=$log_root/step-$step_index.log
  status_file=$log_root/step-$step_index.status
  timeout_file=$log_root/step-$step_index.timeout

  echo ""
  echo "==> $title"

  if (
    cd "$workdir" &&
    run_logged_command "$log_file" "$status_file" "$timeout_file" "$@"
  ); then
    echo "PASS: $title"
    rm -f "$log_file" "$status_file" "$timeout_file"
    return 0
  fi

  exit_code=$(read_step_exit_code "$status_file")
  if [ -f "$timeout_file" ]; then
    detail=$(cat "$timeout_file")
    timeout_count=$((timeout_count + 1))
    >&2 echo "TIMEOUT: $title ($detail)"
    add_failure "$title (TIMEOUT: $detail)"
    >&2 echo ""
    >&2 echo "Last 40 lines of the step log:"
    tail -n 40 "$log_file" >&2 || true
    >&2 echo ""
    rm -f "$log_file" "$status_file" "$timeout_file"
    if [ "$timeout_count" -ge 2 ]; then
      >&2 echo "Aborting after a second timeout: the environment is wedged, not one step."
      print_failures
      exit 1
    fi
    >&2 echo "Continuing with the remaining steps (the gate is already red)."
    return 0
  fi

  >&2 echo "FAIL: $title (exit $exit_code)"
  add_failure "$title"
  rm -f "$log_file" "$status_file" "$timeout_file"
}

# A test step: same as run_step with the (shorter) test silence bound.
run_test_step() {
  step_timeout_seconds=$test_step_timeout_seconds
  run_step "$@"
  step_timeout_seconds=$build_step_timeout_seconds
}

skip_step() {
  title=$1
  reason=$2

  echo ""
  echo "==> $title"
  echo "SKIP: $title ($reason)"
}

print_section() {
  echo ""
  echo "### $1"
}

print_failures() {
  if [ -z "$failures" ]; then
    return 0
  fi
  >&2 echo "Example build failures:"
  OLD_IFS=$IFS
  IFS='
'
  for failure in $failures; do
    >&2 echo "  - $failure"
  done
  IFS=$OLD_IFS
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

run_layouts_tests_or_skip() {
  if [ "${SWIFTTUI_EXAMPLES_LAYOUTS_TESTS:-0}" = "1" ]; then
    run_test_step \
      "Test layouts" \
      "$repo_root" \
      run_swift test --package-path layouts
  else
    skip_step \
      "Test layouts" \
      "opt-in via SWIFTTUI_EXAMPLES_LAYOUTS_TESTS=1: 55 of 85 LayoutsTests fail against 0.9.9 — raster expectations predate the inset-border default; repair them, then make this step unconditional"
  fi
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
      "argparse" \
      "sextant" \
      "gallery" \
      "gifcat" \
      "gifeditor" \
      "git-viz" \
      "terminal-workspace" \
      "layouts" \
      "SwiftUIExample/TerminalApp" \
      "WebHostExample"; do
      run_step \
        "Clean $package_path" \
        "$repo_root" \
        run_swift package clean --package-path "$package_path"
    done

    run_step \
      "Clean mrkdwn" \
      "$repo_root" \
      run_swift package clean --package-path "$mrkdwn_package_path"

    run_step \
      "Clean csvui" \
      "$repo_root" \
      run_swift package clean --package-path "$csvui_package_path"
  fi

  print_section "Linux build-only coverage"

  for package_path in \
    "minimal" \
    "equatable-demo" \
    "argparse" \
    "sextant" \
    "gifcat" \
    "gifeditor" \
    "git-viz" \
    "terminal-workspace"; do
    run_step \
      "Build $package_path" \
      "$repo_root" \
      run_swift build --package-path "$package_path"

    if [ "$release_builds" -eq 1 ]; then
      run_step \
        "Build $package_path (release)" \
        "$repo_root" \
        run_swift build -c release --package-path "$package_path"
    fi
  done

  run_step \
    "Build mrkdwn" \
    "$repo_root" \
    run_swift build --package-path "$mrkdwn_package_path"

  if [ "$release_builds" -eq 1 ]; then
    run_step \
      "Build mrkdwn (release)" \
      "$repo_root" \
      run_swift build -c release --package-path "$mrkdwn_package_path"
  fi

  run_step \
    "Build csvui" \
    "$repo_root" \
    run_swift build --package-path "$csvui_package_path"

  if [ "$release_builds" -eq 1 ]; then
    run_step \
      "Build csvui (release)" \
      "$repo_root" \
      run_swift build -c release --package-path "$csvui_package_path"
  fi

  run_step \
    "Build gallery" \
    "$repo_root" \
    run_swift build --package-path gallery

  if [ "$release_builds" -eq 1 ]; then
    run_step \
      "Build gallery (release)" \
      "$repo_root" \
      run_swift build -c release --package-path gallery
  fi

  run_test_step \
    "Stack safety gallery (debug)" \
    "$repo_root" \
    python3 Scripts/stack_safety_harness.py \
      --binary "$(swiftpm_binary_path gallery debug gallery-demo)" \
      --count 20

  if [ "$release_builds" -eq 1 ]; then
    run_test_step \
      "Stack safety gallery (release)" \
      "$repo_root" \
      python3 Scripts/stack_safety_harness.py \
        --binary "$(swiftpm_binary_path gallery release gallery-demo)" \
        --count 20
  fi

  run_step \
    "Build layouts" \
    "$repo_root" \
    run_swift build --package-path layouts

  if [ "$release_builds" -eq 1 ]; then
    run_step \
      "Build layouts (release)" \
      "$repo_root" \
      run_swift build -c release --package-path layouts
  fi

  run_step \
    "Build SwiftUIExample/TerminalApp" \
    "$repo_root" \
    run_swift build --package-path SwiftUIExample/TerminalApp

  run_step \
    "Build WebHostExample" \
    "$repo_root" \
    run_swift build --package-path WebHostExample

  print_section "Linux framework-seam tests"

  run_test_step \
    "Test WebHostExample" \
    "$repo_root" \
    run_swift test --package-path WebHostExample

  run_test_step \
    "Test mrkdwn (terminal lease + performance envelope)" \
    "$repo_root" \
    run_mrkdwn_lease_perf_tests

  run_test_step \
    "Test mrkdwn (PTY journeys)" \
    "$repo_root" \
    run_mrkdwn_journey_tests

  run_test_step \
    "Test csvui (view contracts + PTY journeys)" \
    "$repo_root" \
    run_csvui_tests

  # The gallery exercises the full app shell (lazy-tab capture-host seam,
  # toolbar strip, command palette). Its test suite is the only coverage of
  # seam-hosted interactivity end to end; build-only checks cannot catch a
  # stranded action handler. The default suite is deterministic
  # (GALLERY_RUNTIME_TESTS-gated PTY/timing tests stay opt-in: that set has
  # no green history on Linux CI; flip it on once the silence watchdog has
  # been seen to bound a real hang there).
  run_test_step \
    "Test gallery" \
    "$repo_root" \
    run_swift test --package-path gallery

  run_test_step \
    "Test gifcat" \
    "$repo_root" \
    run_swift test --package-path gifcat

  run_layouts_tests_or_skip

  # Last on purpose: this is the invocation that parks at the 0.9.11 pin
  # (example_suites.sh). It stays on the hot path because it is real
  # framework-vs-app signal; the watchdog bounds what a park costs, and every
  # other step has already delivered its verdict by the time it runs.
  run_test_step \
    "Test mrkdwn (view contracts + viewer model)" \
    "$repo_root" \
    run_mrkdwn_view_tests
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

    run_step \
      "Clean mrkdwn" \
      "$repo_root" \
      run_swift package clean --package-path "$mrkdwn_package_path"

    run_step \
      "Clean csvui" \
      "$repo_root" \
      run_swift package clean --package-path "$csvui_package_path"
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
    "Build mrkdwn" \
    "$repo_root" \
    run_swift build --package-path "$mrkdwn_package_path"

  if [ "$release_builds" -eq 1 ]; then
    run_step \
      "Build mrkdwn (release)" \
      "$repo_root" \
      run_swift build -c release --package-path "$mrkdwn_package_path"
  fi

  run_step \
    "Build csvui" \
    "$repo_root" \
    run_swift build --package-path "$csvui_package_path"

  if [ "$release_builds" -eq 1 ]; then
    run_step \
      "Build csvui (release)" \
      "$repo_root" \
      run_swift build -c release --package-path "$csvui_package_path"
  fi

  run_test_step \
    "Test mrkdwn (terminal lease + performance envelope)" \
    "$repo_root" \
    run_mrkdwn_lease_perf_tests

  run_test_step \
    "Test mrkdwn (PTY journeys)" \
    "$repo_root" \
    run_mrkdwn_journey_tests

  run_test_step \
    "Test csvui (view contracts + PTY journeys)" \
    "$repo_root" \
    run_csvui_tests

  run_test_step \
    "Test mrkdwn (view contracts + viewer model)" \
    "$repo_root" \
    run_mrkdwn_view_tests

  run_step \
    "Build SwiftUIExample macOS app" \
    "$repo_root" \
    run_xcodebuild_swiftui_example

  # The gallery suite is the only end-to-end coverage of seam-hosted
  # interactivity, and it has trapped on macOS (signal 5 in the org native
  # gate) while every remote CI check stayed green because this suite was
  # build-only. Run it when macOS is the selected suite; a combined run
  # (suite=all) already covers it once in the roster section above.
  if [ "$suite" = "macos" ]; then
    print_section "macOS framework-seam tests"

    run_test_step \
      "Test gallery" \
      "$repo_root" \
      run_swift test --package-path gallery
  fi
}

run_step \
  "Self-test step watchdog" \
  "$repo_root" \
  sh Scripts/check_step_watchdog.sh

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


echo ""
if [ -z "$failures" ]; then
  echo "All example builds succeeded."
  exit 0
fi

print_failures

exit 1
