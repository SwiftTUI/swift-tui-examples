import SwiftTUIWASI
import ThreeHostsDemoCore

// The browser host. Unlike the terminal host (which uses the batteries-included
// `SwiftTUI.App` runner that serves over HTTP via FlyingFox), the WASI host runs
// *inside* the browser: the wasm module is the client, mounted onto a canvas by
// `@swifttui/web`. The entry point is therefore `WASIRunner.run`, not a server
// runner — and the dependency closure deliberately stops at `SwiftTUIWASI` +
// `ThreeHostsDemoCore`, neither of which reaches FlyingFox/Dispatch.
try await WASIRunner.run(CounterApp.self)
