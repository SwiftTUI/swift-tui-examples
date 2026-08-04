#!/usr/bin/env python3

"""Validate csvui's public and disposable-overlay SwiftPM contracts."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any


PUBLIC_DEPENDENCIES = {
    "swift-tui": {
        "url": "https://github.com/SwiftTUI/swift-tui.git",
        "lower": "0.6.1",
        "resolved": "0.6.1",
        "revision": "1c19c77bb3a4830a1ac65cdf55a4688ad5c52f45",
    }
}
SWIFT_TUI_CONTRACT = PUBLIC_DEPENDENCIES["swift-tui"]
IDENTITY = "swift-tui"
PUBLIC_URL = SWIFT_TUI_CONTRACT["url"]
LOWER_VERSION = SWIFT_TUI_CONTRACT["lower"]
RESOLVED_VERSION = SWIFT_TUI_CONTRACT["resolved"]
RESOLVED_REVISION = SWIFT_TUI_CONTRACT["revision"]
GIT_OID_PATTERN = re.compile(r"[0-9a-f]{40}")
REMOTE_DEPENDENCY_PATTERN = re.compile(
    r"""\.package\(
        \s*url:\s*"%s"\s*,
        \s*\.upToNextMinor\(from:\s*"%s"\)\s*
    \)"""
    % (re.escape(PUBLIC_URL), re.escape(LOWER_VERSION)),
    re.VERBOSE,
)
LOCAL_DEPENDENCY_PATTERN = re.compile(
    r"""\.package\(
        \s*name:\s*"swift-tui"\s*,
        \s*path:\s*"[^"]+"\s*
    \)""",
    re.VERBOSE,
)


class ContractError(Exception):
    """A reader-facing dependency contract failure."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def canonical_directory(path: pathlib.Path, label: str) -> pathlib.Path:
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise ContractError(f"{label} is unavailable: {path}: {error}") from error
    require(resolved.is_dir(), f"{label} must be a directory: {resolved}")
    return resolved


def single_record(value: Any, label: str) -> dict[str, Any]:
    require(isinstance(value, list) and len(value) == 1, f"{label} must contain one record")
    record = value[0]
    require(isinstance(record, dict), f"{label} record must be an object")
    return record


def expected_upper_bound() -> str:
    major, minor, _ = LOWER_VERSION.split(".", 2)
    return f"{major}.{int(minor) + 1}.0"


def validate_dump(package: dict[str, Any], overlay: pathlib.Path | None) -> None:
    require(package.get("name") == "csvui", "dump-package must describe csvui")
    dependencies = package.get("dependencies")
    require(isinstance(dependencies, list), "dump-package dependencies must be an array")
    require(len(dependencies) == 1, "csvui must have exactly one direct dependency")
    dependency = dependencies[0]
    require(isinstance(dependency, dict), "the direct dependency must be an object")

    if overlay is None:
        require(set(dependency) == {"sourceControl"}, "public csvui must use source control")
        record = single_record(dependency["sourceControl"], "source-control dependency")
        require(record.get("identity") == IDENTITY, "public dependency must be swift-tui")
        location = record.get("location")
        require(isinstance(location, dict), "swift-tui must have a source-control location")
        remote = single_record(location.get("remote"), "swift-tui remote location")
        require(remote.get("urlString") == PUBLIC_URL, f"swift-tui must use {PUBLIC_URL}")
        requirement = record.get("requirement")
        require(isinstance(requirement, dict), "swift-tui must have a version requirement")
        require(set(requirement) == {"range"}, "swift-tui must use only a released range")
        version_range = single_record(requirement["range"], "swift-tui version range")
        require(
            version_range
            == {"lowerBound": LOWER_VERSION, "upperBound": expected_upper_bound()},
            f"swift-tui range must be [{LOWER_VERSION}, {expected_upper_bound()})",
        )
        return

    require(set(dependency) == {"fileSystem"}, "overlay csvui must use one local path")
    record = single_record(dependency["fileSystem"], "file-system dependency")
    require(record.get("identity") == IDENTITY, "overlay dependency must be swift-tui")
    path = record.get("path")
    require(isinstance(path, str), "swift-tui overlay path must be a string")
    require(
        canonical_directory(pathlib.Path(path), "swift-tui overlay path") == overlay,
        f"swift-tui overlay path must resolve to {overlay}",
    )


def validate_lock(package_root: pathlib.Path) -> None:
    lock_path = package_root / "Package.resolved"
    require(lock_path.is_file(), "real checkout must commit csvui/Package.resolved")
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    require(isinstance(lock, dict), "Package.resolved root must be an object")
    require(lock.get("version") == 3, "Package.resolved must use schema version 3")
    pins = lock.get("pins")
    require(isinstance(pins, list), "Package.resolved pins must be an array")
    matching = [pin for pin in pins if isinstance(pin, dict) and pin.get("identity") == IDENTITY]
    require(len(matching) == 1, "Package.resolved must contain one swift-tui pin")
    pin = matching[0]
    require(pin.get("kind") == "remoteSourceControl", "swift-tui lock must be remote source control")
    require(pin.get("location") == PUBLIC_URL, "swift-tui lock URL changed")
    state = pin.get("state")
    require(isinstance(state, dict), "swift-tui must have resolved state")
    require("branch" not in state, "swift-tui must not resolve a branch")
    require(state.get("version") == RESOLVED_VERSION, f"swift-tui must resolve {RESOLVED_VERSION}")
    revision = state.get("revision")
    require(isinstance(revision, str), "swift-tui must resolve a revision")
    require(GIT_OID_PATTERN.fullmatch(revision) is not None, "swift-tui revision must be a full Git OID")
    require(
        revision == RESOLVED_REVISION,
        f"swift-tui {RESOLVED_VERSION} must resolve revision {RESOLVED_REVISION}",
    )


def localize_manifest(source_path: pathlib.Path, destination_path: pathlib.Path, checkout: pathlib.Path) -> None:
    checkout = canonical_directory(checkout, "swift-tui checkout")
    source = source_path.read_text(encoding="utf-8")
    remote_matches = list(REMOTE_DEPENDENCY_PATTERN.finditer(source))
    local_matches = list(LOCAL_DEPENDENCY_PATTERN.finditer(source))
    require(
        len(remote_matches) + len(local_matches) == 1,
        "Package.swift must contain exactly one supported swift-tui dependency",
    )
    checkout_string = str(checkout)
    require(
        all(ord(character) >= 0x20 for character in checkout_string),
        "swift-tui checkout path must not contain control characters",
    )
    replacement = (
        '.package(name: "swift-tui", path: '
        f"{json.dumps(checkout_string, ensure_ascii=False)})"
    )
    pattern = REMOTE_DEPENDENCY_PATTERN if remote_matches else LOCAL_DEPENDENCY_PATTERN
    localized, count = pattern.subn(lambda _: replacement, source, count=1)
    require(count == 1, "could not localize the swift-tui dependency")
    destination_path.write_text(localized, encoding="utf-8")


def run_localize(arguments: list[str]) -> int:
    if len(arguments) != 4:
        print(
            "usage: check_manifest_contract.py --localize-manifest "
            "SOURCE_PACKAGE_SWIFT DESTINATION_PACKAGE_SWIFT SWIFTTUI_CHECKOUT",
            file=sys.stderr,
        )
        return 2
    try:
        localize_manifest(pathlib.Path(arguments[1]), pathlib.Path(arguments[2]), pathlib.Path(arguments[3]))
    except (ContractError, OSError, UnicodeError) as error:
        print(f"csvui dependency localization failed: {error}", file=sys.stderr)
        return 1
    return 0


def run_contract(arguments: list[str]) -> int:
    overlay: pathlib.Path | None = None
    if arguments[:1] == ["--overlay"]:
        if len(arguments) < 2:
            print("--overlay requires SWIFTTUI_CHECKOUT", file=sys.stderr)
            return 2
        overlay = pathlib.Path(arguments[1])
        arguments = arguments[2:]
    if len(arguments) != 2:
        print(
            "usage: check_manifest_contract.py "
            "[--overlay SWIFTTUI_CHECKOUT] DUMP_PACKAGE_JSON PACKAGE_ROOT",
            file=sys.stderr,
        )
        return 2
    try:
        if overlay is not None:
            overlay = canonical_directory(overlay, "expected swift-tui checkout")
        package = json.loads(pathlib.Path(arguments[0]).read_text(encoding="utf-8"))
        require(isinstance(package, dict), "dump-package root must be an object")
        validate_dump(package, overlay)
        if overlay is None:
            validate_lock(pathlib.Path(arguments[1]).resolve())
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"csvui dependency contract failed: {error}", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    arguments = sys.argv[1:]
    if arguments[:1] == ["--localize-manifest"]:
        return run_localize(arguments)
    return run_contract(arguments)


if __name__ == "__main__":
    raise SystemExit(main())
