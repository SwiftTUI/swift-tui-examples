# AGENTS.md

Guidance for agentic assistants working in **`swift-tui-examples`**. Keep this
file concise. [`README.md`](README.md) is the canonical roster. If you add an
example, update that file.

## What this repo is

This repository contains the maintained list of runnable SwiftTUI example apps.
Each example has one directory and one README. The examples exercise public
products such as `SwiftTUI`, `SwiftTUIRuntime`, and `SwiftUIHost`. They also
use the `SwiftTUICharts` product from the separate
`swift-tui-charts` package. Use the README roster for the run and test commands
of each example.

This repository is a public beta. Default manifests must use tagged HTTPS
SwiftPM dependencies and released package artifacts. They must not use sibling
source checkouts. Do not add coordination-only pin files. Pre-tag integration
belongs in `swift-tui-org`.

## Toolchains

Use **`swiftly` run** for Swift packages. This command uses the pinned Swift
6.3.x toolchain. Do not use bare `swift` or `xcrun swift`.

## Commands

```bash
bun run check                                          # repo gate (Scripts/check_examples.sh --skip-clean)
swiftly run swift run  --package-path <example> <exe>  # run one example (see README roster)
swiftly run swift test --package-path <example>        # test one example
```

`//:swift_tui_examples_native_gate` in the org root runs
`Scripts/check_examples.sh --skip-clean`. Examples without focused test targets
are still build-checked by that script.

## Notes

- The browser/WASI counter demo (formerly `counter` + `WebExample` here) lives
  in its own repo:
  [`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo).
  Every example here is a small, uniform demo covered by the roster — no
  per-example agent file needed.
- `SwiftUIExample` is a native Apple app (`open SwiftUIExample/...xcodeproj`).

## Conventions

`AGENTS.md` is the real file. `CLAUDE.md` is a symlink to it. Edit `AGENTS.md`.
