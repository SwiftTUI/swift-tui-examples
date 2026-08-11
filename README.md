# SwiftTUI Examples

**SwiftUI semantics, drawn in terminal cells**, and the same authored `App`
shipped to every host. This repo holds runnable examples for
[`SwiftTUI`](https://github.com/SwiftTUI/swift-tui): one directory per demo, each
proving a specific capability, each with the exact command to run it.

![Status](https://img.shields.io/badge/status-0.8.6%20pre--release-DAA520)

## Start here

Pick by what you want to see, then run one command:

- **The most in one window**: run [`gallery`](gallery) for tabs, controls,
  charts, images, animated GIFs, popovers, and physics in a single terminal app.
- **One source on every host**: clone
  [`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo)
  to get the *same* `CounterApp` value as a terminal executable, an embedded
  native SwiftUI window, and a static WASI browser bundle (it also powers the
  live demo on [swifttui.sh](https://swifttui.sh)).
- **The smallest possible start**: read [`minimal`](minimal), one
  `RenderOnce.print(...)` with no app runtime and no argument parser.
- **A polished document reader**: run [`mrkdwn`](mrkdwn) for complete GFM
  compilation, responsive navigation, XDG theming, and bounded images.
- **A terminal data workbench**: run [`csvui`](csvui) for lazy CSV/TSV viewing,
  sparse editing, projections, live reload, and conflict-aware atomic saves.

Building something specific? Scan the [roster](#roster) by what each example
proves, or jump straight to a package in [By product](#by-product).

## Prerequisites

- **Swift 6.3.x** (`.swift-version` pins 6.3.3), plus **[Bun](https://bun.sh)**
  for the browser/WASI example.
- Commands below use **[`swiftly`](https://swiftly.dev)** so every example builds
  against the repository pinned toolchain. If Swift 6.3.x is active through
  Xcode 26 or `PATH`, remove the `swiftly run` prefix. Then run the bare
  `swift ...` command.

Run from the repo root unless a local README says otherwise.

## Quick start

```bash
git clone https://github.com/SwiftTUI/swift-tui-examples.git
cd swift-tui-examples
swiftly run swift run --package-path gallery gallery-demo   # the full workbench
swiftly run swift run --package-path minimal minimal        # the smallest path
```

Each example builds from a fresh clone with tagged HTTPS dependencies. Each
example pins the current `0.8.6` release graph. Gallery uses matching
`swift-tui` and `swift-tui-charts` versions. `mrkdwn` uses the independent
`swift-markdown` release range. No sibling source checkout is necessary.

## Roster

| Example | Host | What it proves | Run |
| --- | --- | --- | --- |
| [minimal](minimal) | CLI | Smallest `RenderOnce.print(...)` path for report-like CLI output, with no app runtime or argument parser | `swiftly run swift run --package-path minimal minimal` |
| [equatable-demo](equatable-demo) | Terminal | Smallest `View.equatable()` usage: a stable panel is memoized (reused across frames) while a counter updates | `swiftly run swift run --package-path equatable-demo EquatableDemo` |
| [argparse](argparse) | Terminal | `SwiftTUI.App` command conformance, consumer flags, standard SwiftTUI flags, and completions in one app type | `swiftly run swift run --package-path argparse argparse-demo --help` |
| [gallery](gallery) | Terminal+Web | Primary component workbench: tabs, controls, palette, text input, scroll commands, charts, images, animated GIFs, file drop, popovers, and logo-breaker physics | `swiftly run swift run --package-path gallery gallery-demo` |
| [layouts](layouts) | Terminal | SwiftTUI layout catalog with behavior tests for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | `swiftly run swift run --package-path layouts layouts-demo` |
| [LayoutsSwiftUI](LayoutsSwiftUI) | Native SwiftUI | Native SwiftUI layout catalog beside the embedded SwiftTUI catalog through `SwiftUIHost` | `swiftly run swift run --package-path LayoutsSwiftUI layouts-swiftui-demo` |
| [AndroidGallery](AndroidGallery) | Android | Compose host app embedding the SwiftTUI gallery through `SwiftTUIAndroidHost` and the Swift Android SDK | `(cd AndroidGallery && ./gradlew :app:assembleDebug)` |
| [sextant](sextant) | Terminal | Miller-column browser and file previews through `SwiftTUITerminal` / `TerminalProcessSession` | `swiftly run swift run --package-path sextant sextant` |
| [terminal-workspace](terminal-workspace) | Terminal | Terminal multiplexer built on `SwiftTUITerminal`, with an example-owned workspace layer: tabs, splits, retained sessions, command-palette actions, and persisted layout metadata | `swiftly run swift run --package-path terminal-workspace terminal-workspace` |
| [mrkdwn](mrkdwn) | Terminal | Responsive CommonMark/GFM reader with outline, search, local-document history, XDG TOML themes, and bounded images | `swiftly run swift run --package-path mrkdwn mrkdwn README.md` |
| [csvui](csvui) | Terminal | Viewer-first CSV/TSV workbench with lazy row decoding, sparse edits, search/filter/sort projections, XDG theming, live reload, and safe atomic saves | `swiftly run swift run --package-path csvui csvui data.csv` |
| [git-viz](git-viz) | CLI | `SwiftTUICharts` over real git data, with a command for every chart primitive | `swiftly run swift run --package-path git-viz git-viz dashboard --path .` |
| [gifcat](gifcat) | Terminal | `SwiftTUIAnimatedImage` playback, source GIF delays, regular-size image attachments, and row-major tiling of multiple GIFs | `swiftly run swift run --package-path gifcat gifcat gifeditor/nyan.gif` |
| [gifeditor](gifeditor) | Terminal+Web | Full GIF editor: half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, and GIF import/export | `swiftly run swift run --package-path gifeditor gifeditor` |
| [SwiftUIExample](SwiftUIExample) | Native SwiftUI | SwiftUI host app embedding reusable SwiftTUI scenes through `SwiftUIHost` | `open SwiftUIExample/SwiftUIExample.xcodeproj` |
| [swift-tui-counter-demo](https://github.com/SwiftTUI/swift-tui-counter-demo) | Multi-host | Own repo: the same `CounterApp` value runs as a terminal executable, embeds in a native SwiftUI window via `SwiftUIHost`, and ships as a static WASI bundle in the browser (the swifttui.sh live demo) | `git clone https://github.com/SwiftTUI/swift-tui-counter-demo.git` |
| [WebHostExample](WebHostExample) | Terminal+Web | Smallest `SwiftTUI` convenience app: terminal by default, localhost browser host with `--web` | `swiftly run swift run --package-path WebHostExample WebHostExample --web` |

## By product

Already know the package you need? Jump straight to an example that uses it.

| Product or package | Examples |
| --- | --- |
| `SwiftTUI` convenience surface | [argparse](argparse), [gallery](gallery), [layouts](layouts), [sextant](sextant), [terminal-workspace](terminal-workspace), [mrkdwn](mrkdwn), [csvui](csvui), [gifcat](gifcat), [gifeditor](gifeditor), [WebHostExample](WebHostExample) |
| `SwiftTUIRuntime` / host-managed scenes | [gallery](gallery), [swift-tui-counter-demo](https://github.com/SwiftTUI/swift-tui-counter-demo) |
| `SwiftTUICLI` / one-shot rendering and terminal launch | [minimal](minimal), [git-viz](git-viz) |
| `SwiftTUIArguments` / `SwiftTUICommand` | [argparse](argparse), [gallery](gallery), [gifeditor](gifeditor), [git-viz](git-viz) |
| `SwiftTUICharts` (separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package) | [git-viz](git-viz), [gallery](gallery), [layouts](layouts) |
| `SwiftTUIAnimatedImage` | Included by `SwiftTUI`. Used directly by [gifcat](gifcat) and [gallery](gallery) |
| `SwiftTUITerminal` | [sextant](sextant), [terminal-workspace](terminal-workspace) |
| `SwiftUIHost` | [SwiftUIExample](SwiftUIExample), [swift-tui-counter-demo](https://github.com/SwiftTUI/swift-tui-counter-demo) |
| `SwiftTUIAndroidHost` | [AndroidGallery](AndroidGallery) |
| `SwiftTUIWebHostCLI` | Included by `SwiftTUI`. Used directly by [gifeditor](gifeditor) |
| `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build` | [swift-tui-counter-demo](https://github.com/SwiftTUI/swift-tui-counter-demo) (own repo, the swifttui.sh live demo) |

The [coverage document](docs/EXAMPLE-COVERAGE.md) contains the full matrix,
category definitions, gate contract, and new-example checklist. For the APIs
behind these demos, read the
[DocC reference](https://swifttui.sh/docs/documentation/), and see the
[showcase](https://swifttui.sh/showcase/) for these examples running on every
host. The host halves live in the sibling repositories
[`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) (native
SwiftUI host), [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(browser packages), and
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android) (Android
host).

## Tests

Run `bun run check:focused` for all focused behavior tests. To test one example,
run `swiftly run swift test --package-path <example>`. The repository gates also
build examples that have no focused test suite. See the
[coverage document](docs/EXAMPLE-COVERAGE.md) for the `check:linux`,
`check:macos`, `check:web`, and `check` build gates and their
scratch-directory environment variables, and [`AGENTS.md`](AGENTS.md) for the
toolchain policy.

## License

MIT. See [LICENSE](LICENSE).
