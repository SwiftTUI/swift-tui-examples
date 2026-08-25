import Foundation
@_spi(Testing) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

// One runtime test per Animations tab section that landed with the keyframe,
// matched geometry, and transaction stages (plan 2026-08-25-002 G3). Each
// test drives the section's buttons through the real run loop, records every
// presented frame, and writes the recording as a frame strip when
// `GALLERY_FRAME_STRIP_DIR` is set (see `GalleryFrameStrip`).
//
// Assertions are deliberately coarse: the section reaches its end state, a
// readout moved through an intermediate value, a counter has the expected
// value, a barrier fired no earlier than its animation allows. Nothing here
// depends on frame rate, so a loaded runner slows these tests down instead of
// failing them (the 2026-08-19 lesson recorded in `GalleryBoundedWaits`).
@MainActor
@Suite(.serialized)
struct AnimationSectionRuntimeTests {
  private typealias Step = AnimationRegressionAwaitedInputStep

  /// Tall enough that every section of the longest page is on screen, so its
  /// buttons can be located on a static render.
  private static let terminalSize = CellSize(width: 96, height: 96)

  // MARK: - Keyframes page

  @Test(
    "section 10: KeyframeAnimator(trigger:) rises three rows and returns to rest",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func keyframeTriggerSection() async throws {
    let needle = "state: offsetY="
    let rest = "offsetY=0.0 color=0.92/0.70/0.24 opacity=1.00"
    var sawMotion = false
    let host = try await Self.drive(
      page: .keyframes,
      section: 10,
      strip: "section-10-keyframe-trigger",
      stateNeedle: needle,
      controls: ["run keyframes"]
    ) { host, at in
      [.awaitCondition { Self.latestState(host, needle).contains(rest) }]
        + Step.click(at["run keyframes"]!) + [
          .awaitCondition {
            // The opacity track sits below 1 for about a second of the
            // pass, so even a slow runner sees the animator move before it
            // lands back on the rest value.
            let state = Self.latestState(host, needle)
            if state.contains("opacity=0.") {
              sawMotion = true
            }
            return sawMotion && state.contains(rest)
              && Self.latestColumn(of: "runs=1", in: host) != nil
          }
        ]
    }

    let states = Self.states(host, needle)
    #expect(
      states.contains { $0.contains("offsetY=-") },
      "the marker never rose above its rest row: \(states.suffix(20))"
    )
    #expect(states.last?.contains(rest) == true)
  }

  @Test(
    "section 11: the repeating KeyframeAnimator breathes while started and rests when stopped",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func keyframeRepeatingSection() async throws {
    let needle = "state: running="
    let host = try await Self.drive(
      page: .keyframes,
      section: 11,
      strip: "section-11-keyframe-repeating",
      stateNeedle: needle,
      controls: ["start breathing", "stop breathing"]
    ) { host, at in
      [.awaitCondition { Self.latestState(host, needle).contains("running=false width=8") }]
        + Step.click(at["start breathing"]!) + [
          .awaitCondition {
            Self.readout("width", in: Self.latestState(host, needle)).map { $0 >= 22 } == true
          }
        ] + Step.click(at["stop breathing"]!) + [
          .awaitCondition { Self.latestState(host, needle).contains("running=false width=8") }
        ]
    }

    let widths = Self.states(host, needle).compactMap { Self.readout("width", in: $0) }
    #expect(widths.max() ?? 0 >= 22, "the bar never widened: \(widths)")
    #expect(widths.last == 8)
  }

  // MARK: - Matched page

  @Test(
    "section 6: the matched badge slides to the other slot and settles",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func matchedGeometrySection() async throws {
    let needle = "state: heroOnRight="
    let host = try await Self.drive(
      page: .matched,
      section: 6,
      strip: "section-6-matched-geometry",
      stateNeedle: needle,
      controls: ["move right"]
    ) { host, at in
      [.awaitCondition { Self.latestColumn(of: "★9x1", in: host) != nil }]
        + Step.click(at["move right"]!) + [
          .awaitCondition {
            Self.latestState(host, needle).contains("heroOnRight=true")
              && Self.latestState(host, needle).contains("settled=1")
          }
        ]
    }

    let columns = Self.columns(of: "★", in: host).compactMap { $0 }
    let start = try #require(columns.first)
    let end = try #require(columns.last)
    #expect(end >= start + 8, "the badge did not travel to the right slot: \(columns)")
    #expect(
      columns.contains { $0 > start && $0 < end },
      "the badge jumped instead of sliding: \(columns)"
    )
    #expect(
      Self.latestColumn(of: "★18x3", in: host) != nil, "the badge did not adopt its slot size")
  }

  // MARK: - Transactions page

  @Test(
    "section 14: the key-path transaction snaps one write inside an animated scope",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func keyPathTransactionSection() async throws {
    let needle = "state: accent="
    let host = try await Self.drive(
      page: .transactions,
      section: 14,
      strip: "section-14-with-transaction-key-path",
      stateNeedle: needle,
      controls: ["animate", "snap"]
    ) { host, at in
      [.awaitCondition { Self.latestState(host, needle).contains("accent=false lastWrite=none") }]
        + Step.click(at["snap"]!) + [
          .awaitCondition { Self.latestState(host, needle).contains("accent=true lastWrite=snap") }
        ] + Step.click(at["animate"]!) + [
          .awaitCondition {
            Self.latestState(host, needle).contains("accent=false lastWrite=animate")
          }
        ]
    }

    #expect(Self.latestState(host, needle).contains("accent=false lastWrite=animate"))
  }

  @Test(
    "section 15: .transaction(value:) animates only across a ten",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func valueTransactionSection() async throws {
    let needle = "state: count="
    var restColumn: Int?
    let host = try await Self.drive(
      page: .transactions,
      section: 15,
      strip: "section-15-transaction-value",
      stateNeedle: needle,
      controls: ["+1", "+10"]
    ) { host, at in
      [
        .awaitCondition {
          restColumn = Self.latestColumn(of: "▶ 0", in: host)
          return restColumn != nil
        }
      ] + Step.click(at["+10"]!) + [
        .awaitCondition {
          guard let restColumn else { return false }
          return Self.latestState(host, needle).contains("count=10 tens=1")
            && Self.latestColumn(of: "▶ 10", in: host) == restColumn + 4
        }
      ] + Step.click(at["+1"]!) + [
        .awaitCondition { Self.latestState(host, needle).contains("count=11 tens=1") }
      ]
    }

    let start = try #require(restColumn)
    let slideColumns = Self.columns(of: "▶ 10", in: host).compactMap { $0 }
    #expect(
      slideColumns.contains { $0 > start && $0 < start + 4 },
      "crossing a ten jumped instead of sliding: \(slideColumns)"
    )
    #expect(Self.latestColumn(of: "▶ 11", in: host) == start + 4, "+1 moved the counter")
  }

  @Test(
    "section 16: the scoped body forms animate one modifier and hold the other",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func scopedTransactionSection() async throws {
    let needle = "state: scopedShift="
    var scopedRest: Int?
    var heldRest: Int?
    let host = try await Self.drive(
      page: .transactions,
      section: 16,
      strip: "section-16-scoped-body-forms",
      stateNeedle: needle,
      controls: ["shift (plain write)", "shift (withAnimation)"]
    ) { host, at in
      [
        .awaitCondition {
          scopedRest = Self.latestColumn(of: "▶ scoped offset", in: host)
          heldRest = Self.latestColumn(of: "▶ held opacity", in: host)
          return scopedRest != nil && heldRest != nil
        }
      ] + Step.click(at["shift (plain write)"]!) + [
        .awaitCondition {
          guard let scopedRest else { return false }
          return Self.latestState(host, needle).contains("scopedShift=true")
            && Self.latestColumn(of: "▶ scoped offset", in: host) == scopedRest + 24
        }
      ] + Step.click(at["shift (withAnimation)"]!) + [
        .awaitCondition {
          guard let heldRest else { return false }
          return Self.latestState(host, needle).contains("heldShift=true")
            && Self.latestColumn(of: "▶ held opacity", in: host) == heldRest + 24
        }
      ]
    }

    let scopedStart = try #require(scopedRest)
    let heldStart = try #require(heldRest)
    let scopedColumns = Self.columns(of: "▶ scoped offset", in: host).compactMap { $0 }
    let heldColumns = Self.columns(of: "▶ held opacity", in: host).compactMap { $0 }
    #expect(
      scopedColumns.contains { $0 > scopedStart && $0 < scopedStart + 24 },
      ".animation(_:body:) did not slide the offset: \(scopedColumns)"
    )
    #expect(
      heldColumns.contains { $0 > heldStart && $0 < heldStart + 24 },
      "the wrapped offset under .transaction(_:body:) did not slide: \(heldColumns)"
    )
  }

  @Test(
    "section 17: two transaction completions fire together and .removed waits for the fade",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func completionListSection() async throws {
    let needle = "state: completions="
    var fadeClickFrame = 0
    let host = try await Self.drive(
      page: .transactions,
      section: 17,
      strip: "section-17-add-animation-completion",
      stateNeedle: needle,
      controls: ["run pair", "fade out"]
    ) { host, at in
      [.awaitCondition { Self.latestState(host, needle).contains("completions=0") }]
        + Step.click(at["run pair"]!) + [
          .awaitCondition { Self.latestState(host, needle).contains("completions=2") },
          .awaitCondition {
            fadeClickFrame = host.surfaces.count
            return true
          },
        ] + Step.click(at["fade out"]!) + [
          .awaitCondition { Self.latestState(host, needle).contains("shown=false") },
          // The `.removed` barrier of a removal transition is released one
          // committed turn after its curve ends, and the runtime schedules
          // no such turn itself (swift-tui b826fc9c): with nothing else on
          // screen the run loop idles and the completion waits for the next
          // input. Re-running the pair supplies that input (a focus move
          // would do, but a Tab press with the page picker focused trips the
          // F66 oracle noted at the drag probe below) until it fires.
          .nudge(Step.click(at["run pair"]!).events, every: .seconds(3)) {
            Self.latestState(host, needle).contains("removed=1")
          },
        ]
    }

    let states = Self.states(host, needle)
    #expect(!states.contains { $0.contains("completions=1 ") }, "the two completions fired apart")
    let removedFrame = try #require(states.firstIndex { $0.contains("removed=1") })
    let hiddenFrame = try #require(states.firstIndex { $0.contains("shown=false") })
    #expect(hiddenFrame >= fadeClickFrame)
    #expect(removedFrame > hiddenFrame, ".removed fired before the removal began")
  }

  @Test(
    "section 18: a retargeted spring turns back and settles at home",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func trackedVelocityRetargetSection() async throws {
    let needle = "state: x="
    var home: Int?
    let host = try await Self.drive(
      page: .transactions,
      section: 18,
      strip: "section-18-tracks-velocity-retarget",
      stateNeedle: needle,
      controls: ["◆", "retarget spring"]
    ) { host, at in
      [
        .awaitCondition {
          home = Self.latestColumn(of: "◆", in: host)
          return home != nil
        }
      ] + Step.click(at["retarget spring"]!) + [
        .awaitCondition { Self.latestState(host, needle).contains("x=50") },
        .awaitCondition {
          guard let home else { return false }
          return Self.latestState(host, needle).contains("x=20")
            && Self.marker("◆", restsAt: home, forLast: 4, in: host)
        },
      ]
    }

    // The readout is the check: the first spring's target (x=50) and the
    // retarget (x=20) both showed, and the marker ends at home. How far the
    // marker travels before the retarget depends on how much animation time
    // the 300 ms wall-clock gap covers: under this harness the animation
    // clock advances one frame step per presented frame, so a slow debug
    // build may retarget after a cell or less.
    let restColumn = try #require(home)
    let states = Self.states(host, needle)
    let retargetFrame = try #require(states.firstIndex { $0.contains("x=50") })
    #expect(states[retargetFrame...].contains { $0.contains("x=20") })
    #expect(Self.latestColumn(of: "◆", in: host) == restColumn)
  }

  // A velocity-tracked drag cannot be driven through this harness today: the
  // first `.dragged` pointer sample on the Animations tab trips the DEBUG
  // oracle in `AnimationController.noteSkippedResolvedTreeProcessing`
  // ("processResolvedTree skipped for a resolved tree that differs in
  // animation-processing inputs") and kills the test process. The divergence
  // is the page picker's segmented body: the last-processed tree holds
  // `PickerOption[0]` where the fully reused tree holds its `Group[0]`
  // wrapper. It is a resolve-side seam, not this tab's animation content: a
  // Tab press or a press-and-drag trips it on the Transitions and
  // Transactions pages only, on the G1 gallery (`618e07c`) against swift-tui
  // 0.9.9 as well as HEAD (plan 2026-08-25-002 §12 follow-ups). Drag section
  // 18 by hand until the seam is settled; this probe stays listed so the gap
  // is visible.
  @Test(
    "section 18: a velocity-tracked drag springs home",
    .disabled("a .dragged pointer sample trips the F66 skip-gate oracle (pre-existing at 0.9.9)"))
  func trackedVelocityFlingSection() async throws {
    let needle = "state: x="
    var home: Int?
    let host = try await Self.drive(
      page: .transactions,
      section: 18,
      strip: "section-18-tracks-velocity-fling",
      stateNeedle: needle,
      controls: ["◆"]
    ) { host, at in
      let start = at["◆"]!
      func sample(_ delta: Int) -> Point {
        Point(x: start.x + Double(delta), y: start.y)
      }
      // Four velocity-tracked samples 40 ms apart, then the release.
      var steps: [Step] = [
        .awaitCondition {
          home = Self.latestColumn(of: "◆", in: host)
          return home != nil
        },
        .event(.mouse(.init(kind: .down(.primary), location: start))),
      ]
      for delta in stride(from: 3, through: 12, by: 3) {
        steps += [
          .sleep(.milliseconds(40)),
          .event(.mouse(.init(kind: .dragged(.primary), location: sample(delta)))),
          .awaitCondition { Self.latestState(host, needle).contains("lastDelta=\(delta)") },
        ]
      }
      steps += [
        .event(.mouse(.init(kind: .up(.primary), location: sample(12)))),
        .awaitCondition {
          guard let home else { return false }
          return Self.latestState(host, needle).contains("x=20 lastDelta=12")
            && Self.marker("◆", restsAt: home, forLast: 4, in: host)
        },
      ]
      return steps
    }

    let restColumn = try #require(home)
    let columns = Self.columns(of: "◆", in: host).compactMap { $0 }
    #expect(
      columns.contains { $0 >= restColumn + 12 }, "the drag never moved the marker: \(columns)")
    #expect(columns.last == restColumn)
    let elapsed = Self.readout("elapsedMs", in: Self.latestState(host, needle)) ?? 0
    #expect(elapsed > 0, "the drag readout recorded no elapsed time")
  }

  @Test(
    "section 19: logicallyComplete(after:) fires early and .removed waits for the spring",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func logicallyCompleteSection() async throws {
    let needle = "state: logical="
    var clickFrame = 0
    let host = try await Self.drive(
      page: .transactions,
      section: 19,
      strip: "section-19-logically-complete",
      stateNeedle: needle,
      controls: ["run spring"]
    ) { host, at in
      [
        .awaitCondition {
          clickFrame = host.surfaces.count
          return Self.latestState(host, needle).contains("logical=0 removed=0")
        }
      ] + Step.click(at["run spring"]!) + [
        .awaitCondition { Self.latestState(host, needle).contains("logical=1 removed=0") },
        .awaitCondition { Self.latestState(host, needle).contains("logical=1 removed=1") },
      ]
    }

    let states = Self.states(host, needle)
    let logicalFrame = try #require(states.firstIndex { $0.contains("logical=1") })
    let removedFrame = try #require(states.firstIndex { $0.contains("removed=1") })
    // Order and counts only. The strip carries the frame gap between the two
    // barriers: today it is one frame, because the state write the
    // `.logicallyComplete` closure makes snaps the still-bouncing spring to
    // its end value and `.removed` follows on the next frame (swift-tui
    // b826fc9c; without the write the spring runs its full course).
    #expect(logicalFrame > clickFrame)
    #expect(removedFrame > logicalFrame, ".removed fired before .logicallyComplete")
    #expect(states.last?.contains("logical=1 removed=1 wide=true") == true)
  }

  // MARK: - Driver

  /// Drives one section: renders `page` statically to locate `controls`,
  /// runs the run loop over `steps` plus the exit key, fails on a wait
  /// ceiling, and writes the recording as the `strip` frame strip.
  private static func drive(
    page: AnimationsPage,
    section: Int,
    strip: String,
    stateNeedle: String,
    controls: [String],
    steps: (AnimationRegressionRecordingHost, [String: Point]) -> [Step]
  ) async throws -> AnimationRegressionRecordingHost {
    let rootIdentity = Identity(components: [.named("AnimationSectionRuntime")])
    var locations: [String: Point] = [:]
    for control in controls {
      // Search below the section's title so a label that also occurs in the
      // tab header or an earlier section ("animate" in "animates") cannot
      // capture the click.
      locations[control] = try AnimationRegressionHarness.centerOfText(
        control,
        after: "\(section). ",
        in: AnimationsTab(initialPage: page),
        terminalSize: terminalSize,
        rootIdentity: rootIdentity
      )
    }

    let host = AnimationRegressionRecordingHost(size: terminalSize)
    let inputReader = AnimationRegressionAwaitedInputReader(
      frameSignal: host.frameSignal,
      steps: steps(host, locations) + [.exit]
    )
    let result = try await AnimationRegressionHarness.run(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      inputReader: inputReader,
      viewBuilder: { AnimationsTab(initialPage: page) }
    )
    // The strip is written before the ceiling check so a stalled section
    // still leaves its recording behind for inspection.
    try GalleryFrameStrip.write(name: strip, host: host, stateNeedle: stateNeedle)
    // Fails with the named ceiling diagnostic if the section stopped
    // presenting frames, instead of leaving the assertions to report a
    // confusing mismatch against a truncated capture.
    try await inputReader.requireNoWaitFailure()
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    return host
  }

  // MARK: - Readout helpers

  /// The section's state line on the latest frame, trailing spaces removed.
  /// Reads only the last surface: predicates run on every presented frame,
  /// so scanning the whole recording here would make each frame cost more
  /// than the one before it.
  private static func latestState(
    _ host: AnimationRegressionRecordingHost,
    _ needle: String
  ) -> String {
    host.surfaces.last.map { state(in: $0, needle) } ?? ""
  }

  private static func state(in surface: RasterSurface, _ needle: String) -> String {
    surface.lines.first { $0.contains(needle) }
      .map(GalleryFrameStrip.trimmingTrailingSpaces) ?? ""
  }

  /// The section's state line on every frame ("" where it is off screen).
  private static func states(
    _ host: AnimationRegressionRecordingHost,
    _ needle: String
  ) -> [String] {
    host.surfaces.map { state(in: $0, needle) }
  }

  /// `key=<integer>` from a state line.
  private static func readout(_ key: String, in state: String) -> Int? {
    for field in state.split(separator: " ") where field.hasPrefix("\(key)=") {
      return Int(field.dropFirst(key.count + 1))
    }
    return nil
  }

  private static func latestColumn(
    of text: String,
    in host: AnimationRegressionRecordingHost
  ) -> Int? {
    host.surfaces.last.flatMap { AnimationRegressionHarness.column(of: text, in: $0) }
  }

  private static func columns(
    of text: String,
    in host: AnimationRegressionRecordingHost
  ) -> [Int?] {
    host.surfaces.map { AnimationRegressionHarness.column(of: text, in: $0) }
  }

  /// Whether `text` sat at `column` on each of the last `frames` frames: the
  /// settle signal for a spring with no completion of its own.
  private static func marker(
    _ text: String,
    restsAt column: Int,
    forLast frames: Int,
    in host: AnimationRegressionRecordingHost
  ) -> Bool {
    let recent = host.surfaces.suffix(frames)
    return recent.count == frames
      && recent.allSatisfy { AnimationRegressionHarness.column(of: text, in: $0) == column }
  }
}
