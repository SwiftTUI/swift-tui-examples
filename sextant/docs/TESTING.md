# Testing

`swiftly run swift test --skip SextantPerformanceTests` runs the deterministic
browser, filesystem, preview, configuration, watcher, search, layout, and
rendering suites.

Run performance separately:

```sh
swiftly run swift test --filter SextantPerformanceTests
```

The performance lane synchronously renders committed frames on the main actor.
Isolating it prevents test-runner contention from inflating its measurements or
delaying unrelated main-actor cancellation checks.

The real-terminal journey uses production async rendering and verifies input,
resize, preview replacement, host Escape interception, and bounded shutdown. It
owns a PTY and child processes, so run it in an isolated test process:

```sh
SEXTANT_REAL_PTY_TESTS=1 swiftly run swift test \
  --filter SextantRealTerminalJourneyTests
```

The performance suite measures selection and filtering through committed
SwiftTUI renders, records the other end-to-end slices, and keeps 10,000-entry
selection, filtering, layout, directory, and preview work within the budgets in
the checked-in [performance baseline](PERFORMANCE.md).

Run `Scripts/check.sh` for the release-shaped native gate.
