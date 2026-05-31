import SwiftTUI
import ThreeHostsDemoCore

/// Terminal (and WASI) entry point. `@main` is required here rather than a
/// bare `CounterApp.main()` call: `App.main()` is `async`, but a top-level
/// `CounterApp.main()` resolves to the *synchronous* `ParsableCommand.main()`
/// overload (`await` does not override that), which aborts with an
/// "asynchronous root command needs availability annotation" message. `@main`
/// synthesis binds the async entry point correctly. The scene is delegated to
/// the shared `CounterApp` so every host still drives the same source.
@main
struct CounterAppTerminalHost: App {
  var body: some Scene {
    CounterApp().body
  }
}
