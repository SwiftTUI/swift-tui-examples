import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// Palette editing through `EditingSession`.
///
/// Two things are being pinned here, and they fail in opposite
/// directions:
///
/// 1. **Completeness of the remap.** `remove`, `compact` and `sorted`
///    renumber slots, so one undoable edit has to rewrite every
///    `PaletteIndex` the editor holds — every `PixelBuffer` in every
///    layer of every frame, the primary and secondary selections, and
///    the clipboard. Miss one and the document silently recolors, which
///    is why the headline test compares the rendered composite byte for
///    byte across a sort.
/// 2. **Honesty of the invalidation.** The palette is the first thing in
///    the codebase to write `document.palette`, and that write must
///    declare `.everyFrame`. Nothing but the composite oracle can catch
///    a wrong answer here, so the palette paths run with
///    `compositeOracleEnabled` and assert the recompute count.
@MainActor
@Suite("GIF editor palette editing")
struct PaletteEditingTests {
  // MARK: - The correctness hinge

  @Test("Sorting the palette leaves every composited frame byte-identical")
  func sortLeavesCompositesByteIdentical() {
    let model = EditingSession(document: artwork())
    let before = model.compositedFrames()
    let paletteBefore = model.document.palette

    model.sortPalette()

    let after = model.compositedFrames()
    // Guard against a vacuous pass: the sort must actually renumber.
    #expect(model.document.palette.usedColors != paletteBefore.usedColors)
    #expect(model.document.palette.usedCount == paletteBefore.usedCount)
    #expect(after == before)
  }

  @Test("Sorting remaps the color selections and the clipboard")
  func sortRemapsSelectionsAndClipboard() throws {
    let model = EditingSession(document: artwork())
    model.primaryColorIndex = 6
    model.secondaryColorIndex = 21
    model.copySelection()
    let paletteBefore = model.document.palette
    let clipboardBefore = try #require(model.clipboard)
    let primaryColorBefore = paletteBefore[model.primaryColorIndex]
    let secondaryColorBefore = paletteBefore[model.secondaryColorIndex]

    model.sortPalette()

    let paletteAfter = model.document.palette
    #expect(paletteAfter[model.primaryColorIndex] == primaryColorBefore)
    #expect(paletteAfter[model.secondaryColorIndex] == secondaryColorBefore)
    // The slots moved — otherwise the assertions above would hold for
    // free — and every clipboard pixel still names the same color.
    #expect(model.primaryColorIndex != 6 || model.secondaryColorIndex != 21)
    let clipboardAfter = try #require(model.clipboard)
    #expect(clipboardAfter.pixels.count == clipboardBefore.pixels.count)
    for (old, new) in zip(clipboardBefore.pixels, clipboardAfter.pixels) {
      switch (old, new) {
      case (nil, nil):
        continue
      case (let old?, let new?):
        #expect(paletteAfter[new] == paletteBefore[old])
      default:
        Issue.record("a clipboard pixel changed transparency across a sort")
      }
    }
  }

  @Test("Sorting is one undoable edit that restores the palette and the pixels")
  func sortIsOneUndoableEdit() {
    let model = EditingSession(document: artwork())
    let paletteBefore = model.document.palette
    let framesBefore = model.document.frames

    model.sortPalette()
    #expect(model.canUndo)
    #expect(model.document.frames != framesBefore)

    model.undo()

    #expect(model.document.palette == paletteBefore)
    #expect(model.document.frames == framesBefore)
    #expect(!model.canUndo)
  }

  // MARK: - Invalidation

  @Test("Editing a palette slot recomposites every frame and passes the oracle")
  func slotEditRecompositesEveryFrame() {
    let model = EditingSession(document: artwork())
    model.compositeOracleEnabled = true
    _ = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.setPaletteColor(EditorColor(rgbHex: 0x123456), at: 6)
    _ = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + model.document.frames.count)
    // The pass above refreshed every entry, so this one is all hits — and
    // with the oracle on, every hit is re-derived and compared. A write
    // site that under-declared its invalidation traps here instead of
    // quietly rendering a stale frame.
    let settled = model.compositeRecomputeCount
    _ = model.compositedFrames()
    #expect(model.compositeRecomputeCount == settled)
  }

  @Test("Every palette edit shape passes the composite soundness oracle")
  func everyPaletteEditPassesTheOracle() throws {
    let model = EditingSession(document: artwork())
    model.compositeOracleEnabled = true
    let frameCount = model.document.frames.count

    /// One refresh pass, then one all-hits pass the oracle audits.
    func settle() {
      _ = model.compositedFrames()
      let hits = model.compositeRecomputeCount
      _ = model.compositedFrames()
      #expect(model.compositeRecomputeCount == hits)
    }

    settle()
    let baseline = model.compositeRecomputeCount

    model.setPaletteColor(EditorColor(rgbHex: 0x00FF00), at: 3)
    settle()
    model.appendPaletteColor(EditorColor(rgbHex: 0x101010))
    settle()
    model.sortPalette()
    settle()
    model.removePaletteSlot(at: 4)
    settle()
    model.compactPalette()
    settle()
    let file = try temporaryPaletteFile(named: "oracle.hex", contents: "000000\nFF0000\n00FF00\n")
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(model.importPalette(contentsOf: file))
    settle()
    model.undo()
    settle()

    // Five palette writes reached the document (compact found no
    // duplicates and returned early), each invalidating all three frames,
    // plus the undo that swapped the document back.
    #expect(model.compositeRecomputeCount == baseline + 6 * frameCount)
  }

  // MARK: - Structural edits

  @Test("Removing a slot recolors its pixels to the nearest survivor")
  func removeRecolorsToNearestSurvivor() {
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0x000000),
      EditorColor(rgbHex: 0xFF0000),
      EditorColor(rgbHex: 0xFE0000),
    ])
    let size = GIFEditorCore.PixelSize(width: 2, height: 2)
    let buffer = PixelBuffer(size: size, pixels: [0, 1, 2, 3])
    let document = GIFDocument(
      size: size,
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: buffer)])]
    )
    let model = EditingSession(document: document)

    // Slot 2 (FF0000) goes; its pixels land on FE0000, which slid down
    // into slot 2 as everything above the hole shifted.
    model.removePaletteSlot(at: 2)

    #expect(model.document.palette.usedCount == 3)
    #expect(model.currentLayer.pixels.pixels == [0, 1, 2, 2])
    #expect(model.document.palette[2] == EditorColor(rgbHex: 0xFE0000))
  }

  @Test("Slot 0 is pinned as the transparency sentinel and refuses removal")
  func slotZeroRefusesRemoval() {
    let model = EditingSession(document: artwork())
    let before = model.document.palette

    model.removePaletteSlot(at: ColorPalette.transparentSlot)

    #expect(model.document.palette == before)
    #expect(!model.canUndo)
    #expect(model.statusMessage.contains("Slot 0"))
  }

  @Test("Compacting collapses duplicates without changing a rendered pixel")
  func compactCollapsesDuplicates() {
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0x112233),
      EditorColor(rgbHex: 0x445566),
      EditorColor(rgbHex: 0x112233),
    ])
    let size = GIFEditorCore.PixelSize(width: 2, height: 2)
    let buffer = PixelBuffer(size: size, pixels: [0, 1, 2, 3])
    let document = GIFDocument(
      size: size,
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: buffer)])]
    )
    let model = EditingSession(document: document)
    let before = model.compositedFrames()

    model.compactPalette()

    #expect(model.document.palette.usedCount == 3)
    #expect(model.currentLayer.pixels.pixels == [0, 1, 2, 1])
    #expect(model.compositedFrames() == before)
  }

  @Test("Adding a color lands in the first unused slot and selects it")
  func addLandsInFirstUnusedSlot() {
    let model = EditingSession(document: artwork())
    let used = model.document.palette.usedCount
    let color = EditorColor(rgbHex: 0xABCDEF)

    model.appendPaletteColor(color)

    #expect(model.document.palette.usedCount == used + 1)
    #expect(model.document.palette[PaletteIndex(used)] == color)
    #expect(model.primaryColorIndex == PaletteIndex(used))
  }

  @Test("Editing a slot repaints every pixel that references it")
  func slotEditRepaintsReferencingPixels() throws {
    let model = EditingSession(document: artwork())
    let replacement = EditorColor(rgbHex: 0x7F00FF)
    // Take a slot the artwork actually shows, so the assertion below
    // can't pass by finding nothing to check.
    let target = try #require(model.document.flatten(frameIndex: 0).pixels.compactMap { $0 }.first)

    model.setPaletteColor(replacement, at: target)

    #expect(model.document.palette[target] == replacement)
    let composited = model.compositedFrames()[0]
    let flattened = model.document.flatten(frameIndex: 0).pixels
    var repainted = 0
    for (index, slot) in flattened.enumerated() where slot == target {
      #expect(composited[index] == replacement)
      repainted += 1
    }
    #expect(repainted > 0)
  }

  // MARK: - Import

  @Test("Importing a .hex palette keeps slot 0 transparent and recolors to nearest")
  func importHexRecolorsToNearest() throws {
    let model = EditingSession(document: artwork())
    let file = try temporaryPaletteFile(
      named: "swatches.hex",
      contents: "#FF0000\n00FF00\n0000FF\n"
    )
    defer { try? FileManager.default.removeItem(at: file) }
    model.primaryColorIndex = 6  // the default palette's red

    #expect(model.importPalette(contentsOf: file))

    let palette = model.document.palette
    // The parsers hand back opaque colors only, so the transparency
    // sentinel is the editor's to prepend.
    #expect(palette.usedCount == 4)
    #expect(palette[0] == .transparent)
    #expect(palette[1] == EditorColor(rgbHex: 0xFF0000))
    // Every surviving pixel names a used slot of the new palette, and the
    // old red selection landed on the new red.
    #expect(palette[model.primaryColorIndex] == EditorColor(rgbHex: 0xFF0000))
    for frame in model.document.frames {
      for layer in frame.layers {
        for slot in layer.pixels.pixels.compactMap({ $0 }) {
          #expect(Int(slot) < palette.usedCount)
        }
      }
    }
  }

  @Test("Importing a .gpl palette parses the GIMP format")
  func importGimpPalette() throws {
    let model = EditingSession(document: artwork())
    let file = try temporaryPaletteFile(
      named: "swatches.gpl",
      contents: "GIMP Palette\nName: Test\n#comment\n17 34 51\t Slate\n255 255 255 White\n"
    )
    defer { try? FileManager.default.removeItem(at: file) }

    #expect(model.importPalette(contentsOf: file))

    #expect(model.document.palette.usedCount == 3)
    #expect(model.document.palette[1] == EditorColor(rgbHex: 0x112233))
    #expect(model.document.palette[2] == .white)
  }

  @Test("A malformed palette file leaves the document untouched")
  func malformedImportIsRejected() throws {
    let model = EditingSession(document: artwork())
    let before = model.document
    let file = try temporaryPaletteFile(named: "broken.hex", contents: "FF00\nnot-a-color\n")
    defer { try? FileManager.default.removeItem(at: file) }

    #expect(!model.importPalette(contentsOf: file))

    #expect(model.document == before)
    #expect(!model.canUndo)
    #expect(model.statusMessage.contains("failed"))
  }

  @Test("An unreadable or unknown palette path is reported, not thrown")
  func unknownPaletteFormatIsReported() {
    let model = EditingSession(document: artwork())

    #expect(!model.importPalette(fromPath: "/nowhere/palette.txt"))
    #expect(model.statusMessage.contains("failed"))
    #expect(!model.importPalette(fromPath: "   "))
    #expect(model.statusMessage.contains("Enter a palette path"))
    #expect(!model.canUndo)
  }

  // MARK: - Sheet parsing

  @Test("The palette sheet's hex field accepts RRGGBB with or without a #")
  func hexFieldParsing() {
    #expect(PaletteEditorSheetView.color(fromHex: "FF8800") == EditorColor(rgbHex: 0xFF8800))
    #expect(PaletteEditorSheetView.color(fromHex: " #ff8800 ") == EditorColor(rgbHex: 0xFF8800))
    #expect(PaletteEditorSheetView.color(fromHex: "FF88") == nil)
    // Eight digits is rejected rather than truncated: an accidental alpha
    // must not silently rewrite a slot's opacity.
    #expect(PaletteEditorSheetView.color(fromHex: "FF8800FF") == nil)
    #expect(PaletteEditorSheetView.color(fromHex: "GGGGGG") == nil)
    #expect(PaletteEditorSheetView.color(fromHex: "") == nil)
  }

  @Test("The palette sheet's RGB fields accept 0-255 per channel")
  func rgbFieldParsing() {
    #expect(
      PaletteEditorSheetView.color(red: "255", green: "0", blue: " 128 ")
        == EditorColor(red: 255, green: 0, blue: 128)
    )
    #expect(PaletteEditorSheetView.color(red: "256", green: "0", blue: "0") == nil)
    #expect(PaletteEditorSheetView.color(red: "-1", green: "0", blue: "0") == nil)
    #expect(PaletteEditorSheetView.color(red: "12.5", green: "0", blue: "0") == nil)
    #expect(PaletteEditorSheetView.color(red: "", green: "0", blue: "0") == nil)
  }

  @Test("Palette hex labels round-trip through the hex field")
  func hexLabelRoundTrips() {
    for color in ColorPalette.default.usedColors {
      let label = EditingSession.hexLabel(for: color)
      #expect(label.count == 6)
      let parsed = PaletteEditorSheetView.color(fromHex: label)
      #expect(parsed?.red == color.red)
      #expect(parsed?.green == color.green)
      #expect(parsed?.blue == color.blue)
    }
  }

  // MARK: - Sheet rendering

  @Test("The palette editor sheet renders its grid, fields and actions")
  func paletteSheetRenders() {
    let model = EditingSession(document: artwork())
    let rendered = renderSheet(
      PaletteEditorSheetView(model: model, refresh: {}, onClose: {}),
      width: 62,
      height: 24
    )

    let text = rendered.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("32 of 256 slots in use"))
    #expect(text.contains("Slot 0"))
    #expect(text.contains("Hex"))
    #expect(text.contains("Add"))
    #expect(text.contains("Remove"))
    #expect(text.contains("Sort"))
    #expect(text.contains("Compact"))
    #expect(text.contains("Import"))
    #expect(text.contains("Close"))
  }

  // MARK: - Fixtures

  /// Three frames of two layers each, painted with a spread of the
  /// default palette's slots plus transparent gaps, so a dropped remap
  /// shows up as a recolored composite rather than as an empty canvas.
  private func artwork() -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let frames = (0..<3).map { frameIndex in
      let layers = (0..<2).map { layerIndex -> EditorLayer in
        var buffer = PixelBuffer(size: size)
        for i in 0..<size.area {
          let slot = (i * 3 + frameIndex * 5 + layerIndex * 7) % 31
          // Every fifth pixel stays transparent so layer stacking (and
          // slot 0's pinning) is part of what the composite proves.
          buffer.pixels[i] = i % 5 == layerIndex ? nil : PaletteIndex(slot + 1)
        }
        return EditorLayer(name: "Layer \(layerIndex + 1)", pixels: buffer)
      }
      return EditorFrame(layers: layers, delayCentiseconds: frameIndex + 1)
    }
    return GIFDocument(size: size, palette: .default, frames: frames)
  }

  /// Resolves a sheet body against a fixed terminal size. Enough to
  /// catch a layout that traps or a control that silently disappears.
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
        identity: Identity(components: ["gifeditor.palette.tests.\(id)"]),
        environmentValues: env
      ),
      proposal: ProposedSize(width: width, height: height)
    )
  }

  private func temporaryPaletteFile(named name: String, contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifeditor-palette-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(name)
    try contents.write(to: file, atomically: true, encoding: .utf8)
    return file
  }
}
