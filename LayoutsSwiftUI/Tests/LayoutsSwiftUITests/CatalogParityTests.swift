import Testing

import Layouts
import SwiftUILayouts

/// Cross-engine catalog parity guard.
///
/// The SwiftUI-vs-SwiftTUI comparison harness pairs scenarios by a stable
/// `id` shared between the two mirrored catalogs (`SwiftUILayouts.LayoutCatalog`
/// renders in native SwiftUI; `Layouts.LayoutCatalog` renders in SwiftTUI).
/// If the catalogs drift — a different count, a renamed id, or a divergent
/// `marker` (the substring guaranteed to appear in each engine's render and the
/// element-pairing anchor) — id-keyed pairing silently loses entries. These
/// tests fail loudly the moment that happens.
@Suite struct CatalogParityTests {
  private typealias SwiftUICatalog = SwiftUILayouts.LayoutCatalog
  private typealias SwiftTUICatalog = Layouts.LayoutCatalog

  @Test("Both catalogs list exactly 56 entries")
  func bothCatalogsHave56Entries() {
    #expect(SwiftUICatalog.all.count == 56)
    #expect(SwiftTUICatalog.all.count == 56)
  }

  @Test("Both catalogs expose the identical id set")
  func idSetsMatchAcrossEngines() {
    let swiftUI = Set(SwiftUICatalog.all.map(\.id))
    let swiftTUI = Set(SwiftTUICatalog.all.map(\.id))
    #expect(
      swiftUI == swiftTUI,
      """
      catalog id drift:
        only in SwiftUI:  \(swiftUI.subtracting(swiftTUI).sorted())
        only in SwiftTUI: \(swiftTUI.subtracting(swiftUI).sorted())
      """
    )
  }

  @Test("Entry order matches across engines (sidebar order == probe order)")
  func entryOrderMatchesAcrossEngines() {
    #expect(SwiftUICatalog.all.map(\.id) == SwiftTUICatalog.all.map(\.id))
  }

  @Test("Per-id markers agree across engines")
  func markersMatchAcrossEngines() {
    let swiftTUIByID = Dictionary(
      SwiftTUICatalog.all.map { ($0.id, $0.marker) },
      uniquingKeysWith: { first, _ in first }
    )
    for entry in SwiftUICatalog.all {
      #expect(
        swiftTUIByID[entry.id] == entry.marker,
        "marker drift for \(entry.id): swiftUI=\(entry.marker) swiftTUI=\(swiftTUIByID[entry.id] ?? "<missing>")"
      )
    }
  }
}
