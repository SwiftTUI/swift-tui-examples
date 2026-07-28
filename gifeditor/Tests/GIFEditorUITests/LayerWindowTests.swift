import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// The bound that keeps the inspector's height a property of the layout
/// rather than of the open document.
///
/// The window is what lets ``EditorLayoutFloor/inspectorHeight(at:)`` be a
/// constant at all, so its two promises are checked here rather than left to
/// the floor's arithmetic: the selected layer is always inside the window, and
/// a layer outside it is *counted*, never silently absent.
@MainActor
@Suite("GIF editor layer list window")
struct LayerWindowTests {
  @Test("the window always holds the selection", arguments: 0..<9)
  func theWindowHoldsTheSelection(selected: Int) {
    let window = LayerListView.visibleWindow(count: 9, selected: selected, rows: 3)
    #expect(window.count == 3)
    #expect(window.contains(selected), "layer \(selected) is selected but off the list")
    #expect(window.lowerBound >= 0)
    #expect(window.upperBound <= 9)
  }

  @Test("a list that fits is not windowed")
  func aShortListIsWhole() {
    #expect(LayerListView.visibleWindow(count: 2, selected: 1, rows: 3) == 0..<2)
    #expect(LayerListView.visibleWindow(count: 3, selected: 0, rows: 3) == 0..<3)
  }

  @Test("the window never runs off either end")
  func theWindowClampsToTheStack() {
    #expect(LayerListView.visibleWindow(count: 9, selected: 0, rows: 3) == 0..<3)
    #expect(LayerListView.visibleWindow(count: 9, selected: 8, rows: 3) == 6..<9)
    // Degenerate inputs a resize or a delete can produce mid-frame.
    #expect(LayerListView.visibleWindow(count: 0, selected: 0, rows: 3).isEmpty)
    #expect(LayerListView.visibleWindow(count: 4, selected: 0, rows: 0).isEmpty)
  }

  /// What the author sees: the selected layer's row, and a heading that says
  /// how many are not on screen.
  @Test("a windowed list counts the layers it is holding back")
  func theHeadingCountsTheWholeStack() {
    let text = render(layerList(count: 9, selected: 7, density: .compact))
    #expect(text.contains("Layers 8/9"), "the heading must say which layer of how many")
    #expect(text.contains("Layer 8"), "the selected layer is not in the window it defines")
    #expect(!text.contains("Layer 1"), "a nine-layer list rendered more rows than its window")
    #expect(text.contains("New layer"), "the footer fell out of the windowed list")
  }

  @Test("a list inside its window says only what it is")
  func anUnwindowedListHasAPlainHeading() {
    let text = render(layerList(count: 2, selected: 0, density: .compact))
    #expect(text.contains("Layers"))
    #expect(!text.contains("/2"), "a list with nothing held back must not count itself")
  }

  // MARK: - Harness

  private func layerList(
    count: Int,
    selected: Int,
    density: EditorLayoutDensity
  ) -> LayerListView {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let layers = (0..<count).map {
      EditorLayer(name: "Layer \($0 + 1)", pixels: PixelBuffer(size: size))
    }
    let model = EditingSession(
      document: GIFDocument(
        size: size,
        frames: [EditorFrame(layers: layers, delayCentiseconds: 10)]
      )
    )
    return LayerListView(
      layers: layers,
      selectedIndex: selected,
      model: model,
      refresh: {},
      density: density
    )
  }

  private func render(_ view: some View) -> String {
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: 80, height: 24)
    return DefaultRenderer().render(
      view,
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.layer-window.\(UUID().uuidString)"]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: InspectorColumnView.width, height: 24)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  /// A directory no test writes to — it exists so constructing a view model
  /// cannot read the developer's real `~/.config/halfcell/` recents list.
  private static let throwawayStateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-layer-window-\(UUID().uuidString)")
}
