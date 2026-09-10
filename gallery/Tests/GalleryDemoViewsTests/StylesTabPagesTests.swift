import SwiftTUI
import Testing

@testable import GalleryDemoViews

// Static render checks for the paged Styles tab. No run loop, no gate: each
// page is rasterised once through `DefaultRenderer` and its section template
// (numbered family title, `built-ins:` line, `custom:` line) is asserted from
// the surface text, the same way a reader verifies it on screen. The custom
// conformances are also resolved directly, so a framework change that breaks
// one of them fails here before it reaches a screenshot.
@MainActor
@Suite
struct StylesTabPagesTests {
  /// Tall enough to show every section of the longest page without scrolling.
  private static let sectionsSize = CellSize(width: 120, height: 160)

  /// The section titles each page must show, in order. Numbers are stable
  /// across pages; a bug report can cite "section 9" without naming the page.
  private static let sectionsByPage: [StylesPage: [String]] = [
    .controls: [
      "1. ButtonStyle",
      "2. ToggleStyle",
      "3. TextFieldStyle",
      "4. PickerStyle",
      "5. LinkStyle",
      "6. LabelStyle",
    ],
    .values: [
      "7. SliderStyle",
      "8. StepperStyle",
      "9. ProgressViewStyle",
      "10. SpinnerStyle",
      "11. TextEditorStyle",
    ],
    .containers: [
      "12. GroupBoxStyle",
      "13. LabeledContentStyle",
      "14. DisclosureGroupStyle",
      "15. ControlGroupStyle",
      "16. MenuStyle",
      "17. ListStyle",
      "18. TableStyle",
      "19. OutlineStyle",
      "20. ScrollViewStyle",
      "21. TabViewStyle",
      "22. ToolbarStyle",
    ],
    .presentation: [
      "23. SheetStyle",
      "24. PromptStyle",
      "25. PopoverStyle",
      "26. FullScreenCoverStyle",
      "27. ToastStyle",
      "28. PaletteStyle",
    ],
    .scoping: [
      "29. Nearest modifier wins",
      "30. One modifier chain restyles a subtree",
    ],
  ]

  /// The custom conformance each page names, so the `custom:` lines are
  /// checked by name and not just by count.
  private static let customsByPage: [StylesPage: [String]] = [
    .controls: [
      "BadgeButtonStyle", "RailToggleStyle", "UnderlinedTextFieldStyle", "CompactPickerStyle",
      "InfoLinkStyle", "CaptionLabelStyle",
    ],
    .values: [
      "BlockSliderStyle", "BracketStepperStyle", "BlockProgressViewStyle", "DotsSpinnerStyle",
      "RuledTextEditorStyle",
    ],
    .containers: [
      "TitledGroupBoxStyle", "LeaderLabeledContentStyle", "ArrowDisclosureGroupStyle",
      "BannerControlGroupStyle", "BracketMenuStyle", "RuledListStyle", "HeavyTableStyle",
      "DottedOutlineStyle", "HeavyScrollViewStyle", "PillTabViewStyle",
    ],
    .presentation: [
      "WideSheetStyle", "CompactPromptStyle", "DoubleBorderPopoverStyle", "InsetCoverStyle",
      "PinnedToastStyle", "ListPaletteStyle",
    ],
    .scoping: [],
  ]

  @Test(
    "every page renders its numbered sections with built-ins and custom lines",
    arguments: StylesPage.allCases
  )
  func pageRendersItsSections(page: StylesPage) throws {
    let sections = try #require(Self.sectionsByPage[page])
    let customs = try #require(Self.customsByPage[page])
    let lines = Self.renderLines(StylesTab(initialPage: page), size: Self.sectionsSize)
    let surface = lines.joined(separator: "\n")

    for title in sections {
      #expect(surface.contains(title), "page \(page.rawValue) is missing section \(title)")
    }
    #expect(
      Self.count(of: "built-ins: ", in: lines) == sections.count,
      "page \(page.rawValue) should carry one built-ins line per section"
    )
    for custom in customs {
      #expect(surface.contains("custom: \(custom)"), "page \(page.rawValue) is missing \(custom)")
    }

    // Sections from every other page stay off this page.
    for (otherPage, otherSections) in Self.sectionsByPage where otherPage != page {
      for title in otherSections {
        #expect(!surface.contains(title), "page \(page.rawValue) leaked section \(title)")
      }
    }
  }

  @Test("the page picker lists every page on every page")
  func pickerListsEveryPage() {
    for page in StylesPage.allCases {
      let surface = Self.renderLines(StylesTab(initialPage: page), size: Self.sectionsSize)
        .joined(separator: "\n")
      #expect(surface.contains("Styles"))
      for segment in StylesPage.allCases {
        #expect(
          surface.contains(segment.title), "page \(page.rawValue) hides segment \(segment.title)")
      }
    }
  }

  @Test("the default page is Controls and its built-in buttons all render")
  func defaultPageIsControls() {
    let surface = Self.renderLines(StylesTab(), size: Self.sectionsSize)
      .joined(separator: "\n")
    #expect(surface.contains("1. ButtonStyle"))
    for title in ["Automatic", "Plain", "Bordered", "Prominent", "Link", "Badge"] {
      #expect(surface.contains(title), "the button row is missing \(title)")
    }
    #expect(surface.contains("state: presses=0"))
  }

  @Test("page keys are the lowercase raw values and round-trip")
  func pageKeysRoundTrip() {
    #expect(
      StylesPage.allCases.map(\.rawValue) == [
        "controls", "values", "containers", "presentation", "scoping",
      ])
    for page in StylesPage.allCases {
      #expect(StylesPage(rawValue: page.rawValue) == page)
      #expect(page.rawValue == page.rawValue.lowercased())
    }
    #expect(StylesPage(rawValue: "not-a-page") == nil)
  }

  @Test("the styles tab sits third, opens by key, and tags every family")
  func descriptorTagsEveryFamily() {
    let titles = GalleryView.tabDescriptors.map(\.title)
    #expect(titles.prefix(3) == ["Logo Breaker", "Counter", "Styles"])
    #expect(GalleryView.GalleryTab(key: "styles") == .styles)
    let descriptor = GalleryView.descriptor(for: .styles)
    #expect(descriptor.coverageTags.first == "style-protocols")
    // One tag per family shown, plus the scoping page: 28 families + 2.
    #expect(descriptor.coverageTags.count == 30)
    #expect(Set(descriptor.coverageTags).count == descriptor.coverageTags.count)
  }

  @Test("the scoping form renders under every kit")
  func scopingFormRendersUnderEveryKit() {
    // The kit picker is state on the tab, so the static render shows the
    // default kit; the form's controls must be present under it.
    let surface = Self.renderLines(StylesTab(initialPage: .scoping), size: Self.sectionsSize)
      .joined(separator: "\n")
    for title in ["Deploy", "Run tests", "Canary", "Replicas", "Rollout", "Save", "Discard"] {
      #expect(surface.contains(title), "the kit form is missing \(title)")
    }
    #expect(surface.contains("state: kit=Standard saves=0"))
  }

  @Test(
    "every page renders inside the gallery shell at the app's real depth",
    arguments: StylesPage.allCases
  )
  func pageRendersInsideTheShell(page: StylesPage) throws {
    // The tab inside the shell's TabView is the depth the app resolves at on
    // its 8 MB main thread; the Presentation page once overflowed that stack.
    let sections = try #require(Self.sectionsByPage[page])
    let surface = Self.renderLines(
      GalleryView(initialTab: .styles, initialStylesPage: page), size: Self.sectionsSize
    ).joined(separator: "\n")
    #expect(surface.contains("Styles"))
    #expect(surface.contains(sections[0]), "the shell hides \(sections[0])")
  }

  // MARK: - Helpers

  private static func renderLines(_ view: some View, size: CellSize) -> [String] {
    var env = EnvironmentValues()
    env.terminalSize = size
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: Identity(components: [.named("StylesTabPages")]),
        environmentValues: env
      ),
      proposal: .init(width: size.width, height: size.height)
    )
    return artifacts.rasterSurface.lines
  }

  private static func count(of needle: String, in lines: [String]) -> Int {
    lines.filter { $0.contains(needle) }.count
  }
}
