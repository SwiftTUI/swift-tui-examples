# AGENTS.md

Guidance for agentic assistants working in **`swift-tui-examples`**. Keep this
concise; [`README.md`](README.md) is the canonical roster and source of truth —
update it there when adding an example.

## What this repo is

The maintained, consumer-facing roster of runnable SwiftTUI example apps (one
directory + README per example). Examples exercise the public products
(`SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUICharts`, `SwiftUIHost`,
`SwiftTUIWASI`, …). Use the README roster table for the exact run/test command
per example.

This repo is public beta. Default manifests must use tagged HTTPS
SwiftPM dependencies and released package artifacts, not sibling source
checkouts. Do not add coordination-only pin files; pre-tag integration belongs
in `swift-tui-org`.

## Toolchains

Use **`swiftly` run** for Swift packages so examples use the repo's pinned Swift
6.3.x toolchain — not bare `swift`/`xcrun swift`. The browser example also needs
**Bun**.

## Commands

```bash
bun run check                                          # repo gate (Scripts/check_examples.sh --skip-clean)
swiftly run swift run  --package-path <example> <exe>  # run one example (see README roster)
swiftly run swift test --package-path <example>        # test one example
bun --cwd WebExample dev                               # the browser/WASI example
```

`//:swift_tui_examples_native_gate` in the org root runs
`Scripts/check_examples.sh --skip-clean`. Examples without focused test targets
are still build-checked by that script.

## Notes

- **WebExample** is the browser/WASI deployment example and has its own
  `AGENTS.md` (non-obvious COOP/COEP + wasm-build-flag gotchas). Every other
  example is a small, uniform demo covered by the roster — no per-example agent
  file needed.
- `SwiftUIExample` is a native Apple app (`open SwiftUIExample/...xcodeproj`).

## Conventions

`AGENTS.md` is the real file; `CLAUDE.md` is a symlink to it. Edit `AGENTS.md`.
