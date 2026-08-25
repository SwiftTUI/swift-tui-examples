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
| [minimal](../minimal) | Copyable tutorial | `SwiftTUICLI` | One-shot `RenderOnce.print(...)` rendering | Terminal CLI, no app runtime | Linux framework-seam gate builds debug (release on tags) |
| [equatable-demo](../equatable-demo) | Copyable tutorial | `SwiftTUICLI` | `View.equatable()` memoized-body reuse: a stable panel reused across frames while a `@State` counter updates | Terminal app | Linux framework-seam gate builds debug (release on tags) |
| [argparse](../argparse) | Copyable tutorial | `SwiftTUI` | `SwiftTUI.App` command conformance, app flags, standard SwiftTUI flags, completions | Terminal CLI app | Linux framework-seam gate builds debug (release on tags) |
| [gallery](../gallery) | Focused product sample and stress/regression sample | `SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUIAnimatedImage`, `SwiftTUICharts` | Batteries-included terminal/WebHost launch and component workbench for tabs, controls, containers, presentation, navigation, collections, palette, input, focus context, pointer gestures, accessibility metadata, scrolling, charts, images, GIFs, file drop, popovers, a paged animation workbench (basics, transitions, matched geometry, keyframes, transactions), and logo-breaker physics | Terminal app plus optional localhost WebHost | Linux framework-seam gate builds debug (release on tags), runs stack-safety smoke checks, and runs the gallery suite. |
| [layouts](../layouts) | Focused product sample and stress/regression sample | `SwiftTUI`, `SwiftTUIRuntime`, `SwiftTUICharts` | Layout catalog for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | Terminal app | Linux framework-seam gate builds debug (release on tags). `LayoutsTests` is opt-in (`SWIFTTUI_EXAMPLES_LAYOUTS_TESTS=1`) until its raster expectations are repaired against the current framework. |
| [LayoutsSwiftUI](../LayoutsSwiftUI) | Host/build configuration sample | `SwiftTUIRuntime`, `SwiftUIHost`, `Layouts` | Native SwiftUI comparison app for the `layouts` catalog | Native Apple app via SwiftPM executable | macOS native gate builds the package |
| [AndroidGallery](../AndroidGallery) | Host/build configuration sample | `SwiftTUIAndroidHost`, `SwiftTUIRuntime`, `GalleryDemoViews` | Native Android Compose app embedding the reusable SwiftTUI gallery scene with styled raster cells, image payloads, accessibility semantics, and basic input bridging | Android app via Gradle/Swift Android SDK, `arm64-v8a` only | Manual local gate: `./gradlew :app:assembleDebug`. Emulator smoke remains local-only. |
| [sextant](../sextant) | Focused product sample | `SwiftTUI`, `SwiftTUITerminal` | Miller-column browser and embedded terminal process previews | Terminal app plus child processes | Linux framework-seam gate builds debug (release on tags). App-logic suite runs in `check:focused` when the package changes and on tags. |
| [terminal-workspace](../terminal-workspace) | Focused product sample | `SwiftTUI`, `SwiftTUITerminal` (through the example-owned `TerminalWorkspace` module) | Tabs, splits, retained sessions, command palette actions, persisted workspace metadata | Terminal workspace app | Linux framework-seam gate builds debug (release on tags). App-logic suite runs in `check:focused` when the package changes and on tags. |
| [mrkdwn](../mrkdwn) | Advanced app and focused product sample | `SwiftTUI`, `Markdown`, vendored `MrkdwnMermaid` | Complete CommonMark/GFM compilation, responsive outline/search/navigation, XDG TOML theming, bounded images, and Unicode semantic-cell Mermaid rendering | Terminal app on macOS and Linux | Linux and macOS gates build debug (release on tags) and run the framework suites (view contracts, viewer model, PTY journeys); the compiler/links/theme/watcher suites run in `check:focused`. |
| [csvui](../csvui) | Advanced app, focused product sample, and stress/regression sample | `SwiftTUI` | Lazy byte-indexed CSV/TSV viewing, sparse edits and bounded history, search/filter/sort projections, XDG TOML theming, live reload, conflict detection, and atomic saves | Terminal app on macOS and Linux | Linux and macOS gates build debug (release on tags) and run the view-contract and rebuilt real-PTY journey suites; the CSV core suites run in `check:focused`. |
| [git-viz](../git-viz) | Copyable tutorial and focused product sample | `SwiftTUI`, `SwiftTUICLI`, `SwiftTUICharts` | Non-interactive git reporting and chart primitives | Terminal CLI report generator | Linux framework-seam gate builds debug (release on tags). App-logic suite runs in `check:focused` when the package changes and on tags. |
| [gifcat](../gifcat) | Copyable tutorial and focused product sample | `SwiftTUI`, `SwiftTUIAnimatedImage` | GIF playback, source delays, image attachments, row-major tiling | Terminal app | Linux framework-seam gate builds debug (release on tags) and runs the gifcat suite. |
| [gifeditor](../gifeditor) | Advanced app and stress/regression sample | `SwiftTUI`, `SwiftTUIWebHostCLI`, `GIFEditorCore`, `GIFEditorUI` | Half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, GIF import/export | Terminal app plus optional localhost WebHost | Linux framework-seam gate builds debug (release on tags). App-logic suite runs in `check:focused` when the package changes and on tags. |
| [SwiftUIExample](../SwiftUIExample) | Host/build configuration sample | `SwiftUIHost`, `SwiftTUI`, `GalleryDemoViews` | Native SwiftUI app embedding reusable SwiftTUI scenes | Xcode macOS app plus terminal package | Linux native gate builds the terminal package. The macOS native gate builds the terminal package and Xcode app. |
| [WebHostExample](../WebHostExample) | Copyable tutorial and host/build configuration sample | `SwiftTUI` convenience host | Smallest app that runs in the terminal by default and localhost browser host with `--web` | Terminal app plus localhost WebHost | Linux framework-seam gate builds the package and runs its suite. |

`SharedHostScenes` is a support package, not a runnable example. It contains the
host-details scene UI that `SwiftUIExample` uses. The multi-host counter demo
(terminal + native SwiftUI + browser/WASI) lives in its own repo:
[`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo).

## Gate Contract

- `bun run check` is the build-first gate for the full example matrix from a
  local macOS checkout. It delegates to the Linux-compatible SwiftPM lane and
  the macOS native lane.
- `bun run check:linux` is the Linux framework-seam gate and the push/PR CI
  lane. It builds every CLI, terminal, shared-scene, and localhost WebHost
  package in debug and runs the suites that exercise SwiftTUI behaviour:
  `WebHostExample`, `mrkdwn` (terminal lease and performance envelope, PTY
  journeys, and — last, because it parks at the 0.9.9 pin and pays the
  watchdog's bound — view contracts and viewer model),
  `csvui` (view contracts, PTY journeys), `gallery`, and `gifcat`. Pass
  `--release-builds` (`bun run check:release`) for the release configuration
  and the release stack-safety run; CI does that on release tags.
- `bun run check:macos` is the native Apple host gate (dispatch and tags in
  CI). It builds the SwiftUI terminal package, the `LayoutsSwiftUI` comparison
  package, and the Xcode macOS app with code signing disabled for CI.
- `bun run check:focused` is the app-logic lane: the examples' own domain
  suites — `gifeditor`, `sextant`, `git-viz`, `terminal-workspace`, and the
  `mrkdwn`/`csvui` suites the framework-seam gate does not run. CI runs one
  matrix job per package when that package changes, on dispatch, and on tags
  (`--package <name>` selects one). The two lanes read one suite partition,
  `Scripts/lib/example_suites.sh`.
- The six-hourly `Framework HEAD seam` workflow runs `check:linux` against the
  `main` branches of swift-tui and swift-tui-charts through
  `Scripts/localize_siblings.sh`, skipping itself when none of its inputs
  moved since the last green run.
- Every gate step runs under `Scripts/lib/step_watchdog.sh`: a step silent
  for the bound (600 s builds, 300 s tests; 600 s on the slower macOS lane)
  is dumped and killed; the gate records it and continues, and aborts on a
  second one.
- The gates share sequential SwiftPM scratch state through
  `SWIFTTUI_EXAMPLES_SWIFTPM_SCRATCH`, and the macOS lane isolates Xcode
  derived data through `SWIFTTUI_EXAMPLES_XCODE_DERIVED_DATA`. Both default to
  in-repo scratch paths; override them only to relocate scratch storage.

## New Example Checklist

- Add the example to the README roster.
- Describe what the example proves in one sentence.
- Add one command that runs the example.
- Add a row to the coverage matrix with category, product surface, feature
  surface, host/build mode, and gate status.
- If the matrix does not mark the example as manual-only, add the package to
  `Scripts/check_examples.sh`.
- If the example owns behavior that must not regress, add focused tests. Put
  suites that exercise SwiftTUI behaviour in `Scripts/check_examples.sh`
  (framework seam, every push) and the example's own domain suites in
  `Scripts/check_examples_focused_tests.sh` (app-logic lane); a package that
  has both splits them in `Scripts/lib/example_suites.sh`.
- If the example is an advanced app, add or update README "what to copy"
  guidance.

## Current Gaps

- Pointer hover still needs first-class coverage when a public hover API lands.

## Keep / Fold Decisions

- Keep `gifcat` as the tiny direct `SwiftTUIAnimatedImage` reference. The
  gallery covers image playback in a broad component workbench, while
  `gifeditor` is an advanced app. `gifcat` remains the copyable animated-image
  package with direct tests.
