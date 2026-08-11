# SwiftUI Example

> Embed live SwiftTUI scenes inside an ordinary SwiftUI app so the same terminal-style UI runs unchanged on a desktop, proof that the framework reaches beyond the terminal. Its canonical host is a native SwiftUI surface (macOS app via `SwiftUIHost`).

## Run

```bash
open SwiftUIExample/SwiftUIExample.xcodeproj
```

Run the `SwiftUIExample` scheme from Xcode. To build the reusable scene package
without Xcode, run:

```bash
swiftly run swift build --package-path SwiftUIExample/TerminalApp
```

## Project generation

[`project.yml`](project.yml) is the source of truth for the Xcode project.
[XcodeGen](https://github.com/yonaskolb/XcodeGen) generates
`SwiftUIExample.xcodeproj` from it. The generated project stays checked in, so
building and running this example needs Xcode only. XcodeGen is required to
change the project, not to use it.

Regenerate after you edit `project.yml`, or after you add, remove, or rename a
file under `SwiftUIExample/`. The spec lists sources at generation time, so a
new file reaches the target only after a regenerate:

```bash
cd SwiftUIExample && xcodegen generate
```

The spec declares a minimum XcodeGen version of 2.45.0. Different versions can
emit a different project from the same spec, so keep the regenerated project in
the same commit as the spec change and review the diff.

Commit the regenerated project with your change. Do not hand-edit
`project.pbxproj`. The next regenerate discards the edit.

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

- [swift-tui-counter-demo](https://github.com/SwiftTUI/swift-tui-counter-demo): the shared counter scene deployed to a browser/WASI surface (own repo).
- [DocC reference](https://swifttui.sh/docs/documentation/): the full `SwiftUIHost` and `SwiftTUIRuntime` API surface.
