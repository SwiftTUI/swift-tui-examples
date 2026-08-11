# Layouts (SwiftUI)

> An on-brand side-by-side gallery that proves SwiftTUI layout parity: 56 layout shapes rendered as native SwiftUI on the left and the matching SwiftTUI implementation on the right, so a reader can eyeball the two engines against each other. Runs as a native SwiftUI surface, with the SwiftTUI pane embedded via `SwiftUIHost`.

## Run

```bash
swiftly run swift run --package-path LayoutsSwiftUI layouts-swiftui-demo
```

The app opens a sidebar and a comparison detail. When you select a layout, both
panes use the same catalog ID.

## Demonstrates

- `SwiftUIHost` embeds a live SwiftTUI scene in a SwiftUI window. Both engines
  render the same catalog ID side by side.
- A shared layout catalog drives both panes. This catalog is the `Layouts`
  product from the `layouts` example. Differences between SwiftUI and SwiftTUI
  are visible in the two panes.
- The app exercises 56 focused layout shapes against the public SwiftTUI layout
  surface. Developers can compare the results visually.

## Build

```bash
swiftly run swift build --package-path LayoutsSwiftUI
```

This is a GUI app (native SwiftUI host) targeting macOS 15+ / iOS 18+.

## Findings

The behavior test files describe differences between the libraries and open
design questions. Behavior tests record the current behavior. Before you
change the library, update the test comment and open a discussion.

## Test

```bash
swiftly run swift test --package-path LayoutsSwiftUI
```

The `LayoutsSwiftUITests` target makes sure that both catalogs have the same
IDs. Raster smoke and behavior tests for these IDs are in the SwiftTUI layouts
package. That package has the public `DefaultRenderer` and `RasterSurface`
APIs. This SwiftUI port cannot use those APIs.

## See also

- [`layouts`](../layouts): the SwiftTUI-native catalog this port mirrors.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/): `SwiftUIHost` and the public layout surface.
