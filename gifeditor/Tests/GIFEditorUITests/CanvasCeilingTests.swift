import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// The raised canvas ceiling: the size progression, the resize sheet's
/// arbitrary `width × height` entry, and the 256-per-axis cap.
///
/// The cap is a **UI** bound and lives only in the New / Resize flow.
/// `GIFLoader` and the project format deliberately accept any size, so
/// nothing here should ever grow into a check on the model.
@MainActor
@Suite("GIF editor canvas ceiling")
struct CanvasCeilingTests {
  @Test("The size progression runs to the documented ceiling")
  func progressionRunsToTheCeiling() {
    #expect(EditorViewModel.canvasSizeProgression == [16, 24, 32, 48, 64, 96, 128, 192, 256])
    #expect(EditorViewModel.canvasSizeProgression.last == EditorViewModel.maximumCanvasDimension)
    #expect(EditorViewModel.canvasSizeProgression.allSatisfy { $0 >= 1 })
    #expect(
      EditorViewModel.canvasSizeProgression
        == EditorViewModel.canvasSizeProgression.sorted()
    )
  }

  @Test("Cycling steps past the old 64 ceiling and wraps at 256")
  func cyclingWalksTheWholeProgression() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 64, height: 64))
    )

    model.cycleCanvasSize()
    #expect(model.document.size == GIFEditorCore.PixelSize(width: 96, height: 96))

    model.resizeCanvas(to: GIFEditorCore.PixelSize(width: 256, height: 256))
    model.cycleCanvasSize()
    #expect(model.document.size == GIFEditorCore.PixelSize(width: 16, height: 16))
  }

  @Test("Resizing to the ceiling keeps the artwork and clamps the cursor")
  func resizeToCeilingKeepsArtwork() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 16, height: 16))
    )
    model.primaryColorIndex = 9
    model.cursor = GIFEditorCore.PixelPoint(x: 3, y: 3)
    model.applyToolAtCursor()

    model.resizeCanvas(to: GIFEditorCore.PixelSize(width: 256, height: 256))

    #expect(model.document.size == GIFEditorCore.PixelSize(width: 256, height: 256))
    #expect(model.currentLayer.pixels.pixels.count == 256 * 256)
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 3, y: 3)] == 9)

    model.cursor = GIFEditorCore.PixelPoint(x: 255, y: 255)
    model.resizeCanvas(to: GIFEditorCore.PixelSize(width: 32, height: 32))
    #expect(model.cursor == GIFEditorCore.PixelPoint(x: 31, y: 31))
  }

  @Test("Non-square sizes survive the resize path")
  func nonSquareResize() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 16, height: 16))
    )

    model.resizeCanvas(to: GIFEditorCore.PixelSize(width: 200, height: 120))

    #expect(model.document.size == GIFEditorCore.PixelSize(width: 200, height: 120))
    #expect(model.currentLayer.pixels.size == GIFEditorCore.PixelSize(width: 200, height: 120))
    #expect(model.compositedFrames()[0].count == 200 * 120)
  }

  // MARK: - Resize sheet entry

  @Test("The resize sheet accepts arbitrary dimensions inside the cap")
  func customEntryAcceptsArbitraryDimensions() {
    #expect(
      ResizeCanvasSheetView.parseCustomSize(width: "200", height: " 120 ")
        == .valid(GIFEditorCore.PixelSize(width: 200, height: 120))
    )
    #expect(
      ResizeCanvasSheetView.parseCustomSize(width: "256", height: "256")
        == .valid(GIFEditorCore.PixelSize(width: 256, height: 256))
    )
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "1", height: "1").size != nil)
  }

  @Test("The resize sheet rejects — never clamps — anything past the cap")
  func customEntryRejectsOutOfRange() {
    // Clamping 512 to 256 would hand back a canvas nobody asked for, and
    // naming an exact size is the whole point of the field.
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "512", height: "64").size == nil)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "64", height: "257").isInvalid)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "0", height: "64").isInvalid)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "-8", height: "64").isInvalid)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "64.5", height: "64").isInvalid)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "wide", height: "64").isInvalid)
  }

  @Test("The resize sheet treats a half-filled or blank pair as unfinished, not wrong")
  func customEntryTreatsPartialInputAsEmpty() {
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "", height: "") == .empty)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "  ", height: "\t") == .empty)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "64", height: "") == .empty)
    #expect(ResizeCanvasSheetView.parseCustomSize(width: "", height: "64") == .empty)
  }

  @Test("The resize sheet renders every preset plus the custom fields")
  func resizeSheetRendersPresetsAndCustomEntry() {
    let rendered = renderSheet(
      ResizeCanvasSheetView(
        currentSize: GIFEditorCore.PixelSize(width: 32, height: 32),
        onSelect: { _ in },
        onCancel: {}
      ),
      width: 52,
      height: 16
    )

    let text = rendered.rasterSurface.lines.joined(separator: "\n")
    for dimension in EditorViewModel.canvasSizeProgression {
      #expect(text.contains("\(dimension) × \(dimension)"))
    }
    #expect(text.contains("256 per axis"))
    #expect(text.contains("Resize"))
    #expect(text.contains("Cancel"))
  }

  /// Resolves a sheet body against a fixed terminal size.
  private func renderSheet(
    _ view: some View,
    width: Int,
    height: Int,
    id: String = "\(#function)"
  ) -> RenderSnapshot {
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: width, height: height)
    return DefaultRenderer().render(
      view,
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.ceiling.tests.\(id)"]),
        environmentValues: env
      ),
      proposal: ProposedSize(width: width, height: height)
    )
  }
}
