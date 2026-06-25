import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor save sheet")
struct SaveGIFSheetViewTests {
  @Test("Save preview is built from encoded GIF bytes")
  func savePreviewIsBuiltFromEncodedGIFBytes() throws {
    let document = twoFrameDocument()
    let preview = SaveGIFPreview.make(from: document)

    #expect(preview.canSave)
    #expect(preview.encodedByteCount != nil)
    #expect(preview.frames.count == 2)
    #expect(preview.frames.map(\.delayCentiseconds) == [3, 4])
    #expect(preview.frames[0].pixels == document.flattenedColors(frameIndex: 0))
    #expect(preview.frames[1].pixels == document.flattenedColors(frameIndex: 1))
  }

  @Test("Save sheet renders encoded preview and overwrite confirmation")
  func saveSheetRendersPreviewAndOverwriteConfirmation() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifeditor-save-sheet-\(UUID().uuidString).gif")
    try Data("existing".utf8).write(to: url)
    defer {
      try? FileManager.default.removeItem(at: url)
    }

    var pathText = url.path
    var overwriteConfirmed = false
    let rendered = render(
      SaveGIFSheetView(
        preview: SaveGIFPreview.make(from: twoFrameDocument()),
        pathText: Binding(
          get: { pathText },
          set: { pathText = $0 }
        ),
        overwriteConfirmed: Binding(
          get: { overwriteConfirmed },
          set: { overwriteConfirmed = $0 }
        ),
        onSave: { _, _ in },
        onCancel: {}
      ),
      width: 80,
      height: 24
    )

    let text = rendered.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("Review GIF before saving"))
    #expect(text.contains("Encoded preview"))
    #expect(text.contains("A file already exists"))
    #expect(text.contains("Confirm overwrite"))
  }

  @Test("Save sheet renders loading state before async preview completes")
  func saveSheetRendersLoadingStateBeforeAsyncPreviewCompletes() throws {
    var pathText = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifeditor-save-sheet-\(UUID().uuidString).gif")
      .path
    var overwriteConfirmed = false
    let rendered = render(
      SaveGIFSheetView(
        preview: nil,
        pathText: Binding(
          get: { pathText },
          set: { pathText = $0 }
        ),
        overwriteConfirmed: Binding(
          get: { overwriteConfirmed },
          set: { overwriteConfirmed = $0 }
        ),
        onSave: { _, _ in },
        onCancel: {}
      ),
      width: 80,
      height: 24
    )

    let text = rendered.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("Review GIF before saving"))
    #expect(text.contains("Preparing encoded preview"))
    #expect(text.contains("Preparing preview before save"))
    #expect(!text.contains("Ready to save"))
  }
}

private func twoFrameDocument() -> GIFDocument {
  let size = GIFEditorCore.PixelSize(width: 2, height: 2)
  let first = EditorFrame(
    layers: [EditorLayer(name: "Frame 1", pixels: PixelBuffer(size: size, fill: 1))],
    delayCentiseconds: 3
  )
  let second = EditorFrame(
    layers: [EditorLayer(name: "Frame 2", pixels: PixelBuffer(size: size, fill: 2))],
    delayCentiseconds: 4
  )
  return GIFDocument(size: size, frames: [first, second])
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["gifeditor.save-sheet.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
