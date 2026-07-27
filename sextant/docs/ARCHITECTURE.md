# Architecture

Sextant is a read-only SwiftTUI application with one semantic state owner:
`@MainActor BrowserModel`. Views render `BrowserState` and translate input or
pointer events into `BrowserAction`; they do not own filesystem, preview,
search, or watcher lifecycles.

## Browser domain

`BrowserModel.send` owns navigation, stable identity, selection restoration,
focus, overlays, filters, request generations, stale-result rejection, status
messages, and shutdown. Lightweight trail/selection state is separate from
cached directory snapshots.

`BrowserLayoutPolicy` selects a bounded surface window before `MillerLayout`
measures children. At most two browser columns and one preview surface are
composed, independent of trail depth.

## Filesystem

`FileSystemClient` is the only listing/metadata/prefix seam. The live adapter
retains typed failures and filesystem kinds; the in-memory adapter makes model
tests deterministic.

`DirectoryStore` limits reads to four, caches at most 64 snapshots and 50,000
items, pins the visible window, and cancels or supersedes abandoned requests.
Watcher events invalidate store entries and ask the model to refresh; they
never mutate state directly.

## Preview

`BuiltInPreviewer` performs one bounded prefix read and returns value models for
text, hexadecimal, metadata, directory summaries, unsupported items, or typed
failures.

`PreviewResolver` is pure adapter selection. `PreviewExecutableCache` probes
each executable once. `PreviewCoordinator` owns debounce, generation checks,
serialized replacement, TERM/KILL escalation, lifecycle states, and shutdown.
`PreviewPipeline` maps those events into the model while retaining the built-in
fallback.

## Commands and services

`CommandCatalog` is shared by key dispatch, modal help, the command palette,
configuration validation, and `docs/KEYBINDINGS.md`. Application exit remains a
runtime-owned command, so configuration rejects `application.quit` overrides
instead of presenting a binding the runtime cannot honor.

Configuration and persistent state use versioned Codable values with atomic
same-directory writes. Handoff uses argv arrays and a tested POSIX-word lexer;
no action evaluates shell source. External preview templates require `{path}` as
a standalone argv element, and every adapter failure retains the built-in
preview.

`FilenameSearchCoordinator` performs cancellable, filename-only breadth-first
search with visited-directory identities and bounded batches/results.
`LiveDirectoryWatcher` coalesces visible-directory events and closes every file
descriptor during shutdown.
