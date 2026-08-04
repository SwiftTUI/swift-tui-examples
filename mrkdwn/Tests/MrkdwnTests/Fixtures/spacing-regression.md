# SwiftTUI Examples

**SwiftUI semantics, drawn in terminal cells** — and the same authored `App`
shipped to every host. This repo holds runnable examples for
[`SwiftTUI`](https://github.com/SwiftTUI/swift-tui): one directory per demo, each
proving a specific capability, each with the exact command to run it.

![Status](https://img.shields.io/badge/status-0.3.x%20pre--release-DAA520)

## Start here

Pick by what you want to see, then run one command:

- **The most in one window** — run `gallery`: tabs, controls, charts, images,
  animated GIFs, popovers, and physics in a single terminal app.
- **One source on every host** — run `counter`: the same app value as a
  terminal executable, an embedded native window, and a static browser bundle.
- **The smallest possible start** — read `minimal`: one render call, no app
  runtime, and no argument parser.
- **A polished document reader** — run `mrkdwn`: complete GFM compilation,
  responsive navigation, XDG theming, and bounded images.
- **A terminal data workbench** — run `csvui`: lazy CSV/TSV viewing, sparse
  editing, projections, live reload, and conflict-aware atomic saves.

Building something specific? Scan the roster by what each example proves, or
jump straight to a package in By product.

## Prerequisites

- **Swift 6.3.x**, plus **Bun** for the browser example.
- Commands below use the repository-pinned toolchain.

Run from the repo root unless a local README says otherwise.

## Quick start

```bash
swift run --package-path gallery gallery-demo
swift run --package-path minimal minimal
```

Each example builds from a fresh clone with tagged HTTPS dependencies. The
examples retain their native package-manager contracts.
