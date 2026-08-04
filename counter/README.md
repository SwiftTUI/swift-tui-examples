# Counter

> One `CounterApp` source, three hosts: the same scene runs unchanged as a terminal executable, a native SwiftUI window, and a static WASI bundle in the browser — proving a SwiftTUI App targets every host without per-target source forks (terminal + native SwiftUI surface + static WASI bundle, one source, three hosts).

## Run

```bash
swiftly run swift run --package-path counter counter
```

Increment the counter with `Space` or `Return`. Quit with `Ctrl-C`.
The value uses the Gallery counter's `TextFigure` treatment.
Each press launches its own ripple, so rapid presses leave several rings in
flight. Overlapping rings brighten through screen blending.

Run the same scene on a **native SwiftUI surface** (macOS-only SwiftPM target):

```bash
swiftly run swift run --package-path counter CounterSwiftUI
```

Build the **static WASI bundle** for the browser host. It is a separate product.
The [Build](#build) section explains the required flags.

```bash
swiftly run swift build \
  --package-path counter \
  --swift-sdk swift-6.3.3-RELEASE_wasm \
  -c release \
  -Xswiftc -Osize \
  -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass \
  --product CounterWASI
```

## Demonstrates

- `SwiftTUIRuntime` is the host-neutral authoring layer, not the `SwiftTUI`
  umbrella. One `CounterView` and `CounterApp` source compiles for each host,
  including WASI.
- The native hosts use the `SwiftTUI` umbrella runner. The terminal host is a
  small `@main` wrapper over the shared scene. It uses the `SwiftTUI.App`
  runner.
- `SwiftUIHost` from `swift-tui-swiftui` mounts the same scene in a native
  `SwiftUI.Scene` and `WindowGroup` on macOS.
- `SwiftTUIWASI` runs the same scene through `WASIRunner.run` in the browser.
  Its dependency closure excludes FlyingFox and Dispatch. Thus, the wasm has no
  server or runtime stack.
- Identity-preserving `ForEach` animation layers and `.screen` compositing let
  independently timed ripples overlap on each host.

## Layout

| Path | Role |
| --- | --- |
| [`Sources/CounterCore/CounterApp.swift`](Sources/CounterCore/CounterApp.swift) | The shared `CounterView` + `CounterApp` consumed by every host. Imports `SwiftTUIRuntime` (not the `SwiftTUI` umbrella) so it stays host-neutral and WASI-safe. |
| [`Sources/counter/CounterAppTerminalHost.swift`](Sources/counter/CounterAppTerminalHost.swift) | Terminal entry point. A thin `@main` wrapper uses the `SwiftTUI.App` runner over the shared scene (native only). |
| [`Sources/CounterSwiftUI/SwiftUIHostApp.swift`](Sources/CounterSwiftUI/SwiftUIHostApp.swift) | Native SwiftUI entry point — `@main SwiftUI.App` hosting the shared scene via `SwiftUIHostAppView` (macOS-only SwiftPM target). |
| [`Sources/CounterWASI/main.swift`](Sources/CounterWASI/main.swift) | Browser entry point with top-level `WASIRunner.run(CounterApp.self)`. It depends only on `SwiftTUIWASI`, so no server or Dispatch stack enters the wasm. |
| [`Tests/CounterCoreTests/`](Tests/CounterCoreTests/) | Smoke tests asserting trivial instantiability from any host target. |

## Build

The browser host is a **separate product** named `CounterWASI`. The terminal
executable imports the `SwiftTUI` umbrella. Its runner serves HTTP through
FlyingFox and Dispatch, which do not build for WASI. Therefore, build the WASI
product with the `swift build` command above.

The resulting `.wasm` artifact can be served by the same Bun-driven host shell
used by [`../WebExample/`](../WebExample/). The required `-Osize` plus
`-disable-llvm-merge-functions-pass` flags are documented in
`../WebExample/AGENTS.md`.

The native SwiftUI host, `CounterSwiftUI`, is a macOS-only target.
`Package.swift` guards it with `#if os(macOS)`. Other platforms do not build
this target.

## Controls

| Key | Action |
| --- | --- |
| `Space` / `Return` | Increment the counter |
| `Ctrl-C` | Quit |

## Test

```bash
swiftly run swift test --package-path counter
```

The command runs the `CounterCoreTests` target. These smoke tests create
the shared `CounterApp` and `CounterView` from each host.

## See also

- [`../WebExample/`](../WebExample/) — the full browser/WASI deployment shell that serves a `.wasm` like this one.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — `SwiftTUIRuntime`, `SwiftTUIWASI`, and `SwiftUIHost` API surface.
