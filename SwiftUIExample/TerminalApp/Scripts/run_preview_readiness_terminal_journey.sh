#!/usr/bin/env bash
set -euo pipefail

package_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

swiftly run swift build \
  --package-path "$package_root" \
  --product preview-readiness-terminal

bin_path=$(swiftly run swift build --package-path "$package_root" --show-bin-path)
SWIFTTUI_PREVIEW_READINESS_TERMINAL_JOURNEY=1 \
SWIFTTUI_PREVIEW_READINESS_TERMINAL_EXECUTABLE="$bin_path/preview-readiness-terminal" \
  swiftly run swift test \
    --package-path "$package_root" \
    --filter PreviewReadinessRealTerminalJourneyTests
