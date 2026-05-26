#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
workflow="$repo_root/.github/workflows/test.yml"

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

require_file "$workflow"
require_text "Linux examples" "$workflow"
require_text "runs-on: ubuntu-24.04" "$workflow"
require_text "Scripts/check_examples_linux.sh --skip-clean" "$workflow"
require_text "macOS examples" "$workflow"
require_text "runs-on: macos-26" "$workflow"
require_text "Scripts/check_examples_macos.sh --skip-clean" "$workflow"
require_text "Web examples" "$workflow"
require_text "Scripts/check_examples_web.sh --skip-clean" "$workflow"
require_text "repository: SwiftTUI/swift-tui" "$workflow"
require_text "repository: SwiftTUI/swift-tui-web" "$workflow"
require_text 'secrets.SWIFTTUI_CI_TOKEN || github.token' "$workflow"
require_text "actions/cache@v5" "$workflow"
require_text "SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH" "$workflow"
require_text "SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA" "$workflow"
require_text "swift sdk install" "$workflow"
require_text "swift-6.3.1-RELEASE_wasm.artifactbundle.tar.gz" "$workflow"
require_text "binaryen" "$workflow"
require_text "CODE_SIGNING_ALLOWED=NO" "$repo_root/Scripts/check_examples.sh"

printf '[check_examples_ci_workflow] ok\n'
