# SwiftTUI Examples

Runnable examples for
[`SwiftTUI`](https://github.com/SwiftTUI/swift-tui). Use this repo to find a
complete sample for a product surface, execution mode, or host integration
pattern.

Use `swiftly run swift ...` for Swift packages so the examples use the repo's
pinned Swift toolchain. Use the repo root for the commands below unless a local
README says otherwise.

## Quick Start

```bash
git clone https://github.com/SwiftTUI/swift-tui-examples.git
cd swift-tui-examples
swiftly run swift run --package-path argparse argparse-demo --help
swiftly run swift run --package-path gallery gallery-demo
```

For the browser/WASI example:

```bash
bun install
bun --cwd WebExample run build
```

Pre-public status: these examples still use source-checkout dependencies for
active development. The public release cutover will switch the default manifests
to tagged `https://github.com/SwiftTUI/swift-tui.git` SwiftPM dependencies and
published `@swifttui/web` / `@swifttui/build` packages so a fresh clone builds
without sibling checkouts.

## Roster

| Example | Surface | What it proves | Run |
| --- | --- | --- | --- |
| [minimal](minimal) | One-shot renderer | Smallest `RenderOnce.print(...)` path for report-like CLI output, with no app runtime or argument parser | `swiftly run swift run --package-path minimal minimal` |
| [terminal-runner](terminal-runner) | Terminal-only runner | Explicit `TerminalRunner` launch with custom preflight policy that rejects `--web` | `swiftly run swift run --package-path terminal-runner terminal-runner` |
| [argparse](argparse) | Terminal app CLI | `SwiftTUI.App` command conformance, consumer flags, standard SwiftTUI flags, and completions in one app type | `swiftly run swift run --package-path argparse argparse-demo --help` |
| [gallery](gallery) | Batteries-included terminal app plus optional WebHost | Primary component workbench for the public view surface: tabs, controls, palette, text input, scroll commands, charts, images, animated GIFs, file drop, popovers, and physics | `swiftly run swift run --package-path gallery gallery-demo` |
| [layouts](layouts) | Terminal app | SwiftTUI layout catalog with behavior tests for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | `swiftly run swift run --package-path layouts layouts-demo` |
| [LayoutsSwiftUI](LayoutsSwiftUI) | SwiftUI comparison app | Native SwiftUI layout catalog beside the embedded SwiftTUI catalog through `SwiftUIHost` | `swiftly run swift run --package-path LayoutsSwiftUI layouts-swiftui-demo` |
| [file-previewer](file-previewer) | Terminal app plus embedded processes | Miller-column browser and file previews through `SwiftTUITerminal` / `TerminalProcessSession` | `swiftly run swift run --package-path file-previewer FilePreviewerApp` |
| [terminal-workspace](terminal-workspace) | Terminal workspace | First-party `SwiftTUITerminalWorkspace` surface: tabs, splits, retained sessions, command palette actions, and persisted layout metadata | `swiftly run swift run --package-path terminal-workspace terminal-workspace` |
| [gitviz](gitviz) | Non-interactive CLI | `SwiftTUICharts` over real git data, with one or more commands for every chart primitive | `swiftly run swift run --package-path gitviz gitviz dashboard --path .` |
| [gifcat](gifcat) | Terminal app | `SwiftTUIAnimatedImage` playback, source GIF delays, regular-size image attachments, and row-major tiling of multiple GIFs | `swiftly run swift run --package-path gifcat gifcat nyan.gif` |
| [gifeditor](gifeditor) | Terminal app plus optional WebHost | Full GIF editor: half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, and GIF import/export | `swiftly run swift run --package-path gifeditor gifeditor` |
| [SwiftUIExample](SwiftUIExample) | Native Apple app | SwiftUI host app embedding reusable SwiftTUI scenes through `SwiftUIHost` | `open SwiftUIExample/SwiftUIExample.xcodeproj` |
| [WebHostExample](WebHostExample) | Localhost browser host | Smallest `SwiftTUI` convenience app showing terminal by default and browser host with `--web` | `swiftly run swift run --package-path WebHostExample WebHostExample --web` |
| [WebExample](WebExample) | Static browser/WASI app | Browser deployment using `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build`, and a Bun-served host shell | `bun --cwd WebExample dev` |

## By Product

| Product or package | Examples |
| --- | --- |
| `SwiftTUI` convenience surface | [argparse](argparse), [gallery](gallery), [layouts](layouts), [file-previewer](file-previewer), [terminal-workspace](terminal-workspace), [gifcat](gifcat), [gifeditor](gifeditor), [WebHostExample](WebHostExample) |
| `SwiftTUIRuntime` / host-managed scenes | [gallery](gallery), [WebExample](WebExample) |
| `SwiftTUICLI` / one-shot rendering and terminal launch | [minimal](minimal), [terminal-runner](terminal-runner), [gitviz](gitviz) |
| `SwiftTUIArguments` / `SwiftTUICommand` | [argparse](argparse), [gallery](gallery), [gifeditor](gifeditor), [gitviz](gitviz) |
| `SwiftTUICharts` | [gitviz](gitviz), [gallery](gallery), [layouts](layouts) |
| `SwiftTUIAnimatedImage` | Included by `SwiftTUI`; used directly by [gifcat](gifcat), [gallery](gallery) |
| `SwiftTUITerminal` | [file-previewer](file-previewer) |
| `SwiftTUITerminalWorkspace` | [terminal-workspace](terminal-workspace) |
| `SwiftUIHost` | [SwiftUIExample](SwiftUIExample) |
| `SwiftTUIWebHostCLI` | Included by `SwiftTUI`; used directly by [gifeditor](gifeditor) |
| `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build` | [WebExample](WebExample) |

The detailed coverage matrix, category definitions, gate contract, and new
example checklist live in [docs/EXAMPLE-COVERAGE.md](docs/EXAMPLE-COVERAGE.md).

## Focused Tests

Run the full focused behavior-test lane with:

```bash
bun run check:focused
```

Or run individual focused test suites directly:

```bash
swiftly run swift test --package-path file-previewer
swiftly run swift test --package-path terminal-runner
swiftly run swift test --package-path gallery
swiftly run swift test --package-path gifcat
swiftly run swift test --package-path gifeditor
swiftly run swift test --package-path gitviz
swiftly run swift test --package-path layouts
swiftly run swift test --package-path terminal-workspace
swiftly run swift test --package-path WebHostExample
bun test --cwd WebExample
```

Examples without focused test targets are still covered by the repo gates.
`bun run check:linux` runs the Linux-compatible SwiftPM builds serially,
`bun run check:macos` runs the native Apple example lane, and
`bun run check:web` runs the browser/WASI packaging lane. `bun run check` runs
all lanes from one local macOS checkout.

`SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH` can point the gate at one sequential shared
SwiftPM scratch directory. This is useful for maintainers running the full
matrix repeatedly; do not share the same scratch directory across parallel
checks. `SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA` can point the macOS lane at a
reusable DerivedData directory for the Xcode app build.
