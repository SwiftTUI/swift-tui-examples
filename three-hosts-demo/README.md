# three-hosts-demo

The same `CounterApp` source running as three hosts: terminal executable,
native SwiftUI window, and a static WASI bundle in the browser. Built to
back the marketing claim that one SwiftTUI App targets every host without
per-target source forks.

## What's here

| Path | Role |
| --- | --- |
| [`Sources/ThreeHostsDemoCore/CounterApp.swift`](Sources/ThreeHostsDemoCore/CounterApp.swift) | The shared `CounterView` + `CounterApp` consumed by every host |
| [`Sources/three-hosts-demo/main.swift`](Sources/three-hosts-demo/main.swift) | Terminal entry point — three lines, no host-specific code |
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

```bash
swiftly run swift build \
  --package-path three-hosts-demo \
  --swift-sdk swift-6.3.1-RELEASE_wasm \
  -c release \
  -Xswiftc -Osize \
  -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass \
  --product three-hosts-demo
```

The resulting `.wasm` artifact can be served by the same Bun-driven host shell
used by [`../WebExample/`](../WebExample/). The required `-Osize` plus
`-disable-llvm-merge-functions-pass` flags are documented in
`../WebExample/CLAUDE.md`.

## Tests

```bash
swiftly run swift test --package-path three-hosts-demo
```
