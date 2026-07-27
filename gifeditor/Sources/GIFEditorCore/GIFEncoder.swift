import EditorGIF

/// Errors thrown while encoding a `GIFDocument` into GIF89a bytes.
public typealias GIFEncoderError = GIF.EncodingError

/// Adapts the editor's document model into `swift-gif`'s indexed encoder.
public enum GIFEncoder {

  /// How a document's frames are laid out inside the emitted GIF.
  ///
  /// Both codings describe the *same animation*: decoding either and
  /// compositing frame `i` yields byte-identical pixels. They differ only
  /// in how much of the canvas each frame's image descriptor covers, and
  /// therefore in file size.
  public enum FrameCoding: Hashable, Sendable {
    /// Every frame is written full-canvas, carrying the disposal the
    /// document authored. Simple, and the only coding that can express an
    /// arbitrary authored disposal sequence.
    case fullFrames

    /// Frames after the first are written as the smallest rectangle that
    /// differs from the previous composite, with `.keep` disposal so the
    /// untouched region persists. See ``GIFEncoder`` for the transparency
    /// rule that decides when a frame can be coded this way.
    case deltaFrames
  }

  /// Encodes a flattened document into GIF89a bytes.
  ///
  /// `flattenedFrames[i]` is the result of `document.flatten(frameIndex: i)`,
  /// passed in by the caller so callers that want to do their own
  /// flattening (e.g. with effects on top) don't pay twice.
  ///
  /// The default is ``FrameCoding/deltaFrames``: it is provably
  /// render-identical to ``FrameCoding/fullFrames`` (see the discussion
  /// below), and export size is the number a GIF tool is judged on.
  /// ``FrameCoding/fullFrames`` stays available for callers that want the
  /// authored disposal sequence written through verbatim.
  ///
  /// ## Why a delta frame cannot always be taken
  ///
  /// The encoder maps the editor's `nil` pixels to
  /// ``ColorPalette/transparentSlot`` and declares that slot the frame's
  /// GIF transparent index. Under `.keep` disposal a transparent pixel
  /// means **"leave whatever was already there"** — not "erase to
  /// transparent". There is no index that means "erase": the only eraser
  /// in the format is a *previous* frame's `.background` disposal, which
  /// clears that frame's rectangle.
  ///
  /// So a pixel that goes painted → transparent between two frames cannot
  /// be expressed by a `.keep` delta at all. When frame `k` needs one, the
  /// encoder emits frame `k - 1` full-canvas with `.background` disposal
  /// (a full-canvas rectangle is what makes the clear cover the whole
  /// screen) and frame `k` full-canvas on the cleared result.
  ///
  /// One more transition needs the same treatment, and it is easy to miss.
  /// The canvas a decoder starts with is *transparent*, whereas the canvas
  /// left by a `.background` disposal holds the logical-screen background
  /// colour. Those are different pixel values, so a hole inherited from
  /// frame 0 is not interchangeable with a hole left by a clear. The
  /// planner tracks which of the two every hole currently is, and treats
  /// "hole that is not already background" exactly like painted →
  /// transparent. That single flag covers both cases.
  public static func encode(
    document: GIFDocument,
    flattenedFrames: [PixelBuffer]? = nil,
    frameCoding: FrameCoding = .deltaFrames
  ) throws -> [UInt8] {
    let flattened =
      flattenedFrames ?? (0..<document.frames.count).map { document.flatten(frameIndex: $0) }
    precondition(flattened.count == document.frames.count)

    // Every frame as the GIF will carry it: the editor's `nil` becomes the
    // reserved transparent slot. This is exactly the array the full-frame
    // path has always written, and the delta planner reasons entirely in
    // terms of it — so "what changed" is asked of the bytes that actually
    // reach the file, not of the editor's richer optional representation.
    let encodedFrames = flattened.map { buffer in
      buffer.pixels.map { $0 ?? ColorPalette.transparentSlot }
    }

    let frames: [GIF.IndexedFrame]
    switch frameCoding {
    case .fullFrames:
      frames = fullCanvasFrames(document: document, encodedFrames: encodedFrames)
    case .deltaFrames:
      frames =
        deltaCodedFrames(document: document, encodedFrames: encodedFrames)
        ?? fullCanvasFrames(document: document, encodedFrames: encodedFrames)
    }

    let image = GIF.IndexedImage(
      size: (x: document.size.width, y: document.size.height),
      globalColorTable: globalColorTable(document: document, encodedFrames: encodedFrames),
      backgroundIndex: Int(ColorPalette.transparentSlot),
      loopCount: document.loopCount,
      frames: frames
    )

    return try GIF.Encoder.encode(image)
  }

  /// Whether ``FrameCoding/deltaFrames`` can be applied to `document` at
  /// all, or whether an export would silently fall back to full frames.
  ///
  /// Two documents are declined:
  ///
  /// - **Single-frame documents**, where there is no previous composite to
  ///   diff against and the two codings would agree anyway.
  /// - **Documents with an authored disposal other than `.background`.**
  ///   Delta coding *derives* disposal from the diff, so it can only be
  ///   applied where the authored sequence is the one the editor produces
  ///   (every frame `.background` — the `EditorFrame` default, and what
  ///   `GIFLoader` stamps on every imported frame). Anything else is the
  ///   author saying something specific about compositing, and is written
  ///   through verbatim rather than reinterpreted.
  ///
  /// This is public because it is also a *fact about the document a user
  /// is editing*: setting one frame to `.keep` costs the whole export its
  /// delta coding, which is a surprise worth warning about before the file
  /// size does it. The encoder is the authority and the UI asks it, rather
  /// than keeping a second copy of the rule that can drift.
  public static func supportsDeltaCoding(_ document: GIFDocument) -> Bool {
    document.frames.count > 1 && document.frames.allSatisfy { $0.disposal == .background }
  }

  // MARK: - Global color table

  /// The palette entries the file actually needs.
  ///
  /// ``ColorPalette`` is always ``ColorPalette/capacity`` entries long —
  /// slots past ``ColorPalette/usedCount`` duplicate the last used color —
  /// and handing all of them over made every exported GIF carry a 768-byte
  /// global color table and start LZW at 9-bit codes, however few colors
  /// the document actually held. Trimming buys both back: the vendored
  /// encoder pads whatever it is given up to the next power of two and
  /// derives the minimum code size from *that*, so a 32-color document
  /// writes 96 bytes of table and starts at 6 bits.
  ///
  /// Nothing about the rendered animation changes. The trimmed entries are
  /// padding by construction, the transparent slot and the background
  /// index are slot 0, and every index a frame references still resolves
  /// to the same color.
  ///
  /// The floor is the highest index any frame actually references rather
  /// than ``ColorPalette/usedCount`` alone. The two normally agree, but a
  /// `PixelBuffer` can hold an index past `usedCount` — the palette's
  /// subscript setter writes padding slots verbatim — and a table that did
  /// not cover such a pixel would make the encoder reject the document
  /// instead of writing it.
  private static func globalColorTable(
    document: GIFDocument,
    encodedFrames: [[UInt8]]
  ) -> [(r: UInt8, g: UInt8, b: UInt8)] {
    let highest = encodedFrames.compactMap { $0.max() }.max() ?? ColorPalette.transparentSlot
    let count = max(document.palette.usedCount, Int(highest) + 1)
    return document.palette.colors.prefix(count).map { color in
      (r: color.red, g: color.green, b: color.blue)
    }
  }

  // MARK: - Full-canvas coding

  private static func fullCanvasFrames(
    document: GIFDocument,
    encodedFrames: [[UInt8]]
  ) -> [GIF.IndexedFrame] {
    zip(document.frames, encodedFrames).map { frame, indices in
      GIF.IndexedFrame(
        width: document.size.width,
        height: document.size.height,
        indices: indices,
        transparentIndex: Int(ColorPalette.transparentSlot),
        delayCentiseconds: frame.delayCentiseconds,
        disposal: GIF.Disposal(editorDisposal: frame.disposal)
      )
    }
  }

  // MARK: - Delta coding

  /// Which frames must be written full-canvas, and what disposal each
  /// frame carries. Planning is a separate forward pass because a frame's
  /// disposal is decided by its **successor's** needs — the clear that
  /// lets frame `k` erase something is written on frame `k - 1`.
  private struct DeltaPlan {
    var isFullCanvas: [Bool]
    var disposals: [GIF.Disposal]
  }

  /// Returns the delta-coded frames, or `nil` when the document is not a
  /// candidate and the caller should fall back to full frames.
  ///
  /// See ``supportsDeltaCoding(_:)`` for which documents are declined and
  /// why. `encodedFrames` is one entry per frame (the caller asserts it),
  /// so that predicate answers for this array too.
  private static func deltaCodedFrames(
    document: GIFDocument,
    encodedFrames: [[UInt8]]
  ) -> [GIF.IndexedFrame]? {
    guard supportsDeltaCoding(document) else { return nil }

    let size = document.size
    let plan = planDelta(size: size, encodedFrames: encodedFrames)

    var frames: [GIF.IndexedFrame] = []
    frames.reserveCapacity(encodedFrames.count)

    for (index, frame) in document.frames.enumerated() {
      let current = encodedFrames[index]
      let rect: PixelRect
      let indices: [UInt8]

      if plan.isFullCanvas[index] {
        rect = size.bounds
        indices = current
      } else {
        let previous = encodedFrames[index - 1]
        rect = changedRect(previous: previous, current: current, size: size)
        indices = deltaIndices(previous: previous, current: current, size: size, rect: rect)
      }

      frames.append(
        GIF.IndexedFrame(
          left: rect.minX,
          top: rect.minY,
          width: rect.size.width,
          height: rect.size.height,
          indices: indices,
          transparentIndex: Int(ColorPalette.transparentSlot),
          delayCentiseconds: frame.delayCentiseconds,
          disposal: plan.disposals[index]
        )
      )
    }

    return frames
  }

  /// Decides, frame by frame, whether a `.keep` delta can reproduce the
  /// full-frame render — and inserts a full-canvas `.background` clear
  /// where it cannot.
  ///
  /// The invariant the pass maintains is: *after emitting frame `k`, the
  /// decoder's canvas equals the canvas the full-frame coding would have
  /// produced for frame `k`.* It holds for frame 0 (both codings paint the
  /// whole canvas over the decoder's transparent start), and each step
  /// below preserves it.
  private static func planDelta(
    size: PixelSize,
    encodedFrames: [[UInt8]]
  ) -> DeltaPlan {
    let transparent = ColorPalette.transparentSlot
    let count = encodedFrames.count
    let area = size.area

    var isFullCanvas = [Bool](repeating: false, count: count)
    var disposals = [GIF.Disposal](repeating: .keep, count: count)
    isFullCanvas[0] = true

    // `true` at pixels currently showing the logical-screen background
    // left by a `.background` disposal — as opposed to a painted colour,
    // or the transparency the canvas starts life with. Frame 0 paints onto
    // the initial canvas, so nothing is background yet.
    var showsBackground = [Bool](repeating: false, count: area)

    for index in 1..<count {
      let current = encodedFrames[index]

      // A hole in this frame is only free if the canvas already shows
      // background there; anything else (a painted pixel, or a frame-0
      // hole) would survive a `.keep` delta and be wrong.
      var needsClear = false
      for pixel in 0..<area where current[pixel] == transparent {
        if !showsBackground[pixel] {
          needsClear = true
          break
        }
      }

      if needsClear {
        // The clear is written on the *predecessor*, and only covers that
        // frame's rectangle — so the predecessor must be full-canvas too.
        // (Forcing a frame full-canvas never changes what it renders: its
        // transparent pixels leave the canvas alone either way.)
        isFullCanvas[index - 1] = true
        disposals[index - 1] = .background
        isFullCanvas[index] = true
        for pixel in 0..<area {
          showsBackground[pixel] = current[pixel] == transparent
        }
      } else {
        for pixel in 0..<area where current[pixel] != transparent {
          showsBackground[pixel] = false
        }
      }
    }

    // Loop boundary. `composited(frameIndex:)` never applies the last
    // frame's disposal, but a *player* does: on wrap-around the canvas is
    // whatever the last frame left. If frame 0 has holes, they must show
    // the same thing on the second pass as on the first, which means the
    // last frame has to clear the whole screen exactly as the full-frame
    // coding does.
    if encodedFrames[0].contains(transparent) {
      isFullCanvas[count - 1] = true
      disposals[count - 1] = .background
    }

    return DeltaPlan(isFullCanvas: isFullCanvas, disposals: disposals)
  }

  /// The smallest rectangle covering every pixel that differs between two
  /// frames.
  ///
  /// Identical frames have no such rectangle, and GIF cannot express a
  /// zero-area image descriptor (the encoder rejects one, and decoders
  /// that don't tend to disagree about what it means). They get a 1×1
  /// rectangle at the origin instead, which the caller fills with the
  /// transparent index — a frame that paints nothing but still carries its
  /// delay, which is the whole content of "this frame is a pause".
  private static func changedRect(
    previous: [UInt8],
    current: [UInt8],
    size: PixelSize
  ) -> PixelRect {
    var minX = size.width
    var minY = size.height
    var maxX = -1
    var maxY = -1

    for y in 0..<size.height {
      let row = y * size.width
      for x in 0..<size.width where previous[row + x] != current[row + x] {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
      }
    }

    guard maxX >= 0 else {
      return PixelRect(x: 0, y: 0, width: 1, height: 1)
    }
    return PixelRect(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1
    )
  }

  /// The indices for a delta rectangle.
  ///
  /// A pixel that did not change is written as the transparent index —
  /// under `.keep` that means "leave what is there", and what is there is
  /// already the right colour. It costs nothing in fidelity and gives LZW
  /// long runs of a single symbol exactly where the frame is quiet, which
  /// is where the savings live.
  private static func deltaIndices(
    previous: [UInt8],
    current: [UInt8],
    size: PixelSize,
    rect: PixelRect
  ) -> [UInt8] {
    var indices: [UInt8] = []
    indices.reserveCapacity(rect.size.area)
    for y in rect.minY..<rect.maxY {
      let row = y * size.width
      for x in rect.minX..<rect.maxX {
        let pixel = row + x
        indices.append(
          current[pixel] == previous[pixel] ? ColorPalette.transparentSlot : current[pixel]
        )
      }
    }
    return indices
  }
}

extension GIF.Disposal {
  fileprivate init(editorDisposal: EditorFrame.FrameDisposal) {
    self = GIF.Disposal(rawValue: editorDisposal.rawValue) ?? .unspecified
  }
}
