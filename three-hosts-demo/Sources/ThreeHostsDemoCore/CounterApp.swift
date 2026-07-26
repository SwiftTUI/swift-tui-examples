public import SwiftTUIRuntime

struct CounterView: View {

  @Environment(\.terminalSize) private var terminalSize
  @State private var count = 0
  @State private var rippleProgress: Double = 1

  var body: some View {
    VStack(spacing: 1) {
      Text("Count: \(count)").bold()
      Button("Increment") {
        count += 1
        rippleProgress = 0
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Rectangle()
        .fill(ripple)
    }
    .onChange(of: count) {
      withAnimation(.linear(duration: .milliseconds(1600))) {
        rippleProgress = 1
      }
    }
  }

  private var reach: Double {
    let horizontal = Double(terminalSize.width) / 2
    let vertical = Double(terminalSize.height)
    return (horizontal * horizontal + vertical * vertical).squareRoot()
  }

  private var ripple: RadialGradient {
    let innerEdge = rippleProgress * reach
    return RadialGradient(
      gradient: Gradient(stops: [
        .init(color: .clear, location: 0),
        .init(
          color: Color(red: 0x00 / 255, green: 0xE3 / 255, blue: 0xAB / 255),
          location: 0.5
        ),
        .init(color: .clear, location: 1),
      ]),
      center: .center,
      startRadius: innerEdge,
      endRadius: innerEdge + 14
    )
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
