import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor Canvas view")
struct CanvasViewTests {
  @Test("CanvasView renders pixel colors and sparse overlays through Canvas")
  func canvasViewRendersPixelGridAndOverlay() {
    let red = EditorColor(rgbHex: 0xE05757)
    let blue = EditorColor(rgbHex: 0x5BA3FF)
    let size = GIFEditorCore.PixelSize(width: 2, height: 2)
    let raster = render(
      CanvasView(
        size: size,
        cells: [
          red, nil,
          blue, .white,
        ],
        cursor: GIFEditorCore.PixelPoint(x: 0, y: 0),
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .fullCell
      ),
      width: 8,
      height: 6
    ).rasterSurface

    #expect(raster.cells[1][1].character == "◆")
    #expect(raster.cells[1][1].style?.foregroundColor == Color.cyan)
    #expect(raster.cells[1][1].style?.backgroundColor == red.toTerminalColor())
    #expect(raster.cells[2][1].style?.backgroundColor == blue.toTerminalColor())
  }

  @Test("CanvasView can render the document grid in half-block mode")
  func canvasViewRendersHalfBlockMode() {
    let red = EditorColor(rgbHex: 0xE05757)
    let blue = EditorColor(rgbHex: 0x5BA3FF)
    let size = GIFEditorCore.PixelSize(width: 2, height: 3)
    let raster = render(
      CanvasView(
        size: size,
        cells: [
          red, .white,
          blue, .white,
          red, nil,
        ],
        cursor: GIFEditorCore.PixelPoint(x: 1, y: 2),
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .verticalHalfBlock
      ),
      width: 8,
      height: 6
    ).rasterSurface

    #expect(raster.cells[1][1].character == "▀")
    #expect(raster.cells[1][1].style?.foregroundColor == red.toTerminalColor())
    #expect(raster.cells[1][1].style?.backgroundColor == blue.toTerminalColor())
    #expect(raster.cells[2][1].character == "▀")
    #expect(raster.cells[2][1].style?.foregroundColor == red.toTerminalColor())
    #expect(raster.cells[2][2].character == "▀")
    #expect(raster.cells[2][2].style?.foregroundColor == Color.cyan)
    #expect(raster.cells[2][2].style?.backgroundColor == nil)
  }

  @Test("Interactive canvas pointer drawing region excludes the border")
  func interactiveCanvasPointerDrawingRegionExcludesBorder() throws {
    let size = GIFEditorCore.PixelSize(width: 8, height: 6)
    let model = EditingSession(document: GIFDocument.blank(size: size))
    let artifacts = render(
      InteractiveCanvasHarnessView(model: model, size: size),
      width: 16,
      height: 8
    )

    let drawingRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first {
        $0.rect.size == CellSize(width: 8, height: 3)
      }
    )
    #expect(
      drawingRegion.rect
        == CellRect(
          origin: CellPoint(x: 1, y: 1),
          size: CellSize(width: 8, height: 3)
        )
    )
  }

  @Test("Interactive canvas click-and-drag paints through the RunLoop mouse path")
  func interactiveCanvasClickAndDragPaintsThroughRunLoop() async throws {
    let size = GIFEditorCore.PixelSize(width: 8, height: 6)
    let model = EditingSession(document: GIFDocument.blank(size: size))
    model.primaryColorIndex = 3
    let terminalSize = CellSize(width: 16, height: 8)
    let rootIdentity = Identity(components: ["gifeditor.ui.drag"])
    let view = InteractiveCanvasHarnessView(model: model, size: size)
    let artifacts = render(
      view,
      width: terminalSize.width,
      height: terminalSize.height
    )

    let drawingRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first {
        $0.rect.size == CellSize(width: 8, height: 3)
      }
    )
    #expect(drawingRegion.captureOnPress)

    let metrics = CellPixelMetrics(width: 10, height: 20, source: .reported)
    let start = pointer(
      local: Point(x: 0.25, y: 0.20),
      in: drawingRegion.rect,
      metrics: metrics
    )
    let end = pointer(
      local: Point(x: 4.25, y: 2.20),
      in: drawingRegion.rect,
      metrics: metrics
    )
    let host = RecordingCanvasTerminalHost(
      size: terminalSize,
      pointerInputCapabilities: PointerInputCapabilities(
        precision: .subCell(source: .terminalPixels, metrics: metrics)
      )
    )
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: ScriptedCanvasInput(
        events: [
          .mouse(.init(kind: .down(.primary), location: start)),
          .mouse(.init(kind: .dragged(.primary), location: end)),
          .mouse(.init(kind: .up(.primary), location: end)),
        ]
      ),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: env,
      proposal: ProposedSize(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in view }
    ).run()

    #expect(result.exitReason == .inputEnded)
    let pixels = model.currentLayer.pixels
    for offset in 0...4 {
      #expect(pixels[GIFEditorCore.PixelPoint(x: offset, y: offset)] == 3)
    }
    #expect(model.cursor == GIFEditorCore.PixelPoint(x: 4, y: 4))
  }

  @Test("Canvas pixel mapping preserves sub-cell half-block rows")
  func canvasPixelMappingUsesSubCellPrecision() {
    let metrics = CellPixelMetrics(width: 10, height: 20, source: .reported)
    let precision = PointerPrecision.subCell(source: .terminalPixels, metrics: metrics)
    let viewport = CanvasViewport.wholeCanvas(
      GIFEditorCore.PixelSize(width: 4, height: 4)
    )

    #expect(
      viewport.sourcePoint(
        forLocalCell: Point(x: 1.25, y: 0.20),
        precision: precision,
        mode: .verticalHalfBlock
      ) == GIFEditorCore.PixelPoint(x: 1, y: 0)
    )
    #expect(
      viewport.sourcePoint(
        forLocalCell: Point(x: 1.25, y: 0.75),
        precision: precision,
        mode: .verticalHalfBlock
      ) == GIFEditorCore.PixelPoint(x: 1, y: 1)
    )
    #expect(
      viewport.sourcePoint(
        forLocalCell: Point(x: 1.25, y: 1.25),
        precision: precision,
        mode: .verticalHalfBlock
      ) == GIFEditorCore.PixelPoint(x: 1, y: 2)
    )
  }

  @Test("Canvas pixel mapping anchors cell-only input to a stable half-cell")
  func canvasPixelMappingCellFallbackUsesCellOrigin() {
    let viewport = CanvasViewport.wholeCanvas(
      GIFEditorCore.PixelSize(width: 4, height: 4)
    )

    #expect(
      viewport.sourcePoint(
        forLocalCell: Point(x: 1.5, y: 0.5),
        precision: .cell,
        mode: .verticalHalfBlock
      ) == GIFEditorCore.PixelPoint(x: 1, y: 0)
    )
  }

  @Test("Cull-then-scale: the resolved array tracks the viewport, not the canvas")
  func resolvedPixelCountIsIndependentOfCanvasArea() {
    // 4x into a 40x20-cell region: 40 logical columns and 40 logical rows,
    // i.e. 10x10 source pixels magnified fourfold. The same budget must
    // produce the same array whether the document is 256x256 or 512x512 —
    // that is the whole F3 fix in one assertion.
    let budget = CellSize(width: 40, height: 20)
    let state = CanvasViewportState(level: .x4)

    func resolvedCount(canvas: GIFEditorCore.PixelSize) -> Int {
      let viewport = state.resolved(
        in: CanvasViewportContext(
          canvasSize: canvas,
          cellBudget: budget,
          mode: .verticalHalfBlock
        )
      )
      return CanvasSurfaceView(
        size: canvas,
        cells: Array(repeating: nil, count: canvas.area),
        cursor: .zero,
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .verticalHalfBlock,
        viewport: viewport
      ).resolvedPixels.count
    }

    let large = resolvedCount(canvas: GIFEditorCore.PixelSize(width: 256, height: 256))
    let larger = resolvedCount(canvas: GIFEditorCore.PixelSize(width: 512, height: 512))

    #expect(large == 40 * 40)
    #expect(large == larger)
    // The rendered grid must also still fit the region it was measured for.
    #expect(large <= budget.width * budget.height * 2)
  }

  @Test("EditorView sizes its canvas from the layout proposal, not the canvas size")
  func editorCanvasIsProposalDriven() throws {
    // A 64x64 document in an 80x24 terminal cannot fit at 1x. Without a
    // proposal-driven viewport the canvas would either overflow the region
    // (the old `ScrollView` shape) or collapse to `GeometryReader`'s 10x10
    // unspecified ideal. It must instead be clipped to the region it was
    // measured into.
    let artifacts = render(
      EditorView(document: GIFDocument.blank(size: .init(width: 64, height: 64))),
      width: 80,
      height: 24
    )
    let canvasRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first { $0.captureOnPress }
    )

    #expect(canvasRegion.rect.size.width < 64)
    #expect(canvasRegion.rect.size.width > 10)
    #expect(canvasRegion.rect.size.height > 5)
    #expect(canvasRegion.rect.maxX <= 80)
    #expect(canvasRegion.rect.maxY <= 24)
  }

  @Test("At 2x the cursor brackets its block instead of covering it")
  func zoomedCursorDrawsAnOutline() {
    let red = EditorColor(rgbHex: 0xE05757)
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let raster = render(
      CanvasView(
        size: size,
        cells: Array(repeating: red, count: size.area),
        cursor: GIFEditorCore.PixelPoint(x: 1, y: 1),
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .verticalHalfBlock,
        viewport: CanvasViewport(
          zoom: .magnified(2),
          origin: .zero,
          visibleSize: size
        )
      ),
      width: 12,
      height: 8
    ).rasterSurface

    // Source pixel (1, 1) at 2x half-block owns cells (2..3, 1) inside the
    // 1-cell border, so raster columns 3-4 of raster row 2.
    #expect(raster.cells[2][3].character == "▌")
    #expect(raster.cells[2][3].style?.foregroundColor == Color.cyan)
    #expect(raster.cells[2][3].style?.backgroundColor == red.toTerminalColor())
    #expect(raster.cells[2][4].character == "▐")
    #expect(raster.cells[2][4].style?.foregroundColor == Color.cyan)
    // Neighbouring blocks are untouched by the cursor.
    #expect(raster.cells[2][2].style?.foregroundColor != Color.cyan)
    #expect(raster.cells[2][5].style?.foregroundColor != Color.cyan)
    #expect(raster.cells[1][3].style?.foregroundColor != Color.cyan)
  }

  @Test("At 4x the cursor's bracket leaves the block's interior visible")
  func fourTimesCursorLeavesInteriorVisible() {
    let red = EditorColor(rgbHex: 0xE05757)
    let size = GIFEditorCore.PixelSize(width: 2, height: 2)
    let raster = render(
      CanvasView(
        size: size,
        cells: Array(repeating: red, count: size.area),
        cursor: GIFEditorCore.PixelPoint(x: 0, y: 0),
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .verticalHalfBlock,
        viewport: CanvasViewport(
          zoom: .magnified(4),
          origin: .zero,
          visibleSize: size
        )
      ),
      width: 14,
      height: 8
    ).rasterSurface

    // (0, 0) at 4x half-block is 4 cells wide and 2 cells tall: raster
    // columns 1-4, raster rows 1-2.
    for row in 1...2 {
      #expect(raster.cells[row][1].character == "▌")
      #expect(raster.cells[row][4].character == "▐")
      // Interior columns keep the pixel, unobscured.
      #expect(raster.cells[row][2].style?.foregroundColor != Color.cyan)
      #expect(raster.cells[row][3].style?.foregroundColor != Color.cyan)
    }
  }
}

private struct InteractiveCanvasHarnessView: View {
  let model: EditingSession
  let size: GIFEditorCore.PixelSize

  @State private var revision = 0

  var body: some View {
    _ = revision
    let refresh: @MainActor @Sendable () -> Void = {
      revision &+= 1
    }
    return ScrollView {
      InteractiveCanvasView(
        size: size,
        cells: model.document.flattenedColors(frameIndex: model.currentFrameIndex),
        model: model,
        refresh: refresh,
        mode: .verticalHalfBlock
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .border(.separator, set: .single)
  }
}

private func pointer(
  local: Point,
  in rect: CellRect,
  metrics: CellPixelMetrics
) -> PointerLocation {
  PointerLocation.subCell(
    location: Point(
      x: Double(rect.origin.x) + local.x,
      y: Double(rect.origin.y) + local.y
    ),
    source: .terminalPixels,
    metrics: metrics
  )
}

private final class ScriptedCanvasInput: TerminalInputReading {
  private let events: [InputEvent]

  init(events: [InputEvent]) {
    self.events = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let events = self.events
      let task = Task {
        for event in events {
          continuation.yield(event)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class RecordingCanvasTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let pointerInputCapabilities: PointerInputCapabilities

  init(
    size: CellSize,
    pointerInputCapabilities: PointerInputCapabilities
  ) {
    self.surfaceSize = size
    self.pointerInputCapabilities = pointerInputCapabilities
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> RenderSnapshot {
  var env = EnvironmentValues()
  env.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["gifeditor.ui.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
