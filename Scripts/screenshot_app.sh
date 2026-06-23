#!/usr/bin/env bash
#
# Capture a screenshot of any terminal SwiftTUI example app running in kitty.app
# (generalises screenshot_gallery.sh to an arbitrary built binary + args).
#
# Usage:
#   Scripts/screenshot_app.sh <out.png> <binary> [args...]
#
# Environment:
#   SCREENSHOT_DELAY  Seconds to wait after kitty launches before capturing (default 3).
#   HOLD              If non-empty, wrap the binary so the window stays open after a
#                     non-interactive app (e.g. gitviz) exits, so it can be captured.
#   KITTY             kitty binary (default /opt/homebrew/bin/kitty).
#
# Requirements: kitty (Homebrew), macOS screencapture, osascript, and the driving
# terminal granted Screen Recording + Accessibility permissions.
set -euo pipefail

out="${1:?usage: screenshot_app.sh <out.png> <binary> [args...]}"; shift
bin="${1:?missing binary}"; shift || true
delay="${SCREENSHOT_DELAY:-3}"
kitty_bin="${KITTY:-/opt/homebrew/bin/kitty}"

[[ -x "$bin" ]]       || { echo "binary not executable: $bin" >&2; exit 69; }
[[ -x "$kitty_bin" ]] || { echo "kitty not found at $kitty_bin (override KITTY=...)" >&2; exit 69; }

common=(--override remember_window_size=no --override initial_window_width=1200 --override initial_window_height=720)
if [[ -n "${HOLD:-}" ]]; then
  # printf %q quotes each arg so the bash -c command line is safe; read holds the window.
  "$kitty_bin" "${common[@]}" -e bash -c "$(printf '%q ' "$bin" "$@"); read -r -t 600 _" >/dev/null 2>&1 &
else
  "$kitty_bin" "${common[@]}" -e "$bin" "$@" >/dev/null 2>&1 &
fi
kpid=$!
cleanup() { kill "$kpid" 2>/dev/null || true; wait "$kpid" 2>/dev/null || true; }
trap cleanup EXIT

sleep "$delay"

bounds=$(osascript <<'OSA'
tell application "System Events"
  tell process "kitty"
    if (count of windows) > 0 then
      set w to front window
      set p to position of w
      set s to size of w
      return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
    else
      return "0,0,0,0"
    end if
  end tell
end tell
OSA
)
IFS=',' read -r x y w h <<< "$bounds"
[[ "$w" == "0" || "$h" == "0" ]] && { echo "could not locate kitty window ($bounds)" >&2; exit 75; }

/usr/sbin/screencapture -x -R "${x},${y},${w},${h}" "$out"
echo "wrote $out (bounds $bounds)"
