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

# Why the SDK is passed explicitly on macOS.
#
# `swiftc` on `PATH` is a shim — Apple's `/usr/bin/swiftc`, or swiftly's —
# and it reaches the real compiler through `xcrun`, which hands the driver
# an SDK. A compiler named *directly*, which is exactly what `SWIFTC=` is
# for and what a `swiftly`-located toolchain looks like
# (`~/Library/Developer/Toolchains/swift-*.xctoolchain/usr/bin/swiftc`),
# gets no such treatment: the compile succeeds and the link fails with
#
#   ld: library 'System' not found
#
# because the linker has no sysroot. Supplying `-sdk` is the whole fix, it
# is what the shim would have done, and passing it to the shim as well is
# a no-op — so there is one code path rather than a shim/toolchain fork.
#
# This repo's convention is `swiftly run swift …` for packages, so a
# script that only works under one spelling of the toolchain is a trap;
# both spellings work here.
sdk_flags=()
if [ "$(uname -s)" = "Darwin" ]; then
  if sdk_path="$(xcrun --show-sdk-path 2>/dev/null)" && [ -n "$sdk_path" ]; then
    sdk_flags=(-sdk "$sdk_path")
  fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'print(KeyBindingCatalog.markdownDocument, terminator: "")\n' >"$work/main.swift"

"$swiftc_bin" \
  -swift-version 6 \
  -O \
  "${sdk_flags[@]}" \
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
