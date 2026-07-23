# SwiftTUI Examples

**SwiftUI semantics, drawn in terminal cells** — and the same authored `App`
shipped to every host. This repo holds runnable examples for
[`SwiftTUI`](https://github.com/SwiftTUI/swift-tui): one directory per demo, each
proving a specific capability, each with the exact command to run it.

![Status](https://img.shields.io/badge/status-0.1.15%20pre--release-DAA520)

## Start here

Pick by what you want to see, then run one command:

- **The most in one window** — run [`gallery`](gallery): tabs, controls, charts,
  images, animated GIFs, popovers, and physics in a single terminal app.
- **One source on every host** — run [`three-hosts-demo`](three-hosts-demo): the
  *same* `CounterApp` value as a terminal executable, an embedded native SwiftUI
  window, and a static WASI browser bundle.
- **The smallest possible start** — read [`minimal`](minimal): one
  `RenderOnce.print(...)`, no app runtime, no argument parser.

Building something specific? Scan the [roster](#roster) by what each example
proves, or jump straight to a package in [By product](#by-product).

## Prerequisites

- **Swift 6.3.x** (`.swift-version` pins 6.3.1), plus **[Bun](https://bun.sh)**
  for the browser/WASI example.
- Commands below use **[`swiftly`](https://swiftly.dev)** so every example builds
  against the repo's pinned toolchain. Already have Swift 6.3.x active (Xcode 26,
  or a toolchain on `PATH`)? Drop the `swiftly run` prefix and run the bare
  `swift ...` command.

Run from the repo root unless a local README says otherwise.

## Quick start

```bash
git clone https://github.com/SwiftTUI/swift-tui-examples.git
cd swift-tui-examples
swiftly run swift run --package-path gallery gallery-demo   # the full workbench
swiftly run swift run --package-path minimal minimal        # the smallest path
```

For the browser/WASI example:

```bash
bun install
bun --cwd WebExample run build
```

Everything builds from a fresh clone at tag `0.1.15`. Swift packages resolve
`swift-tui` — and, for the native SwiftUI host, `swift-tui-swiftui` — over tagged
HTTPS, and WebExample pulls the `swift-tui-web` `0.1.15` release tarballs for
`@swifttui/web` and `@swifttui/build`. No sibling source checkout required.

## Roster

| Example | Host | What it proves | Run |
| --- | --- | --- | --- |
| [minimal](minimal) | CLI | Smallest `RenderOnce.print(...)` path for report-like CLI output, with no app runtime or argument parser | `swiftly run swift run --package-path minimal minimal` |
| [equatable-demo](equatable-demo) | Terminal | Smallest `View.equatable()` usage: a stable panel is memoized (reused across frames) while a counter updates | `swiftly run swift run --package-path equatable-demo EquatableDemo` |
| [terminal-runner](terminal-runner) | Terminal | Explicit `TerminalRunner` launch with a custom preflight policy that rejects `--web` | `swiftly run swift run --package-path terminal-runner terminal-runner` |
| [argparse](argparse) | Terminal | `SwiftTUI.App` command conformance, consumer flags, standard SwiftTUI flags, and completions in one app type | `swiftly run swift run --package-path argparse argparse-demo --help` |
| [gallery](gallery) | Terminal+Web | Primary component workbench: tabs, controls, palette, text input, scroll commands, charts, images, animated GIFs, file drop, popovers, and logo-breaker physics | `swiftly run swift run --package-path gallery gallery-demo` |
| [layouts](layouts) | Terminal | SwiftTUI layout catalog with behavior tests for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | `swiftly run swift run --package-path layouts layouts-demo` |
| [LayoutsSwiftUI](LayoutsSwiftUI) | Native SwiftUI | Native SwiftUI layout catalog beside the embedded SwiftTUI catalog through `SwiftUIHost` | `swiftly run swift run --package-path LayoutsSwiftUI layouts-swiftui-demo` |
| [AndroidGallery](AndroidGallery) | Android | Compose host app embedding the SwiftTUI gallery through `SwiftTUIAndroidHost` and the Swift Android SDK | `(cd AndroidGallery && ./gradlew :app:assembleDebug)` |
| [file-previewer](file-previewer) | Terminal | Miller-column browser and file previews through `SwiftTUITerminal` / `TerminalProcessSession` | `swiftly run swift run --package-path file-previewer FilePreviewerApp` |
| [terminal-workspace](terminal-workspace) | Terminal | First-party `SwiftTUITerminalWorkspace` surface: tabs, splits, retained sessions, command-palette actions, and persisted layout metadata | `swiftly run swift run --package-path terminal-workspace terminal-workspace` |
| [gitviz](gitviz) | CLI | `SwiftTUICharts` over real git data, with a command for every chart primitive | `swiftly run swift run --package-path gitviz gitviz dashboard --path .` |
| [gifcat](gifcat) | Terminal | `SwiftTUIAnimatedImage` playback, source GIF delays, regular-size image attachments, and row-major tiling of multiple GIFs | `swiftly run swift run --package-path gifcat gifcat nyan.gif` |
| [gifeditor](gifeditor) | Terminal+Web | Full GIF editor: half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, and GIF import/export | `swiftly run swift run --package-path gifeditor gifeditor` |
| [SwiftUIExample](SwiftUIExample) | Native SwiftUI | SwiftUI host app embedding reusable SwiftTUI scenes through `SwiftUIHost` | `open SwiftUIExample/SwiftUIExample.xcodeproj` |
| [three-hosts-demo](three-hosts-demo) | Multi-host | The same `CounterApp` value runs as a terminal executable, embeds in a native SwiftUI window via `SwiftUIHost`, and ships as a static WASI bundle in the browser | `swiftly run swift run --package-path three-hosts-demo three-hosts-demo` |
| [WebHostExample](WebHostExample) | Terminal+Web | Smallest `SwiftTUI` convenience app: terminal by default, localhost browser host with `--web` | `swiftly run swift run --package-path WebHostExample WebHostExample --web` |
| [WebExample](WebExample) | Web-WASI | Static browser deployment using `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build`, and a Bun-served host shell | `bun --cwd WebExample dev` |

## By product

Already know the package you need? Jump straight to an example that uses it.

| Product or package | Examples |
| --- | --- |
| `SwiftTUI` convenience surface | [argparse](argparse), [gallery](gallery), [layouts](layouts), [file-previewer](file-previewer), [terminal-workspace](terminal-workspace), [gifcat](gifcat), [gifeditor](gifeditor), [WebHostExample](WebHostExample) |
| `SwiftTUIRuntime` / host-managed scenes | [gallery](gallery), [three-hosts-demo](three-hosts-demo), [WebExample](WebExample) |
| `SwiftTUICLI` / one-shot rendering and terminal launch | [minimal](minimal), [terminal-runner](terminal-runner), [gitviz](gitviz) |
| `SwiftTUIArguments` / `SwiftTUICommand` | [argparse](argparse), [gallery](gallery), [gifeditor](gifeditor), [gitviz](gitviz) |
| `SwiftTUICharts` (separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package) | [gitviz](gitviz), [gallery](gallery), [layouts](layouts) |
| `SwiftTUIAnimatedImage` | Included by `SwiftTUI`; used directly by [gifcat](gifcat), [gallery](gallery) |
| `SwiftTUITerminal` | [file-previewer](file-previewer) |
| `SwiftTUITerminalWorkspace` | [terminal-workspace](terminal-workspace) |
| `SwiftUIHost` | [SwiftUIExample](SwiftUIExample), [three-hosts-demo](three-hosts-demo) |
| `SwiftTUIAndroidHost` | [AndroidGallery](AndroidGallery) |
| `SwiftTUIWebHostCLI` | Included by `SwiftTUI`; used directly by [gifeditor](gifeditor) |
| `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build` | [WebExample](WebExample) |

The full coverage matrix, category definitions, gate contract, and new-example
checklist live in [docs/EXAMPLE-COVERAGE.md](docs/EXAMPLE-COVERAGE.md). For the
authored APIs behind these demos, read the
[DocC reference](https://swifttui.sh/docs/documentation/).

## Tests

Run the full focused behavior-test lane with `bun run check:focused`, or test one
example with `swiftly run swift test --package-path <example>`. Examples without
focused suites are still build-checked by the repo gates. For the build/gate
lanes (`check:linux`, `check:macos`, `check:web`, `check`) and their
scratch-directory environment variables, see [`AGENTS.md`](AGENTS.md).

## License

MIT — see [LICENSE](LICENSE).
