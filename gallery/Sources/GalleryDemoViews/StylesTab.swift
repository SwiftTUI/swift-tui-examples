import SwiftTUIRuntime

/// The pages of the Styles tab. The raw value is the command-line key
/// accepted by `gallery-demo --styles-page <key>`.
public enum StylesPage: String, CaseIterable, Hashable, Sendable {
  case controls
  case values
  case containers
  case presentation
  case scoping

  /// Segment title shown in the page picker.
  public var title: String {
    switch self {
    case .controls: "Controls"
    case .values: "Values"
    case .containers: "Containers"
    case .presentation: "Presentation"
    case .scoping: "Scoping"
    }
  }
}

/// A paged workbench for the style system: every one of SwiftTUI's open style
/// families, its built-in styles side by side, and one custom conformance per
/// family so the open-protocol contract is visible, not just claimed.
///
/// Every section follows one template so a reader can verify it without the
/// source:
///
/// ```
/// N. <FamilyStyle>                               muted
///    built-ins: .a · .b · .c                     separator
///    <the built-ins, one control each, in that order>
///    custom: <ConformanceName>                   separator
///    <the same control under the custom style>
/// ```
///
/// Section numbers stay sequential across pages so a bug report can cite
/// "section 9" without naming the page. The custom conformances live in
/// `StylesTab+CustomStyles.swift` and are the same shapes the DocC style
/// guides use, so the gallery doubles as a compiled copy of the docs.
///
/// Section state lives on the tab, not on the pages, so a page's readouts
/// survive switching away and back. Each page is its own small `View` struct
/// that receives bindings to that state (`ControlsPage`, `ValuesPage`, and so
/// on, one per sibling file). That shape is load-bearing: the page switch
/// below is an enum whose size is the largest page, and the gallery shell
/// copies the selected tab's value once per modifier on its root chain while
/// resolving. A page struct is a few bindings wide; a page built inline from
/// its sections would be tens of kilobytes and overflow the resolve stack.
public struct StylesTab: View {
  @State private var page: StylesPage

  /// Creates the tab open on `initialPage` (Controls by default).
  public init(initialPage: StylesPage = .controls) {
    _page = State(initialValue: initialPage)
  }

  // MARK: - Controls page state

  @State var buttonPresses: Int = 0
  @State var toggleOn: Bool = true
  @State var fieldText: String = "swift-tui"
  @State var pickerChoice: String = "Lists"

  // MARK: - Values page state

  @State var sliderValue: Double = 0.4
  @State var stepperValue: Int = 3
  @State var progress: Double = 0.6
  @State var editorText: String = "Styled editors keep\nthe same caret map."

  // MARK: - Containers page state

  @State var disclosureOpen: Bool = true
  @State var listSelection: String = "alpha"
  @State var tableSelection: String = "queued"
  @State var nestedTab: Int = 0
  @State var menuPicks: Int = 0

  // MARK: - Presentation page state

  @State var showSurfaceSheet: Bool = false
  @State var showDropdownSheet: Bool = false
  @State var showWideSheet: Bool = false
  @State var showAlert: Bool = false
  @State var showConfirmation: Bool = false
  @State var showCompactAlert: Bool = false
  @State var showPopover: Bool = false
  @State var showStyledPopover: Bool = false
  @State var showCover: Bool = false
  @State var showInsetCover: Bool = false
  @State var showInfoToast: Bool = false
  @State var showSuccessToast: Bool = false
  @State var showWarningToast: Bool = false
  @State var showDangerToast: Bool = false
  @State var showPinnedToast: Bool = false
  @State var showPalette: Bool = false
  @State var lastPresentationEvent: String = "nothing opened yet"

  // MARK: - Scoping page state

  @State var kit: StyleKit = .standard
  @State var kitToggle: Bool = true
  @State var kitText: String = "one modifier chain"
  @State var kitProgress: Double = 0.5
  @State var kitSlider: Double = 0.25
  @State var kitStepper: Int = 2
  @State var kitSaves: Int = 0

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
      Text("Styles").foregroundStyle(.foreground)
      Text(
        "Every style family is an open protocol. Each section shows the built-ins, then one custom conformance."
      )
      .foregroundStyle(.separator)
    }
  }

  private var pagePicker: some View {
    Picker("Page", selection: $page) {
      ForEach(StylesPage.allCases, id: \.self) { page in
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
    case .controls:
      ControlsPage(
        buttonPresses: $buttonPresses,
        toggleOn: $toggleOn,
        fieldText: $fieldText,
        pickerChoice: $pickerChoice
      )
    case .values:
      ValuesPage(
        sliderValue: $sliderValue,
        stepperValue: $stepperValue,
        progress: $progress,
        editorText: $editorText
      )
    case .containers:
      ContainersPage(
        disclosureOpen: $disclosureOpen,
        listSelection: $listSelection,
        tableSelection: $tableSelection,
        nestedTab: $nestedTab,
        menuPicks: $menuPicks
      )
    case .presentation:
      PresentationPage(
        showSurfaceSheet: $showSurfaceSheet,
        showDropdownSheet: $showDropdownSheet,
        showWideSheet: $showWideSheet,
        showAlert: $showAlert,
        showConfirmation: $showConfirmation,
        showCompactAlert: $showCompactAlert,
        showPopover: $showPopover,
        showStyledPopover: $showStyledPopover,
        showCover: $showCover,
        showInsetCover: $showInsetCover,
        showInfoToast: $showInfoToast,
        showSuccessToast: $showSuccessToast,
        showWarningToast: $showWarningToast,
        showDangerToast: $showDangerToast,
        showPinnedToast: $showPinnedToast,
        showPalette: $showPalette,
        lastPresentationEvent: $lastPresentationEvent
      )
    case .scoping:
      ScopingPage(
        kit: $kit,
        kitToggle: $kitToggle,
        kitText: $kitText,
        kitProgress: $kitProgress,
        kitSlider: $kitSlider,
        kitStepper: $kitStepper,
        kitSaves: $kitSaves
      )
    }
  }

  /// Two-place fixed-point text for a readout, without Foundation.
  static func readout(_ value: Double) -> String {
    let hundredths = Int((value * 100).rounded())
    let whole = hundredths / 100
    let fraction = hundredths % 100
    return "\(whole)." + (fraction < 10 ? "0" : "") + "\(fraction)"
  }
}

// MARK: - Section template (shared by every page)

/// The muted section title. `number` is stable across pages.
@MainActor func styleSectionTitle(_ number: Int, _ family: String) -> some View {
  Text("\(number). \(family)")
    .foregroundStyle(.muted)
}

/// The built-in styles the section renders, in render order.
@MainActor func styleBuiltinsLine(_ names: [String]) -> some View {
  Text("built-ins: " + names.joined(separator: " · "))
    .foregroundStyle(.separator)
}

/// The custom conformance the section renders beneath the built-ins.
@MainActor func styleCustomLine(_ name: String) -> some View {
  Text("custom: \(name)")
    .foregroundStyle(.separator)
}

/// A one-line note, for behaviour the render cannot show on its own.
@MainActor func styleNoteLine(_ text: String) -> some View {
  Text("note: \(text)")
    .foregroundStyle(.separator)
}

/// One page: a scroll view over its sections, separated by dividers.
@MainActor func stylePageScroll<Content: View>(
  @ViewBuilder _ content: () -> Content
) -> some View {
  ScrollView {
    VStack(alignment: .leading, spacing: 1) {
      content()
      Spacer(minLength: 0)
    }
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}

/// The value the gallery shell keeps in its tab tuple for the Styles tab.
///
/// `StylesTab` carries several dozen `@State` wrappers, so its value is large.
/// The shell's root modifier chain copies the whole tab tuple once per layer
/// while resolving, and that tuple already sat near the resolve stack's limit
/// (the Presentation Lab tab overflowed as soon as `StylesTab` joined it). A
/// host one field wide keeps the tuple at its previous size; the state itself
/// still belongs to the tab's identity, so dormant-tab archiving is unchanged.
public struct StylesTabHost: View {
  private let initialPage: StylesPage

  /// Creates the host open on `initialPage` (Controls by default).
  public init(initialPage: StylesPage = .controls) {
    self.initialPage = initialPage
  }

  public var body: some View {
    StylesTab(initialPage: initialPage)
  }
}
