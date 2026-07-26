public import SwiftTUIRuntime

/// The visible piece of the demo: a counter with one increment button, each
/// press sending a ripple out from the center.
///
/// `CounterView` is the exact snippet shown in the marketing homepage's
/// code-to-frame proof.
struct CounterView: View {
  /// The ripple's accent, `#00E3AB`.
  private static let accent = Color(red: 0x00 / 255, green: 0xE3 / 255, blue: 0xAB / 255)

  /// Thickness of the travelling band, in horizontal cells.
  private static let thickness: Double = 14

  /// How long one ripple takes to cross ``reach``.
  private static let period: Duration = .milliseconds(1600)

  @Environment(\.terminalSize) private var terminalSize

  @State private var count = 0

  /// How far along the current ripple is: 0 launches it at the center, 1 has
  /// it past the far corner and fully faded. It *rests* at 1, because a spent
  /// ripple is an invisible one — so nothing is drawn until the first press.
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
      Rectangle().fill(ripple)
    }
    .onChange(of: count) {
      withAnimation(.linear(duration: Self.period)) {
        rippleProgress = 1
      }
    }
  }

  /// Far enough that a ring at this radius has cleared the furthest corner,
  /// so a finished ripple leaves nothing on screen at any terminal size.
  ///
  /// Distances are in horizontal cells: the sampler corrects cell space to
  /// device pixels, which makes the half-height count double on a 2:1 cell —
  /// so the vertical leg is the full height rather than half of it.
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
        .init(color: Self.accent, location: 0.5),
        .init(color: .clear, location: 1),
      ]),
      center: .center,
      startRadius: innerEdge,
      endRadius: innerEdge + Self.thickness
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
