# Three Hosts Demo

> One `CounterApp` source, three hosts: the same scene runs unchanged as a terminal executable, a native SwiftUI window, and a static WASI bundle in the browser — proving a SwiftTUI App targets every host without per-target source forks (terminal + native SwiftUI surface + static WASI bundle, one source, three hosts).

## Run

```bash
swiftly run swift run --package-path three-hosts-demo three-hosts-demo
```

Increment the counter with `Space` or `Return`; quit with `Ctrl-C`.

Run the same scene on a **native SwiftUI surface** (macOS-only SwiftPM target):

```bash
swiftly run swift run --package-path three-hosts-demo ThreeHostsSwiftUI
```

Build the **static WASI bundle** for the browser host (separate product; see Build below for why the flags are required):

```bash
swiftly run swift build \
  --package-path three-hosts-demo \
  --swift-sdk swift-6.3.1-RELEASE_wasm \
  -c release \
  -Xswiftc -Osize \
  -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass \
  --product ThreeHostsWASI
```

## Demonstrates

- `SwiftTUIRuntime` (the host-neutral authoring layer, not the `SwiftTUI` umbrella) — which means one `CounterView` + `CounterApp` source compiles into every host target, including WASI, with no per-host forks.
- `SwiftTUI` umbrella runner on native (terminal + WebHost) — which means the terminal host is a thin `@main` wrapper over the shared scene using the batteries-included `SwiftTUI.App` runner.
- `SwiftUIHost` (`swift-tui-swiftui`) — which means the identical scene mounts inside a native `SwiftUI.Scene`/`WindowGroup` as a real macOS app surface.
- `SwiftTUIWASI` — which means the browser host runs the same scene via `WASIRunner.run` with a dependency closure that stops short of FlyingFox/Dispatch, keeping the wasm server/runtime-stack-free.

## Layout

| Path | Role |
| --- | --- |
| [`Sources/ThreeHostsDemoCore/CounterApp.swift`](Sources/ThreeHostsDemoCore/CounterApp.swift) | The shared `CounterView` + `CounterApp` consumed by every host. Imports `SwiftTUIRuntime` (not the `SwiftTUI` umbrella) so it stays host-neutral and WASI-safe. |
| [`Sources/three-hosts-demo/CounterAppTerminalHost.swift`](Sources/three-hosts-demo/CounterAppTerminalHost.swift) | Terminal entry point — a thin `@main` wrapper over the shared scene, using the batteries-included `SwiftTUI.App` runner (native only). |
| [`Sources/ThreeHostsSwiftUI/SwiftUIHostApp.swift`](Sources/ThreeHostsSwiftUI/SwiftUIHostApp.swift) | Native SwiftUI entry point — `@main SwiftUI.App` hosting the shared scene via `SwiftUIHostAppView` (macOS-only SwiftPM target). |
| [`Sources/ThreeHostsWASI/main.swift`](Sources/ThreeHostsWASI/main.swift) | Browser entry point — top-level `WASIRunner.run(CounterApp.self)`; depends only on `SwiftTUIWASI`, so no server/Dispatch stack enters the wasm. |
| [`Tests/ThreeHostsDemoCoreTests/`](Tests/ThreeHostsDemoCoreTests/) | Smoke tests asserting trivial instantiability from any host target. |

## Build

The browser host is a **separate product** (`ThreeHostsWASI`) from the terminal
executable. The terminal host imports the `SwiftTUI` umbrella, whose runner
serves over HTTP via FlyingFox (→ Dispatch) and so cannot build for WASI —
build the WASI product instead (the `swift build` invocation above).

The resulting `.wasm` artifact can be served by the same Bun-driven host shell
used by [`../WebExample/`](../WebExample/). The required `-Osize` plus
`-disable-llvm-merge-functions-pass` flags are documented in
`../WebExample/AGENTS.md`.

The native SwiftUI host (`ThreeHostsSwiftUI`) is a macOS-only target, gated
behind `#if os(macOS)` in `Package.swift`; it is not built on non-Apple
platforms.

## Controls

| Key | Action |
| --- | --- |
| `Space` / `Return` | Increment the counter |
| `Ctrl-C` | Quit |

## Test

```bash
swiftly run swift test --package-path three-hosts-demo
```

Runs the `ThreeHostsDemoCoreTests` target — smoke tests that the shared
`CounterApp`/`CounterView` stay trivially instantiable from every host.

## See also

- [`../WebExample/`](../WebExample/) — the full browser/WASI deployment shell that serves a `.wasm` like this one.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — `SwiftTUIRuntime`, `SwiftTUIWASI`, and `SwiftUIHost` API surface.
