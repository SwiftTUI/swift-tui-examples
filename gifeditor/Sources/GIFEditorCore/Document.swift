import Foundation

/// One layer inside a frame. Layers paint bottom-to-top — the topmost
/// layer wins at every cell where its pixel is not transparent.
public struct EditorLayer: Hashable, Sendable, Codable, Identifiable {
  public let id: UUID
  public var name: String
  public var isVisible: Bool
  public var pixels: PixelBuffer

  public init(
    id: UUID = UUID(),
    name: String,
    isVisible: Bool = true,
    pixels: PixelBuffer
  ) {
    self.id = id
    self.name = name
    self.isVisible = isVisible
    self.pixels = pixels
  }
}

/// A single animation frame: a stack of layers plus its display delay
/// and disposal mode (which the encoder uses to decide how the frame's
/// region is reset before the next one paints).
public struct EditorFrame: Hashable, Sendable, Codable, Identifiable {
  public let id: UUID
  public var layers: [EditorLayer]
  /// Display delay in centiseconds (1/100 sec).
  public var delayCentiseconds: Int
  public var disposal: FrameDisposal

  public init(
    id: UUID = UUID(),
    layers: [EditorLayer],
    delayCentiseconds: Int = 10,
    disposal: FrameDisposal = .background
  ) {
    self.id = id
    self.layers = layers
    self.delayCentiseconds = max(0, delayCentiseconds)
    self.disposal = disposal
  }

  public enum FrameDisposal: UInt8, Hashable, Sendable, Codable {
    case unspecified = 0
    case keep = 1
    case background = 2
    case previous = 3
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case layers
    case delayCentiseconds
    case disposal
  }

  /// Routes through the memberwise initializer so a decoded delay gets
  /// the same `max(0, …)` clamp an authored one does. The frame has no
  /// invariant worth *rejecting* a file over — a nonsense delay is a
  /// nonsense animation, not a crash — but it should not be possible to
  /// hold a `EditorFrame` whose delay could never have been typed.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let layers = try container.decode([EditorLayer].self, forKey: .layers)
    let delayCentiseconds = try container.decode(Int.self, forKey: .delayCentiseconds)
    let disposal = try container.decode(FrameDisposal.self, forKey: .disposal)
    self.init(
      id: id,
      layers: layers,
      delayCentiseconds: delayCentiseconds,
      disposal: disposal
    )
  }
}

/// The complete editor document. Everything else in the editor reads
/// from or writes into this value type.
///
public struct GIFDocument: Hashable, Sendable, Codable {
  public var size: PixelSize
  public var palette: ColorPalette
  public var frames: [EditorFrame]
  /// Number of times the GIF should loop on playback. Zero = infinite.
  public var loopCount: Int

  public init(
    size: PixelSize,
    palette: ColorPalette = .default,
    frames: [EditorFrame],
    loopCount: Int = 0
  ) {
    precondition(!frames.isEmpty, "GIFDocument must have at least one frame")
    self.size = size
    self.palette = palette
    self.frames = frames
    self.loopCount = loopCount
  }

  /// A blank document: one frame, one transparent layer.
  public static func blank(
    size: PixelSize,
    palette: ColorPalette = .default
  ) -> GIFDocument {
    let layer = EditorLayer(
      name: "Layer 1",
      pixels: PixelBuffer(size: size)
    )
    let frame = EditorFrame(layers: [layer])
    return GIFDocument(size: size, palette: palette, frames: [frame])
  }

  /// Composites every visible layer of `frame` into a single flat buffer
  /// (bottom-to-top). The returned buffer is independent of any layer
  /// and is the format the renderer/encoder consumes.
  public func flatten(_ frame: EditorFrame) -> PixelBuffer {
    var result = PixelBuffer(size: size)
    for layer in frame.layers where layer.isVisible {
      // Paint the layer onto the running composite, treating the layer's
      // `nil` pixels as fully transparent so deeper layers show through.
      result.stamp(layer.pixels, at: .zero, respectingTransparency: true)
    }
    return result
  }

  public func flatten(frameIndex: Int) -> PixelBuffer {
    precondition(frames.indices.contains(frameIndex), "frame index out of range")
    return flatten(frames[frameIndex])
  }

  /// Composites a frame value as `[EditorColor]`, evaluating the palette so
  /// the renderer doesn't need to know about palette indices. Taking the
  /// frame by value (rather than index) lets callers memoize the result on
  /// frame content without threading the index through.
  public func flattenedColors(for frame: EditorFrame) -> [EditorColor?] {
    flatten(frame).pixels.map { idx in
      guard let idx else { return nil }
      let color = palette[idx]
      return color.alpha == 0 ? nil : color
    }
  }

  public func flattenedColors(frameIndex: Int) -> [EditorColor?] {
    precondition(frames.indices.contains(frameIndex), "frame index out of range")
    return flattenedColors(for: frames[frameIndex])
  }
}

// MARK: - Project-file coding

extension GIFDocument {
  private enum CodingKeys: String, CodingKey {
    case size
    case palette
    case frames
    case loopCount
  }

  /// The palette is written as its *used* colors — the array an author
  /// would recognise — rather than as the padded 256-entry storage.
  /// Padding is derived (every slot past `usedCount` duplicates the last
  /// used color), so writing it would be storing a computation, and
  /// re-deriving it on read is what re-establishes the "exactly
  /// `capacity` entries" invariant.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(size, forKey: .size)
    try container.encode(palette.usedColors, forKey: .palette)
    try container.encode(frames, forKey: .frames)
    try container.encode(loopCount, forKey: .loopCount)
  }

  /// Hardened decoding. Everything a renderer indexes without asking is
  /// established here, by the checked initializers, before the document
  /// escapes:
  ///
  /// - the canvas size is positive and within the format's sanity
  ///   limits (``PixelSize/init(from:)``);
  /// - every layer's pixel count matches its size
  ///   (``PixelBuffer/init(from:)``) and its size matches the canvas;
  /// - the frame list is non-empty, so `frames[currentFrameIndex]` on
  ///   the first render cannot trap, and no frame is layerless;
  /// - the palette is re-normalized through ``ColorPalette/init(colors:)``.
  ///
  /// That last one is not a workaround, and it stays. The palette is
  /// *written* as a plain `[EditorColor]` of used colors (see
  /// ``encode(to:)`` above), so this side never decodes a
  /// `ColorPalette` at all — there is no `usedCount` on the wire to
  /// trust or distrust, and re-deriving the padding through the type's
  /// single normalizing entry point is simply how the format reads.
  /// ``ColorPalette/init(from:)`` now hardens the type's *own* coded
  /// form for every other decode site; the two are independent, and
  /// collapsing either into the other would mean storing a computation
  /// in the file.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let size = try container.decode(PixelSize.self, forKey: .size)

    let colors = try container.decode([EditorColor].self, forKey: .palette)
    guard !colors.isEmpty else { throw ProjectDecodeError.emptyPalette }

    let frames = try container.decode([EditorFrame].self, forKey: .frames)
    guard !frames.isEmpty else { throw ProjectDecodeError.emptyFrameList }
    for (frameIndex, frame) in frames.enumerated() {
      guard !frame.layers.isEmpty else {
        throw ProjectDecodeError.emptyLayerList(frameIndex: frameIndex)
      }
      for layer in frame.layers where layer.pixels.size != size {
        throw ProjectDecodeError.layerSizeMismatch(canvas: size, layer: layer.pixels.size)
      }
    }

    // Clamped rather than rejected, matching `EditorFrame`'s delay: a
    // negative loop count is meaningless but harmless, and the GIF
    // encoder clamps it too.
    let decodedLoopCount = try container.decode(Int.self, forKey: .loopCount)
    let loopCount = max(0, decodedLoopCount)

    self.init(
      size: size,
      palette: ColorPalette(colors: colors),
      frames: frames,
      loopCount: loopCount
    )
  }
}
