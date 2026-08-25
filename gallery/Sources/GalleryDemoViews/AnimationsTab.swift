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
/// "section 4" without naming the page. Numbers 10 to 19 are reserved for
/// later stages.
///
/// All durations are long (1000 to 2000 ms) so the interpolation is
/// unmistakable on a 30fps terminal. Only the Keyframes page hosts an
/// always-on loop (section 7); every other section animates on demand.
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

  // MARK: - Matched page state

  // Matched geometry demo: which column the "hero" lives in.
  @State var heroOnRight: Bool = false
  // Namespace scoping the matched geometry key so the same "hero" string ID
  // would not collide with any other section's usage.
  @Namespace var heroNamespace

  // MARK: - Keyframes page state

  // Trigger-mode PhaseAnimator demo: each tap bumps the counter, which drives
  // one full pass through the phase sequence back to rest. The counter itself
  // is the trigger value.
  @State var bounceTrigger: Int = 0

  // MARK: - Transactions page state

  // Binding.animation demo: the bar width written through an animated
  // binding rather than an explicit withAnimation block.
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
