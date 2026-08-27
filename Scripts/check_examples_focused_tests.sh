#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
framework_root=${SWIFTTUI_CHECKOUT:-}
swiftpm_scratch=${SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH:-}
runtime_tmpdir=
mrkdwn_package_path="$repo_root/mrkdwn"
csvui_package_path="$repo_root/csvui"
skip_bun_install=0
failures=""
selected_packages=""
step_index=0
timeout_count=0

# Every app-logic package, in the order the lane runs them when no --package
# is given. The CI matrix runs one package per job (see
# .github/workflows/test.yml `app-logic`); locally the default is all six.
all_packages="gifeditor sextant git-viz terminal-workspace mrkdwn csvui"

# Silence watchdog, same library and semantics as check_examples.sh. One
# bound for these steps: each is a `swift test` whose compile phase streams
# progress, so a quiet 300 s means a parked test, not a slow build.
case "$(uname -s)" in
  Darwin) default_test_step_timeout_seconds=600 ;;
  *) default_test_step_timeout_seconds=300 ;;
esac
step_timeout_seconds=${SWIFTTUI_EXAMPLES_TEST_STEP_TIMEOUT_SECONDS:-$default_test_step_timeout_seconds}
step_timeout_kill_grace_seconds=${SWIFTTUI_EXAMPLES_TIMEOUT_KILL_GRACE_SECONDS:-10}
step_absolute_timeout_seconds=${SWIFTTUI_EXAMPLES_STEP_ABSOLUTE_TIMEOUT_SECONDS:-$((step_timeout_seconds * 4))}
step_output_probe_ticks=${SWIFTTUI_EXAMPLES_STEP_OUTPUT_PROBE_TICKS:-25}
# Idle windows the watchdog forgives while the step's process tree is still
# consuming CPU. Silence alone does not mean parked: `swift test` writes to a
# pipe, so libc block-buffers it and a healthy binary is quiet until its buffer
# fills — measured at 274 s on a CI runner. A wedge consumes no CPU, so it
# still dies at the first idle bound; a quiet worker gets up to this many more
# windows before the gate stops believing it.
step_busy_extensions=${SWIFTTUI_EXAMPLES_STEP_BUSY_EXTENSIONS:-3}

usage() {
  cat <<'EOF'
Usage: Scripts/check_examples_focused_tests.sh [--package <name>]... [--skip-bun-install]

The app-logic lane: runs the example packages' own domain-logic test suites —
gifeditor (GIF/LZW/quantizer/project), sextant (filesystem, search, preview),
git-viz, terminal-workspace, mrkdwn (compiler, links, theme, watcher), csvui
(document core, model, lifecycle). These are real tests of the apps, not of
the framework, so they run when their package changes and at tags rather than
on every push; the framework-exercising suites run on every push in the
framework-seam gate (Scripts/check_examples.sh).

  --package <name>   Run one package (repeatable). Default: all six.

Set SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH to reuse one sequential SwiftPM scratch
directory across the example package tests. Do not share that directory across
parallel checks.
When SWIFTTUI_CHECKOUT is set, mrkdwn and csvui run from disposable package
roots whose SwiftTUI dependency points at that exact checkout; public manifests
are not modified.
Every step runs under the silence watchdog (SWIFTTUI_EXAMPLES_TEST_STEP_TIMEOUT_SECONDS,
default 300 on Linux and 600 on macOS; 0 disables it).
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-bun-install)
      skip_bun_install=1
      shift
      ;;
    --package)
      if [ "$#" -lt 2 ]; then
        >&2 echo "--package needs a value"
        exit 1
      fi
      case " $all_packages " in
        *" $2 "*) ;;
        *)
          >&2 echo "Unknown app-logic package: $2 (expected one of: $all_packages)"
          exit 1
          ;;
      esac
      selected_packages="$selected_packages $2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      >&2 echo "Unknown argument: $1"
      >&2 echo ""
      usage
      exit 1
      ;;
  esac
done

if [ -z "$selected_packages" ]; then
  selected_packages=$all_packages
fi

package_selected() {
  case " $selected_packages " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
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

log_root=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-examples-focused-gate.XXXXXX")

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
require_command python3
ensure_runtime_tmpdir
if [ -n "$framework_root" ]; then
  require_checkout "$framework_root" "swift-tui"
  if package_selected mrkdwn; then
    prepare_mrkdwn_package
  fi
  if package_selected csvui; then
    prepare_csvui_package
  fi
fi

# Command prefix that line-buffers a child's stdout/stderr, or empty where the
# platform has no way to ask.
#
# `swift test` writes to a pipe, so libc block-buffers it: the 2026-08-26
# gallery step delivered 453 test lines in 14 bursts, and a burst gap of 274 s
# is indistinguishable from a stall to anyone reading the log. The watchdog no
# longer kills on that (it checks CPU too), but the log is still unreadable in
# real time, and "which test was running when it stopped" is the first question
# anyone asks. `stdbuf` fixes it at the source.
#
# Verified in the gate container against a real Swift binary: 120 printed lines
# arrived in 2 buffer flushes without it and spread across the whole run with
# it, and LD_PRELOAD/_STDBUF_O reach the grandchild that `swift test` spawns.
# Linux only, deliberately. That is where this was verified and where the
# runners are known. GNU stdbuf works by preloading libstdbuf, which on macOS
# means DYLD_INSERT_LIBRARIES — stripped by SIP for protected binaries, so it
# would be a silent no-op at best and a per-process loader warning at worst,
# and a stock macOS runner has no stdbuf at all. The macOS lanes keep the wider
# idle bound instead.
if [ "$(uname -s)" = "Linux" ] && command -v stdbuf >/dev/null 2>&1; then
  line_buffered_prefix="stdbuf -oL -eL"
else
  line_buffered_prefix=""
fi

run_swift() {
  # Only for `test`: builds already stream progress, and this puts an
  # LD_PRELOAD on every process in the subtree.
  swift_prefix=""
  if [ "${1:-}" = "test" ]; then
    swift_prefix=$line_buffered_prefix
  fi
  if [ -n "$swiftpm_scratch" ]; then
    $swift_prefix swiftly run swift "$@" --scratch-path "$swiftpm_scratch"
  else
    $swift_prefix swiftly run swift "$@"
  fi
}

# `swift test --skip` that skips everything exits 0; prove the app-logic
# selection is non-empty before trusting a green run.
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

# mrkdwn app logic = everything the framework-seam gate does not run (the
# complementary --skip of Scripts/lib/example_suites.sh's regex).
run_mrkdwn_tests() {
  run_mrkdwn_manifest_contract || return 1
  require_selected_tests "$mrkdwn_package_path" "mrkdwn app-logic suites" \
    --skip "$mrkdwn_framework_suites" || return 1
  run_swift test --package-path "$mrkdwn_package_path" --skip "$mrkdwn_framework_suites"
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

# csvui core = everything but the view contracts and PTY journeys.
run_csvui_tests() {
  run_csvui_manifest_contract || return 1
  require_selected_tests "$csvui_package_path" "csvui core suites" \
    --skip "$csvui_framework_suites" || return 1
  run_swift test --package-path "$csvui_package_path" --skip "$csvui_framework_suites"
}

print_failures() {
  if [ -z "$failures" ]; then
    return 0
  fi
  >&2 echo "App-logic test failures:"
  OLD_IFS=$IFS
  IFS='
'
  for failure in $failures; do
    >&2 echo "  - $failure"
  done
  IFS=$OLD_IFS
}

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

echo ""
echo "### App-logic tests ($selected_packages)"

for package_path in gifeditor sextant git-viz terminal-workspace; do
  if package_selected "$package_path"; then
    run_step \
      "Test $package_path" \
      "$repo_root" \
      run_swift test --package-path "$package_path"
  fi
done

if package_selected mrkdwn; then
  run_step \
    "Test mrkdwn (app-logic suites)" \
    "$repo_root" \
    run_mrkdwn_tests
fi

if package_selected csvui; then
  run_step \
    "Test csvui (core suites)" \
    "$repo_root" \
    run_csvui_tests
fi

echo ""
if [ -z "$failures" ]; then
  echo "All app-logic tests succeeded."
  exit 0
fi

print_failures

exit 1
