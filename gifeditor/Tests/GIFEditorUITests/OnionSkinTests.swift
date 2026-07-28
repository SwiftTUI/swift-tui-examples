import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// Onion skinning: which frames get ghosted, what a ghost looks like, that
/// the blend happens inside the viewport-bounded loop, and that none of it
/// escapes the view layer.
@MainActor
@Suite("GIF editor onion skin")
struct OnionSkinTests {
  // MARK: - Selection

  @Test("the defaults are off, one ghost, both sides")
  func defaultsAreOffOneGhostBothSides() {
    let settings = OnionSkinSettings()
    #expect(settings.isEnabled == false)
    #expect(settings.depth == 1)
    #expect(settings.sides == .both)
    // Off means off: no ghosts, no matter where the playhead is.
    #expect(settings.ghosts(around: 2, frameCount: 5).isEmpty)
    #expect(settings.statusLabel.isEmpty)
  }

  @Test("enabled, one ghost each side, ordered farthest to nearest")
  func ghostsAreOrderedFarthestFirst() {
    var settings = OnionSkinSettings()
    settings.toggle()
    settings.depth = 2

    let ghosts = settings.ghosts(around: 4, frameCount: 9)
    #expect(ghosts.map(\.frameIndex) == [2, 6, 3, 5])
    #expect(ghosts.map(\.distance) == [2, 2, 1, 1])
    #expect(ghosts.map(\.direction) == [.previous, .next, .previous, .next])
    // Farther ghosts are fainter, which is what makes "farthest first"
    // the right compositing order.
    #expect(
      OnionSkinAppearance.opacity(atDistance: 2)
        < OnionSkinAppearance.opacity(atDistance: 1)
    )
  }

  @Test(
    "sides filter which neighbours are ghosted",
    arguments: [
      (OnionSkinSides.previous, [3]),
      (OnionSkinSides.next, [5]),
      (OnionSkinSides.both, [3, 5]),
    ])
  func sidesFilterNeighbours(sides: OnionSkinSides, expected: [Int]) {
    let settings = OnionSkinSettings(isEnabled: true, depth: 1, sides: sides)
    let ghosts = settings.ghosts(around: 4, frameCount: 9)
    #expect(ghosts.map(\.frameIndex).sorted() == expected)
  }

  /// **The loop decision.** Ghosting clamps at the ends of the timeline
  /// rather than wrapping: at frame 0 there is nothing before the current
  /// frame, and at the last frame nothing after.
  @Test("frame 0 has no previous ghost and the last frame has no next ghost")
  func boundaryFramesDoNotWrap() {
    let settings = OnionSkinSettings(isEnabled: true, depth: 2, sides: .both)

    let atStart = settings.ghosts(around: 0, frameCount: 4)
    #expect(atStart.allSatisfy { $0.direction == .next })
    #expect(atStart.map(\.frameIndex) == [2, 1])
    #expect(!atStart.contains { $0.frameIndex == 3 }, "the last frame must not wrap onto frame 0")

    let atEnd = settings.ghosts(around: 3, frameCount: 4)
    #expect(atEnd.allSatisfy { $0.direction == .previous })
    #expect(atEnd.map(\.frameIndex) == [1, 2])
    #expect(!atEnd.contains { $0.frameIndex == 0 }, "frame 0 must not wrap onto the last frame")

    // With `previous` alone, frame 0 ghosts nothing at all.
    var previousOnly = settings
    previousOnly.sides = .previous
    #expect(previousOnly.ghosts(around: 0, frameCount: 4).isEmpty)
  }

  @Test("a one-frame document ghosts nothing")
  func singleFrameDocumentHasNoGhosts() {
    var settings = OnionSkinSettings()
    settings.toggle()
    #expect(settings.ghosts(around: 0, frameCount: 1).isEmpty)
  }

  @Test("depth is clamped to its declared range")
  func depthIsClamped() {
    var settings = OnionSkinSettings()
    for _ in 0..<10 { settings.increaseDepth() }
    #expect(settings.depth == OnionSkinSettings.maximumDepth)
    for _ in 0..<10 { settings.decreaseDepth() }
    #expect(settings.depth == OnionSkinSettings.minimumDepth)
    // Every distance in range has an opacity, and a distance past the end
    // fades rather than trapping.
    #expect(OnionSkinAppearance.opacity(atDistance: OnionSkinSettings.maximumDepth) > 0)
    #expect(
      OnionSkinAppearance.opacity(atDistance: 99)
        == OnionSkinAppearance.opacity(atDistance: OnionSkinSettings.maximumDepth)
    )
  }

  @Test("adjusting the count or the sides turns onion skin on")
  func adjustingASettingEnablesIt() {
    var byDepth = OnionSkinSettings()
    byDepth.increaseDepth()
    #expect(byDepth.isEnabled)

    var bySides = OnionSkinSettings()
    bySides.cycleSides()
    #expect(bySides.isEnabled)
    #expect(bySides.sides == .previous)

    // The cycle closes.
    bySides.cycleSides()
    #expect(bySides.sides == .next)
    bySides.cycleSides()
    #expect(bySides.sides == .both)

    var byMenu = OnionSkinSettings()
    byMenu.cycleDepth()
    #expect(byMenu.isEnabled)
    #expect(byMenu.depth == 2)
    byMenu.cycleDepth()
    byMenu.cycleDepth()
    #expect(byMenu.depth == OnionSkinSettings.minimumDepth, "the menu row wraps")
  }

  // MARK: - The catalog

  /// The four bindings are all *bare* keys, and that is a structural claim,
  /// not a taste one: bare keys ride the `onKeyPress(.any)` handler the
  /// editor root already wears, so a whole feature's worth of shortcuts adds
  /// zero nested `ModifiedContent` layers to a root chain that is already at
  /// its resolve-stack budget. A `keyCommand` here would cost one layer each.
  @Test("onion skin is a catalog section of four bare keys")
  func catalogExposesTheOnionSkinSection() {
    #expect(KeyBindingCatalog.populatedSections.contains(.onionSkin))

    let entries = KeyBindingCatalog.entries(in: .onionSkin)
    #expect(
      entries.map(\.command) == [
        .toggleOnionSkin, .cycleOnionSkinSides,
        .decreaseOnionSkinGhosts, .increaseOnionSkinGhosts,
      ]
    )
    #expect(entries.map(\.display) == ["o", "O", "{", "}"])
    #expect(
      entries.allSatisfy { $0.dispatch == .focusedKey },
      "an onion-skin keyCommand would add a layer to the editor root's chain"
    )
    #expect(entries.allSatisfy { $0.chords.allSatisfy(\.isBare) })

    // Each chord resolves back through the lookup `handleFocusedEditorKey`
    // dispatches on, which is the only route a bare key has.
    for entry in entries {
      for chord in entry.chords {
        #expect(KeyBindingCatalog.focusedCommand(for: chord) == entry.command)
      }
    }

    // The section's prose is where the wrap decision is written down, and
    // the doc is generated from it.
    #expect(KeyBindingSection.onionSkin.notes.contains { $0.contains("does not wrap") })
    #expect(KeyBindingSection.onionSkin.notes.contains { $0.contains("display only") })
  }

  // MARK: - Color math

  @Test("source-over compositing is straight alpha in the destination's space")
  func compositingIsStraightAlpha() {
    let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
    let white = Color(red: 1, green: 1, blue: 1, alpha: 1)

    // A fully opaque source replaces the destination, a fully transparent
    // one leaves it, and a half-alpha one lands halfway.
    #expect(white.composited(over: black) == white)
    #expect(white.faded(by: 0).composited(over: black) == black)
    let half = white.faded(by: 0.5).composited(over: black)
    #expect(abs(half.red - 0.5) < 1e-9)
    #expect(abs(half.alpha - 1.0) < 1e-9)
  }

  @Test("tinting moves the hue and leaves the alpha alone")
  func tintingLeavesAlphaAlone() {
    let translucentWhite = Color(red: 1, green: 1, blue: 1, alpha: 0.5)
    let tinted = translucentWhite.tinted(toward: OnionSkinAppearance.previousTint, amount: 0.5)
    #expect(tinted.alpha == 0.5, "a tint must not make a translucent pixel solid")
    #expect(tinted.blue > tinted.red, "the cool tint pulls blue above red")
    #expect(translucentWhite.tinted(toward: .black, amount: 0) == translucentWhite)
  }

  /// The two tints have to be told apart in a terminal, so the claim worth
  /// pinning is the ordering of the channels, not their exact values.
  @Test("previous ghosts read cool and next ghosts read warm")
  func tintsAreCoolAndWarm() {
    let white = EditorColor.white
    let previous = ghostLayer(direction: .previous, distance: 1, cells: [white])
    let next = ghostLayer(direction: .next, distance: 1, cells: [white])

    let cool = previous.ghostColor(for: white)
    let warm = next.ghostColor(for: white)
    #expect(cool.blue > cool.red)
    #expect(warm.red > warm.blue)
    // Both are reduced in intensity as well as tinted: the alpha is what
    // keeps a ghost from competing with real content.
    #expect(cool.alpha < 1)
    #expect(warm.alpha < 1)
  }

  // MARK: - Blending on the canvas

  /// One fully worked cell, so the blend is pinned to numbers rather than
  /// to itself. A white ghost of the previous frame, one frame away, over
  /// the transparent checker's light square.
  @Test("a ghost blends over the transparent checker at the declared strength")
  func ghostBlendsOverTheCheckerboard() throws {
    let size = GIFEditorCore.PixelSize(width: 1, height: 1)
    let surface = CanvasSurfaceView(
      size: size,
      cells: [nil],
      cursor: .zero,
      selection: nil,
      pendingMarqueeAnchor: nil,
      pendingGradientAnchor: nil,
      mode: .fullCell,
      viewport: .wholeCanvas(size),
      ghosts: [ghostLayer(direction: .previous, distance: 1, cells: [.white])]
    )

    // checker(0,0) = 0.18 grey; ghost = white tinted 0.55 toward
    // (0.36, 0.60, 1.0) then faded to alpha 0.45.
    let tint = OnionSkinAppearance.previousTint
    let amount = OnionSkinAppearance.tintAmount
    let alpha = OnionSkinAppearance.opacity(atDistance: 1)
    func expected(_ tintChannel: Double) -> Double {
      let ghost = 1.0 + (tintChannel - 1.0) * amount
      return ghost * alpha + 0.18 * (1 - alpha)
    }

    let resolved = try #require(surface.resolvedPixels.first ?? nil)
    #expect(abs(resolved.red - expected(tint.red)) < 1e-9)
    #expect(abs(resolved.green - expected(tint.green)) < 1e-9)
    #expect(abs(resolved.blue - expected(tint.blue)) < 1e-9)
    #expect(abs(resolved.alpha - 1.0) < 1e-9, "the cell the terminal paints is opaque")
  }

  @Test("a nearer ghost reads stronger than a farther one")
  func nearerGhostsAreStronger() {
    let near = ghostLayer(direction: .previous, distance: 1, cells: [.white])
    let far = ghostLayer(direction: .previous, distance: 3, cells: [.white])
    let checker = Color(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)

    let nearColor = near.ghostColor(for: .white).composited(over: checker)
    let farColor = far.ghostColor(for: .white).composited(over: checker)
    #expect(nearColor.blue > farColor.blue)
    #expect(farColor.blue > checker.blue, "even the faintest ghost is visible")
  }

  /// The blend has to be right at every zoom step and in both grid modes,
  /// so this checks the *shape* of the change rather than one cell: with
  /// ghosts on, exactly the logical pixels whose source pixel is
  /// transparent-and-ghosted may differ, and nothing else may.
  @Test(
    "ghosts change exactly the ghosted transparent pixels, at every zoom and mode",
    arguments: [
      CanvasZoom.magnified(1), .magnified(2), .magnified(4), .reduced(2),
    ]
  )
  func ghostsChangeOnlyGhostedTransparentPixels(zoom: CanvasZoom) {
    for mode in [CanvasPixelGridMode.fullCell, .verticalHalfBlock] {
      let size = GIFEditorCore.PixelSize(width: 4, height: 4)
      // Current frame: a diagonal of solid red, everything else transparent.
      var current: [EditorColor?] = Array(repeating: nil, count: size.area)
      for index in 0..<4 { current[index * size.width + index] = EditorColor(rgbHex: 0xE05757) }
      // Ghost frame: the left half painted, so it overlaps both the
      // current frame's content and its holes.
      var ghostCells: [EditorColor?] = Array(repeating: nil, count: size.area)
      for y in 0..<4 {
        for x in 0..<2 { ghostCells[y * size.width + x] = EditorColor.white }
      }

      let viewport = CanvasViewport(zoom: zoom, origin: .zero, visibleSize: size)
      func resolve(ghosts: [CanvasGhostLayer]) -> [Color?] {
        CanvasSurfaceView(
          size: size,
          cells: current,
          cursor: .zero,
          selection: nil,
          pendingMarqueeAnchor: nil,
          pendingGradientAnchor: nil,
          mode: mode,
          viewport: viewport,
          ghosts: ghosts
        ).resolvedPixels
      }

      let plain = resolve(ghosts: [])
      let ghosted = resolve(
        ghosts: [ghostLayer(direction: .previous, distance: 1, cells: ghostCells)]
      )
      #expect(plain.count == ghosted.count)

      let logical = viewport.logicalSize
      var changedCount = 0
      for y in 0..<logical.height {
        for x in 0..<logical.width {
          let index = y * logical.width + x
          let source = viewport.sourcePoint(forLogicalX: x, y: y)
          let sourceIndex = size.indexOf(source)
          let isOpaque = current[sourceIndex] != nil
          let isGhosted = ghostCells[sourceIndex] != nil
          let label = "zoom \(zoom) mode \(mode) at logical (\(x), \(y))"

          if isOpaque {
            #expect(plain[index] == ghosted[index], "\(label): real content must not change")
          } else if isGhosted {
            #expect(plain[index] != ghosted[index], "\(label): a ghosted hole must change")
            changedCount += 1
          } else {
            #expect(plain[index] == ghosted[index], "\(label): an unghosted hole must not change")
          }
        }
      }
      #expect(changedCount > 0, "the fixture must actually exercise the blend")
    }
  }

  @Test("ghosts stack far to near, so the nearest neighbour wins")
  func nearestGhostWins() throws {
    let size = GIFEditorCore.PixelSize(width: 1, height: 1)
    let far = ghostLayer(direction: .previous, distance: 2, cells: [.white])
    let near = ghostLayer(direction: .next, distance: 1, cells: [.white])
    let stacked = CanvasSurfaceView(
      size: size,
      cells: [nil],
      cursor: .zero,
      selection: nil,
      pendingMarqueeAnchor: nil,
      pendingGradientAnchor: nil,
      mode: .fullCell,
      viewport: .wholeCanvas(size),
      ghosts: [far, near]
    ).resolvedPixels

    let resolved = try #require(stacked.first ?? nil)
    // The nearest ghost is the warm one and it is composited last, so the
    // stack leans warm even though a cool ghost is underneath it.
    #expect(resolved.red > resolved.blue)
  }

  // MARK: - The cull-then-scale invariant

  /// **The proof that the blend is inside the bounded loop.**
  ///
  /// If ghosts were resolved by materializing whole frames and blending
  /// afterwards, the resolved array would grow with the canvas — which is
  /// exactly the area-proportional cost the viewport was built to delete.
  /// The array's length must stay pinned to the cell budget whatever the
  /// canvas size, the zoom, or the number of ghosts.
  @Test("resolvedPixels stays bounded by the cell budget with ghosts on")
  func resolvedPixelCountIsIndependentOfCanvasAreaAndGhostCount() {
    let budget = CellSize(width: 40, height: 20)

    func resolvedCount(
      canvas: GIFEditorCore.PixelSize,
      level: CanvasZoomLevel,
      ghostCount: Int
    ) -> Int {
      let viewport = CanvasViewportState(level: level).resolved(
        in: CanvasViewportContext(
          canvasSize: canvas,
          cellBudget: budget,
          mode: .verticalHalfBlock
        )
      )
      let cells: [EditorColor?] = Array(repeating: nil, count: canvas.area)
      let ghosts = (0..<ghostCount).map { offset in
        ghostLayer(
          direction: offset.isMultiple(of: 2) ? .previous : .next,
          distance: offset / 2 + 1,
          cells: Array(repeating: EditorColor.white, count: canvas.area)
        )
      }
      return CanvasSurfaceView(
        size: canvas,
        cells: cells,
        cursor: .zero,
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .verticalHalfBlock,
        viewport: viewport,
        ghosts: ghosts
      ).resolvedPixels.count
    }

    let small = GIFEditorCore.PixelSize(width: 256, height: 256)
    let large = GIFEditorCore.PixelSize(width: 1024, height: 1024)
    let ceiling = budget.width * budget.height * 2

    for level in CanvasZoomLevel.allCases {
      for ghostCount in [0, 1, 6] {
        let atSmall = resolvedCount(canvas: small, level: level, ghostCount: ghostCount)
        let atLarge = resolvedCount(canvas: large, level: level, ghostCount: ghostCount)
        for (canvas, count) in [("256²", atSmall), ("1024²", atLarge)] {
          #expect(
            count <= ceiling,
            "\(level) at \(canvas) with \(ghostCount) ghosts resolved \(count) > \(ceiling) cells"
          )
        }
        // At a magnified level the array is *identical* across canvas
        // sizes. `fit` is the one level whose logical size legitimately
        // depends on the canvas — it picks the integer stride that makes
        // the whole document fit — so there the budget ceiling above is
        // the whole claim.
        guard level != .fit else { continue }
        #expect(
          atSmall == atLarge,
          "\(level) with \(ghostCount) ghosts: 256² resolved \(atSmall), 1024² resolved \(atLarge)"
        )
      }
    }

    // Pinned numbers, so a regression that merely kept the two sides equal
    // while growing both still fails: 4× into a 40×20-cell region is
    // 40 logical columns and 40 logical rows.
    #expect(resolvedCount(canvas: small, level: .x4, ghostCount: 6) == 40 * 40)
    #expect(resolvedCount(canvas: large, level: .x1, ghostCount: 6) == 40 * 40)
  }

  // MARK: - Ghosts do not leak

  /// The eyedropper reads the model, and the model has never heard of onion
  /// skin — so a ghost under the cursor cannot be picked.
  @Test("the eyedropper picks the real pixel, never the ghost under it")
  func eyedropperIgnoresGhosts() {
    let model = EditingSession(document: twoFrameDocument())
    model.primaryColorIndex = 7
    model.selectTool(.eyedropper)
    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)

    // Frame 0 is transparent at the cursor and frame 1 — the ghost — is
    // not, so a leak would show up as the ghost's slot being picked.
    let composites = model.compositedFrames()
    #expect(composites[0][0] == nil)
    #expect(composites[1][0] != nil)

    var settings = OnionSkinSettings()
    settings.toggle()
    let ghosts = settings.ghostLayers(around: 0, composites: composites)
    #expect(ghosts.count == 1, "the next frame is ghosted under the cursor")
    _ = renderCanvas(model: model, composites: composites, ghosts: ghosts)

    model.applyToolAtCursor()
    #expect(model.primaryColorIndex == 7, "the ghost must not be pickable")
    #expect(model.statusMessage.contains("Nothing to pick"))
  }

  /// The document and both of its serializations are byte-identical with
  /// onion skin on and off. Rendering the canvas with ghosts is the only
  /// new code path, so it is the one run between the two measurements.
  @Test("the exported GIF and the project file are unchanged by onion skin")
  func ghostsNeverReachAnExport() throws {
    let model = EditingSession(document: twoFrameDocument())
    let before = model.document
    let gifBefore = try GIFEncoder.encode(document: before)
    let projectBefore = try ProjectFile.data(for: before)

    let composites = model.compositedFrames()
    let settings = OnionSkinSettings(isEnabled: true, depth: 3, sides: .both)
    for frameIndex in 0..<before.frames.count {
      let ghosts = settings.ghostLayers(around: frameIndex, composites: composites)
      _ = renderCanvas(model: model, composites: composites, ghosts: ghosts)
    }

    #expect(model.document == before)
    #expect(try GIFEncoder.encode(document: model.document) == gifBefore)
    #expect(try ProjectFile.data(for: model.document) == projectBefore)
    // The composites the ghosts were drawn from are untouched too, so a
    // later frame cannot inherit a blended pixel.
    #expect(model.compositedFrames() == composites)
    #expect(!model.isDirty, "onion skin is display state and must not dirty the document")
  }

  /// Ghost color never round-trips back into the editor's own color type,
  /// which is the only representation a `PixelBuffer` can hold.
  @Test("no ghosted cell is representable as a document pixel")
  func ghostedCellsNeverBecomeDocumentPixels() {
    let model = EditingSession(document: twoFrameDocument())
    let composites = model.compositedFrames()
    var settings = OnionSkinSettings()
    settings.toggle()
    let ghosts = settings.ghostLayers(around: 0, composites: composites)

    let resolved = renderCanvas(model: model, composites: composites, ghosts: ghosts)
    let blended = resolved.compactMap { $0 }.map { $0.toEditorColor() }
    #expect(!blended.isEmpty)
    // Every layer of both frames still holds exactly what it held before —
    // the blended colors exist only in the resolved array above.
    for frame in model.document.frames {
      for layer in frame.layers {
        #expect(layer.pixels.pixels.allSatisfy { $0 == nil || $0! <= 2 })
      }
    }
  }

  // MARK: - Rendering end to end

  @Test("a ghost reaches the rendered surface as a background color")
  func ghostReachesTheRenderedSurface() throws {
    let size = GIFEditorCore.PixelSize(width: 2, height: 2)
    let ghostCells: [EditorColor?] = [.white, nil, nil, nil]
    func raster(ghosts: [CanvasGhostLayer]) -> RasterSurface {
      render(
        CanvasView(
          size: size,
          cells: Array(repeating: nil, count: size.area),
          cursor: GIFEditorCore.PixelPoint(x: 1, y: 1),
          selection: nil,
          pendingMarqueeAnchor: nil,
          pendingGradientAnchor: nil,
          mode: .fullCell,
          ghosts: ghosts
        ),
        width: 8,
        height: 6
      ).rasterSurface
    }

    let plain = raster(ghosts: [])
    let ghosted = raster(
      ghosts: [ghostLayer(direction: .previous, distance: 1, cells: ghostCells)]
    )
    let plainCell = plain.cells[1][1].style?.backgroundColor
    let ghostedCell = ghosted.cells[1][1].style?.backgroundColor
    #expect(plainCell != ghostedCell, "the ghost must be visible on the surface")
    let ghostColor = try #require(ghostedCell)
    #expect(ghostColor.blue > ghostColor.red, "and it must read as the cool, previous-frame tint")
    // The unghosted neighbour is untouched.
    #expect(plain.cells[1][2].style?.backgroundColor == ghosted.cells[1][2].style?.backgroundColor)
  }

  // MARK: - The View menu

  /// The three controls are reachable without the keyboard too, and each
  /// menu row shows the value it will change — a dropdown row is one click,
  /// so the two settings rows cycle rather than offering a submenu.
  @Test("the View menu carries the onion-skin controls and their values")
  func viewMenuCarriesTheOnionSkinControls() {
    let model = EditingSession(document: twoFrameDocument())
    var settings = OnionSkinSettings(isEnabled: true, depth: 2, sides: .previous)
    let binding = Binding(get: { settings }, set: { settings = $0 })

    let text = render(
      MenuBarDropdownView(
        menu: .view,
        openMenu: .constant(.view),
        model: model,
        showsToolDock: .constant(true),
        showsRightPanel: .constant(true),
        showsTimeline: .constant(true),
        pixelGridMode: .constant(.verticalHalfBlock),
        isResizeSheetPresented: .constant(false),
        onionSkin: binding,
        refresh: {}
      ),
      width: 44,
      height: 24
    ).rasterSurface.lines.joined(separator: "\n")

    #expect(text.contains("Onion Skin"))
    #expect(text.contains("Ghosted Sides: Previous"))
    #expect(text.contains("Ghost Frames: 2"))
    // The enabled row is checked; a disabled one is not.
    #expect(text.contains("✓ Onion Skin"))
  }

  // MARK: - Fixtures

  private func ghostLayer(
    direction: OnionSkinDirection,
    distance: Int,
    cells: [EditorColor?]
  ) -> CanvasGhostLayer {
    CanvasGhostLayer(
      cells: cells,
      tint: OnionSkinAppearance.tint(for: direction),
      opacity: OnionSkinAppearance.opacity(atDistance: distance)
    )
  }

  /// Two frames, 4×4: the first blank apart from a single pixel away from
  /// the origin, the second filled — so frame 0's origin is transparent and
  /// frame 1's is not.
  private func twoFrameDocument() -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    var sparse = PixelBuffer(size: size)
    sparse[GIFEditorCore.PixelPoint(x: 3, y: 3)] = 1
    let first = EditorFrame(
      layers: [EditorLayer(name: "Frame 1", pixels: sparse)],
      delayCentiseconds: 10
    )
    let second = EditorFrame(
      layers: [EditorLayer(name: "Frame 2", pixels: PixelBuffer(size: size, fill: 2))],
      delayCentiseconds: 10
    )
    return GIFDocument(size: size, frames: [first, second])
  }

  private func renderCanvas(
    model: EditingSession,
    composites: [[EditorColor?]],
    ghosts: [CanvasGhostLayer]
  ) -> [Color?] {
    CanvasSurfaceView(
      size: model.document.size,
      cells: composites[model.currentFrameIndex],
      cursor: model.cursor,
      selection: model.selection,
      pendingMarqueeAnchor: nil,
      pendingGradientAnchor: nil,
      mode: .verticalHalfBlock,
      viewport: .wholeCanvas(model.document.size),
      ghosts: ghosts
    ).resolvedPixels
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
      identity: Identity(components: ["gifeditor.onionskin.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
