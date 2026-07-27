#!/usr/bin/env bash
#
# Emits docs/KEYBINDINGS.md from KeyBindingCatalog.
#
# `KeyBindingCatalog.swift` and `KeyBindingCatalogDocument.swift` import
# nothing, which is what lets this compile them on their own instead of
# building — and then somehow driving — a terminal application. The two
# files plus a one-line entry point are a complete program.
#
#   Scripts/generate-keybindings-doc.sh              # rewrite docs/KEYBINDINGS.md
#   Scripts/generate-keybindings-doc.sh -            # print to stdout
#   Scripts/generate-keybindings-doc.sh path/to.md   # write somewhere else
#
# `KeyBindingDocumentTests` fails when the checked-in file and this
# script's output disagree, so running it is the fix for that failure and
# the only supported way to change the doc.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-$root/docs/KEYBINDINGS.md}"
swiftc_bin="${SWIFTC:-swiftc}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'print(KeyBindingCatalog.markdownDocument, terminator: "")\n' >"$work/main.swift"

"$swiftc_bin" \
  -swift-version 6 \
  -O \
  "$root/Sources/GIFEditorUI/KeyBindingCatalog.swift" \
  "$root/Sources/GIFEditorUI/KeyBindingCatalogDocument.swift" \
  "$work/main.swift" \
  -o "$work/generate-keybindings-doc"

if [ "$destination" = "-" ]; then
  "$work/generate-keybindings-doc"
else
  "$work/generate-keybindings-doc" >"$destination"
  echo "Wrote $destination"
fi
