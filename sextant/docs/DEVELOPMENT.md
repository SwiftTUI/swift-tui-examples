# Development

Use the repository-pinned Swift toolchain:

```bash
swiftly run swift build --package-path sextant
swiftly run swift build -c release --package-path sextant
swiftly run swift test --package-path sextant
```

The public package dependency is tagged HTTPS SwiftTUI. Untagged candidate
testing belongs in the SwiftTUI coordination root's pre-tag/worktree overlay.

Tests are layered around the owning seams:

- `BrowserModelTests` for semantic transitions and late-result rejection;
- filesystem/store suites for typed truth, concurrency, and budgets;
- built-in preview and resolver/coordinator suites for bounded content and
  child lifecycle;
- layout/render suites for bounded composition and lazy rows;
- watcher/search/state suites for Phase 3 services;
- `SextantRealTerminalJourneyTests` for production-async PTY input, resize,
  focus, replacement, and shutdown;
- `SextantPerformanceTests` for 10,000-entry interaction budgets.

Optional preview tools are never test requirements.

When changing commands, update `CommandCatalog`. The drift test requires
`docs/KEYBINDINGS.md` to match its generated Markdown exactly.
