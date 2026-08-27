#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
workflow="$repo_root/.github/workflows/test.yml"
seam_workflow="$repo_root/.github/workflows/framework-head.yml"

fail() {
  printf '[check_examples_ci_workflow] %s\n' "$1" >&2
  exit 1
}

require_file() {
  path=$1
  if [[ ! -f "$path" ]]; then
    fail "missing required file: ${path#$repo_root/}"
  fi
}

require_text() {
  needle=$1
  path=$2
  if ! grep -Fq -- "$needle" "$path"; then
    fail "expected ${path#$repo_root/} to contain: $needle"
  fi
}

forbid_text() {
  needle=$1
  path=$2
  if grep -Fq -- "$needle" "$path"; then
    fail "forbidden stale text in ${path#$repo_root/}: $needle"
  fi
}

require_file "$workflow"
# Framework-seam lane: every push/PR, Linux, debug builds, watchdog with hang
# dumps, and a cap a hang can no longer reach.
require_text "Linux examples (framework seam)" "$workflow"
require_text "runs-on: ubuntu-24.04" "$workflow"
require_text "Scripts/check_examples_linux.sh --skip-clean" "$workflow"
require_text "SWIFTTUI_HANG_DIAGNOSTICS: \"1\"" "$workflow"
require_text "            gdb \\" "$workflow"
require_text "timeout-minutes: \${{ startsWith(github.ref, 'refs/tags/') && 60 || 30 }}" "$workflow"
# App-logic lane: per-package matrix, path-filtered on push/PR, everything
# on dispatch and tags.
require_text "App logic (\${{ matrix.package }})" "$workflow"
require_text "dorny/paths-filter@v3" "$workflow"
require_text "package: \${{ fromJSON(needs.changes.outputs.packages) }}" "$workflow"
require_text "Scripts/check_examples_focused_tests.sh --package" "$workflow"
# Tags run everything, add release builds, and are never cancelled.
require_text 'tags: ["*.*.*"]' "$workflow"
require_text "--release-builds" "$workflow"
# macOS: pushes to main, tags, and dispatch with the flag. Not pull requests —
# `push` and `pull_request` are distinct events, so the second clause does not
# match a PR. Re-enabled on push 2026-08-27 (was dispatch/tag only under plan
# 2026-08-25-001 Stage 1e/5); macOS is the primary user platform and a tag is a
# late place to first hear about it.
require_text "macOS examples" "$workflow"
require_text "runs-on: macos-26" "$workflow"
require_text "Scripts/check_examples_macos.sh --skip-clean" "$workflow"
require_text "(github.event_name == 'workflow_dispatch' && inputs.run_macos)" "$workflow"
require_text "|| (github.event_name == 'push')" "$workflow"
forbid_text "repository: SwiftTUI/swift-tui" "$workflow"
forbid_text "repository: SwiftTUI/swift-tui-web" "$workflow"
forbid_text 'secrets.SWIFTTUI_CI_TOKEN || github.token' "$workflow"
forbid_text "timeout-minutes: 75" "$workflow"
require_text "actions/cache@v6" "$workflow"
require_text "Scripts/install_swift_toolchain_ci.sh swift-tui-examples/.swift-version" "$workflow"
require_text "SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH" "$workflow"
require_text "SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA" "$workflow"
require_text "CODE_SIGNING_ALLOWED=NO" "$repo_root/Scripts/check_examples.sh"

# Framework HEAD seam: six-hourly, skip-if-unchanged, records its verdict.
require_file "$seam_workflow"
require_text "cron: \"23 */6 * * *\"" "$seam_workflow"
require_text "uses: ./.github/actions/lane-verdict-probe" "$seam_workflow"
require_text "siblings: SwiftTUI/swift-tui SwiftTUI/swift-tui-charts" "$seam_workflow"
require_text "if: needs.changes.outputs.changed == 'true'" "$seam_workflow"
require_text "uses: ./.github/actions/lane-verdict-record" "$seam_workflow"
require_text "Scripts/localize_siblings.sh" "$seam_workflow"
require_file "$repo_root/.github/actions/lane-verdict-probe/action.yml"
require_file "$repo_root/.github/actions/lane-verdict-record/action.yml"
require_file "$repo_root/Scripts/localize_siblings.sh"

# Both gate scripts must drive their steps through the shared watchdog and
# read the same suite partition, or the lanes drift apart silently.
for gate in check_examples.sh check_examples_focused_tests.sh; do
  require_text 'Scripts/lib/step_watchdog.sh' "$repo_root/Scripts/$gate"
  require_text 'Scripts/lib/example_suites.sh' "$repo_root/Scripts/$gate"
  require_text 'run_logged_command' "$repo_root/Scripts/$gate"
done

printf '[check_examples_ci_workflow] ok\n'
