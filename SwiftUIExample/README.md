# SwiftUI Example

> Embed live SwiftTUI scenes inside an ordinary SwiftUI app so the same terminal-style UI runs unchanged on a desktop — proving the framework reaches beyond the terminal. Its canonical host is a native SwiftUI surface (macOS app via `SwiftUIHost`).

## Run

```bash
open SwiftUIExample/SwiftUIExample.xcodeproj
```

Then run the app scheme from Xcode. The reusable scene package also builds headless, without opening Xcode:

```bash
swiftly run swift build --package-path SwiftUIExample/TerminalApp
```

## Demonstrates

- `SwiftUIHost` (`SwiftUIHostAppView`) — which means you can drop a SwiftTUI scene into a native SwiftUI view hierarchy and run it in the standard SwiftUI app lifecycle.
- Reusing SwiftTUI scenes from a separate Swift package (`TerminalApp`) — which means the same scene code is authored once and consumed by multiple hosts.
- Hosting the shared `GalleryDemoViews` surface natively — which means the terminal component gallery renders identically inside the Apple app.
- Multi-scene authoring through a component-gallery scene and a details scene — which means a host app can compose more than one embedded SwiftTUI surface.

## Architecture

The Xcode project owns the native app shell. `TerminalApp/` is a local Swift package whose `ExampleScenes` library defines the reusable SwiftTUI scenes (including the component-gallery views), and the SwiftUI app embeds those scenes with `SwiftUIHostAppView`. `ExampleScenes` depends on `GalleryDemoViews`, `SharedHostScenes`, and `SwiftTUIRuntime` (the embedded host pulls the runtime, never the `SwiftTUI` umbrella, to keep the iOS build clean).

## Test

No test target. The shared gallery views are tested by `gallery`, and the host product is tested in the `swift-tui-swiftui` package's `SwiftUIHost` suite.

## See also

- [WebExample](../WebExample/README.md) — the same scenes deployed to a browser/WASI surface.
- [DocC reference](https://swifttui.sh/docs/documentation/) — the full `SwiftUIHost` and `SwiftTUIRuntime` API surface.
