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

  // MARK: - Transitions page

  @Test(
    "section 2: the slide figure slides back in on its own, with no further input",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func slideTransitionSection() async throws {
    // Regression for the reported gallery bug. Slide OUT was fine; slide IN
    // was invisible unless you clicked during the animation, and a late click
    // popped the figure straight to its final position. The insertion
    // registers only a placed-level offset animation, and off-screen frame
    // elision used to skip that animation's pass forever — the arriving figure
    // starts outside the clipped box, so it had never been drawn, so the gate
    // read every deadline tick as unable to reach the screen. The two clicks
    // below are the only input: everything after the second one has to run on
    // animation deadlines alone, and a stall stops the frames the awaited
    // steps wait on, ending the test at the gallery ceiling with a named
    // diagnostic.
    let needle = "state: showFade="
    var fullInk = 0
    var arrivalFirstFrame = 0
    let host = try await Self.drive(
      page: .transitions,
      section: 2,
      strip: "section-2-transitions",
      stateNeedle: needle,
      // The label tracks the state ("slide out" while the figure is up), and
      // the button does not move between the two, so one location serves both
      // clicks.
      controls: ["slide out"]
    ) { host, at in
      [
        .awaitCondition {
          guard Self.latestState(host, needle).contains("showSlide=true") else { return false }
          fullInk = Self.latestFigureInk(host)
          return true
        }
      ]
        + Step.click(at["slide out"]!) + [
          .awaitCondition {
            // The exit is done when the box is empty: the departing overlay has
            // left the clipped box and been purged.
            guard Self.latestState(host, needle).contains("showSlide=false"),
              Self.latestFigureInk(host) == 0
            else { return false }
            arrivalFirstFrame = host.surfaces.count
            return true
          }
        ]
        + Step.click(at["slide out"]!) + [
          // The arrival is done when the box carries the whole figure again:
          // both ends of the comparison count the same coloured glyphs in the
          // same view state, so they are exactly equal on a completed
          // slide-in.
          .awaitCondition { Self.latestFigureInk(host) >= fullInk }
        ]
    }

    let arrival = host.surfaces.dropFirst(arrivalFirstFrame).map(Self.figureInk)
    #expect(arrival.last == fullInk, "the slide figure never arrived: \(arrival.suffix(20))")
    // Column by column, not all at once: the ink passes through the middle of
    // its range on the way in. This is the half the surface-relative edge
    // offset used to break — the figure started a whole screen away and only
    // entered the clipped box on the final frame.
    #expect(
      arrival.contains { $0 > 0 && $0 < fullInk },
      "the figure popped in instead of sliding: \(arrival)"
    )
  }

  /// Cells of the arriving/departing SLIDE figure on a frame.
  ///
  /// Counted by colour, not by glyph: the section stacks the coloured figure
  /// in an `.overlay` over an `opacity(0)` copy of itself, so the box holds a
  /// full set of invisible glyphs at the destination at all times. A
  /// character-based count would read that invisible copy as a fully arrived
  /// figure on every frame; only the yellow foreground belongs to the figure
  /// under test.
  private static func figureInk(_ surface: RasterSurface) -> Int {
    surface.cells.reduce(0) { total, row in
      total + row.count { $0.style?.foregroundColor == .yellow }
    }
  }

  private static func latestFigureInk(_ host: AnimationRegressionRecordingHost) -> Int {
    host.surfaces.last.map(figureInk) ?? 0
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

  @Test(
    "section 13: the badge adopts the card, follows its move, and slides home on detach",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func adoptionSection() async throws {
    let needle = "state: cardSlot="
    var adoptedAtLeft: CellRect?
    var adoptedAtRight: CellRect?
    var homeAfterDetach: CellRect?
    let host = try await Self.drive(
      page: .matched,
      section: 13,
      strip: "section-13-adoption",
      stateNeedle: needle,
      controls: ["move card", "detach card"]
    ) { host, at in
      [
        // At rest the badge is already adopted: drawn somewhere above its
        // "badge home:" layout row (on the card), with no animation run yet.
        .awaitCondition {
          guard Self.latestState(host, needle).contains("cardSlot=left attached=true") else {
            return false
          }
          adoptedAtLeft = Self.latestBounds(of: "NEW", in: host, section: 13)
          guard let adoptedAtLeft, let home = Self.latestBounds(of: "badge home:", in: host) else {
            return false
          }
          return adoptedAtLeft.origin.y < home.origin.y
        },
      ] + Step.click(at["move card"]!) + [
        // The move's completion closure is the settle authority (see the
        // section 18 tests); the badge must have followed the card right.
        .awaitCondition {
          guard Self.readout("settled", in: Self.latestState(host, needle)) == 1 else {
            return false
          }
          adoptedAtRight = Self.latestBounds(of: "NEW", in: host, section: 13)
          guard let adoptedAtRight, let adoptedAtLeft else { return false }
          return adoptedAtRight.origin.x >= adoptedAtLeft.origin.x + 8
        },
      ] + Step.click(at["detach card"]!) + [
        // With no source on screen the badge owns its layout slot again: same
        // row as the "badge home:" label.
        .awaitCondition {
          guard Self.latestState(host, needle).contains("attached=false"),
            Self.readout("settled", in: Self.latestState(host, needle)) == 2
          else { return false }
          homeAfterDetach = Self.latestBounds(of: "NEW", in: host, section: 13)
          guard let homeAfterDetach, let home = Self.latestBounds(of: "badge home:", in: host)
          else { return false }
          return homeAfterDetach.origin.y == home.origin.y
        },
      ] + Step.click(at["detach card"]!) + [
        // Re-attach at the third slot: the badge adopts the new source's
        // rect, further right than either of the first two slots.
        .awaitCondition {
          guard Self.latestState(host, needle).contains("cardSlot=third attached=true"),
            Self.readout("settled", in: Self.latestState(host, needle)) == 3,
            let bounds = Self.latestBounds(of: "NEW", in: host, section: 13),
            let home = Self.latestBounds(of: "badge home:", in: host),
            let adoptedAtRight
          else { return false }
          return bounds.origin.y < home.origin.y && bounds.origin.x > adoptedAtRight.origin.x
        },
      ]
    }

    let leftRect = try #require(adoptedAtLeft)
    let rightRect = try #require(adoptedAtRight)
    let homeRect = try #require(homeAfterDetach)
    #expect(rightRect.origin.y == leftRect.origin.y, "the badge left the slots row on the move")
    #expect(
      homeRect.origin.y > leftRect.origin.y,
      "the detached badge should sit below the slots row, at its own slot"
    )
    #expect(Self.latestState(host, needle).contains("moves=1"))
  }

  // MARK: - Transitions page

  @Test(
    "section 21: the numericText counter rolls through intermediate digits",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func rollingCounterSection() async throws {
    let needle = "state: count="
    let host = try await Self.drive(
      page: .transitions,
      section: 21,
      strip: "section-21-rolling-counter",
      stateNeedle: needle,
      controls: ["roll to 68"]
    ) { host, at in
      [
        .awaitCondition { Self.latestState(host, needle).contains("count=41") }
      ] + Step.click(at["roll to 68"]!) + [
        // The model snaps to 68 at the click; the drawn counter only reaches
        // "68" once the per-column roll has run its course.
        .awaitCondition {
          Self.latestState(host, needle).contains("count=68")
            && Self.counterText(in: host) == "▶ 68"
        },
      ]
    }

    // The roll's whole point: mid-flight frames draw digits that are neither
    // the old nor the new value (41's ones column has seven intermediates on
    // its way to 8), so even a text capture distinguishes a roll from a cut.
    let counters = host.surfaces.compactMap { Self.counterText(in: $0) }
    #expect(counters.last == "▶ 68")
    #expect(
      counters.contains { $0 != "▶ 41" && $0 != "▶ 68" },
      "no frame showed an intermediate digit; the counter cut instead of rolling: \(counters)"
    )
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
          home = Self.latestColumn(of: "◆", in: host, section: 18)
          return home != nil
        }
      ] + Step.click(at["retarget spring"]!) + [
        .awaitCondition { Self.latestState(host, needle).contains("x=50") },
        // `settled=1` is the retarget spring's completion closure: it fires
        // only when the spring truly finishes, so the wait cannot be
        // satisfied mid-oscillation when frames are sparse under load (the
        // marker-at-rest readout alone aliased that way, 1-in-6 under a
        // parallel full suite). The marker check then pins the rest column.
        .awaitCondition {
          guard let home else { return false }
          return Self.latestState(host, needle).contains("x=20")
            && Self.readout("settled", in: Self.latestState(host, needle)) == 1
            && Self.marker("◆", restsAt: home, forLast: 2, in: host, section: 18)
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
    #expect(Self.latestColumn(of: "◆", in: host, section: 18) == restColumn)
  }

  // Drives the real gesture path: a press on the marker, four velocity-tracked
  // `.dragged` samples, then the release whose spring keeps the drag's
  // velocity.
  //
  // This probe was `.disabled` from 2026-08-25 to 2026-08-30, blamed first on
  // the F66 skip-gate oracle and later on a "runtime stall" at input step 4.
  // Re-enabled 2026-08-30: it passes against the pinned 0.9.11 framework with
  // the DEBUG oracles armed, so neither diagnosis holds on this path. Three
  // harness defects were: `centerOfText(after:)` searched from the
  // anchor row *inclusive*, so `"◆"` matched this section's own title prose
  // ("drag the ◆ and release") four rows above the marker — the press landed
  // on a `Text` with no gesture, nothing changed, and the runtime correctly
  // went idle while the wait blamed a stalled animation; `column(of:)` had no
  // row floor, so every `"◆"` readout tracked that same title glyph; and every
  // scripted `MouseEvent` shared one construction-time timestamp, so the
  // release measured a zero-length drag. The framework's drag path was correct
  // throughout — translations arrive as 0/3/6/9/12.
  @Test(
    "section 18: a velocity-tracked drag springs home")
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
      // Every scripted event is constructed before the run starts, so the
      // default `.now()` stamp would give all of them one instant and the
      // release would measure a zero-length drag (`elapsedMs=0`). Stamp
      // deterministic, advancing times, as `MouseEvent.timestamp` prescribes.
      let base = MonotonicInstant.now()
      func stamp(_ milliseconds: Int) -> MonotonicInstant {
        base.advanced(by: .milliseconds(milliseconds))
      }
      // Four velocity-tracked samples 40 ms apart, then the release.
      var steps: [Step] = [
        .awaitCondition {
          home = Self.latestColumn(of: "◆", in: host, section: 18)
          return home != nil
        },
        .event(.mouse(.init(kind: .down(.primary), location: start, timestamp: stamp(0)))),
      ]
      for delta in stride(from: 3, through: 12, by: 3) {
        steps += [
          .sleep(.milliseconds(40)),
          .event(
            .mouse(
              .init(
                kind: .dragged(.primary),
                location: sample(delta),
                timestamp: stamp(40 * (delta / 3))
              ))),
          .awaitCondition { Self.latestState(host, needle).contains("lastDelta=\(delta)") },
        ]
      }
      steps += [
        .event(
          .mouse(.init(kind: .up(.primary), location: sample(12), timestamp: stamp(200)))),
        // As in the retarget test: the release spring's completion closure
        // (`settled=1`) is the settle authority; the marker readout only
        // confirms where it came to rest.
        .awaitCondition {
          guard let home else { return false }
          return Self.latestState(host, needle).contains("x=20 lastDelta=12")
            && Self.readout("settled", in: Self.latestState(host, needle)) == 1
            && Self.marker("◆", restsAt: home, forLast: 2, in: host, section: 18)
        },
      ]
      return steps
    }

    let restColumn = try #require(home)
    let columns = Self.columns(of: "◆", in: host, section: 18).compactMap { $0 }
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
    // Order and counts only. Against 0.9.12 the strip shows the two barriers
    // one frame apart with the bar jumping 35 → 40 on the `logical=1` frame:
    // root-caused 2026-08-31 (org T5) as a frame-clock bug, not a completion
    // bug — under this harness's per-frame predicate cost the run loop lags
    // the 30 fps cadence, deadline frames animate to their *scheduled*
    // instants, and the closure's state write woke a non-deadline frame that
    // sampled at the wall clock, advancing the spring by the whole
    // accumulated lag at once. Fixed in swift-tui (`deriveFrameInstant`
    // clamps wake frames to the armed deadline chain; pinned by
    // `AnimationLogicalCompletionAsyncTests`); the strip shows the spring's
    // full course once a tag carries the fix.
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

  /// `section` scopes the search below that section's title row; omit it when
  /// the target cannot collide with title prose.
  private static func latestColumn(
    of text: String,
    in host: AnimationRegressionRecordingHost,
    section: Int? = nil
  ) -> Int? {
    host.surfaces.last.flatMap {
      AnimationRegressionHarness.column(of: text, in: $0, from: floor(section, in: $0))
    }
  }

  private static func columns(
    of text: String,
    in host: AnimationRegressionRecordingHost,
    section: Int? = nil
  ) -> [Int?] {
    host.surfaces.map {
      AnimationRegressionHarness.column(of: text, in: $0, from: floor(section, in: $0))
    }
  }

  private static func floor(_ section: Int?, in surface: RasterSurface) -> Int {
    section.map { AnimationRegressionHarness.rowBelowSectionTitle($0, in: surface) } ?? 0
  }

  /// Bounds of `text` on the latest frame, scoped below `section`'s title
  /// when given (see `latestColumn`).
  private static func latestBounds(
    of text: String,
    in host: AnimationRegressionRecordingHost,
    section: Int? = nil
  ) -> CellRect? {
    host.surfaces.last.flatMap {
      AnimationRegressionHarness.boundsOfText(text, in: $0, from: floor(section, in: $0))
    }
  }

  /// The section 21 odometer ("▶ NN") as drawn on `surface`, or `nil` when
  /// the counter is off screen.
  private static func counterText(in surface: RasterSurface) -> String? {
    let floor = AnimationRegressionHarness.rowBelowSectionTitle(21, in: surface)
    guard let bounds = AnimationRegressionHarness.boundsOfText("▶ ", in: surface, from: floor)
    else { return nil }
    let line = surface.lines[bounds.origin.y]
    return GalleryFrameStrip.trimmingTrailingSpaces(
      String(line.dropFirst(bounds.origin.x).prefix(4)))
  }

  private static func counterText(in host: AnimationRegressionRecordingHost) -> String? {
    host.surfaces.last.flatMap { Self.counterText(in: $0) }
  }

  /// Whether `text` sat at `column` on each of the last `frames` frames: the
  /// settle signal for a spring with no completion of its own.
  private static func marker(
    _ text: String,
    restsAt column: Int,
    forLast frames: Int,
    in host: AnimationRegressionRecordingHost,
    section: Int? = nil
  ) -> Bool {
    let recent = host.surfaces.suffix(frames)
    return recent.count == frames
      && recent.allSatisfy {
        AnimationRegressionHarness.column(of: text, in: $0, from: floor(section, in: $0)) == column
      }
  }
}
