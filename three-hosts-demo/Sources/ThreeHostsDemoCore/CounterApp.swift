public import SwiftTUIRuntime

/// The visible piece of the demo: a focused counter with one increment button.
///
/// `CounterView` is the exact snippet shown in the marketing homepage's
/// code-to-frame proof.
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

public struct CounterApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Counter", id: WindowIdentifier("counter")) {
      CounterView()
    }
  }
}
