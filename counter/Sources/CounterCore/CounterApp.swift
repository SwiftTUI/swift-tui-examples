public import SwiftTUIRuntime

struct CounterView: View {

  @Environment(\.terminalSize) private var terminalSize
  @State private var count = 0
  @State private var activeRipple: Bool = false

  var body: some View {
    VStack(spacing: 1) {
      TextFigure("\(count)", font: .future)
        .frame(minWidth: 14, alignment: .center)
      Button("Increment") {
        count += 1
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: count) {
      if !activeRipple {
        activeRipple = true
      }
    }
    .background {
      if activeRipple {
        RippleLayer(reach: reach) {
          activeRipple = false
        }
      }
    }
  }

  private var reach: Double {
    let horizontal = Double(terminalSize.width) / 2
    let vertical = Double(terminalSize.height)
    return (horizontal * horizontal + vertical * vertical).squareRoot()
  }
}

private struct RippleLayer: View {
  @State private var progress: Double = 0

  let reach: Double
  let onCompletion: @MainActor @Sendable () -> Void

  var body: some View {
    Rectangle()
      .fill(ripple)
      .task {
        @MainActor in
          withAnimation(.linear(duration: .milliseconds(1600))) {
            progress = 1
          } completion: {
            onCompletion()
          }
      }
  }

  private var ripple: RadialGradient {
    let innerEdge = progress * reach
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
      endRadius: innerEdge + 5
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
