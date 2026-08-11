# Architecture

Sextant is a read-only SwiftTUI application with one semantic state owner:
`@MainActor BrowserModel`. Views render `BrowserState` and translate input or
pointer events into `BrowserAction`. They do not own filesystem, preview,
search, or directory-watch lifecycles.

## Browser domain

`BrowserModel.send` owns navigation, stable identity, selection restoration,
focus, overlays, filters, request generations, stale-result rejection, status
messages, and shutdown. Lightweight trail/selection state is separate from
cached directory snapshots.

`BrowserLayoutPolicy` selects a bounded surface window before `MillerLayout`
measures children. At most two browser columns and one preview surface are
composed, independent of trail depth. The window looks only at the parent and
active nodes. Thus, the prefetched node for a selected directory remains off
screen until the user enters it.

## Filesystem

`FileSystemClient` is the only listing/metadata/prefix seam. The live adapter
retains typed failures and filesystem kinds. The in-memory adapter makes model
tests deterministic.

`DirectoryStore` permits four reads at one time. It caches at most 64 snapshots
and 50,000 items. It pins the visible window and cancels abandoned requests.
Directory-watch events invalidate store entries and request a model refresh.
They do not change state directly.

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
same-directory writes. Handoff uses argv arrays and a tested POSIX-word lexer.
No action evaluates shell source. External preview templates require `{path}` as
a standalone argv element, and every adapter failure retains the built-in
preview.

`FilenameSearchCoordinator` performs cancellable, filename-only breadth-first
search with visited-directory identities and bounded batches/results.
`LiveDirectoryWatcher` coalesces visible-directory events and closes every file
descriptor during shutdown.

## Vocabulary

- **Dispatch**: `CommandCatalog.dispatch(_:context:)` connects a key press to
  its effect. It determines key eligibility, effect availability, and effect
  ownership. It returns `.perform(BrowserAction)`, `.unavailable(reason)`,
  `.runtimeOwned`, or `nil`. Callers previously made some of these decisions.
  For example, a view contained a `focus` guard. This duplication made catalog
  availability closures unreachable and silently disabled bindings.
- **Command context**: This value contains all data that a binding can use.
  The data covers selection, preview, focus, overlays, hidden files, and
  root-relative selection. Tests can determine dispatch without a live
  `BrowserModel`. A command reads browser state only through this value.
