public import SwiftTUI

/// The visible piece of the demo: a focused counter with one increment button.
///
/// `CounterView` is intentionally minimal so that the same source can drive
/// every host without per-host conditionals. It is the exact snippet shown in
/// the `AuthoringSnippet` block on the marketing site.
public struct CounterView: View {
  @State private var count = 0
  @FocusState private var focused: Bool

  public init() {}

  public var body: some View {
    VStack(spacing: 1) {
      Text("Count: \(count)").bold()
      Button("Increment") { count += 1 }
        .focused($focused)
    }
    .onAppear { focused = true }
    .padding(2)
  }
}

/// The App that drives `CounterView`. The same value runs as a terminal
/// executable, as a static WASI bundle in the browser, and embedded in a
/// native SwiftUI surface through `SwiftUIHostAppState(app: CounterApp())`.
public struct CounterApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Counter", id: WindowIdentifier("counter")) {
      CounterView()
    }
  }
}
