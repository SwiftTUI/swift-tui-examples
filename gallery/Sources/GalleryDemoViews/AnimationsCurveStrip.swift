import SwiftTUIRuntime

/// The timelines section 12 of the Animations tab can chart. The raw value is
/// the segment title in the picker.
enum CurveStripKind: String, CaseIterable, Hashable, Sendable {
  case linear
  case cubic
  case spring
  case mixed
}

/// A `KeyframeTimeline<Double>` sampled one column per 50 ms and drawn as a
/// six-row sparkline of block characters, with each keyframe boundary marked
/// by a `|` rule above the bar (and in the top row when the bar is full).
///
/// The strip is pure interpolation math over a fixed sample grid, so it
/// renders identically on every run: `AnimationsTabPagesTests` snapshots all
/// four kinds through `DefaultRenderer`.
struct CurveStrip {
  /// One column per this much timeline time.
  static let sampleInterval = Duration.milliseconds(50)
  /// Rows in the strip; each row holds eight levels (partial blocks).
  static let rows = 6
  /// Block characters by fill level, empty to full.
  static let glyphs: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

  let kind: CurveStripKind
  let timeline: KeyframeTimeline<Double>
  /// The instants at which one keyframe hands over to the next, excluding
  /// the timeline's end.
  let boundaries: [Duration]

  init(kind: CurveStripKind) {
    self.kind = kind
    switch kind {
    case .linear:
      timeline = KeyframeTimeline(initialValue: 0.0) {
        LinearKeyframe(1, duration: .milliseconds(700))
        LinearKeyframe(0.2, duration: .milliseconds(600), timingCurve: .easeInOut)
        LinearKeyframe(0.8, duration: .milliseconds(700), timingCurve: .easeOut)
      }
      boundaries = [.milliseconds(700), .milliseconds(1300)]
    case .cubic:
      timeline = KeyframeTimeline(initialValue: 0.0) {
        CubicKeyframe(1, duration: .milliseconds(600))
        CubicKeyframe(0.2, duration: .milliseconds(700))
        CubicKeyframe(0.7, duration: .milliseconds(700))
      }
      boundaries = [.milliseconds(600), .milliseconds(1300)]
    case .spring:
      timeline = KeyframeTimeline(initialValue: 0.0) {
        SpringKeyframe(1, duration: .milliseconds(1000), spring: .bouncy)
        SpringKeyframe(
          0, duration: .milliseconds(1000),
          spring: Spring(duration: .milliseconds(600), bounce: 0.5))
      }
      boundaries = [.milliseconds(1000)]
    case .mixed:
      timeline = KeyframeTimeline(initialValue: 0.0) {
        LinearKeyframe(1, duration: .milliseconds(500))
        MoveKeyframe(0.25)
        SpringKeyframe(0.9, duration: .milliseconds(700), spring: .bouncy)
        CubicKeyframe(0, duration: .milliseconds(800))
      }
      boundaries = [.milliseconds(500), .milliseconds(1200)]
    }
  }

  /// The timeline's duration (its longest track).
  var duration: Duration {
    timeline.duration
  }

  /// Sample columns, the timeline's end included.
  var columns: Int {
    Int((duration / Self.sampleInterval).rounded()) + 1
  }

  /// The value at every column.
  var samples: [Double] {
    (0..<columns).map { column in
      timeline.value(time: Self.sampleInterval * column)
    }
  }

  var minimum: Double {
    samples.min() ?? 0
  }

  var maximum: Double {
    samples.max() ?? 0
  }

  /// The strip's rows, top first. Values are normalized to the sampled range
  /// so the strip always uses its full height; every column keeps at least
  /// one level so the line never vanishes.
  var lines: [String] {
    let samples = samples
    let low = minimum
    let span = max(maximum - low, 0.0001)
    let levels = Self.rows * 8
    let heights = samples.map { sample in
      1 + Int(((sample - low) / span * Double(levels - 1)).rounded())
    }
    let boundaryColumns = Set(
      boundaries.map { boundary in
        Int((boundary / Self.sampleInterval).rounded())
      }
    )
    return (0..<Self.rows).map { row in
      let base = (Self.rows - 1 - row) * 8
      var line = ""
      for (column, height) in heights.enumerated() {
        let fill = min(max(height - base, 0), 8)
        // A boundary rules every empty cell of its column and always owns
        // the top cell, so a full-height column still shows its tick.
        if boundaryColumns.contains(column), fill == 0 || row == 0 {
          line.append("|")
        } else {
          line.append(Self.glyphs[fill])
        }
      }
      return line
    }
  }
}

/// The rendered strip: one `Text` per row.
struct CurveStripView: View {
  let kind: CurveStripKind

  var body: some View {
    let strip = CurveStrip(kind: kind)
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(strip.lines.enumerated()), id: \.offset) { row in
        Text(row.element)
          .foregroundStyle(Color.cyan)
      }
    }
  }
}
