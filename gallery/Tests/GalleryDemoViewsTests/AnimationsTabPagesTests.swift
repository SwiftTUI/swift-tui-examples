import SwiftTUI
import Testing

@testable import GalleryDemoViews

// Static render checks for the paged Animations tab. No run loop, no gate:
// each page is rasterised once through `DefaultRenderer` and its section
// template (numbered title, `expect:` line, `state:` line) is asserted from
// the surface text, the same way a reader verifies it on screen.
@MainActor
@Suite
struct AnimationsTabPagesTests {
  private static let terminalSize = CellSize(width: 96, height: 60)

  /// The section titles each page must show, in order. Numbers are stable
  /// across pages; 10 to 19 are reserved for later stages.
  private static let sectionsByPage: [AnimationsPage: [String]] = [
    .basics: [
      "1. withAnimation foreground color",
      "3. frame animation via .frame(maxWidth:)",
      "4. .offset(x:y:) animation",
      "5. .position(x:y:) absolute placement",
      "9. withAnimation completion callback",
    ],
    .transitions: [
      "2. .transition(...) insertion and removal"
    ],
    .matched: [
      "6. matchedGeometryEffect"
    ],
    .keyframes: [
      "7. PhaseAnimator auto-cycles",
      "8. PhaseAnimator(trigger:)",
    ],
    .transactions: [
      "20. Binding.animation toggle"
    ],
  ]

  @Test(
    "every page renders its numbered sections with expect and state lines",
    arguments: AnimationsPage.allCases
  )
  func pageRendersItsSections(page: AnimationsPage) throws {
    let sections = try #require(Self.sectionsByPage[page])
    let lines = Self.renderLines(AnimationsTab(initialPage: page))
    let surface = lines.joined(separator: "\n")

    for title in sections {
      #expect(surface.contains(title), "page \(page.rawValue) is missing section \(title)")
    }
    #expect(
      Self.count(of: "expect: ", in: lines) == sections.count,
      "page \(page.rawValue) should carry one expect line per section"
    )
    #expect(
      Self.count(of: "state: ", in: lines) == sections.count,
      "page \(page.rawValue) should carry one state line per section"
    )

    // Sections from every other page stay off this page.
    for (otherPage, otherSections) in Self.sectionsByPage where otherPage != page {
      for title in otherSections {
        #expect(!surface.contains(title), "page \(page.rawValue) leaked section \(title)")
      }
    }
  }

  @Test("the page picker lists every page on every page")
  func pickerListsEveryPage() {
    for page in AnimationsPage.allCases {
      let surface = Self.renderLines(AnimationsTab(initialPage: page)).joined(separator: "\n")
      #expect(surface.contains("Animations"))
      for segment in AnimationsPage.allCases {
        #expect(
          surface.contains(segment.title), "page \(page.rawValue) hides segment \(segment.title)")
      }
    }
  }

  @Test("the default page is Basics and hosts the offset regression controls")
  func defaultPageIsBasics() {
    let surface = Self.renderLines(AnimationsTab()).joined(separator: "\n")
    #expect(surface.contains("4. .offset(x:y:) animation"))
    #expect(surface.contains("slide me"))
    #expect(surface.contains("state: offsetX=0"))
  }

  @Test("page keys are the lowercase raw values and round-trip")
  func pageKeysRoundTrip() {
    #expect(
      AnimationsPage.allCases.map(\.rawValue) == [
        "basics", "transitions", "matched", "keyframes", "transactions",
      ])
    for page in AnimationsPage.allCases {
      #expect(AnimationsPage(rawValue: page.rawValue) == page)
      #expect(page.rawValue == page.rawValue.lowercased())
    }
    #expect(AnimationsPage(rawValue: "not-a-page") == nil)
  }

  @Test("the animations tab descriptor tags every page's capability")
  func descriptorTagsEveryPage() {
    let descriptor = GalleryView.descriptor(for: .animations)
    #expect(
      descriptor.coverageTags == [
        "with-animation", "transitions", "phase-animator", "matched-geometry",
        "keyframe-animator", "transactions",
      ]
    )
  }

  // MARK: - Helpers

  private static func renderLines(_ tab: AnimationsTab) -> [String] {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      tab,
      context: .init(
        identity: Identity(components: [.named("AnimationsTabPages")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    return artifacts.rasterSurface.lines
  }

  private static func count(of needle: String, in lines: [String]) -> Int {
    lines.filter { $0.contains(needle) }.count
  }
}
