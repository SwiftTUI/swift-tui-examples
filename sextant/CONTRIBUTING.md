# Contributing

Sextant is pre-1.0 software. Keep issues and pull requests small and focused.

Use the pinned Swift toolchain and run the native gate:

```bash
swiftly run swift test
swiftly run swift build -c release
```

Add focused tests for each behavior change. Use `BrowserModel.send` or the
applicable deterministic adapter. Keep Sextant read-only. File changes, shell
evaluation, and unbounded filesystem work are outside the v0.1 contract.

Architecture, testing, and release details live in [`docs/`](docs/).
