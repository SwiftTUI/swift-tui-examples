import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

private let allModes: [CanvasPixelGridMode] = [.fullCell, .verticalHalfBlock]
private let magnifications = [1, 2, 4]

private func subCellPrecision() -> PointerPrecision {
  .subCell(
    source: .terminalPixels,
    metrics: CellPixelMetrics(width: 10, height: 20, source: .reported)
  )
}

/// The 2x spike this item was prototyped against, kept as the anchor case.
///
/// 2x half-block is the geometry that decided the overlay design: one source
/// pixel is exactly two cells wide and *one* cell tall, so its cell rect has no
/// interior at all. A literal "one-cell outline" would therefore have covered
/// the pixel completely — which is why the cursor brackets the block's outer
/// half-columns instead.
@MainActor
@Suite("Canvas viewport — 2x anchor case")
struct CanvasViewportPrototypeTests {
  @Test("2x half-block: one source pixel is two cells wide and one cell tall")
  func twoTimesHalfBlockBlockGeometry() {
    let viewport = CanvasViewport(
      zoom: .magnified(2),
      origin: GIFEditorCore.PixelPoint(x: 4, y: 6),
      visibleSize: GIFEditorCore.PixelSize(width: 5, height: 3)
    )

    #expect(viewport.logicalSize == GIFEditorCore.PixelSize(width: 10, height: 6))
    #expect(viewport.cellSize(mode: .verticalHalfBlock) == CellSize(width: 10, height: 3))
    #expect(
      viewport.cellRect(
        forSource: GIFEditorCore.PixelPoint(x: 4, y: 6),
        mode: .verticalHalfBlock
      ) == CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 2, height: 1))
    )
    #expect(
      viewport.cellRect(
        forSource: GIFEditorCore.PixelPoint(x: 6, y: 7),
        mode: .verticalHalfBlock
      ) == CellRect(origin: CellPoint(x: 4, y: 1), size: CellSize(width: 2, height: 1))
    )
  }

  @Test("2x half-block: every logical pixel maps back to the source pixel that made it")
  func twoTimesHalfBlockPointerRoundTrip() {
    let viewport = CanvasViewport(
      zoom: .magnified(2),
      origin: GIFEditorCore.PixelPoint(x: 4, y: 6),
      visibleSize: GIFEditorCore.PixelSize(width: 5, height: 3)
    )
    let logical = viewport.logicalSize

    for y in 0..<logical.height {
      for x in 0..<logical.width {
        #expect(
          viewport.sourcePoint(
            forLocalCell: viewport.localCellPoint(
              forLogicalX: x,
              y: y,
              mode: .verticalHalfBlock
            ),
            precision: subCellPrecision(),
            mode: .verticalHalfBlock
          ) == viewport.sourcePoint(forLogicalX: x, y: y)
        )
      }
    }
  }

  @Test("2x half-block: cell-only pointers still address every source pixel")
  func twoTimesHalfBlockCellPrecisionRoundTrip() {
    let viewport = CanvasViewport(
      zoom: .magnified(2),
      origin: GIFEditorCore.PixelPoint(x: 4, y: 6),
      visibleSize: GIFEditorCore.PixelSize(width: 5, height: 3)
    )
    let rect = viewport.sourceRect()

    for y in rect.minY..<rect.maxY {
      for x in rect.minX..<rect.maxX {
        let source = GIFEditorCore.PixelPoint(x: x, y: y)
        let cell = viewport.cellPoint(forSource: source, mode: .verticalHalfBlock)
        #expect(
          viewport.sourcePoint(
            forLocalCell: Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5),
            precision: .cell,
            mode: .verticalHalfBlock
          ) == source
        )
      }
    }
  }
}

/// The properties that actually de-risk P0.3: the pointer inverse and the
/// overlay's cell math, swept across every zoom, grid mode, and pointer
/// precision the editor can be in.
@MainActor
@Suite("Canvas viewport — mapping properties")
struct CanvasViewportMappingTests {
  /// Every logical pixel resolves back to the source pixel `resolvedPixels`
  /// sampled for it. This is the literal inverse of the render loop, so a
  /// mapping that drifts makes the pointer paint a pixel other than the one
  /// under the cursor — the exact failure mode F2 warned about.
  @Test("Logical → local → source is the identity under sub-cell pointers")
  func logicalRoundTripAcrossZoomAndMode() {
    for mode in allModes {
      for magnification in magnifications {
        let viewport = CanvasViewport(
          zoom: .magnified(magnification),
          origin: GIFEditorCore.PixelPoint(x: 3, y: 5),
          visibleSize: GIFEditorCore.PixelSize(width: 6, height: 7)
        )
        let logical = viewport.logicalSize

        for y in 0..<logical.height {
          for x in 0..<logical.width {
            let expected = viewport.sourcePoint(forLogicalX: x, y: y)
            let local = viewport.localCellPoint(forLogicalX: x, y: y, mode: mode)
            #expect(
              viewport.sourcePoint(
                forLocalCell: local,
                precision: subCellPrecision(),
                mode: mode
              ) == expected,
              "z=\(magnification) mode=\(mode) logical=(\(x), \(y))"
            )
          }
        }
      }
    }
  }

  /// Every source pixel in the visible rect round-trips through its own
  /// top-left corner.
  @Test("Source → local → source is the identity under sub-cell pointers")
  func sourceRoundTripAcrossZoomAndMode() {
    for mode in allModes {
      for magnification in magnifications {
        let viewport = CanvasViewport(
          zoom: .magnified(magnification),
          origin: GIFEditorCore.PixelPoint(x: 3, y: 5),
          visibleSize: GIFEditorCore.PixelSize(width: 6, height: 7)
        )
        let rect = viewport.sourceRect()

        for y in rect.minY..<rect.maxY {
          for x in rect.minX..<rect.maxX {
            let source = GIFEditorCore.PixelPoint(x: x, y: y)
            let logical = viewport.logicalOrigin(forSource: source)
            let local = viewport.localCellPoint(
              forLogicalX: logical.x,
              y: logical.y,
              mode: mode
            )
            #expect(
              viewport.sourcePoint(
                forLocalCell: local,
                precision: subCellPrecision(),
                mode: mode
              ) == source,
              "z=\(magnification) mode=\(mode) source=(\(x), \(y))"
            )
          }
        }
      }
    }
  }

  /// Cell-only hosts cannot address half a cell, so the honest property is
  /// conditional: a source pixel round-trips through its cell iff its block
  /// starts on a cell boundary, and otherwise resolves to the pixel owning the
  /// cell's upper half. Half-block at `1x` is the only case where that bites —
  /// `2x` and `4x` make every block cell-aligned, so zooming in is precisely
  /// what *gives* a cell-only host full addressability.
  @Test("Cell-only pointers address whichever pixel owns the cell's top half")
  func cellPrecisionResolvesToCellOwner() {
    for mode in allModes {
      for magnification in magnifications {
        let viewport = CanvasViewport(
          zoom: .magnified(magnification),
          origin: GIFEditorCore.PixelPoint(x: 3, y: 5),
          visibleSize: GIFEditorCore.PixelSize(width: 6, height: 7)
        )
        let subdivisions = CanvasViewport.ySubdivisions(for: mode)
        let rect = viewport.sourceRect()

        for y in rect.minY..<rect.maxY {
          for x in rect.minX..<rect.maxX {
            let source = GIFEditorCore.PixelPoint(x: x, y: y)
            let logical = viewport.logicalOrigin(forSource: source)
            let cell = viewport.cellPoint(forSource: source, mode: mode)
            let resolved = viewport.sourcePoint(
              forLocalCell: Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5),
              precision: .cell,
              mode: mode
            )
            let cellOwner = viewport.sourcePoint(
              forLogicalX: logical.x,
              y: cell.y * subdivisions
            )
            #expect(resolved == cellOwner, "z=\(magnification) mode=\(mode) source=(\(x), \(y))")
            if logical.y.isMultiple(of: subdivisions) {
              #expect(resolved == source, "z=\(magnification) mode=\(mode) should be aligned")
            }
          }
        }
      }
    }
  }

  @Test("Cell rects stay inside the grid and tile it exactly")
  func cellRectsTileTheGrid() {
    for mode in allModes {
      for magnification in magnifications {
        let viewport = CanvasViewport(
          zoom: .magnified(magnification),
          origin: GIFEditorCore.PixelPoint(x: 2, y: 3),
          visibleSize: GIFEditorCore.PixelSize(width: 4, height: 4)
        )
        let bounds = viewport.cellSize(mode: mode)
        // At 1x half-block two source pixels legitimately share one cell (top
        // and bottom halves); at every other zoom a cell has a single owner.
        let sharesCells = magnification == 1 && mode == .verticalHalfBlock
        var owners: [CellPoint: GIFEditorCore.PixelPoint] = [:]
        let rect = viewport.sourceRect()

        for y in rect.minY..<rect.maxY {
          for x in rect.minX..<rect.maxX {
            let source = GIFEditorCore.PixelPoint(x: x, y: y)
            let block = viewport.cellRect(forSource: source, mode: mode)
            #expect(block.origin.x >= 0 && block.maxX <= bounds.width)
            #expect(block.origin.y >= 0 && block.maxY <= bounds.height)
            guard !sharesCells else { continue }
            for cy in block.origin.y..<block.maxY {
              for cx in block.origin.x..<block.maxX {
                let cell = CellPoint(x: cx, y: cy)
                #expect(owners[cell] == nil, "cell \(cell) claimed twice at z=\(magnification)")
                owners[cell] = source
              }
            }
          }
        }

        if !sharesCells {
          #expect(owners.count == bounds.width * bounds.height)
        }
      }
    }
  }
}

/// Cull-then-scale, stated on the type that owns the decision.
@MainActor
@Suite("Canvas viewport — cull then scale")
struct CanvasViewportCullingTests {
  @Test("The logical grid is bounded by the cell budget, never by canvas area")
  func logicalGridTracksTheBudgetNotTheCanvas() {
    let budget = CellSize(width: 40, height: 20)
    let canvases = [
      GIFEditorCore.PixelSize(width: 32, height: 32),
      GIFEditorCore.PixelSize(width: 256, height: 256),
      GIFEditorCore.PixelSize(width: 1024, height: 1024),
    ]

    for mode in allModes {
      let subdivisions = CanvasViewport.ySubdivisions(for: mode)
      for level in [CanvasZoomLevel.fit, .x1, .x2, .x4] {
        var sizes: Set<GIFEditorCore.PixelSize> = []
        for canvas in canvases {
          let viewport = CanvasViewportState(level: level).resolved(
            in: CanvasViewportContext(canvasSize: canvas, cellBudget: budget, mode: mode)
          )
          let logical = viewport.logicalSize
          #expect(
            logical.width <= budget.width,
            "level=\(level) mode=\(mode) canvas=\(canvas) width=\(logical.width)"
          )
          #expect(
            logical.height <= budget.height * subdivisions,
            "level=\(level) mode=\(mode) canvas=\(canvas) height=\(logical.height)"
          )
          if canvas.width >= budget.width * 4 {
            sizes.insert(logical)
          }
        }
        // At a magnified zoom the visible extent is derived purely from the
        // budget, so growing the canvas cannot change how much work a render
        // does at all. `fit` is bounded by the budget (asserted above) but not
        // *constant*: its stride is the smallest integer that fits the canvas,
        // so 256 wide picks 7 (a 37-wide grid) while 1024 picks 26 (40 wide).
        // Both are inside the region; only the rounding slack differs.
        if level != .fit {
          #expect(sizes.count == 1, "level=\(level) mode=\(mode) grid varied with canvas area")
        }
      }
    }
  }

  @Test("4x on a 256x256 canvas resolves exactly the visible cells")
  func fourTimesOnALargeCanvas() {
    let viewport = CanvasViewportState(level: .x4).resolved(
      in: CanvasViewportContext(
        canvasSize: GIFEditorCore.PixelSize(width: 256, height: 256),
        cellBudget: CellSize(width: 40, height: 20),
        mode: .verticalHalfBlock
      )
    )

    // 40 cells wide / 4 = 10 source columns; 20 cells x 2 logical rows / 4 = 10
    // source rows. The logical grid is therefore exactly the cell budget.
    #expect(viewport.visibleSize == GIFEditorCore.PixelSize(width: 10, height: 10))
    #expect(viewport.logicalSize == GIFEditorCore.PixelSize(width: 40, height: 40))
    #expect(viewport.logicalSize.area == 1600)
    #expect(viewport.cellSize(mode: .verticalHalfBlock) == CellSize(width: 40, height: 20))
  }
}

@MainActor
@Suite("Canvas viewport — clamping and fit")
struct CanvasViewportClampingTests {
  private let canvas = GIFEditorCore.PixelSize(width: 64, height: 64)
  private let budget = CellSize(width: 16, height: 8)

  private func context(_ mode: CanvasPixelGridMode = .verticalHalfBlock)
    -> CanvasViewportContext
  {
    CanvasViewportContext(canvasSize: canvas, cellBudget: budget, mode: mode)
  }

  @Test("The origin is clamped at every edge")
  func originClampsAtEveryEdge() {
    let visible = CanvasViewportState(level: .x1).resolved(in: context()).visibleSize
    #expect(visible == GIFEditorCore.PixelSize(width: 16, height: 16))

    let farNegative = CanvasViewportState(
      level: .x1,
      origin: GIFEditorCore.PixelPoint(x: -100, y: -100)
    ).resolved(in: context())
    #expect(farNegative.origin == .zero)

    let farPositive = CanvasViewportState(
      level: .x1,
      origin: GIFEditorCore.PixelPoint(x: 900, y: 900)
    ).resolved(in: context())
    #expect(
      farPositive.origin
        == GIFEditorCore.PixelPoint(
          x: canvas.width - visible.width,
          y: canvas.height - visible.height
        )
    )
    #expect(farPositive.sourceRect().maxX == canvas.width)
    #expect(farPositive.sourceRect().maxY == canvas.height)
  }

  @Test("A canvas smaller than the region pins the origin and shows everything")
  func canvasSmallerThanTheViewport() {
    let small = GIFEditorCore.PixelSize(width: 4, height: 3)
    for mode in allModes {
      for level in [CanvasZoomLevel.fit, .x1, .x2] {
        let viewport = CanvasViewportState(
          level: level,
          origin: GIFEditorCore.PixelPoint(x: 7, y: 7)
        ).resolved(
          in: CanvasViewportContext(canvasSize: small, cellBudget: budget, mode: mode)
        )
        #expect(viewport.origin == .zero, "level=\(level) mode=\(mode)")
        #expect(viewport.visibleSize == small, "level=\(level) mode=\(mode)")
      }
    }
  }

  @Test("Panning moves half a viewport and stops at the edges")
  func panMovesHalfAViewport() {
    var state = CanvasViewportState(level: .x1)
    let visible = state.resolved(in: context()).visibleSize

    state.pan(dx: 1, dy: 1, in: context())
    #expect(
      state.origin == GIFEditorCore.PixelPoint(x: visible.width / 2, y: visible.height / 2)
    )

    for _ in 0..<20 {
      state.pan(dx: 1, dy: 1, in: context())
    }
    #expect(
      state.origin
        == GIFEditorCore.PixelPoint(
          x: canvas.width - visible.width,
          y: canvas.height - visible.height
        )
    )

    for _ in 0..<20 {
      state.pan(dx: -1, dy: -1, in: context())
    }
    #expect(state.origin == .zero)
  }

  @Test("Fit downsamples until the whole canvas is inside the region")
  func fitShowsTheWholeCanvas() {
    for mode in allModes {
      let subdivisions = CanvasViewport.ySubdivisions(for: mode)
      let viewport = CanvasViewportState(level: .fit).resolved(in: context(mode))
      #expect(viewport.origin == .zero, "mode=\(mode)")
      #expect(viewport.visibleSize == canvas, "mode=\(mode)")
      #expect(viewport.logicalSize.width <= budget.width, "mode=\(mode)")
      #expect(viewport.logicalSize.height <= budget.height * subdivisions, "mode=\(mode)")
    }
  }

  @Test("Fit collapses to 1x when the canvas already fits")
  func fitIsIdentityWhenTheCanvasFits() {
    let small = GIFEditorCore.PixelSize(width: 8, height: 8)
    let viewport = CanvasViewportState(level: .fit).resolved(
      in: CanvasViewportContext(canvasSize: small, cellBudget: budget, mode: .verticalHalfBlock)
    )
    #expect(viewport.zoom == .magnified(1))
    #expect(viewport.visibleSize == small)
  }

  @Test("Zoom steps walk fit → 1x → 2x → 4x and stop at both ends")
  func zoomStepsSaturate() {
    var state = CanvasViewportState(level: .fit)
    let cursor = GIFEditorCore.PixelPoint(x: 10, y: 10)

    state.zoomIn(cursor: cursor, in: context())
    #expect(state.level == .x1)
    state.zoomIn(cursor: cursor, in: context())
    #expect(state.level == .x2)
    state.zoomIn(cursor: cursor, in: context())
    #expect(state.level == .x4)
    state.zoomIn(cursor: cursor, in: context())
    #expect(state.level == .x4)

    state.zoomOut(cursor: cursor, in: context())
    #expect(state.level == .x2)
    state.fitToWindow(cursor: cursor, in: context())
    #expect(state.level == .fit)
    state.zoomOut(cursor: cursor, in: context())
    #expect(state.level == .fit)
  }
}

@MainActor
@Suite("Canvas viewport — cursor follow")
struct CanvasViewportFollowTests {
  private let canvas = GIFEditorCore.PixelSize(width: 96, height: 96)
  private let budget = CellSize(width: 20, height: 10)

  private func context(_ mode: CanvasPixelGridMode) -> CanvasViewportContext {
    CanvasViewportContext(canvasSize: canvas, cellBudget: budget, mode: mode)
  }

  @Test("Single-pixel moves never leave the cursor off-screen")
  func followKeepsSinglePixelMovesVisible() {
    for mode in allModes {
      for level in [CanvasZoomLevel.fit, .x1, .x2, .x4] {
        var state = CanvasViewportState(level: level)
        var cursor = GIFEditorCore.PixelPoint.zero

        // Walk the full width, then the full height, one pixel at a time.
        for _ in 0..<(canvas.width - 1) {
          cursor.x += 1
          state.follow(cursor: cursor, in: context(mode))
          #expect(
            state.resolved(in: context(mode)).contains(cursor),
            "level=\(level) mode=\(mode) cursor=\(cursor)"
          )
        }
        for _ in 0..<(canvas.height - 1) {
          cursor.y += 1
          state.follow(cursor: cursor, in: context(mode))
          #expect(
            state.resolved(in: context(mode)).contains(cursor),
            "level=\(level) mode=\(mode) cursor=\(cursor)"
          )
        }
        // …and all the way back to the origin.
        while cursor.x > 0 || cursor.y > 0 {
          cursor.x = max(0, cursor.x - 1)
          cursor.y = max(0, cursor.y - 1)
          state.follow(cursor: cursor, in: context(mode))
          #expect(
            state.resolved(in: context(mode)).contains(cursor),
            "level=\(level) mode=\(mode) cursor=\(cursor)"
          )
        }
      }
    }
  }

  @Test("Eight-pixel jumps never leave the cursor off-screen")
  func followKeepsJumpsVisible() {
    for mode in allModes {
      for level in [CanvasZoomLevel.x1, .x2, .x4] {
        var state = CanvasViewportState(level: level)
        for step in stride(from: 0, to: canvas.width, by: 8) {
          let cursor = GIFEditorCore.PixelPoint(
            x: min(step, canvas.width - 1),
            y: min(step, canvas.height - 1)
          )
          state.follow(cursor: cursor, in: context(mode))
          #expect(
            state.resolved(in: context(mode)).contains(cursor),
            "level=\(level) mode=\(mode) cursor=\(cursor)"
          )
        }
      }
    }
  }

  @Test("Zoom changes keep the cursor visible")
  func zoomChangesKeepTheCursorVisible() {
    for mode in allModes {
      for cursor in [
        GIFEditorCore.PixelPoint.zero,
        GIFEditorCore.PixelPoint(x: 95, y: 95),
        GIFEditorCore.PixelPoint(x: 48, y: 3),
        GIFEditorCore.PixelPoint(x: 3, y: 90),
      ] {
        var state = CanvasViewportState(level: .fit)
        for level in [CanvasZoomLevel.x1, .x2, .x4, .x1, .fit, .x4] {
          state.setLevel(level, cursor: cursor, in: context(mode))
          #expect(
            state.resolved(in: context(mode)).contains(cursor),
            "level=\(level) mode=\(mode) cursor=\(cursor)"
          )
        }
      }
    }
  }

  @Test("Follow leaves the origin alone while the cursor stays inside")
  func followIsAStillCameraInsideTheViewport() {
    var state = CanvasViewportState(level: .x2, origin: GIFEditorCore.PixelPoint(x: 20, y: 20))
    let viewport = state.resolved(in: context(.verticalHalfBlock))
    let before = viewport.origin
    let inside = GIFEditorCore.PixelPoint(
      x: before.x + viewport.visibleSize.width - 1,
      y: before.y + viewport.visibleSize.height - 1
    )

    state.follow(cursor: inside, in: context(.verticalHalfBlock))
    #expect(state.origin == before)
  }
}
