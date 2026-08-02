# Development

Use the repository-pinned Swift toolchain:

```bash
swiftly run swift build --package-path sextant
swiftly run swift build -c release --package-path sextant
swiftly run swift test --package-path sextant
```

The public package uses a tagged HTTPS SwiftTUI dependency. Use the pre-tag or
worktree overlay in the SwiftTUI coordination root for untagged candidates.

Tests are layered around the owning seams:

- `BrowserModelTests` cover semantic transitions and late-result rejection.
- Filesystem and store suites cover typed results, concurrency, and budgets.
- Built-in preview and resolver/coordinator suites cover bounded content and
  the child lifecycle.
- Layout and render suites cover bounded composition and lazy rows.
- Directory-watch, search, and state suites cover Phase 3 services.
- `SextantRealTerminalJourneyTests` cover production-async PTY input, resize,
  focus, replacement, and shutdown.
- `SextantPerformanceTests` cover 10,000-entry interaction budgets.

Optional preview tools are never test requirements.

When you change commands, update `CommandCatalog`. The drift test requires
`docs/KEYBINDINGS.md` to match its generated Markdown exactly.
