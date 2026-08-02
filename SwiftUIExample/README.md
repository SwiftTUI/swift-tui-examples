# SwiftUI Example

> Embed live SwiftTUI scenes inside an ordinary SwiftUI app so the same terminal-style UI runs unchanged on a desktop — proving the framework reaches beyond the terminal. Its canonical host is a native SwiftUI surface (macOS app via `SwiftUIHost`).

## Run

```bash
open SwiftUIExample/SwiftUIExample.xcodeproj
```

Run the app scheme from Xcode. To build the reusable scene package without
Xcode, run:

```bash
swiftly run swift build --package-path SwiftUIExample/TerminalApp
```

## Demonstrates

- `SwiftUIHost` provides `SwiftUIHostAppView`. This view embeds a SwiftTUI scene in a native SwiftUI view
  hierarchy. The scene uses the standard SwiftUI app lifecycle.
- A separate Swift package, `TerminalApp`, contains reusable SwiftTUI scenes.
  Multiple hosts consume the same scene code.
- The Apple app hosts the shared `GalleryDemoViews` surface. Thus, it renders
  the terminal component gallery natively.
- A component-gallery scene and a details scene demonstrate multi-scene
  authoring. A host app can compose multiple SwiftTUI surfaces.

## Architecture

The Xcode project owns the native app shell. `TerminalApp/` is a local Swift
package. Its `ExampleScenes` library defines the reusable SwiftTUI scenes,
including the component-gallery views. The SwiftUI app embeds these scenes with
`SwiftUIHostAppView`. `ExampleScenes` depends on `GalleryDemoViews`,
`SharedHostScenes`, and `SwiftTUIRuntime`. The embedded host uses the runtime
instead of the `SwiftTUI` umbrella. Thus, the iOS build does not include host
code that it cannot use.

## Test

The package has no test target. The `gallery` package tests the shared gallery
views. The
`SwiftUIHost` suite in `swift-tui-swiftui` tests the host product.

## See also

- [WebExample](../WebExample/README.md) — the same scenes deployed to a browser/WASI surface.
- [DocC reference](https://swifttui.sh/docs/documentation/) — the full `SwiftUIHost` and `SwiftTUIRuntime` API surface.
