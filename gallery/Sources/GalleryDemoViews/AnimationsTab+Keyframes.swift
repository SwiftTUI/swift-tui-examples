import SwiftTUIRuntime

// The Keyframes page: PhaseAnimator in auto-cycling and trigger modes
// (sections 7 and 8). Section 7 is the tab's one always-on loop.
extension AnimationsTab {
  var keyframesPage: some View {
    pageScroll {
      phaseAnimatorSection
      Divider()
      triggerPhaseAnimatorSection
    }
  }

  // MARK: - 7. PhaseAnimator auto-cycling demo

  private var phaseAnimatorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(7, "PhaseAnimator auto-cycles through phases on its own")
      expectLine(
        "dots cycle red/yellow/green/cyan, stepping 0 to 20 cells; 2.6 s per loop, never stops")
      PhaseAnimator([PhaseDemoPhase.red, .yellow, .green, .cyan]) { phase in
        VStack(alignment: .leading, spacing: 0) {
          Text("●●●●●●●●●●●●●●●●")
            .foregroundStyle(phase.color)
            .offset(x: phase.offsetX, y: 0)
          stateLine("phase=\(phase) offsetX=\(phase.offsetX)")
        }
      } animation: { phase in
        switch phase {
        case .red: .linear(duration: .milliseconds(600))
        case .yellow: .easeInOut(duration: .milliseconds(600))
        case .green: .spring(duration: .milliseconds(800), bounce: 0.3)
        case .cyan: .easeInOut(duration: .milliseconds(600))
        }
      }
    }
  }

  // MARK: - 8. PhaseAnimator trigger-driven demo

  private var triggerPhaseAnimatorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(8, "PhaseAnimator(trigger:) one bounce per tap, then returns to rest")
      expectLine(
        "★ bounce ★ hops up (yellow), down (magenta), then settles (cyan); about 1.3 s per tap")
      HStack(spacing: 2) {
        Button("bounce") {
          bounceTrigger += 1
        }
      }
      .focusSection()
      PhaseAnimator(
        [BouncePhase.rest, .up, .down, .rest],
        trigger: bounceTrigger
      ) { phase in
        VStack(alignment: .leading, spacing: 0) {
          Text("★ bounce ★")
            .foregroundStyle(phase.color)
            .offset(x: 0, y: phase.offsetY)
          stateLine("taps=\(bounceTrigger) phase=\(phase) offsetY=\(phase.offsetY)")
        }
      } animation: { phase in
        switch phase {
        case .rest: .easeInOut(duration: .milliseconds(400))
        case .up: .spring(duration: .milliseconds(500), bounce: 0.4)
        case .down: .easeInOut(duration: .milliseconds(400))
        }
      }
    }
  }
}

/// Phase values used by the PhaseAnimator demo section. Each phase pairs a
/// color with an x-offset so the marker visibly cycles color and position
/// together.
enum PhaseDemoPhase: Equatable, Sendable {
  case red
  case yellow
  case green
  case cyan

  var color: Color {
    switch self {
    case .red: .red
    case .yellow: .yellow
    case .green: .green
    case .cyan: .cyan
    }
  }

  var offsetX: Int {
    switch self {
    case .red: 0
    case .yellow: 10
    case .green: 20
    case .cyan: 10
    }
  }
}

/// Phase values for the trigger-driven PhaseAnimator demo. The sequence
/// `[rest, up, down, rest]` models a bounce that returns to a stable rest
/// state so each tap produces a complete round trip before the next tap.
enum BouncePhase: Equatable, Sendable {
  case rest
  case up
  case down

  var offsetY: Int {
    switch self {
    case .rest: 0
    case .up: -1
    case .down: 1
    }
  }

  var color: Color {
    switch self {
    case .rest: .cyan
    case .up: .yellow
    case .down: .magenta
    }
  }
}
