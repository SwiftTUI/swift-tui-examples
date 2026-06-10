# SwiftTUI Example Coverage

This matrix is the maintenance contract for the example repo. Each example
should have a clear product surface, host/build mode, gate status, and audience.
If an example is not built by an automated gate, mark it manual-only here and
explain why.

## Example Categories

- Copyable tutorial: small, canonical code that users can paste into their own
  app.
- Focused product sample: demonstrates one product or feature family with
  realistic structure.
- Advanced app: larger application code that proves framework capability but is
  not intended to be copied wholesale.
- Stress/regression sample: keeps historically fragile behavior visible through
  tests or smoke runs.
- Host/build configuration sample: proves a deployment or embedding mode.

## Coverage Matrix

| Example | Category | Products | Feature surface | Host/build mode | Gate status |
| --- | --- | --- | --- | --- | --- |
| [minimal](../minimal) | Copyable tutorial | `SwiftTUICLI` | One-shot `RenderOnce.print(...)` rendering | Terminal CLI, no app runtime | Linux native gate builds debug and release |
| [terminal-runner](../terminal-runner) | Copyable tutorial; host/build configuration sample | `SwiftTUICLI` | Explicit `TerminalRunner` launch, environment-derived runtime configuration, and terminal-only `--web` rejection | Terminal app, no WebHost fallback | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [argparse](../argparse) | Copyable tutorial | `SwiftTUI` | `SwiftTUI.App` command conformance, app flags, standard SwiftTUI flags, completions | Terminal CLI app | Linux native gate builds debug and release |
| [gallery](../gallery) | Focused product sample; stress/regression sample | `SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUIAnimatedImage`, `SwiftTUICharts` | Batteries-included terminal/WebHost launch and component workbench for tabs, controls, containers, presentation, navigation, collections, palette, input, focus context, pointer gestures, accessibility metadata, scrolling, charts, images, GIFs, file drop, popovers, and physics | Terminal app plus optional localhost WebHost | Linux native gate builds debug and release, stack-safety smoke runs; focused SwiftPM tests in `check:focused` |
| [layouts](../layouts) | Focused product sample; stress/regression sample | `SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUICharts` | Layout catalog for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | Terminal app | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [LayoutsSwiftUI](../LayoutsSwiftUI) | Host/build configuration sample | `SwiftTUIRuntime`, `SwiftUIHost`, `Layouts` | Native SwiftUI comparison app for the `layouts` catalog | Native Apple app via SwiftPM executable | macOS native gate builds the package |
| [AndroidGallery](../AndroidGallery) | Host/build configuration sample | `SwiftTUIAndroidHost`, `SwiftTUIRuntime`, `GalleryDemoViews` | Native Android Compose app embedding the reusable SwiftTUI gallery scene with styled raster cells, image payloads, accessibility semantics, and basic input bridging | Android app via Gradle/Swift Android SDK, `arm64-v8a` only | Manual local gate: `./gradlew :app:assembleDebug`; emulator smoke remains local-only |
| [file-previewer](../file-previewer) | Focused product sample | `SwiftTUI`, `SwiftTUITerminal` | Miller-column browser and embedded terminal process previews | Terminal app plus child processes | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [terminal-workspace](../terminal-workspace) | Focused product sample | `SwiftTUI`, `SwiftTUITerminalWorkspace` | Tabs, splits, retained sessions, command palette actions, persisted workspace metadata | Terminal workspace app | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [gitviz](../gitviz) | Copyable tutorial; focused product sample | `SwiftTUI`, `SwiftTUICLI`, `SwiftTUICharts` | Non-interactive git reporting and chart primitives | Terminal CLI report generator | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [gifcat](../gifcat) | Copyable tutorial; focused product sample | `SwiftTUI`, `SwiftTUIAnimatedImage` | GIF playback, source delays, image attachments, row-major tiling | Terminal app | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [gifeditor](../gifeditor) | Advanced app; stress/regression sample | `SwiftTUI`, `SwiftTUIWebHostCLI`, `GIFEditorCore`, `GIFEditorUI` | Half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, GIF import/export | Terminal app plus optional localhost WebHost | Linux native gate builds debug and release; focused SwiftPM tests in `check:focused` |
| [SwiftUIExample](../SwiftUIExample) | Host/build configuration sample | `SwiftUIHost`, `SwiftTUI`, `GalleryDemoViews` | Native SwiftUI app embedding reusable SwiftTUI scenes | Xcode macOS app plus terminal package | Linux native gate builds terminal package; macOS native gate builds terminal package and Xcode app |
| [WebHostExample](../WebHostExample) | Copyable tutorial; host/build configuration sample | `SwiftTUI` convenience host | Smallest app that runs in the terminal by default and localhost browser host with `--web` | Terminal app plus localhost WebHost | Linux native gate builds package and runs smoke tests; focused SwiftPM tests in `check:focused` |
| [WebExample](../WebExample) | Host/build configuration sample | `SwiftTUIWASI`, `SwiftTUIRuntime`, `@swifttui/web`, `@swifttui/build` | Static browser deployment through WASI and Bun-hosted shell | Browser/WASI app plus reusable terminal scene package | Linux native gate builds terminal package; web gate builds browser app and web host; focused Bun tests in `check:focused` |

`SharedHostScenes` is a support package, not a runnable example. It holds host
details scene UI reused by `SwiftUIExample` and `WebExample` so those host
configuration examples share tutorial code where their scene sets overlap.

## Gate Contract

- `bun run check`: build-first gate for the full example matrix from a local
  macOS checkout. It delegates to the Linux-compatible SwiftPM lane, the macOS
  native lane, and the browser/WASI lane.
- `bun run check:linux`: Linux-compatible SwiftPM build gate. It builds CLI,
  terminal, shared-scene, and localhost WebHost packages that do not require
  native Apple app tooling.
- `bun run check:macos`: native Apple host gate. It builds the SwiftUI terminal
  package, the `LayoutsSwiftUI` comparison package, and the Xcode macOS app with
  code signing disabled for CI.
- `bun run check:web`: browser/WASI build gate for `WebExample` and the
  `swift-tui-web` host package.
- `bun run check:focused`: slower behavior-test gate for examples with real test
  targets: `gallery`, `layouts`, `gifeditor`, `gitviz`, `file-previewer`,
  `terminal-runner`, `gifcat`, `terminal-workspace`, `WebHostExample`, and
  `WebExample`.

## New Example Checklist

- Add the example to the README roster with one sentence that says what it
  proves and one command that runs it.
- Add a row to the coverage matrix with category, product surface, feature
  surface, host/build mode, and gate status.
- Add the package to `Scripts/check_examples.sh` unless it is explicitly
  manual-only in the matrix.
- Add focused tests and include them in
  `Scripts/check_examples_focused_tests.sh` when the example owns behavior that
  should not regress silently.
- Add or update README "what to copy" guidance when the example is advanced app
  code rather than tutorial code.

## Current Gaps

- Pointer hover still needs first-class coverage when a public hover API lands.

## Keep / Fold Decisions

- Keep `gifcat` as the tiny direct `SwiftTUIAnimatedImage` reference. The
  gallery covers image playback in a broad component workbench, while
  `gifeditor` is an advanced app; `gifcat` remains the copyable animated-image
  package with direct tests.
