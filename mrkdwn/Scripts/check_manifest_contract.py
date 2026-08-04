#!/usr/bin/env python3

"""Validate mrkdwn's semantic SwiftPM manifest and resolution contracts."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any


GIT_OID_PATTERN = re.compile(r"[0-9a-f]{40}")
PUBLIC_DEPENDENCIES = {
    "swift-tui": {
        "url": "https://github.com/SwiftTUI/swift-tui.git",
        "lower": "0.6.3",
        "resolved": "0.6.3",
        "revision": "c0570d0f2a4edbc72ca8c0793676efa80aa48721",
    },
    "swift-markdown": {
        "url": "https://github.com/swiftlang/swift-markdown.git",
        "lower": "0.8.0",
        "resolved": "0.8.0",
        "revision": "3c6f9523da3a1ec2fd829673e472d95b8097a3b8",
    },
}


def up_to_next_minor(lower: str) -> str:
    """The exclusive bound SwiftPM derives for `.upToNextMinor(from: lower)`.

    Derived rather than stored. A stored upper bound is a second copy of the
    version that no release step can maintain: the org bump rewrites tokens
    equal to the *old* version, so bumping 0.4.7 to 0.5.0 would rewrite `lower`
    and leave an `upper` of "0.5.0" behind — an empty [0.5.0, 0.5.0) range that
    fails on release day. Every entry above uses `.upToNextMinor`; an entry that
    ever needs another spelling must make this explicit rather than restore the
    stored field.
    """
    major, minor, _ = lower.split(".", 2)
    return f"{major}.{int(minor) + 1}.0"
# Derived from the contract above rather than spelled out again: a second copy
# of the version drifts the moment a release bumps only one of them.
SWIFT_TUI_REMOTE_DEPENDENCY_PATTERN = re.compile(
    r"""\.package\(
        \s*url:\s*"%s"\s*,
        \s*\.upToNextMinor\(from:\s*"%s"\)\s*
    \)"""
    % (
        re.escape(PUBLIC_DEPENDENCIES["swift-tui"]["url"]),
        re.escape(PUBLIC_DEPENDENCIES["swift-tui"]["lower"]),
    ),
    re.VERBOSE,
)
SWIFT_TUI_LOCAL_DEPENDENCY_PATTERN = re.compile(
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


def remote_url(record: dict[str, Any], identity: str) -> str:
    location = record.get("location")
    require(isinstance(location, dict), f"{identity} must have a source-control location")
    remote = single_record(location.get("remote"), f"{identity} remote location")
    url = remote.get("urlString")
    require(isinstance(url, str), f"{identity} remote URL must be a string")
    return url


def validate_range(
    record: dict[str, Any],
    identity: str,
    lower: str,
    upper: str,
) -> None:
    requirement = record.get("requirement")
    require(isinstance(requirement, dict), f"{identity} must have a version requirement")
    require(
        set(requirement) == {"range"},
        f"{identity} must use only a released up-to-next-minor range",
    )
    version_range = single_record(requirement["range"], f"{identity} version range")
    require(
        version_range == {"lowerBound": lower, "upperBound": upper},
        f"{identity} range must be [{lower}, {upper})",
    )


def collect_dependency_records(
    dependencies: list[Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    remote: dict[str, dict[str, Any]] = {}
    local: dict[str, dict[str, Any]] = {}
    for dependency in dependencies:
        require(isinstance(dependency, dict), "every dependency must be an object")
        kinds = set(dependency)
        require(
            kinds in ({"sourceControl"}, {"fileSystem"}),
            "dependencies must be source-control URLs or the named disposable overlay paths",
        )
        kind = "sourceControl" if "sourceControl" in dependency else "fileSystem"
        record = single_record(dependency[kind], f"{kind} dependency")
        identity = record.get("identity")
        require(isinstance(identity, str), f"{kind} identity must be a string")
        require(identity not in remote and identity not in local, f"duplicate {identity}")
        destination = remote if kind == "sourceControl" else local
        destination[identity] = record
    return remote, local


def validate_dump(
    package: dict[str, Any],
    overlay_checkout: pathlib.Path | None,
) -> None:
    require(package.get("name") == "mrkdwn", "dump-package must describe mrkdwn")
    dependencies = package.get("dependencies")
    require(isinstance(dependencies, list), "dump-package dependencies must be an array")
    require(len(dependencies) == 2, "mrkdwn must have exactly two direct dependencies")
    remote, local = collect_dependency_records(dependencies)

    expected_remote = (
        {"swift-markdown"}
        if overlay_checkout is not None
        else set(PUBLIC_DEPENDENCIES)
    )
    expected_local = {"swift-tui"} if overlay_checkout is not None else set()
    require(set(remote) == expected_remote, f"remote identities must be {sorted(expected_remote)}")
    require(set(local) == expected_local, f"local identities must be {sorted(expected_local)}")

    for identity, record in remote.items():
        contract = PUBLIC_DEPENDENCIES[identity]
        require(
            remote_url(record, identity) == contract["url"],
            f"{identity} must use {contract['url']}",
        )
        validate_range(
            record,
            identity,
            contract["lower"],
            up_to_next_minor(contract["lower"]),
        )

    for identity, record in local.items():
        path = record.get("path")
        require(isinstance(path, str), f"{identity} overlay path must be a string")
        if overlay_checkout is None:
            raise ContractError("local dependency requires an expected swift-tui checkout")
        require(
            canonical_directory(pathlib.Path(path), f"{identity} overlay path")
            == overlay_checkout,
            f"{identity} overlay path must resolve to {overlay_checkout}",
        )


def validate_lock(package_root: pathlib.Path) -> None:
    lock_path = package_root / "Package.resolved"
    require(lock_path.is_file(), "real checkout must commit mrkdwn/Package.resolved")
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    require(isinstance(lock, dict), "Package.resolved root must be an object")
    require(lock.get("version") == 3, "Package.resolved must use schema version 3")
    pins = lock.get("pins")
    require(isinstance(pins, list), "Package.resolved pins must be an array")

    pins_by_identity: dict[str, dict[str, Any]] = {}
    for pin in pins:
        require(isinstance(pin, dict), "every resolved pin must be an object")
        identity = pin.get("identity")
        require(isinstance(identity, str), "every resolved pin must have an identity")
        require(identity not in pins_by_identity, f"duplicate resolved pin {identity}")
        require(
            pin.get("kind") == "remoteSourceControl",
            f"{identity} must resolve from remote source control",
        )
        state = pin.get("state")
        require(isinstance(state, dict), f"{identity} must have resolved state")
        require(isinstance(state.get("version"), str), f"{identity} must resolve a version")
        require("branch" not in state, f"{identity} must not resolve a branch")
        revision = state.get("revision")
        require(isinstance(revision, str), f"{identity} must resolve a revision")
        require(
            GIT_OID_PATTERN.fullmatch(revision) is not None,
            f"{identity} revision must be a full lowercase Git OID",
        )
        pins_by_identity[identity] = pin

    require(
        set(PUBLIC_DEPENDENCIES).issubset(pins_by_identity),
        "Package.resolved must include every direct dependency",
    )
    for identity, contract in PUBLIC_DEPENDENCIES.items():
        pin = pins_by_identity[identity]
        require(pin.get("location") == contract["url"], f"{identity} lock URL changed")
        require(
            pin["state"].get("version") == contract["resolved"],
            f"{identity} must resolve {contract['resolved']}",
        )
        require(
            pin["state"].get("revision") == contract["revision"],
            f"{identity} {contract['resolved']} must resolve revision {contract['revision']}",
        )


def localize_manifest(
    source_path: pathlib.Path,
    destination_path: pathlib.Path,
    checkout: pathlib.Path,
) -> None:
    checkout = canonical_directory(checkout, "swift-tui checkout")
    source = source_path.read_text(encoding="utf-8")
    remote_matches = list(SWIFT_TUI_REMOTE_DEPENDENCY_PATTERN.finditer(source))
    local_matches = list(SWIFT_TUI_LOCAL_DEPENDENCY_PATTERN.finditer(source))
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
    pattern = (
        SWIFT_TUI_REMOTE_DEPENDENCY_PATTERN
        if remote_matches
        else SWIFT_TUI_LOCAL_DEPENDENCY_PATTERN
    )
    localized, replacement_count = pattern.subn(
        lambda _: replacement,
        source,
        count=1,
    )
    require(replacement_count == 1, "could not localize the swift-tui dependency")
    destination_path.write_text(localized, encoding="utf-8")


def run_localize_command(arguments: list[str]) -> int:
    if len(arguments) != 4:
        print(
            "usage: check_manifest_contract.py --localize-manifest "
            "SOURCE_PACKAGE_SWIFT DESTINATION_PACKAGE_SWIFT SWIFTTUI_CHECKOUT",
            file=sys.stderr,
        )
        return 2
    try:
        localize_manifest(
            pathlib.Path(arguments[1]),
            pathlib.Path(arguments[2]),
            pathlib.Path(arguments[3]),
        )
    except (ContractError, OSError, UnicodeError) as error:
        print(f"mrkdwn dependency localization failed: {error}", file=sys.stderr)
        return 1
    return 0


def run_contract_command(arguments: list[str]) -> int:
    overlay_checkout: pathlib.Path | None = None
    if arguments[:1] == ["--overlay"]:
        if len(arguments) < 2:
            print(
                "usage: check_manifest_contract.py "
                "[--overlay SWIFTTUI_CHECKOUT] DUMP_PACKAGE_JSON PACKAGE_ROOT",
                file=sys.stderr,
            )
            return 2
        overlay_checkout = pathlib.Path(arguments[1])
        arguments = arguments[2:]
    if len(arguments) != 2:
        print(
            "usage: check_manifest_contract.py "
            "[--overlay SWIFTTUI_CHECKOUT] DUMP_PACKAGE_JSON PACKAGE_ROOT",
            file=sys.stderr,
        )
        return 2

    try:
        dump_path = pathlib.Path(arguments[0]).resolve()
        package_root = pathlib.Path(arguments[1]).resolve()
        if overlay_checkout is not None:
            overlay_checkout = canonical_directory(
                overlay_checkout,
                "expected swift-tui checkout",
            )
        package = json.loads(dump_path.read_text(encoding="utf-8"))
        require(isinstance(package, dict), "dump-package root must be an object")
        validate_dump(package, overlay_checkout)
        if overlay_checkout is None:
            validate_lock(package_root)
    except (
        ContractError,
        OSError,
        RuntimeError,
        UnicodeError,
        json.JSONDecodeError,
    ) as error:
        print(f"mrkdwn dependency contract failed: {error}", file=sys.stderr)
        return 1

    mode = "local swift-tui checkout" if overlay_checkout is not None else "public checkout"
    print(f"mrkdwn dependency contract passed ({mode})")
    return 0


def main() -> int:
    arguments = sys.argv[1:]
    if arguments[:1] == ["--localize-manifest"]:
        return run_localize_command(arguments)
    return run_contract_command(arguments)


if __name__ == "__main__":
    raise SystemExit(main())
