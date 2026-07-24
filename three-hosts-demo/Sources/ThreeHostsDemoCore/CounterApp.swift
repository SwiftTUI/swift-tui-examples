public import SwiftTUIRuntime

/// The visible piece of the demo: an animated counter with one increment button.
///
/// `CounterView` is the exact snippet shown in the marketing homepage's
/// code-to-frame proof.
struct CounterView: View {
  private let palette: [Color] = [.red, .yellow, .green, .blue, .magenta]

  private var displayedColors: [Color] {
    (0..<2).map { offset in
      palette[(count + offset) % palette.count]
    }
  }

  @State private var count = 0

  var body: some View {
    VStack(spacing: 1) {
      Text("Count: \(count)").bold()
      Button("Increment") { count += 1 }
    }
    .padding(3)
    .background {
      Rectangle()
        .fill(
          LinearGradient(
            colors: displayedColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .animation(.bouncy, value: count)
    }
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
