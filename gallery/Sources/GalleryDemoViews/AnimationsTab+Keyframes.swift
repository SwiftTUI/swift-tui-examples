import SwiftTUIRuntime

// The Keyframes page: PhaseAnimator in auto-cycling and trigger modes
// (sections 7 and 8), KeyframeAnimator in trigger and repeating modes
// (sections 10 and 11), and a static KeyframeTimeline curve strip (12).
// Section 7 is the tab's one always-on loop; section 11 defaults to stopped
// and only mounts its animator while running.
extension AnimationsTab {
  var keyframesPage: some View {
    pageScroll {
      phaseAnimatorSection
      Divider()
      triggerPhaseAnimatorSection
      Divider()
      keyframeTriggerSection
      Divider()
      keyframeRepeatingSection
      Divider()
      curveStripSection
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

  // MARK: - 10. KeyframeAnimator trigger-driven demo

  private var keyframeTriggerSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(10, "KeyframeAnimator(trigger:) three tracks, one pass per tap")
      expectLine(
        "★ dips one row, rises three, overshoots one, settles in about 1.6 s; color cycles once")
      // Touch the task-written slot in body so it binds to this tab instance
      // before the task's first access (the PhaseAnimator trick).
      let _ = doubleRunServed
      HStack(spacing: 2) {
        Button("run keyframes") {
          keyframeRunTrigger += 1
        }
        // Two trigger bumps 250 ms apart: the second lands mid-flight, so the
        // animator restarts from the current value and carries its velocity
        // into the first cubic keyframe instead of jumping back to rest.
        Button("run twice quickly") {
          doubleRunRequest += 1
        }
        // The run count is read here, outside the animator: a tab-level
        // @State read inside the animator's content closure (which the
        // animator re-evaluates on its own ticks) lands on the seed value.
        Text("runs=\(keyframeRunTrigger)")
          .foregroundStyle(.separator)
      }
      .focusSection()
      .task(id: doubleRunRequest) { @MainActor in
        guard doubleRunRequest > doubleRunServed else { return }
        doubleRunServed = doubleRunRequest
        keyframeRunTrigger += 1
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        keyframeRunTrigger += 1
      }
      KeyframeAnimator(initialValue: KeyframeStar(), trigger: keyframeRunTrigger) { star in
        VStack(alignment: .leading, spacing: 0) {
          // The marker lives in a fixed five-row slot with its rest row in
          // the middle, so the excursion (-3 to +1 rows) never overdraws the
          // neighbouring lines.
          Text("★ keyframes ★")
            .foregroundStyle(star.color)
            .opacity(star.opacity)
            .offset(x: 0, y: KeyframeStar.restRow + star.offsetRow)
            .frame(height: KeyframeStar.slotHeight, alignment: .topLeading)
          // The interpolated struct, rounded.
          stateLine(
            "offsetY=\(Self.readout(star.offsetY)) color=\(Self.readout(star.color)) "
              + "opacity=\(Self.readout(star.opacity, places: 2))"
          )
        }
      } keyframes: { _ in
        KeyframeTrack(\.offsetY) {
          CubicKeyframe(1, duration: .milliseconds(200))
          CubicKeyframe(-3, duration: .milliseconds(500))
          CubicKeyframe(1, duration: .milliseconds(400))
          CubicKeyframe(0, duration: .milliseconds(500))
        }
        KeyframeTrack(\.color) {
          LinearKeyframe(Color.magenta, duration: .milliseconds(500))
          LinearKeyframe(Color.cyan, duration: .milliseconds(500))
          LinearKeyframe(Color.yellow, duration: .milliseconds(600))
        }
        KeyframeTrack(\.opacity) {
          SpringKeyframe(0.35, duration: .milliseconds(600), spring: .bouncy)
          SpringKeyframe(1, duration: .milliseconds(1000), spring: .smooth)
        }
      }
    }
  }

  // MARK: - 11. KeyframeAnimator repeating demo

  private var keyframeRepeatingSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(11, "KeyframeAnimator(repeating:) breathing bar, stopped until started")
      expectLine(
        "bar widens 8 to 24 cells over 0.8 s, springs back to 18, then snaps to 8; 1.5 s per cycle"
      )
      HStack(spacing: 2) {
        Button("start breathing") {
          breathingRunning = true
        }
        Button("stop breathing") {
          breathingRunning = false
        }
      }
      .focusSection()
      // The animator is only mounted while running, so stopping it also
      // stops its tick task and the page idles at section 7's loop alone.
      if breathingRunning {
        KeyframeAnimator(initialValue: BreathingBar.restWidth, repeating: true) { width in
          breathingBar(width: width, running: true)
        } keyframes: { _ in
          LinearKeyframe(24, duration: .milliseconds(800), timingCurve: .easeInOut)
          SpringKeyframe(18, duration: .milliseconds(700), spring: .bouncy)
          MoveKeyframe(BreathingBar.restWidth)
        }
      } else {
        breathingBar(width: BreathingBar.restWidth, running: false)
      }
    }
  }

  private func breathingBar(width: Double, running: Bool) -> some View {
    let cells = max(Int(width.rounded()), 1)
    return VStack(alignment: .leading, spacing: 0) {
      Text(String(repeating: "█", count: cells))
        .foregroundStyle(Color.green)
      stateLine("running=\(running) width=\(cells)")
    }
  }

  // MARK: - 12. KeyframeTimeline curve strip

  private var curveStripSection: some View {
    let strip = CurveStrip(kind: curveStripKind)
    return VStack(alignment: .leading, spacing: 0) {
      sectionTitle(12, "KeyframeTimeline sampled every 50 ms, no motion")
      expectLine(
        "no motion: a 6-row sparkline of the value, | at each keyframe boundary; the picker swaps timelines"
      )
      Picker("Timeline", selection: $curveStripKind) {
        ForEach(CurveStripKind.allCases, id: \.self) { kind in
          Text(kind.rawValue).tag(kind)
        }
      }
      .pickerStyle(.segmented)
      // The segmented body is height-greedy; pin it like the page picker.
      .frame(height: 4)
      CurveStripView(kind: curveStripKind)
      stateLine(
        "timeline=\(curveStripKind.rawValue) duration=\(Self.readout(strip.duration.totalSeconds))s "
          + "samples=\(strip.columns) min=\(Self.readout(strip.minimum, places: 2)) "
          + "max=\(Self.readout(strip.maximum, places: 2))"
      )
    }
  }
}

/// The value section 10 animates: three independent tracks over one struct.
struct KeyframeStar: Sendable {
  var offsetY: Double = 0
  var color: Color = .yellow
  var opacity: Double = 1

  /// The row the marker rests on inside its slot.
  static let restRow = 3
  /// Rows in the marker's slot: three above rest, one below.
  static let slotHeight = 5

  /// `offsetY` rounded to a row and clamped to the slot, so a cubic overshoot
  /// past the keyframe values can never draw over a neighbouring line.
  var offsetRow: Int {
    min(max(Int(offsetY.rounded()), -Self.restRow), Self.slotHeight - 1 - Self.restRow)
  }
}

/// Constants for the breathing bar of section 11.
enum BreathingBar {
  /// The width the bar rests at, and the value each cycle restarts from.
  static let restWidth = 8.0
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
