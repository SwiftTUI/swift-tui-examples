# SwiftTUI Example Coverage

This matrix is the maintenance contract for the example repository. Each
example must have a clear product surface, host/build mode, gate status, and
audience.
If an example is not built by an automated gate, mark it manual-only here and
explain why. `SwiftTUICharts` resolves from the separate
[`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package, and
`mrkdwn` vendors its terminal Mermaid renderer as the internal `MrkdwnMermaid`
target. Every other SwiftTUI product resolves from `swift-tui`.

## Example Categories

- A copyable tutorial contains small, canonical code that users can paste into
  an app.
- A focused product sample demonstrates one product or feature family with a
  realistic structure.
- An advanced app contains larger application code that demonstrates framework
  capabilities. Do not copy the complete app as a tutorial.
- A stress or regression sample keeps fragile behavior visible through tests or
  smoke runs.
- A host or build configuration sample demonstrates a deployment or embedding
  mode.

## Coverage Matrix

| Example | Category | Products | Feature surface | Host/build mode | Gate status |
| --- | --- | --- | --- | --- | --- |
| [minimal](../minimal) | Copyable tutorial | `SwiftTUICLI` | One-shot `RenderOnce.print(...)` rendering | Terminal CLI, no app runtime | Linux native gate builds debug and release |
| [equatable-demo](../equatable-demo) | Copyable tutorial | `SwiftTUICLI` | `View.equatable()` memoized-body reuse: a stable panel reused across frames while a `@State` counter updates | Terminal app | Linux native gate builds debug and release |
| [terminal-runner](../terminal-runner) | Copyable tutorial and host/build configuration sample | `SwiftTUICLI` | Explicit `TerminalRunner` launch, environment-derived runtime configuration, and terminal-only `--web` rejection | Terminal app, no WebHost fallback | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [argparse](../argparse) | Copyable tutorial | `SwiftTUI` | `SwiftTUI.App` command conformance, app flags, standard SwiftTUI flags, completions | Terminal CLI app | Linux native gate builds debug and release |
| [gallery](../gallery) | Focused product sample and stress/regression sample | `SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUIAnimatedImage`, `SwiftTUICharts` | Batteries-included terminal/WebHost launch and component workbench for tabs, controls, containers, presentation, navigation, collections, palette, input, focus context, pointer gestures, accessibility metadata, scrolling, charts, images, GIFs, file drop, popovers, and logo-breaker physics | Terminal app plus optional localhost WebHost | Linux native gate builds debug and release and runs stack-safety smoke checks. Focused SwiftPM tests run in `check:focused`. |
| [layouts](../layouts) | Focused product sample and stress/regression sample | `SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUICharts` | Layout catalog for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | Terminal app | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [LayoutsSwiftUI](../LayoutsSwiftUI) | Host/build configuration sample | `SwiftTUIRuntime`, `SwiftUIHost`, `Layouts` | Native SwiftUI comparison app for the `layouts` catalog | Native Apple app via SwiftPM executable | macOS native gate builds the package |
| [AndroidGallery](../AndroidGallery) | Host/build configuration sample | `SwiftTUIAndroidHost`, `SwiftTUIRuntime`, `GalleryDemoViews` | Native Android Compose app embedding the reusable SwiftTUI gallery scene with styled raster cells, image payloads, accessibility semantics, and basic input bridging | Android app via Gradle/Swift Android SDK, `arm64-v8a` only | Manual local gate: `./gradlew :app:assembleDebug`. Emulator smoke remains local-only. |
| [sextant](../sextant) | Focused product sample | `SwiftTUI`, `SwiftTUITerminal` | Miller-column browser and embedded terminal process previews | Terminal app plus child processes | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [terminal-workspace](../terminal-workspace) | Focused product sample | `SwiftTUI`, `SwiftTUITerminalWorkspace` | Tabs, splits, retained sessions, command palette actions, persisted workspace metadata | Terminal workspace app | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [mrkdwn](../mrkdwn) | Advanced app and focused product sample | `SwiftTUI`, `Markdown`, vendored `MrkdwnMermaid` | Complete CommonMark/GFM compilation, responsive outline/search/navigation, XDG TOML theming, bounded images, and Unicode semantic-cell Mermaid rendering | Terminal app on macOS and Linux | Linux and macOS gates clean and build debug and release. They also run the focused SwiftPM suite in `check:focused`. |
| [git-viz](../git-viz) | Copyable tutorial and focused product sample | `SwiftTUI`, `SwiftTUICLI`, `SwiftTUICharts` | Non-interactive git reporting and chart primitives | Terminal CLI report generator | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [gifcat](../gifcat) | Copyable tutorial and focused product sample | `SwiftTUI`, `SwiftTUIAnimatedImage` | GIF playback, source delays, image attachments, row-major tiling | Terminal app | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [gifeditor](../gifeditor) | Advanced app and stress/regression sample | `SwiftTUI`, `SwiftTUIWebHostCLI`, `GIFEditorCore`, `GIFEditorUI` | Half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, GIF import/export | Terminal app plus optional localhost WebHost | Linux native gate builds debug and release. Focused SwiftPM tests run in `check:focused`. |
| [SwiftUIExample](../SwiftUIExample) | Host/build configuration sample | `SwiftUIHost`, `SwiftTUI`, `GalleryDemoViews` | Native SwiftUI app embedding reusable SwiftTUI scenes | Xcode macOS app plus terminal package | Linux native gate builds the terminal package. The macOS native gate builds the terminal package and Xcode app. |
| [WebHostExample](../WebHostExample) | Copyable tutorial and host/build configuration sample | `SwiftTUI` convenience host | Smallest app that runs in the terminal by default and localhost browser host with `--web` | Terminal app plus localhost WebHost | Linux native gate builds the package and runs smoke tests. Focused SwiftPM tests run in `check:focused`. |
| [WebExample](../WebExample) | Host/build configuration sample | `SwiftTUIWASI`, `SwiftTUIRuntime`, `ThreeHostsDemoCore`, `@swifttui/web`, `@swifttui/build` | Static browser deployment of the shared multi-host counter through WASI and a Bun-hosted shell | Single-scene browser/WASI app plus reusable terminal scene package | Linux native gate builds the terminal package. The web gate builds the browser app and web host. Focused Bun tests run in `check:focused`. |

`SharedHostScenes` is a support package, not a runnable example. It contains the
host-details scene UI that `SwiftUIExample` uses. `WebExample` imports the
shared counter from `three-hosts-demo`.

## Gate Contract

- `bun run check` is the build-first gate for the full example matrix from a
  local macOS checkout. It delegates to the Linux-compatible SwiftPM lane, the
  macOS native lane, and the browser/WASI lane.
- `bun run check:linux` is the Linux-compatible SwiftPM build gate. It builds CLI,
  terminal, shared-scene, and localhost WebHost packages that do not require
  native Apple app tooling.
- `bun run check:macos` is the native Apple host gate. It builds the SwiftUI terminal
  package, the `LayoutsSwiftUI` comparison package, and the Xcode macOS app with
  code signing disabled for CI.
- `bun run check:web` is the browser/WASI build gate for `WebExample` and the
  `swift-tui-web` host package.
- `bun run check:focused` is the slower behavior-test gate for examples with test
  targets: `gallery`, `layouts`, `gifeditor`, `git-viz`, `sextant`,
  `terminal-runner`, `gifcat`, `terminal-workspace`, `mrkdwn`,
  `WebHostExample`, and `WebExample`.

## New Example Checklist

- Add the example to the README roster.
- Describe what the example proves in one sentence.
- Add one command that runs the example.
- Add a row to the coverage matrix with category, product surface, feature
  surface, host/build mode, and gate status.
- If the matrix does not mark the example as manual-only, add the package to
  `Scripts/check_examples.sh`.
- If the example owns behavior that must not regress, add focused tests. Then
  add the tests to `Scripts/check_examples_focused_tests.sh`.
- If the example is an advanced app, add or update README "what to copy"
  guidance.

## Current Gaps

- Pointer hover still needs first-class coverage when a public hover API lands.

## Keep / Fold Decisions

- Keep `gifcat` as the tiny direct `SwiftTUIAnimatedImage` reference. The
  gallery covers image playback in a broad component workbench, while
  `gifeditor` is an advanced app. `gifcat` remains the copyable animated-image
  package with direct tests.
