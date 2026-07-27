#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: Scripts/package_release.sh <version>" >&2
  exit 64
fi

version=$1
case "$version" in
  *[!0-9.]* | .* | *.)
    echo "error: version must contain dot-separated decimal components" >&2
    exit 64
    ;;
esac

signing_identity=${CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  echo "error: set CODESIGN_IDENTITY to a Developer ID Application identity" >&2
  exit 78
fi

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
distribution_root=${SEXTANT_DISTRIBUTION_DIR:-"$repository_root/dist"}
work_root=$(mktemp -d "${TMPDIR:-/tmp}/sextant-release.XXXXXX")
trap 'rm -rf -- "$work_root"' EXIT

mkdir -p "$distribution_root"

for architecture in arm64 x86_64; do
  scratch_path="$work_root/build-$architecture"
  swiftly run swift build \
    --package-path "$repository_root" \
    --configuration release \
    --arch "$architecture" \
    --scratch-path "$scratch_path"
  binary_path=$(
    swiftly run swift build \
      --package-path "$repository_root" \
      --configuration release \
      --arch "$architecture" \
      --scratch-path "$scratch_path" \
      --show-bin-path
  )

  staging_root="$work_root/sextant-$version-macos-$architecture"
  mkdir -p "$staging_root"
  cp "$binary_path/sextant" "$staging_root/sextant"
  cp "$repository_root/LICENSE" "$staging_root/LICENSE"

  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$signing_identity" \
    "$staging_root/sextant"
  codesign --verify --strict --verbose=2 "$staging_root/sextant"

  archive="$distribution_root/sextant-$version-macos-$architecture.zip"
  ditto -c -k --keepParent "$staging_root" "$archive"

  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit \
      "$archive" \
      --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
      --wait \
      --timeout 30m
  fi
done

(
  cd "$distribution_root"
  shasum -a 256 \
    "sextant-$version-macos-arm64.zip" \
    "sextant-$version-macos-x86_64.zip" \
    > SHA256SUMS
)

echo "release archives: $distribution_root"
if [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "warning: archives are signed but not notarized; set NOTARY_KEYCHAIN_PROFILE" >&2
fi
