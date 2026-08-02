# Testing

`swiftly run swift test --skip SextantPerformanceTests` runs the deterministic
browser, filesystem, preview, configuration, watcher, search, layout, and
rendering suites.

Run performance separately:

```sh
swiftly run swift test --filter SextantPerformanceTests
```

The performance lane renders committed frames synchronously on the main actor.
An isolated run prevents test-runner contention. This contention can increase
measurements or delay unrelated main-actor cancellation checks.

The real-terminal journey uses production async rendering. It covers input,
resize, preview replacement, host Escape interception, and bounded shutdown. It
owns a PTY and child processes. Run it in an isolated test process:

```sh
SEXTANT_REAL_PTY_TESTS=1 swiftly run swift test \
  --filter SextantRealTerminalJourneyTests
```

The performance suite measures selection and filters through committed SwiftTUI
renders. It records the other end-to-end segments. The
[performance baseline](PERFORMANCE.md) contains budgets for 10,000-entry
selection, filters, layout, directory, and preview work.

Run `Scripts/check.sh` for the release-shaped native gate.
