#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/../.." && pwd)"
source_url="https://www.unicode.org/Public/15.1.0/ucd/extracted/DerivedBidiClass.txt"
source_sha256="b57884c59a3a5348d86faed39965bbddb4e4493d3c16c1ec378ec26bfb5821be"
output="$package_dir/Sources/MrkdwnMermaid/Generated/UnicodeBidiData.swift"
source_file="$(mktemp "${TMPDIR:-/tmp}/mrkdwn-mermaid-bidi-source.XXXXXX")"
generated_file="$(mktemp "${TMPDIR:-/tmp}/mrkdwn-mermaid-bidi-generated.XXXXXX")"
trap 'rm -f "$source_file" "$generated_file"' EXIT

curl --fail --location --silent --show-error "$source_url" --output "$source_file"
actual_sha256="$(shasum -a 256 "$source_file" | awk '{print $1}')"
if [[ "$actual_sha256" != "$source_sha256" ]]; then
  printf '[generate_unicode_bidi] source checksum mismatch: expected %s, got %s\n' \
    "$source_sha256" "$actual_sha256" >&2
  exit 1
fi

python3 "$script_dir/generate_unicode_bidi.py" "$source_file" "$generated_file"

if [[ "${1:-}" == "--check" ]]; then
  diff -u "$output" "$generated_file"
else
  cp "$generated_file" "$output"
fi
