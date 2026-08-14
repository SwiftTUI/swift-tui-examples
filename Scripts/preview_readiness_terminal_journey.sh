#!/usr/bin/env bash
set -euo pipefail

examples_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec "$examples_root/SwiftUIExample/TerminalApp/Scripts/run_preview_readiness_terminal_journey.sh" "$@"
