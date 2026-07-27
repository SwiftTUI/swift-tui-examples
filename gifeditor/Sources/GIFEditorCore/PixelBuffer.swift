import Foundation

/// A row-major indexed-color buffer where `nil` represents transparent.
///
/// Pixel storage is `[PaletteIndex?]` rather than `[PaletteIndex]` so the
/// editor can preserve transparency on a per-pixel basis through layer
/// compositing — a layer's `nil` pixel reveals whatever painted below it
/// on the same frame, which is the natural mental model for raster
/// editors and matches the GIF graphics control extension semantics.
public struct PixelBuffer: Hashable, Sendable, Codable {
  public let size: PixelSize
  public var pixels: [PaletteIndex?]

  public init(size: PixelSize, fill: PaletteIndex? = nil) {
    self.size = size
    self.pixels = [PaletteIndex?](repeating: fill, count: size.area)
  }

  public init(size: PixelSize, pixels: [PaletteIndex?]) {
    precondition(pixels.count == size.area, "pixel array must match the buffer size")
    self.size = size
    self.pixels = pixels
  }

  /// The whole buffer as a rect — what a tool intersects a selection
  /// against before it writes anything.
  public var bounds: PixelRect { size.bounds }

  public subscript(point: PixelPoint) -> PaletteIndex? {
    get {
      guard size.contains(point) else { return nil }
      return pixels[size.indexOf(point)]
    }
    set {
      guard size.contains(point) else { return }
      pixels[size.indexOf(point)] = newValue
    }
  }

  /// Sets a single pixel without bounds-checking. Caller must ensure the
  /// point is in range — useful inside tight scan/fill loops.
  public mutating func setUnchecked(_ point: PixelPoint, to value: PaletteIndex?) {
    pixels[size.indexOf(point)] = value
  }

  public func get(_ point: PixelPoint) -> PaletteIndex? {
    guard size.contains(point) else { return nil }
    return pixels[size.indexOf(point)]
  }

  public mutating func clear() {
    for i in pixels.indices {
      pixels[i] = nil
    }
  }

  /// Resize this buffer, copying the overlapping rectangle and filling
  /// new area with transparent pixels. Out-of-bounds content is dropped.
  public func resized(to newSize: PixelSize) -> PixelBuffer {
    var result = PixelBuffer(size: newSize)
    let copyW = min(size.width, newSize.width)
    let copyH = min(size.height, newSize.height)
    for y in 0..<copyH {
      for x in 0..<copyW {
        let src = size.indexOf(PixelPoint(x: x, y: y))
        let dst = newSize.indexOf(PixelPoint(x: x, y: y))
        result.pixels[dst] = pixels[src]
      }
    }
    return result
  }

  /// Crops to the given rect (clamped to bounds). Returns `nil` when the
  /// rect is fully outside the buffer.
  public func cropped(to rect: PixelRect) -> PixelBuffer? {
    guard let clamped = rect.intersected(with: bounds) else { return nil }
    var out = PixelBuffer(size: clamped.size)
    for dy in 0..<clamped.size.height {
      for dx in 0..<clamped.size.width {
        let src = size.indexOf(
          PixelPoint(x: clamped.minX + dx, y: clamped.minY + dy)
        )
        let dst = clamped.size.indexOf(PixelPoint(x: dx, y: dy))
        out.pixels[dst] = pixels[src]
      }
    }
    return out
  }

  /// A quarter turn of the *whole* buffer into a new buffer of the
  /// transposed size — `w × h` in, `h × w` out.
  ///
  /// This is the transposable-buffer half of a lossless rotation, and it
  /// is why ``size`` can stay `let`: a turned buffer is a *new* buffer
  /// built through ``init(size:pixels:)``, exactly as ``cropped(to:)``
  /// and ``resized(to:)`` already build theirs, so the
  /// `pixels.count == size.area` precondition that ``setUnchecked(_:to:)``
  /// leans on is established rather than mutated around.
  ///
  /// The mapping is the exact one: cell `(x, y)` lands at
  /// `(height - 1 - y, x)` clockwise and `(y, width - 1 - x)`
  /// counter-clockwise. It is a bijection, so nothing is dropped, four
  /// turns are the identity, and the two directions undo each other —
  /// including for transparent cells, which travel like any other value.
  public func rotatedQuarterTurn(clockwise: Bool) -> PixelBuffer {
    let turned = size.transposed
    var out = [PaletteIndex?](repeating: nil, count: pixels.count)
    for y in 0..<size.height {
      for x in 0..<size.width {
        let destination =
          clockwise
          ? PixelPoint(x: size.height - 1 - y, y: x)
          : PixelPoint(x: y, y: size.width - 1 - x)
        out[turned.indexOf(destination)] = pixels[size.indexOf(PixelPoint(x: x, y: y))]
      }
    }
    return PixelBuffer(size: turned, pixels: out)
  }

  /// Stamps `other` into this buffer with its top-left at `origin`.
  /// `respectingTransparency` skips `nil` pixels in `other` — the natural
  /// "alpha" paste semantic. When `false`, `nil` pixels punch through.
  public mutating func stamp(
    _ other: PixelBuffer,
    at origin: PixelPoint,
    respectingTransparency: Bool = true
  ) {
    for sy in 0..<other.size.height {
      let dy = origin.y + sy
      if dy < 0 || dy >= size.height { continue }
      for sx in 0..<other.size.width {
        let dx = origin.x + sx
        if dx < 0 || dx >= size.width { continue }
        let src = other.pixels[other.size.indexOf(PixelPoint(x: sx, y: sy))]
        if respectingTransparency, src == nil { continue }
        pixels[size.indexOf(PixelPoint(x: dx, y: dy))] = src
      }
    }
  }
}

// MARK: - Project-file coding

extension PixelBuffer {
  private enum CodingKeys: String, CodingKey {
    case size
    case indices
    case opaqueMask
  }

  /// `[PaletteIndex?]` is the right *in-memory* representation — a
  /// layer's `nil` pixel is what lets deeper layers show through — but
  /// it is a poor wire representation: as a JSON array it costs 4-5
  /// bytes of text per pixel. It is written instead as two base64
  /// planes, one byte and one bit per pixel; see ``ProjectPixelPayload``
  /// for the layout and the arithmetic.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let packed = ProjectPixelPayload.pack(pixels)
    try container.encode(size, forKey: .size)
    try container.encode(Data(packed.indices).base64EncodedString(), forKey: .indices)
    try container.encode(Data(packed.opaqueMask).base64EncodedString(), forKey: .opaqueMask)
  }

  /// Hardened decoding: the planes are length-checked against the
  /// decoded ``size`` before a buffer is built, and the result goes
  /// through ``init(size:pixels:)`` so the `pixels.count == size.area`
  /// invariant that ``setUnchecked(_:to:)`` and ``PixelSize/indexOf(_:)``
  /// depend on is established by the same initializer everything else
  /// uses.
  ///
  /// The base64 strings are decoded by hand rather than through
  /// `Data`'s own `Codable` conformance so that malformed base64
  /// surfaces as a ``ProjectDecodeError`` naming the plane, instead of
  /// as a generic "data corrupted" from whatever
  /// `JSONDecoder.dataDecodingStrategy` happens to be set to.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let size = try container.decode(PixelSize.self, forKey: .size)
    let indicesText = try container.decode(String.self, forKey: .indices)
    let maskText = try container.decode(String.self, forKey: .opaqueMask)

    guard let indices = Data(base64Encoded: indicesText) else {
      throw ProjectDecodeError.invalidBase64(field: "indices")
    }
    guard let opaqueMask = Data(base64Encoded: maskText) else {
      throw ProjectDecodeError.invalidBase64(field: "opaqueMask")
    }

    let pixels = try ProjectPixelPayload.unpack(
      indices: [UInt8](indices),
      opaqueMask: [UInt8](opaqueMask),
      count: size.area
    )
    self.init(size: size, pixels: pixels)
  }
}
