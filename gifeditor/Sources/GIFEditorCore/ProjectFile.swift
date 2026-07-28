import Foundation

/// Why a decode error type exists at all.
///
/// Every `Codable` conformance in this module used to be synthesized,
/// and a synthesized `init(from:)` assigns stored properties directly —
/// it never calls the initializer that enforces the type's invariant.
/// `PixelSize` guarantees positive dimensions, `PixelBuffer` guarantees
/// `pixels.count == size.area`, `ColorPalette` guarantees exactly
/// `capacity` entries, `GIFDocument` guarantees a non-empty frame list.
/// Nothing decoded those types, so the gap was latent. A project file
/// is untrusted input — hand-edited, truncated by a failed write,
/// written by a future build, or crafted — and the moment one can be
/// opened, each of those guarantees becomes a crash-on-open.
///
/// So every hardened `init(from:)` in this module routes through the
/// checked initializer and reports the violation here. A malformed
/// project file produces a thrown, reportable error; never a trap and
/// never an out-of-bounds access.
public enum ProjectDecodeError: Error, Hashable, Sendable, CustomStringConvertible {
  /// The envelope declares a `formatVersion` this build does not know.
  case unsupportedFormatVersion(found: Int, supported: Int)

  /// The bytes are not the envelope at all: not JSON, truncated
  /// mid-object, a missing key, a field of the wrong type. Carries the
  /// underlying `DecodingError` description for logs — the UI supplies
  /// its own wording.
  case malformedContainer(String)

  /// A canvas or buffer declared a non-positive dimension.
  case invalidCanvasSize(width: Int, height: Int)

  /// A canvas declared dimensions past the sanity limits. See
  /// ``ProjectFile/maximumCanvasDimension``.
  case canvasTooLarge(width: Int, height: Int, dimensionLimit: Int, areaLimit: Int)

  /// A pixel plane was not valid base64.
  case invalidBase64(field: String)

  /// A pixel plane's byte count disagrees with the buffer's declared size.
  case payloadLengthMismatch(field: String, expected: Int, found: Int)

  /// The palette carried no colors. ``ColorPalette`` would substitute a
  /// single transparent slot, which silently discards the author's
  /// palette rather than reporting a damaged file.
  case emptyPalette

  /// The palette's `usedCount` disagrees with the colors it carries.
  /// ``ColorPalette/usedColors`` takes a prefix of that length (a
  /// negative one traps) and ``ColorPalette/nearestIndex(to:)`` scans
  /// `0..<usedCount` (an oversized one reads past the end), so the
  /// number is checked against the array rather than trusted.
  case invalidPaletteUsedCount(found: Int, available: Int)

  /// The document carried no frames — `frames[currentFrameIndex]` traps
  /// on the first render.
  case emptyFrameList

  /// A frame carried no layers. Every layer-indexed read in the editor
  /// assumes at least one.
  case emptyLayerList(frameIndex: Int)

  /// A layer's pixel buffer is not the canvas size. Format v1 stores
  /// every layer at full canvas size; offset or cropped layers would be
  /// a format change, not a file the current reader should guess at.
  case layerSizeMismatch(canvas: PixelSize, layer: PixelSize)

  public var description: String {
    switch self {
    case .unsupportedFormatVersion(let found, let supported):
      return
        "project format version \(found) is not supported (this build reads version \(supported))"
    case .malformedContainer(let detail):
      return "project file is damaged or not a project file: \(detail)"
    case .invalidCanvasSize(let width, let height):
      return "canvas size \(width)x\(height) is not positive"
    case .canvasTooLarge(let width, let height, let dimensionLimit, let areaLimit):
      return
        "canvas size \(width)x\(height) exceeds the limit of \(dimensionLimit) per axis / \(areaLimit) pixels total"
    case .invalidBase64(let field):
      return "pixel plane '\(field)' is not valid base64"
    case .payloadLengthMismatch(let field, let expected, let found):
      return "pixel plane '\(field)' has \(found) bytes, expected \(expected)"
    case .emptyPalette:
      return "project file carries an empty palette"
    case .invalidPaletteUsedCount(let found, let available):
      return "palette declares \(found) used slots but carries \(available) colors"
    case .emptyFrameList:
      return "project file carries no frames"
    case .emptyLayerList(let frameIndex):
      return "frame \(frameIndex) carries no layers"
    case .layerSizeMismatch(let canvas, let layer):
      return
        "layer is \(layer.width)x\(layer.height) but the canvas is \(canvas.width)x\(canvas.height)"
    }
  }
}

/// The native project format: a versioned JSON envelope around a
/// ``GIFDocument``.
///
/// Saving through the GIF encoder flattens layers, so a document saved
/// as GIF and reopened comes back as one opaque layer per frame — layer
/// names, visibility, stacking, and palette order are destroyed by the
/// app's own save path. This is the lossless representation, and GIF
/// becomes an explicit *export*.
///
/// The envelope is deliberately boring:
///
/// ```json
/// { "formatVersion": 1, "document": { … } }
/// ```
///
/// JSON rather than a binary container because the interesting payload
/// (the pixel planes) is already packed, everything around it is small
/// metadata, and a text envelope stays inspectable with the tools
/// everyone already has. No compression in v1 — the version field is
/// what buys the right to add it later.
public struct ProjectFile: Hashable, Sendable {
  /// The on-disk extension, declared once so the save verb, the open
  /// filter, and the golden fixture cannot drift apart.
  public static let fileExtension = "halfcell"

  /// The format version this build writes and is willing to read.
  ///
  /// Bump when the *meaning* of the payload changes — a compressed
  /// pixel plane, per-layer offsets, a second palette. A reader that
  /// finds a version it does not know refuses the file rather than
  /// interpreting new bytes under old rules.
  public static let currentFormatVersion = 1

  /// Largest canvas edge a project file may declare, per axis.
  ///
  /// This is a hostile-input backstop, not a product ceiling: the
  /// format stores arbitrary dimensions, and the editor's authoring cap
  /// is a UI concern. The limit exists only so a header claiming
  /// 100000 x 100000 is rejected *before* anything multiplies it out
  /// and tries to allocate 10^10 elements. 16384 is 64x the editor's
  /// 256-pixel authoring ceiling per axis, so it is nowhere near
  /// becoming a de-facto ceiling; ``maximumCanvasArea`` is what
  /// actually bounds the allocation.
  public static let maximumCanvasDimension = 16_384

  /// Largest canvas area (width x height) a project file may declare:
  /// 2^24 pixels — 4096 x 4096, or 16384 x 1024 at the axis limit.
  ///
  /// A `[PaletteIndex?]` element costs 2 bytes, so this caps one layer
  /// buffer at 32 MB: large enough that no plausible authoring size
  /// reaches it, small enough that a crafted header cannot exhaust
  /// memory before the length checks on the pixel planes run.
  public static let maximumCanvasArea = 16_777_216

  public let formatVersion: Int
  public var document: GIFDocument

  public init(document: GIFDocument, formatVersion: Int = ProjectFile.currentFormatVersion) {
    self.formatVersion = formatVersion
    self.document = document
  }

  /// Encodes `document` into project-file bytes.
  ///
  /// Source provenance and Project backing are lifecycle state, not part of
  /// the artwork, so neither appears in these bytes.
  public static func data(for document: GIFDocument) throws -> Data {
    let encoder = JSONEncoder()
    // Sorted keys make a re-save of unchanged content byte-stable,
    // which is what lets the golden fixture and any future diff-based
    // tooling mean something.
    //
    // Slashes go unescaped because roughly one base64 character in 64
    // is `/`, and `\/` — which JSON permits but does not require —
    // costs a measured 5.5% of the file for no reader anywhere. The
    // decoder accepts either spelling, so files written before this
    // still open.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(ProjectFile(document: document))
  }

  /// Decodes project-file bytes back into a document.
  ///
  /// Throws ``ProjectDecodeError`` for every rejection — including the
  /// ones `JSONDecoder` reports as `DecodingError` — so a caller has a
  /// single error type to switch over, and never has to catch a trap it
  /// cannot catch.
  public static func document(from data: Data) throws -> GIFDocument {
    do {
      return try JSONDecoder().decode(ProjectFile.self, from: data).document
    } catch let error as ProjectDecodeError {
      throw error
    } catch {
      throw ProjectDecodeError.malformedContainer(String(describing: error))
    }
  }

  /// True when `data` opens with the GIF signature (`GIF87a` / `GIF89a`).
  ///
  /// `Open` routes on content rather than on the extension, so a
  /// project saved without one — or a GIF someone renamed — still
  /// reaches the right reader.
  public static func hasGIFSignature(_ data: Data) -> Bool {
    let magic = Array("GIF8".utf8)
    guard data.count >= magic.count else { return false }
    return Array(data.prefix(magic.count)) == magic
  }
}

extension ProjectFile: Codable {
  private enum CodingKeys: String, CodingKey {
    case formatVersion
    case document
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Version first, deliberately: a file from a future build must be
    // refused before any of its fields are read under today's rules.
    let version = try container.decode(Int.self, forKey: .formatVersion)
    guard version == Self.currentFormatVersion else {
      throw ProjectDecodeError.unsupportedFormatVersion(
        found: version,
        supported: Self.currentFormatVersion
      )
    }
    self.formatVersion = version
    self.document = try container.decode(GIFDocument.self, forKey: .document)
  }
}

/// Packs a ``PixelBuffer``'s `[PaletteIndex?]` storage into the two flat
/// byte planes the project format stores, and back.
///
/// The obvious encoding — a JSON array of optional indices — costs 4-5
/// bytes of text per pixel (`null,` / `123,`), so a 256x256 x 20-frame
/// document would write a ~6 MB file to describe a ~60 KB GIF. Splitting
/// the buffer into an *index plane* (one byte per pixel) and an *opacity
/// plane* (one bit per pixel) costs 1.125 bytes per pixel packed, ~1.5
/// after base64 — and the planes are already the shape a compressor
/// wants, so RLE or whole-file compression stays available later behind
/// a `formatVersion` bump.
///
/// Transparent pixels write index 0 in the index plane. Slot 0 is the
/// palette's reserved transparent slot, so the substituted byte is
/// meaningful rather than arbitrary, and the plane stays dense.
enum ProjectPixelPayload {
  /// Bit `i` of mask byte `n` (least significant bit first) is pixel
  /// `n * 8 + i`; a set bit means opaque. LSB-first so both directions
  /// are a plain shift by `index % 8`, with no reversal to get wrong.
  static func pack(_ pixels: [PaletteIndex?]) -> (indices: [UInt8], opaqueMask: [UInt8]) {
    var indices = [UInt8](repeating: 0, count: pixels.count)
    var opaqueMask = [UInt8](repeating: 0, count: maskByteCount(forPixelCount: pixels.count))
    for (offset, pixel) in pixels.enumerated() {
      guard let pixel else { continue }
      indices[offset] = pixel
      opaqueMask[offset / 8] |= UInt8(1 << (offset % 8))
    }
    return (indices, opaqueMask)
  }

  /// Rebuilds the optional-index array, or throws when either plane
  /// disagrees with `count`. The length checks run before the result
  /// array is filled, so a short plane can never be read past its end.
  static func unpack(
    indices: [UInt8],
    opaqueMask: [UInt8],
    count: Int
  ) throws -> [PaletteIndex?] {
    guard indices.count == count else {
      throw ProjectDecodeError.payloadLengthMismatch(
        field: "indices",
        expected: count,
        found: indices.count
      )
    }
    let expectedMaskBytes = maskByteCount(forPixelCount: count)
    guard opaqueMask.count == expectedMaskBytes else {
      throw ProjectDecodeError.payloadLengthMismatch(
        field: "opaqueMask",
        expected: expectedMaskBytes,
        found: opaqueMask.count
      )
    }

    var pixels = [PaletteIndex?](repeating: nil, count: count)
    for offset in 0..<count where opaqueMask[offset / 8] & UInt8(1 << (offset % 8)) != 0 {
      pixels[offset] = indices[offset]
    }
    return pixels
  }

  static func maskByteCount(forPixelCount count: Int) -> Int {
    (count + 7) / 8
  }
}
