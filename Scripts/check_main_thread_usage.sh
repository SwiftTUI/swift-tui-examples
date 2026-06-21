#!/usr/bin/env sh

# Forbid bare `Thread.isMainThread` outside of justified call sites.
#
# `Thread.isMainThread` is not a portable proxy for main-actor isolation.
# If you genuinely need `Thread.isMainThread`, justify the call site with a
# `thread-ismain-ok:` comment on the same line or in the contiguous comment
# block immediately above it.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

files=$(
  rg -l --no-messages \
    --glob '*.swift' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --glob '!**/.build-linux/**' \
    'Thread\.isMainThread' \
    . 2>/dev/null || true
)

if [ -z "$files" ]; then
  exit 0
fi

violations=$(
  printf '%s\n' "$files" | while IFS= read -r file; do
    [ -n "$file" ] || continue
    awk -v file="$file" '
      {
        lines[NR] = $0
      }
      END {
        for (n = 1; n <= NR; n++) {
          line = lines[n]
          stripped = line
          sub(/\/\/.*$/, "", stripped)
          if (stripped !~ /Thread\.isMainThread/) continue

          ok = (line ~ /thread-ismain-ok:/)

          if (!ok) {
            for (i = n - 1; i >= 1; i--) {
              prev = lines[i]
              trimmed = prev
              sub(/^[ \t]+/, "", trimmed)
              if (trimmed != "" && trimmed !~ /^\/\//) break
              if (prev ~ /thread-ismain-ok:/) {
                ok = 1
                break
              }
            }
          }

          if (!ok) {
            printf "%s:%d: %s\n", file, n, line
          }
        }
      }
    ' "$file"
  done
)

if [ -n "$violations" ]; then
  >&2 echo "Bare Thread.isMainThread is forbidden because it is not a portable proxy for main-actor isolation."
  >&2 echo ""
  >&2 echo "If you genuinely need Thread.isMainThread, justify the call site with"
  >&2 echo "a 'thread-ismain-ok:' comment on the same line, or in the contiguous"
  >&2 echo "comment block immediately above it, explaining why thread identity"
  >&2 echo "is the right question."
  >&2 echo ""
  >&2 echo "Unjustified call sites:"
  >&2 printf '%s\n' "$violations"
  exit 1
fi
