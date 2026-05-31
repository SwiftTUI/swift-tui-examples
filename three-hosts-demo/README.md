# three-hosts-demo

The same `CounterApp` source running as three hosts: terminal executable,
native SwiftUI window, and a static WASI bundle in the browser. Built to
back the marketing claim that one SwiftTUI App targets every host without
per-target source forks.

## What's here

| Path | Role |
| --- | --- |
| [`Sources/ThreeHostsDemoCore/CounterApp.swift`](Sources/ThreeHostsDemoCore/CounterApp.swift) | The shared `CounterView` + `CounterApp` consumed by every host. Imports `SwiftTUIRuntime` (not the `SwiftTUI` umbrella) so it stays host-neutral and WASI-safe |
| [`Sources/three-hosts-demo/CounterAppTerminalHost.swift`](Sources/three-hosts-demo/CounterAppTerminalHost.swift) | Terminal entry point — a thin `@main` wrapper over the shared scene, using the batteries-included `SwiftTUI.App` runner (native only) |
| [`Sources/ThreeHostsWASI/main.swift`](Sources/ThreeHostsWASI/main.swift) | Browser entry point — top-level `WASIRunner.run(CounterApp.self)`; depends only on `SwiftTUIWASI`, so no server/Dispatch stack enters the wasm |
| [`Tests/ThreeHostsDemoCoreTests/`](Tests/ThreeHostsDemoCoreTests/) | Smoke tests asserting trivial instantiability from any host target |
| [`SwiftUIHost/`](SwiftUIHost/) | Stub source for the native SwiftUI host — see its README for Xcode setup |

## Run as a terminal executable

```bash
swiftly run swift run --package-path three-hosts-demo three-hosts-demo
```

Increment the counter with `Space` or `Return`. Quit with `Ctrl-C`.

## Embed in a native SwiftUI window

See [`SwiftUIHost/README.md`](SwiftUIHost/README.md). The Xcode setup is
out of band of this SwiftPM package because native SwiftUI macOS apps need
a `.app` bundle that SwiftPM does not produce.

## Build as a static WASI bundle

The browser host is a **separate product** (`ThreeHostsWASI`) from the terminal
executable. The terminal host imports the `SwiftTUI` umbrella, whose runner
serves over HTTP via FlyingFox (→ Dispatch) and so cannot build for WASI —
build the WASI product instead:

```bash
swiftly run swift build \
  --package-path three-hosts-demo \
  --swift-sdk swift-6.3.1-RELEASE_wasm \
  -c release \
  -Xswiftc -Osize \
  -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass \
  --product ThreeHostsWASI
```

The resulting `.wasm` artifact can be served by the same Bun-driven host shell
used by [`../WebExample/`](../WebExample/). The required `-Osize` plus
`-disable-llvm-merge-functions-pass` flags are documented in
`../WebExample/AGENTS.md`.

## Tests

```bash
swiftly run swift test --package-path three-hosts-demo
```
