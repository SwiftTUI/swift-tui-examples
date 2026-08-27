#!/usr/bin/env sh

set -eu

# Self-test for the examples gate's per-step watchdog (Scripts/lib/step_watchdog.sh).
#
# The watchdog bounds SILENCE, not total runtime: a lane running slowly under
# contention keeps printing and is left alone; a lane that parked prints nothing
# and is killed after the idle bound, with a hang dump first. A regression here
# does not fail loudly — it silently turns the next wedged journey back into a
# 30-minute cap with no evidence, which is exactly what the 2026-08-25 mrkdwn
# hang cost before this watchdog existed. So the behaviour is pinned here,
# driving the real `run_logged_command` with synthetic steps and sub-second
# bounds. The whole file runs in a few seconds on an idle machine.
#
# Ported from swift-tui's Scripts/check_step_watchdog.sh together with the
# library it exercises.

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-examples-watchdog-selftest.XXXXXX")
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

failures=0

fail() {
  >&2 echo "error: $1"
  failures=$((failures + 1))
}

# Drives one synthetic step through the real watchdog.
#
# Bounds are expressed in whole seconds because that is the watchdog's own unit.
# `probe_ticks=1` samples the log every 0.2 s so a 2 s idle bound still gets ten
# samples — the production default of 25 ticks (5 s) would be coarser than the
# whole test.
case_deadline_seconds=${SWIFTTUI_EXAMPLES_WATCHDOG_SELFTEST_DEADLINE_SECONDS:-40}

run_case() {
  case_name=$1
  idle_seconds=$2
  absolute_seconds=$3
  shift 3

  step_timeout_seconds=$idle_seconds
  step_timeout_kill_grace_seconds=1
  step_absolute_timeout_seconds=$absolute_seconds
  step_output_probe_ticks=1
  # Per-case override; `run_busy_case` raises it to exercise the extension.
  step_busy_extensions=${case_busy_extensions:-0}

  log_file=$work_dir/$case_name.log
  status_file=$work_dir/$case_name.status
  timeout_file=$work_dir/$case_name.timeout
  rm -f "$log_file" "$status_file" "$timeout_file"
  case_wedged=0

  # The case runs in the background behind this script's own deadline. A
  # watchdog bug that fails to kill its step makes `run_logged_command` block in
  # `wait` forever, and a self-test that hangs the gate is worse than the hang
  # it is guarding against — so a wedge has to be reported, not waited on.
  (
    set +e
    run_logged_command "$log_file" "$status_file" "$timeout_file" "$@"
    exit 0
  ) >/dev/null 2>&1 &
  case_pid=$!

  case_waited_ticks=0
  while kill -0 "$case_pid" 2>/dev/null; do
    sleep 0.2
    case_waited_ticks=$((case_waited_ticks + 1))
    if [ "$case_waited_ticks" -ge $((case_deadline_seconds * 5)) ]; then
      case_wedged=1
      kill_process_tree "$case_pid" KILL
      break
    fi
  done
  wait "$case_pid" 2>/dev/null || true

  case_exit=$(read_step_exit_code "$status_file")
  case_detail=""
  if [ -f "$timeout_file" ]; then
    case_detail=$(cat "$timeout_file")
  fi
}

# A step that runs well past the idle bound but never goes quiet for it.
# Emits every 0.4 s for ~4 s against a 2 s idle bound.
chatty_slow_step() {
  i=0
  while [ "$i" -lt 10 ]; do
    echo "progress $i"
    sleep 0.4
    i=$((i + 1))
  done
}

# A step that starts, then parks forever — the mrkdwn-journey shape. MUST die.
parks_after_output_step() {
  echo "starting"
  sleep 600
}

# A step that never emits anything at all. Also killed.
silent_step() {
  sleep 600
}

# A step that never finishes but keeps printing: silence cannot catch it, so
# only the absolute backstop can.
livelock_step() {
  while :; do
    echo "still going"
    sleep 0.2
  done
}

# A step that burns CPU without printing anything — the block-buffered writer
# shape. `swift test` writes to a pipe, so libc holds its output until a ~4 KB
# buffer fills; the 2026-08-26 gallery seam step delivered 453 test lines in 14
# bursts and the watchdog read the gap between two of them as a hang. Bounded by
# wall clock rather than iteration count so the case costs the same everywhere.
busy_silent_step() {
  busy_seconds=$1
  busy_end=$(($(date +%s) + busy_seconds))
  while [ "$(date +%s)" -lt "$busy_end" ]; do
    busy_i=0
    while [ "$busy_i" -lt 2000 ]; do
      busy_i=$((busy_i + 1))
    done
  done
}

# A step whose work is a grandchild process (swift-test -> xctest shape): the
# kill must reach the whole tree, not just the shell that spawned it. The
# grandchild's pid is recorded so the check below can ask about THAT process
# and nothing else — a `pgrep -f`/`pkill -f` on the command text would match
# (and kill) any unrelated process whose argv contains it, including a
# concurrent run of this very self-test.
parks_in_child_step() {
  echo "spawning"
  sh -c 'sleep 600 & printf "%s" "$!" >"$0"; wait' "$work_dir/grandchild.pid" &
  wait
}

. "$repo_root/Scripts/lib/step_watchdog.sh"

echo "1/9 a slow but talking step survives an idle bound it far exceeds"
run_case chatty_slow 2 0 chatty_slow_step
if [ "$case_exit" != "0" ]; then
  fail "a step that kept emitting output was killed (exit=$case_exit, detail='$case_detail'). \
The watchdog is measuring wall clock instead of silence."
fi

echo "2/9 a step that parks after emitting output is killed"
run_case parks_after_output 2 0 parks_after_output_step
if [ "$case_wedged" = "1" ]; then
  fail "the watchdog reported a timeout but never actually killed the step, so the \
runner blocked in wait. kill_process_tree is signalling the wrong pid."
fi
if [ "$case_exit" != "124" ]; then
  fail "a parked step was not killed (exit=$case_exit); a wedged gate would run to the workflow cap."
fi
case "$case_detail" in
*"no output"*) ;;
*) fail "parked step reported an unexpected timeout detail: '$case_detail'" ;;
esac

echo "3/9 a step that never emits anything is killed"
run_case silent 2 0 silent_step
if [ "$case_wedged" = "1" ]; then
  fail "a silent step outlived the watchdog's kill."
fi
if [ "$case_exit" != "124" ]; then
  fail "a silent step was not killed (exit=$case_exit)."
fi

echo "4/9 the absolute backstop kills a step that livelocks while printing"
run_case livelock 60 3 livelock_step
if [ "$case_wedged" = "1" ]; then
  fail "a livelocking step outlived the watchdog's kill."
fi
if [ "$case_exit" != "124" ]; then
  fail "a livelocking step outran the absolute backstop (exit=$case_exit)."
fi
case "$case_detail" in
*"absolute cap"*) ;;
*) fail "livelock step reported an unexpected timeout detail: '$case_detail'" ;;
esac

echo "5/9 a step parked inside a grandchild process is killed with its whole tree"
rm -f "$work_dir/grandchild.pid"
run_case parks_in_child 2 0 parks_in_child_step
if [ "$case_wedged" = "1" ]; then
  fail "a step parked in a grandchild process outlived the watchdog's kill; the tree kill missed a descendant."
fi
if [ "$case_exit" != "124" ]; then
  fail "a step parked in a grandchild process was not killed (exit=$case_exit)."
fi
grandchild_pid=$(cat "$work_dir/grandchild.pid" 2>/dev/null || true)
if [ -z "$grandchild_pid" ]; then
  fail "the parked grandchild never recorded its pid; the case did not exercise the tree kill."
elif kill -0 "$grandchild_pid" 2>/dev/null; then
  fail "the parked grandchild (pid $grandchild_pid) survived the tree kill."
  kill -KILL "$grandchild_pid" 2>/dev/null || true
fi

echo "6/9 a disabled watchdog (0) never kills anything"
run_case disabled 0 0 chatty_slow_step
if [ "$case_exit" != "0" ]; then
  fail "a step ran with the watchdog disabled but still failed (exit=$case_exit)."
fi

echo "7/9 a silent step that is still burning CPU survives the idle bound"
case_busy_extensions=3
run_case busy_silent_survives 2 0 busy_silent_step 5
case_busy_extensions=0
if [ "$case_wedged" = "1" ]; then
  fail "the busy-but-silent case never finished; the watchdog left it running."
fi
if [ "$case_exit" != "0" ]; then
  fail "a silent step that was consuming CPU throughout was killed (exit=$case_exit, \
detail='$case_detail'). Silence is not evidence: a block-buffered writer is quiet \
until its buffer fills, and killing it turns a healthy lane red with a hang dump \
that shows a working thread."
fi

echo "8/9 a silent, busy step still dies once its extensions run out"
case_busy_extensions=1
run_case busy_silent_exhausts 2 0 busy_silent_step 600
case_busy_extensions=0
if [ "$case_wedged" = "1" ]; then
  fail "a livelocking silent step outlived the watchdog's kill."
fi
if [ "$case_exit" != "124" ]; then
  fail "a silent step that burned CPU forever was never killed (exit=$case_exit); the \
busy extension is unbounded, so a real livelock would only die at the absolute cap."
fi
case "$case_detail" in
*"busy extensions"*) ;;
*) fail "exhausted-extension step reported an unexpected detail: '$case_detail'" ;;
esac

echo "9/9 a busy-extension budget does not save a parked step"
case_busy_extensions=3
run_case parked_with_budget 2 0 parks_after_output_step
case_busy_extensions=0
if [ "$case_wedged" = "1" ]; then
  fail "a parked step outlived the watchdog's kill when extensions were available."
fi
if [ "$case_exit" != "124" ]; then
  fail "a parked step survived because extensions were available (exit=$case_exit). The \
extension must require CPU to have advanced; a wedge consumes none."
fi
case "$case_detail" in
*"busy extensions"*)
  fail "a parked step was charged a busy extension: '$case_detail'. It consumed no CPU."
  ;;
*"no output"*) ;;
*) fail "parked step with budget reported an unexpected detail: '$case_detail'" ;;
esac

if [ "$failures" -ne 0 ]; then
  >&2 echo ""
  >&2 echo "Step-watchdog self-test FAILED with $failures problem(s)."
  exit 1
fi

echo "Step-watchdog self-test passed."
