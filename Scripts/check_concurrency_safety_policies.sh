#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

matches=$(
  rg -n \
    --glob '*.swift' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --glob '!**/.build-linux/**' \
    --regexp '@unchecked Sendable' \
    --regexp 'nonisolated\(unsafe\)' \
    --regexp '@safe\b' \
    . || true
)

if [ -n "$matches" ]; then
  >&2 echo "Structured concurrency and memory-safety escape hatches are forbidden in checked-in Swift sources."
  >&2 echo "Replace @unchecked Sendable, nonisolated(unsafe), or @safe with actor isolation, Sendable-safe storage, Synchronization primitives, or explicit unsafe expressions inside reviewed code."
  >&2 echo ""
  >&2 echo "$matches"
  exit 1
fi
