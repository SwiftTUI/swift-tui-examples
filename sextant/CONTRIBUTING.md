# Contributing

Sextant is pre-1.0 software. Small, focused issues and pull requests are easiest
to review.

Use the pinned Swift toolchain and run the native gate:

```bash
swiftly run swift test
swiftly run swift build -c release
```

Behavior changes should include focused tests through `BrowserModel.send` or
the relevant deterministic adapter. Keep Sextant read-only: file mutation,
shell evaluation, and unbounded filesystem work are outside the v0.1 contract.

Architecture, testing, and release details live in [`docs/`](docs/).
