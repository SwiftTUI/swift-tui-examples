# AGENTS.md

Guidance for agentic assistants working in **`swift-tui-examples`**. Keep this
concise; [`README.md`](README.md) is the canonical roster and source of truth —
update it there when adding an example.

## What this repo is

The maintained roster of runnable SwiftTUI example apps, kept as sibling
packages at the repo root (one directory + README per example). Examples
exercise the public products (`SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUICharts`,
`SwiftUIHost`, `SwiftTUIWASI`, …). Use the README roster table for the exact
run/test command per example.

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
