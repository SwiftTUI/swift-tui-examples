import Foundation
import SwiftTUI
import Testing

@testable import GalleryDemoViews

// Static render checks for the paged Animations tab. No run loop, no gate:
// each page is rasterised once through `DefaultRenderer` and its section
// template (numbered title, `expect:` line, `state:` line) is asserted from
// the surface text, the same way a reader verifies it on screen. Every page's
// rest state and the section 12 curve strips are also compared against
// snapshot fixtures, so a layout regression in the tab is caught without the
// runtime gate.
@MainActor
@Suite
struct AnimationsTabPagesTests {
  /// Tall enough to show every section of the longest page without scrolling.
  private static let sectionsSize = CellSize(width: 96, height: 140)

  /// The snapshot sizes: a comfortable terminal and the classic 80x24.
  private nonisolated static let snapshotSizes = [
    CellSize(width: 96, height: 60),
    CellSize(width: 80, height: 24),
  ]

  /// Snapshot fixtures are bundled from `Fixtures/AnimationsTab` next to this
  /// file; set `GALLERY_UPDATE_FIXTURES=1` to rewrite the source copies from
  /// the current render after an intentional change.
  private static let fixturesSourceDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures", isDirectory: true)
    .appendingPathComponent("AnimationsTab", isDirectory: true)

  /// The section titles each page must show, in order. Numbers are stable
  /// across pages; 13 kept its reserved number when co-present adoption
  /// shipped (0.9.12), and 21 is the numericText rolling counter.
  private static let sectionsByPage: [AnimationsPage: [String]] = [
    .basics: [
      "1. withAnimation foreground color",
      "3. frame animation via .frame(maxWidth:)",
      "4. .offset(x:y:) animation",
      "5. .position(x:y:) absolute placement",
      "9. withAnimation completion callback",
    ],
    .transitions: [
      "2. .transition(...) insertion and removal",
      "21. .contentTransition(.numericText()) rolls changed digit columns",
    ],
    .matched: [
      "6. matchedGeometryEffect:",
      "13. matchedGeometryEffect(isSource: false)",
    ],
    .keyframes: [
      "7. PhaseAnimator auto-cycles",
      "8. PhaseAnimator(trigger:)",
      "10. KeyframeAnimator(trigger:)",
      "11. KeyframeAnimator(repeating:)",
      "12. KeyframeTimeline sampled",
    ],
    .transactions: [
      "14. withTransaction(",
      "15. .transaction(value:",
      "16. .animation(_:body:)",
      "17. Transaction.addAnimationCompletion",
      "18. tracksVelocity",
      "19. Animation.logicallyComplete(after:)",
      "20. Binding.animation toggle",
    ],
  ]

  @Test(
    "every page renders its numbered sections with expect and state lines",
    arguments: AnimationsPage.allCases
  )
  func pageRendersItsSections(page: AnimationsPage) throws {
    let sections = try #require(Self.sectionsByPage[page])
    let lines = Self.renderLines(AnimationsTab(initialPage: page), size: Self.sectionsSize)
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
      let surface = Self.renderLines(AnimationsTab(initialPage: page), size: Self.sectionsSize)
        .joined(separator: "\n")
      #expect(surface.contains("Animations"))
      for segment in AnimationsPage.allCases {
        #expect(
          surface.contains(segment.title), "page \(page.rawValue) hides segment \(segment.title)")
      }
    }
  }

  @Test("the default page is Basics and hosts the offset regression controls")
  func defaultPageIsBasics() {
    let surface = Self.renderLines(AnimationsTab(), size: Self.sectionsSize)
      .joined(separator: "\n")
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

  // MARK: - Snapshots

  @Test(
    "every page's rest state matches its snapshot",
    arguments: AnimationsPage.allCases, snapshotSizes
  )
  func pageRestStateMatchesSnapshot(page: AnimationsPage, size: CellSize) throws {
    let lines = Self.renderLines(AnimationsTab(initialPage: page), size: size)
    try Self.expectFixture("page-\(page.rawValue)-\(size.width)x\(size.height)", matches: lines)
  }

  @Test(
    "the section 12 curve strip is deterministic for every timeline",
    arguments: CurveStripKind.allCases
  )
  func curveStripMatchesSnapshot(kind: CurveStripKind) throws {
    let strip = CurveStrip(kind: kind)
    let lines = Self.renderLines(
      CurveStripView(kind: kind),
      size: CellSize(width: strip.columns, height: CurveStrip.rows)
    )
    #expect(lines.count == CurveStrip.rows)
    #expect(lines.joined().contains("|"), "the strip marks no keyframe boundary")
    #expect(strip.samples.count == strip.columns)
    try Self.expectFixture("curve-strip-\(kind.rawValue)", matches: lines)
  }

  // MARK: - Helpers

  private static func renderLines(_ view: some View, size: CellSize) -> [String] {
    var env = EnvironmentValues()
    env.terminalSize = size
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: Identity(components: [.named("AnimationsTabPages")]),
        environmentValues: env
      ),
      proposal: .init(width: size.width, height: size.height)
    )
    return artifacts.rasterSurface.lines
  }

  private static func count(of needle: String, in lines: [String]) -> Int {
    lines.filter { $0.contains(needle) }.count
  }

  /// Compares `lines` (trailing spaces trimmed) with the bundled
  /// `Fixtures/AnimationsTab/<name>.txt`. With `GALLERY_UPDATE_FIXTURES` set
  /// the source fixture is rewritten first and compared against instead.
  private static func expectFixture(
    _ name: String,
    matches lines: [String],
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let rendered = lines.map(trimmingTrailingSpaces).joined(separator: "\n") + "\n"
    let file: URL
    if ProcessInfo.processInfo.environment["GALLERY_UPDATE_FIXTURES"] != nil {
      file = fixturesSourceDirectory.appendingPathComponent("\(name).txt")
      try FileManager.default.createDirectory(
        at: fixturesSourceDirectory, withIntermediateDirectories: true)
      try rendered.write(to: file, atomically: true, encoding: .utf8)
    } else {
      file = try #require(
        Bundle.module.url(
          forResource: name, withExtension: "txt", subdirectory: "Fixtures/AnimationsTab"),
        "missing snapshot fixture \(name).txt; run with GALLERY_UPDATE_FIXTURES=1 to create it",
        sourceLocation: sourceLocation
      )
    }
    let expected = try String(contentsOf: file, encoding: .utf8)
    #expect(
      rendered == expected,
      """
      \(name) drifted from its snapshot. Rendered:
      \(rendered)
      Rerun with GALLERY_UPDATE_FIXTURES=1 if the change is intended.
      """,
      sourceLocation: sourceLocation
    )
  }

  private static func trimmingTrailingSpaces(_ line: String) -> String {
    String(line.reversed().drop(while: { $0 == " " }).reversed())
  }
}
