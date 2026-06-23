#!/usr/bin/env bash
#
# Wrap a raw device screenshot (iOS simctl / Android adb / terminal) into the
# swifttui.sh/showcase "device composite": a framed, rounded, shadowed screen
# bleeding off the bottom of a 1000x1000 warm-gradient canvas — matching the
# band tiles on the Showcase page.
#
# Usage:
#   Scripts/showcase-frame.sh <raw.png> <out.png> [scaleWidth] [yOffset] [topColor] [botColor]
#
# Example (Android Logo Breaker capture -> band tile):
#   Scripts/showcase-frame.sh /tmp/host-android-raw.png public/showcase/host-android.png \
#     860 46 '#5a2f63' '#c2562f'
#
# Requires ImageMagick 7 (`magick`). See docs/plans/2026-06-23-001-showcase-media-capture-plan.md
# in the swift-tui-org coordination root for the full capture playbook.
set -euo pipefail

IN="${1:?usage: showcase-frame.sh <raw.png> <out.png> [scaleW] [yOff] [top] [bot]}"
OUT="${2:?missing output path}"
SCALE="${3:-860}"; YOFF="${4:-46}"
TOP="${5:-#5a2f63}"; BOT="${6:-#c2562f}"
M="${MAGICK:-magick}"
command -v "$M" >/dev/null 2>&1 || { echo "ImageMagick 'magick' not found (set MAGICK=...)" >&2; exit 69; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
r=64; bez=14

"$M" "$IN" -resize "${SCALE}x" "$TMP/scr.png"
W=$("$M" identify -format %w "$TMP/scr.png"); H=$("$M" identify -format %h "$TMP/scr.png")

# round the screen corners
"$M" -size "${W}x${H}" xc:none -fill white \
  -draw "roundrectangle 0,0,$((W-1)),$((H-1)),$r,$r" "$TMP/mask.png"
"$M" "$TMP/scr.png" "$TMP/mask.png" -alpha set -compose DstIn -composite "$TMP/rounded.png"

# dark bezel behind the rounded screen
BW=$((W+2*bez)); BH=$((H+2*bez))
"$M" -size "${BW}x${BH}" xc:none -fill '#0a0a0c' \
  -draw "roundrectangle 0,0,$((BW-1)),$((BH-1)),$((r+bez)),$((r+bez))" "$TMP/bezel.png"
"$M" "$TMP/bezel.png" "$TMP/rounded.png" -gravity center -composite "$TMP/phone.png"

# soft drop shadow
"$M" "$TMP/phone.png" \( +clone -background black -shadow 55x26+0+16 \) \
  +swap -background none -layers merge +repage "$TMP/phoneshadow.png"

# warm gradient canvas + composite (phone bleeds off the bottom edge)
"$M" -size 1000x1000 gradient:"${TOP}-${BOT}" "$TMP/bg.png"
"$M" "$TMP/bg.png" "$TMP/phoneshadow.png" -gravity north -geometry "+0+${YOFF}" \
  -composite -extent 1000x1000 "$OUT"
echo "wrote $OUT"
