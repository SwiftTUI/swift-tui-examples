import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// The two places adding a tool costs terminal space, both pinned at the
/// size the editor promises to work at.
///
/// Neither failure mode is subtle in person and both are invisible to a
/// unit test: a tool dock one row taller than its region drops its last
/// icon off the bottom, and an options row wider than 80 cells squeezes
/// the trailing controls out of the bar — the same class of overrun that,
/// in the timeline's export column, stopped the editor settling at 80×24
/// and timed out every runtime test at once.
@MainActor
@Suite("GIF editor tool dock layout")
struct ToolDockLayoutTests {
  @Test("every tool in the dock is on screen at 80×24")
  func theDockShowsEveryToolAtTheSmallestSupportedSize() {
    let rendered = render(
      EditorView(
        document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 8, height: 8)),
        stateDirectory: Self.throwawayStateDirectory
      ),
      width: 80,
      height: 24
    )
    let text = rendered.rasterSurface.lines.joined(separator: "\n")

    for tool in ActiveTool.allCases {
      #expect(
        text.contains(tool.iconGlyph),
        "\(tool.label)'s dock icon fell off the bottom of an 80×24 editor"
      )
    }
  }

  @Test("a shape tool's options row leaves the trailing controls their columns")
  func shapeOptionsFitTheEightyColumnBar() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 16, height: 16)),
      stateDirectory: Self.throwawayStateDirectory
    )
    model.selectTool(.rectangle)
    model.cursor = GIFEditorCore.PixelPoint(x: 15, y: 15)
    // The widest state the row has: an anchored shape, both toggles on,
    // and a two-digit brush-size readout is not possible (the size caps
    // at 8), so this is the row at full width.
    model.applyToolAtCursor()
    model.toggleShapeFill()

    let rendered = render(ToolOptionsBar(model: model, refresh: {}), width: 80, height: 3)
    let text = rendered.rasterSurface.lines.joined(separator: "\n")

    #expect(text.contains("Rectangle"))
    #expect(text.contains("filled"))
    #expect(text.contains("anchor (15,15)"))
    // The trailing global control is what gets pushed out first.
    #expect(text.contains("swap"), "the shape options row crowded out the swap button")
    #expect(rendered.rasterSurface.lines.allSatisfy { $0.count <= 80 })
  }

  @Test("the pen's options row still fits once mirror-X joins it")
  func penOptionsFitTheEightyColumnBar() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 16, height: 16)),
      stateDirectory: Self.throwawayStateDirectory
    )
    model.toggleStrokeMirrorX()

    let rendered = render(ToolOptionsBar(model: model, refresh: {}), width: 80, height: 3)
    let text = rendered.rasterSurface.lines.joined(separator: "\n")

    #expect(text.contains("mirror-X"))
    #expect(text.contains("swap"))
  }

  /// A directory no test writes to and no run reads anything meaningful
  /// from — it exists so constructing a view model cannot read the
  /// developer's real `~/.config/halfcell/` recents list.
  private static let throwawayStateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-dock-layout-\(UUID().uuidString)")
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> RenderSnapshot {
  var environment = EnvironmentValues()
  environment.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["gifeditor.dock.tests.\(id)"]),
      environmentValues: environment
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
