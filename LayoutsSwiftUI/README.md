# Layouts (SwiftUI)

> An on-brand side-by-side gallery that proves SwiftTUI layout parity: 56 layout shapes rendered as native SwiftUI on the left and the matching SwiftTUI implementation on the right, so a reader can eyeball the two engines against each other. Runs as a native SwiftUI surface, with the SwiftTUI pane embedded via `SwiftUIHost`.

## Run

```bash
swiftly run swift run --package-path LayoutsSwiftUI layouts-swiftui-demo
```

The app launches directly into a sidebar plus a comparison detail. Selecting a layout updates both panes to the same catalog ID.

## Demonstrates

- `SwiftUIHost` — which means a SwiftTUI scene can be embedded as a live subview inside a real SwiftUI window, so the two engines render the same catalog ID side by side in one app.
- A shared layout catalog (the `Layouts` product from the `layouts` example) drives both panes from one source of truth, so divergences between SwiftUI and SwiftTUI are immediately visible.
- 56 focused layout shapes exercised against the public SwiftTUI layout surface, giving a developer a direct visual parity check rather than prose claims.

## Build

```bash
swiftly run swift build --package-path LayoutsSwiftUI
```

This is a GUI app (native SwiftUI host) targeting macOS 15+ / iOS 18+.

## Findings

Library divergences and design questions surfaced while implementing the behaviour tests are documented inline in the behaviour/test files. Behaviour tests pin the *observed* behaviour today; update a test's comment and open a discussion before changing the library.

## Test

```bash
swiftly run swift test --package-path LayoutsSwiftUI
```

The `LayoutsSwiftUITests` target asserts catalog parity (the SwiftUI port covers the same shared catalog IDs as the SwiftTUI original). The SwiftTUI raster smoke and rasterising behaviour tests for those IDs live in the corresponding SwiftTUI layouts package, which has the public `DefaultRenderer` / `RasterSurface` this SwiftUI port cannot use.

## See also

- [`layouts`](../layouts) — the SwiftTUI-native catalog this port mirrors.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — `SwiftUIHost` and the public layout surface.
