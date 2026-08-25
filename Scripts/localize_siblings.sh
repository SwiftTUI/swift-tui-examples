#!/usr/bin/env bash
set -euo pipefail

# Framework HEAD seam (plan 2026-08-25-001 Stage 3e).
#
# Builds and tests this repository's examples against the `main` branches of
# swift-tui and swift-tui-charts instead of their released tags. This is the
# seam where a framework change first meets real consumer code, and the one
# place the identity-churn bug class historically surfaced (org survey F22).
# It used to run in the private coordination root, where it completed on 29%
# of pushes; here it runs on free minutes, on a schedule that skips itself
# when nothing landed.
#
# The committed manifests are never touched. The script copies the repository
# into a throwaway work directory, clones (or accepts) the two siblings, and
# rewrites the COPY's Package.swift files so every
#   .package(url: "https://github.com/SwiftTUI/swift-tui(.git)?", <requirement>)
#   .package(url: "https://github.com/SwiftTUI/swift-tui-charts(.git)?", <requirement>)
# becomes a local `path:` dependency. The charts clone's own swift-tui pin is
# localized the same way, so both siblings resolve to one swift-tui tree. The
# rewrite is verified afterwards: a sibling URL that survives in any copied
# manifest fails the run, because a rewrite that silently no-ops would build
# the released tag and call it a HEAD verdict (the failure mode the root's
# overlay verifier was written against).
#
# mrkdwn and csvui carry their own localization path (`SWIFTTUI_CHECKOUT` +
# `Scripts/check_manifest_contract.py --localize-manifest`) because their
# manifest contract is validated semantically; the gate script drives that
# when SWIFTTUI_CHECKOUT is exported, so this script only exports it.
#
# Usage:
#   Scripts/localize_siblings.sh --work-dir <dir> [--swift-tui <checkout>]
#       [--charts <checkout>] [--scratch <swiftpm-scratch>] [--no-check]
#       [-- <check_examples.sh arguments>]
#
# Without --swift-tui/--charts the siblings are cloned (depth 1, branch main)
# into <work-dir>. With them, existing checkouts are used as-is (local runs).
# The SwiftPM scratch is stamped with the two sibling revisions and purged
# when either changes: SwiftPM does not invalidate consumer objects whose
# mangled references name a type's previous module, so a scratch reused across
# framework module surgery links garbage (struct growth -> far SIGSEGV).

script_source="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
  script_path="$(realpath "$script_source")"
else
  script_path="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$script_source")"
fi
repo_root="$(cd "$(dirname "$script_path")/.." && pwd)"

log() {
  printf '[localize_siblings] %s\n' "$1"
}

fail() {
  printf '[localize_siblings] %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '3,40p' "$script_path" | sed 's/^# \{0,1\}//'
}

work_dir=""
swift_tui_checkout=""
charts_checkout=""
scratch_dir=""
run_check=1
check_arguments=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)
      [[ $# -ge 2 ]] || fail "--work-dir needs a value"
      work_dir=$2
      shift 2
      ;;
    --swift-tui)
      [[ $# -ge 2 ]] || fail "--swift-tui needs a value"
      swift_tui_checkout=$2
      shift 2
      ;;
    --charts)
      [[ $# -ge 2 ]] || fail "--charts needs a value"
      charts_checkout=$2
      shift 2
      ;;
    --scratch)
      [[ $# -ge 2 ]] || fail "--scratch needs a value"
      scratch_dir=$2
      shift 2
      ;;
    --no-check)
      run_check=0
      shift
      ;;
    --)
      shift
      check_arguments=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1 (see --help)"
      ;;
  esac
done

[[ -n "$work_dir" ]] || fail "--work-dir is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v git >/dev/null 2>&1 || fail "git is required"

mkdir -p "$work_dir"
work_dir="$(cd "$work_dir" && pwd)"
[[ "$work_dir" != "$repo_root" ]] || fail "--work-dir must not be the repository itself"
case "$work_dir" in
  "$repo_root"/*) fail "--work-dir must lie outside the repository (got $work_dir)" ;;
esac

clone_sibling() {
  slug=$1
  destination=$2
  if [[ -d "$destination/.git" ]]; then
    log "refreshing $slug main in $destination"
    git -C "$destination" fetch --depth 1 origin main
    git -C "$destination" checkout -q --detach FETCH_HEAD
  else
    rm -rf "$destination"
    log "cloning $slug main into $destination"
    git clone --quiet --depth 1 --branch main "https://github.com/SwiftTUI/$slug.git" "$destination"
  fi
}

if [[ -z "$swift_tui_checkout" ]]; then
  swift_tui_checkout="$work_dir/swift-tui"
  clone_sibling swift-tui "$swift_tui_checkout"
fi
if [[ -z "$charts_checkout" ]]; then
  charts_checkout="$work_dir/swift-tui-charts"
  clone_sibling swift-tui-charts "$charts_checkout"
fi
[[ -f "$swift_tui_checkout/Package.swift" ]] || fail "not a swift-tui checkout: $swift_tui_checkout"
[[ -f "$charts_checkout/Package.swift" ]] || fail "not a swift-tui-charts checkout: $charts_checkout"
swift_tui_checkout="$(cd "$swift_tui_checkout" && pwd)"
charts_checkout="$(cd "$charts_checkout" && pwd)"

revision_of() {
  git -C "$1" rev-parse HEAD 2>/dev/null || printf 'unversioned'
}
swift_tui_revision="$(revision_of "$swift_tui_checkout")"
charts_revision="$(revision_of "$charts_checkout")"
log "swift-tui        = $swift_tui_revision ($swift_tui_checkout)"
log "swift-tui-charts = $charts_revision ($charts_checkout)"

# The charts clone consumes swift-tui by tag; localize it in place when it is
# a clone this script owns, or in a copy when the caller lent us a checkout
# (never edit a developer's working tree).
if [[ "$charts_checkout" != "$work_dir/swift-tui-charts" ]]; then
  localized_charts="$work_dir/swift-tui-charts"
  rm -rf "$localized_charts"
  mkdir -p "$localized_charts"
  # Copy the package sources only; .build and .git stay behind.
  (cd "$charts_checkout" && tar --exclude=.build --exclude=.git -cf - .) | (cd "$localized_charts" && tar -xf -)
  charts_checkout="$localized_charts"
fi

# Throwaway copy of this repository. Everything the gate reads comes from the
# copy; the checked-in manifests are never modified.
examples_copy="$work_dir/swift-tui-examples"
log "copying the examples tree into $examples_copy"
rm -rf "$examples_copy"
mkdir -p "$examples_copy"
(cd "$repo_root" && tar --exclude=.build --exclude=.git --exclude=node_modules -cf - .) \
  | (cd "$examples_copy" && tar -xf -)

# Rewrite every `.package(url: <sibling>, <requirement>)` to a local path
# dependency. Requirement forms accepted: `exact:`, `from:`,
# `.upToNextMinor(from:)`, `.upToNextMajor(from:)`, on one line or spread
# across several (the csvui/mrkdwn/charts manifests use the multi-line form).
localize_manifest() {
  manifest=$1
  python3 - "$manifest" "$swift_tui_checkout" "$charts_checkout" <<'PY'
import pathlib
import re
import sys

manifest = pathlib.Path(sys.argv[1])
swift_tui = sys.argv[2]
charts = sys.argv[3]
text = manifest.read_text(encoding="utf-8")

requirement = r'(?:exact:\s*"[^"]+"|from:\s*"[^"]+"|\.upToNext(?:Minor|Major)\(from:\s*"[^"]+"\))'


def swift_string(value):
    # A Swift string literal for an arbitrary path (backslashes and quotes
    # escaped); paths never contain newlines here.
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def localize(slug, path):
    global text
    pattern = re.compile(
        r'\.package\(\s*url:\s*"https://github\.com/SwiftTUI/'
        + re.escape(slug)
        + r'(?:\.git)?"\s*,\s*'
        + requirement
        + r'\s*\)',
        re.S,
    )
    replacement = f'.package(name: {swift_string(slug)}, path: {swift_string(path)})'
    text, count = pattern.subn(replacement, text)
    return count


# Most specific first: the swift-tui pattern is anchored on `swift-tui(.git)?"`
# so it cannot match swift-tui-charts, but keep the order explicit anyway.
charts_count = localize("swift-tui-charts", charts)
swift_tui_count = localize("swift-tui", swift_tui)
manifest.write_text(text, encoding="utf-8")
print(f"{manifest}: swift-tui x{swift_tui_count}, swift-tui-charts x{charts_count}")
PY
}

log "localizing sibling dependencies"
localize_manifest "$charts_checkout/Package.swift"
while IFS= read -r -d '' manifest; do
  localize_manifest "$manifest"
done < <(find "$examples_copy" -name Package.swift -not -path '*/.build/*' -print0 | sort -z)

# Fail loud on any surviving sibling pin. A manifest form this script does not
# recognise must stop the run, not build the tag under a HEAD label.
log "verifying no sibling tag pin survived"
surviving="$(
  grep -rn --include=Package.swift -E 'github\.com/SwiftTUI/swift-tui(-charts)?(\.git)?"' \
    "$examples_copy" "$charts_checkout/Package.swift" 2>/dev/null \
    | grep -v '/\.build/' || true
)"
if [[ -n "$surviving" ]]; then
  printf '%s\n' "$surviving" >&2
  fail "un-localized sibling pin(s) above; extend localize_manifest for that manifest form"
fi
# Sanity check in the other direction: the rewrite must have produced local
# path dependencies, or the grep above proved nothing.
localized_count="$(grep -rl --include=Package.swift -E '\.package\(name: "swift-tui(-charts)?", path: ' "$examples_copy" | wc -l | tr -d '[:space:]')"
[[ "$localized_count" -gt 0 ]] || fail "no manifest was localized; the examples copy at $examples_copy has no sibling dependencies?"
log "localized $localized_count example manifest(s)"

# Scratch stamp: purge on any sibling revision change.
if [[ -n "$scratch_dir" ]]; then
  mkdir -p "$(dirname "$scratch_dir")"
  stamp_file="$scratch_dir/.swifttui-sibling-revisions"
  stamp="swift-tui=$swift_tui_revision"$'\n'"swift-tui-charts=$charts_revision"
  if [[ -e "$scratch_dir" && "$(cat "$stamp_file" 2>/dev/null || true)" != "$stamp" ]]; then
    log "sibling revisions changed; purging SwiftPM scratch $scratch_dir"
    rm -rf "$scratch_dir"
  fi
  mkdir -p "$scratch_dir"
  printf '%s' "$stamp" >"$stamp_file"
fi

if [[ "$run_check" -eq 0 ]]; then
  log "localized copy ready at $examples_copy (--no-check: not running the gate)"
  exit 0
fi

log "running the framework-seam gate in the localized copy"
cd "$examples_copy"
export SWIFTTUI_CHECKOUT="$swift_tui_checkout"
export SWIFTTUI_CHARTS_CHECKOUT="$charts_checkout"
if [[ -n "$scratch_dir" ]]; then
  export SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH="$scratch_dir"
fi
if [[ ${#check_arguments[@]} -eq 0 ]]; then
  check_arguments=(--linux-only --skip-clean --skip-bun-install)
fi
exec Scripts/check_examples.sh "${check_arguments[@]}"
