import Foundation
import SwiftTUIRuntime

/// The pages of the Animations tab. The raw value is the command-line key
/// accepted by `gallery-demo --animations-page <key>`.
public enum AnimationsPage: String, CaseIterable, Hashable, Sendable {
  case basics
  case transitions
  case matched
  case keyframes
  case transactions

  /// Segment title shown in the page picker.
  public var title: String {
    switch self {
    case .basics: "Basics"
    case .transitions: "Transitions"
    case .matched: "Matched"
    case .keyframes: "Keyframes"
    case .transactions: "Transactions"
    }
  }
}

/// A paged workbench for the public animation surface. Every section follows
/// one template so a reader can verify it without the source:
///
/// ```
/// N. <title>                                     muted
///    expect: <what you should see and roughly how long>
///    [buttons]                                   .focusSection()
///    <the animated subject, large, high-contrast>
///    state: <live readout of the driving value(s)>
/// ```
///
/// Section numbers stay sequential across pages so a bug report can cite
/// "section 4" without naming the page. Section 13 (co-present matched
/// geometry adoption) kept its reserved number when the deferred stage
/// shipped in 0.9.12, so it sits on the Matched page after section 6.
///
/// All durations are long (1000 to 2000 ms) so the interpolation is
/// unmistakable on a 30fps terminal. Only the Keyframes page hosts an
/// always-on loop (section 7); every other section animates on demand, and
/// the continuous demos (section 11) default to stopped.
///
/// Section state lives on the tab, not on the pages, so a page's readouts
/// survive switching away and back. The sections themselves are split into
/// sibling files, one per page (`AnimationsTab+Basics.swift` and so on).
public struct AnimationsTab: View {
  @State private var page: AnimationsPage

  /// Creates the tab open on `initialPage` (Basics by default).
  public init(initialPage: AnimationsPage = .basics) {
    _page = State(initialValue: initialPage)
  }

  // MARK: - Basics page state

  // Color demo: high-contrast red/blue toggle. Direct field mutation inside
  // the withAnimation closure, no mutating method indirection.
  @State var colorBlue: Bool = false
  @State var curveLabel: String = "none"

  // Frame demo: narrow/wide width.
  @State var wide: Bool = false

  // Offset demo: target offset the text slides to.
  @State var offsetX: Int = 0

  // Position demo: absolute target position the marker jumps to.
  @State var positionX: Int = 10
  @State var positionY: Int = 2

  // Completion demo: a counter ticked by the callback closure.
  @State var completionRuns: Int = 0
  @State var completionAccent: Bool = false

  // MARK: - Transitions page state

  // Transition demo: two independent toggles.
  @State var showOpacityFigure: Bool = true
  @State var showSlideFigure: Bool = true

  // Rolling counter (section 21): the odometer value. 41 is the DocC
  // example's seed; "roll to 68" exercises two columns of intermediates.
  @State var rollCount: Int = 41

  // MARK: - Matched page state

  // Matched geometry demo: which slot the badge lives in, what interpolates,
  // and around which anchor, plus move and settled counters for the readout.
  // The interpolated box is a placed-level overlay, so a GeometryReader
  // inside the badge only ever sees the destination size; the counters are
  // what the state line can report each frame.
  @State var heroOnRight: Bool = false
  @State var heroProperties: MatchedPropertiesChoice = .frame
  @State var heroAnchor: MatchedAnchorChoice = .center
  @State var heroMoves: Int = 0
  @State var heroSettled: Int = 0
  // Namespace scoping the matched geometry key so the same "hero" string ID
  // would not collide with any other section's usage.
  @Namespace var heroNamespace

  // Co-present adoption demo (section 13): where the source card sits, whether
  // it is in the tree at all, and move/settled counters for the readout. The
  // badge itself needs no state: an `isSource: false` instance renders at the
  // source's frame whenever a source is on screen.
  @State var cardSlot: AdoptionCardSlot = .left
  @State var cardAttached: Bool = true
  @State var cardMoves: Int = 0
  @State var cardSettled: Int = 0
  @Namespace var badgeNamespace

  // MARK: - Keyframes page state

  // Trigger-mode PhaseAnimator demo: each tap bumps the counter, which drives
  // one full pass through the phase sequence back to rest. The counter itself
  // is the trigger value.
  @State var bounceTrigger: Int = 0

  // Trigger-mode KeyframeAnimator demo (section 10): the run counter is the
  // trigger. The double-run request/served pair drives a task that bumps the
  // trigger twice 250 ms apart; served guards against a dormant-page replay.
  @State var keyframeRunTrigger: Int = 0
  @State var doubleRunRequest: Int = 0
  @State var doubleRunServed: Int = 0

  // Repeating-mode KeyframeAnimator demo (section 11): the animator is only
  // mounted while running, so the page idles at one loop (section 7).
  @State var breathingRunning: Bool = false

  // KeyframeTimeline curve strip (section 12): which timeline is charted.
  @State var curveStripKind: CurveStripKind = .linear

  // MARK: - Transactions page state

  // withTransaction key-path demo (section 14): one bar, two write paths.
  @State var keyPathAccent: Bool = false
  @State var keyPathLastWrite: String = "none"

  // .transaction(value:) demo (section 15): animates on the tens digit only.
  @State var tensCount: Int = 0

  // Scoped body forms (section 16): one flag per row so each button drives
  // exactly one row.
  @State var scopedShift: Bool = false
  @State var heldShift: Bool = false

  // addAnimationCompletion demo (section 17): two closures on one
  // transaction, plus a .removed-criteria closure on a transition.
  @State var pairAccent: Bool = false
  @State var pairCompletions: Int = 0
  @State var removableShown: Bool = true
  @State var removedCompletions: Int = 0

  // tracksVelocity fling (section 18): the marker's column on its track, the
  // last drag's readout, and the retarget request/served pair (see section
  // 10 for the pattern). `flingSettled` counts finished springs via the
  // withAnimation completion, so a reader (and the runtime test) has a
  // deterministic settle signal instead of watching the marker rest.
  @State var flingX: Int = AnimationsTab.flingHome
  @State var flingLastDelta: Int = 0
  @State var flingLastElapsedMilliseconds: Int = 0
  @State var flingDragStart: MonotonicInstant? = nil
  @State var flingSettled: Int = 0
  @State var retargetRequest: Int = 0
  @State var retargetServed: Int = 0

  // logicallyComplete(after:) demo (section 19): two barriers, two counters.
  @State var logicalWide: Bool = false
  @State var logicalCompletions: Int = 0
  @State var removedBarrierCompletions: Int = 0

  // Binding.animation demo (section 20): the bar width written through an
  // animated binding rather than an explicit withAnimation block.
  @State var transactionWide: Bool = false

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      pagePicker
      Divider()
      pageContent
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Animations").foregroundStyle(.foreground)
      Text("Pick a page. Each section says what to expect and prints the value it animates.")
        .foregroundStyle(.separator)
    }
  }

  private var pagePicker: some View {
    Picker("Page", selection: $page) {
      ForEach(AnimationsPage.allCases, id: \.self) { page in
        Text(page.title).tag(page)
      }
    }
    .pickerStyle(.segmented)
    // The segmented body is height-greedy (its inter-segment dividers
    // stretch), so pin it to its natural rows: label plus a three-row box.
    .frame(height: 4)
  }

  @ViewBuilder
  private var pageContent: some View {
    switch page {
    case .basics:
      basicsPage
    case .transitions:
      transitionsPage
    case .matched:
      matchedPage
    case .keyframes:
      keyframesPage
    case .transactions:
      transactionsPage
    }
  }

  // MARK: - Section template helpers

  /// The muted section title. `number` is stable across pages.
  func sectionTitle(_ number: Int, _ title: String) -> some View {
    Text("\(number). \(title)")
      .foregroundStyle(.muted)
  }

  /// One sentence: what the reader should see and roughly how long it takes.
  func expectLine(_ text: String) -> some View {
    Text("expect: \(text)")
      .foregroundStyle(.separator)
  }

  /// Live readout of the value(s) the section animates.
  func stateLine(_ text: String) -> some View {
    Text("state: \(text)")
      .foregroundStyle(.separator)
  }

  /// Fixed-point text for a readout. Negative zero is normalized so a
  /// settled value reads `0.0`, never `-0.0`.
  static func readout(_ value: Double, places: Int = 1) -> String {
    let text = String(format: "%.\(places)f", value)
    let negativeZero = "-0." + String(repeating: "0", count: places)
    return text == negativeZero ? String(text.dropFirst()) : text
  }

  /// A color's stored components as `r/g/b`, two places each.
  static func readout(_ color: Color) -> String {
    [color.red, color.green, color.blue]
      .map { readout($0, places: 2) }
      .joined(separator: "/")
  }

  /// One page: a scroll view over its sections, separated by dividers.
  func pageScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        content()
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
