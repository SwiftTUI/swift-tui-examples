#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/../.." && pwd)"
output="$package_dir/Sources/MrkdwnMermaid/Generated/UnicodeWidthData.swift"
temporary="$(mktemp "${TMPDIR:-/tmp}/mrkdwn-mermaid-width.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

cargo run \
  --locked \
  --release \
  --quiet \
  --manifest-path "$script_dir/width-oracle/Cargo.toml" \
  | python3 "$script_dir/generate_unicode_width.py" "$temporary"

if [[ "${1:-}" == "--check" ]]; then
  diff -u "$output" "$temporary"
else
  mkdir -p "$(dirname "$output")"
  cp "$temporary" "$output"
fi
