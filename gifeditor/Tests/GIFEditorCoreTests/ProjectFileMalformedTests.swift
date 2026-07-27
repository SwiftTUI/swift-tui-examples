import Foundation
import Testing

@testable import GIFEditorCore

/// The malformed-project corpus.
///
/// One case per row of the "every `Codable` conformance bypasses its
/// type's invariant" table, plus the damage a file picks up in the real
/// world: truncation, a version from the future, a mangled base64 plane,
/// planes that disagree with each other, and a header claiming a canvas
/// nothing could allocate.
///
/// The gate is "does not trap", not "produces a nice message". Every
/// case here would, with synthesized decoding, reach an operation that
/// traps — a divide by zero, an out-of-bounds read, an array index past
/// the end — and a trap is not catchable: it would abort this test
/// process rather than fail an expectation. So a green run *is* the
/// proof; the error-case assertions on top of it are there to keep the
/// rejections deliberate rather than accidental.
@Suite("Project file — malformed corpus")
struct ProjectFileMalformedTests {

  // MARK: - One case per invariant

  @Test("PixelSize: a non-positive dimension is rejected, not divided by")
  func nonPositiveCanvasSize() throws {
    // `PixelSize.indexOf` divides by `width`; a zero-width canvas is a
    // divide-by-zero on the first render.
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["size"] = ["width": 0, "height": 3]
      }
    )
    #expect(Corpus.decodeError(data) == .invalidCanvasSize(width: 0, height: 3))

    let negative = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["size"] = ["width": 4, "height": -3]
      }
    )
    #expect(Corpus.decodeError(negative) == .invalidCanvasSize(width: 4, height: -3))
  }

  @Test("PixelBuffer: a plane that disagrees with the declared size is rejected")
  func pixelCountMismatch() throws {
    // The buffer claims 5x3 = 15 pixels while its planes still describe
    // the 4x3 = 12 the encoder wrote. Unchecked, `setUnchecked` and
    // `size.indexOf` would read and write past the end of the array.
    let data = try Corpus.serialize(
      Corpus.mutatingFirstLayerPixels(try Corpus.validEnvelope()) { pixels in
        pixels["size"] = ["width": 5, "height": 3]
      }
    )
    #expect(
      Corpus.decodeError(data) == .payloadLengthMismatch(field: "indices", expected: 15, found: 12)
    )
  }

  @Test("ColorPalette: an empty palette is rejected")
  func emptyPalette() throws {
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["palette"] = [] as [Any]
      }
    )
    #expect(Corpus.decodeError(data) == .emptyPalette)
  }

  @Test("ColorPalette: a short palette is padded to capacity, and high indices do not trap")
  func shortPaletteIsNormalized() throws {
    // The trap this closes: `ColorPalette.subscript` indexes `colors`
    // directly, so a decoded 3-entry palette traps on any pixel that
    // references a higher slot. The corpus document paints slot 200, so
    // this test *executes* the operation that would trap.
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["palette"] = [
          ["red": 0, "green": 0, "blue": 0, "alpha": 0],
          ["red": 255, "green": 0, "blue": 0, "alpha": 255],
          ["red": 0, "green": 255, "blue": 0, "alpha": 255],
        ]
      }
    )

    let decoded = try ProjectFile.document(from: data)
    #expect(decoded.palette.colors.count == ColorPalette.capacity)
    #expect(decoded.palette.usedCount == 3)
    // Padding duplicates the last used color, per `init(colors:)`.
    #expect(decoded.palette[200] == EditorColor(red: 0, green: 255, blue: 0, alpha: 255))
    #expect(decoded.palette[PaletteIndex(ColorPalette.capacity - 1)] == decoded.palette[200])
    #expect(decoded.palette.nearestIndex(to: .white) < ColorPalette.capacity)
    // The renderer's path: this subscripts the palette with slot 200.
    #expect(decoded.flattenedColors(frameIndex: 0).count == decoded.size.area)
  }

  @Test("GIFDocument: an empty frame list is rejected")
  func emptyFrameList() throws {
    // `document.frames[currentFrameIndex]` traps on the first render.
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["frames"] = [] as [Any]
      }
    )
    #expect(Corpus.decodeError(data) == .emptyFrameList)
  }

  // MARK: - Damage a file picks up in the world

  @Test("A truncated file is reported, not misread")
  func truncatedFile() throws {
    let whole = try ProjectFile.data(for: Corpus.subject())
    let half = whole.prefix(whole.count / 2)
    guard case .malformedContainer = try #require(Corpus.decodeError(Data(half))) else {
      Issue.record("expected .malformedContainer")
      return
    }
  }

  @Test("Bytes that are not the envelope at all are reported")
  func notAProjectFile() throws {
    let notJSON = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00])  // a GIF header
    guard case .malformedContainer = try #require(Corpus.decodeError(notJSON)) else {
      Issue.record("expected .malformedContainer for GIF bytes")
      return
    }

    let missingDocument = try Corpus.serialize(["formatVersion": 1])
    guard case .malformedContainer = try #require(Corpus.decodeError(missingDocument)) else {
      Issue.record("expected .malformedContainer for a missing document key")
      return
    }
  }

  @Test("A format version this build does not know is refused before the payload is read")
  func unsupportedFormatVersion() throws {
    for version in [0, 2, -1, 99] {
      var envelope = try Corpus.validEnvelope()
      envelope["formatVersion"] = version
      let data = try Corpus.serialize(envelope)
      #expect(
        Corpus.decodeError(data) == .unsupportedFormatVersion(found: version, supported: 1),
        "formatVersion \(version)"
      )
    }
  }

  @Test("A mangled base64 plane is reported by name")
  func malformedBase64() throws {
    let indices = try Corpus.serialize(
      Corpus.mutatingFirstLayerPixels(try Corpus.validEnvelope()) { pixels in
        pixels["indices"] = "!!! not base64 !!!"
      }
    )
    #expect(Corpus.decodeError(indices) == .invalidBase64(field: "indices"))

    let mask = try Corpus.serialize(
      Corpus.mutatingFirstLayerPixels(try Corpus.validEnvelope()) { pixels in
        pixels["opaqueMask"] = "????"
      }
    )
    #expect(Corpus.decodeError(mask) == .invalidBase64(field: "opaqueMask"))
  }

  @Test("Planes that disagree with each other are rejected")
  func planeLengthMismatch() throws {
    // 12 pixels need a 2-byte mask; hand it 1.
    let short = try Corpus.serialize(
      Corpus.mutatingFirstLayerPixels(try Corpus.validEnvelope()) { pixels in
        pixels["opaqueMask"] = Data([0xFF]).base64EncodedString()
      }
    )
    #expect(
      Corpus.decodeError(short)
        == .payloadLengthMismatch(field: "opaqueMask", expected: 2, found: 1)
    )

    let long = try Corpus.serialize(
      Corpus.mutatingFirstLayerPixels(try Corpus.validEnvelope()) { pixels in
        pixels["indices"] = Data(repeating: 7, count: 4096).base64EncodedString()
      }
    )
    #expect(
      Corpus.decodeError(long)
        == .payloadLengthMismatch(field: "indices", expected: 12, found: 4096)
    )
  }

  @Test("A canvas beyond the sanity limit is refused before anything is allocated")
  func oversizedCanvasHeader() throws {
    // 100000 x 100000 is 10^10 elements — 20 GB of `PaletteIndex?`. The
    // per-axis check runs before the area is multiplied out, so nothing
    // here ever reaches an allocation; if it did, this test would not
    // return to make an assertion.
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["size"] = ["width": 100_000, "height": 100_000]
      }
    )
    #expect(
      Corpus.decodeError(data)
        == .canvasTooLarge(
          width: 100_000,
          height: 100_000,
          dimensionLimit: ProjectFile.maximumCanvasDimension,
          areaLimit: ProjectFile.maximumCanvasArea
        )
    )

    // Within the per-axis limit but past the area limit.
    let wide = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["size"] = ["width": 16_384, "height": 16_384]
      }
    )
    #expect(
      Corpus.decodeError(wide)
        == .canvasTooLarge(
          width: 16_384,
          height: 16_384,
          dimensionLimit: ProjectFile.maximumCanvasDimension,
          areaLimit: ProjectFile.maximumCanvasArea
        )
    )
  }

  @Test("A layerless frame is rejected")
  func emptyLayerList() throws {
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        guard var frames = document["frames"] as? [[String: Any]], !frames.isEmpty else { return }
        frames[0]["layers"] = [] as [Any]
        document["frames"] = frames
      }
    )
    #expect(Corpus.decodeError(data) == .emptyLayerList(frameIndex: 0))
  }

  @Test("A layer that is not the canvas size is rejected")
  func layerSizeMismatch() throws {
    // Legal to build in memory, so no JSON surgery is needed: nothing
    // stops a caller from stacking a 2x2 layer in a 4x3 document today.
    let canvas = PixelSize(width: 4, height: 3)
    let odd = EditorLayer(name: "Odd", pixels: PixelBuffer(size: PixelSize(width: 2, height: 2)))
    let document = GIFDocument(
      size: canvas,
      frames: [EditorFrame(layers: [odd])]
    )
    let data = try ProjectFile.data(for: document)
    #expect(
      Corpus.decodeError(data)
        == .layerSizeMismatch(canvas: canvas, layer: PixelSize(width: 2, height: 2))
    )
  }

  @Test("A negative delay or loop count is clamped rather than carried")
  func nonsenseTimingsAreClamped() throws {
    let data = try Corpus.serialize(
      Corpus.mutatingDocument(try Corpus.validEnvelope()) { document in
        document["loopCount"] = -4
        guard var frames = document["frames"] as? [[String: Any]], !frames.isEmpty else { return }
        frames[0]["delayCentiseconds"] = -9
        document["frames"] = frames
      }
    )
    let decoded = try ProjectFile.document(from: data)
    #expect(decoded.loopCount == 0)
    #expect(decoded.frames[0].delayCentiseconds == 0)
  }
}

/// The same gate, applied to ``ColorPalette`` on its own.
///
/// The project format writes the palette as a plain array of used colors,
/// so the suite above only ever exercises the *document's* re-normalizing
/// read. The type has its own coded form — `colors` plus `usedCount` —
/// and until it had its own `init(from:)` that form was the one hole the
/// document could not cover: anything else that decoded a `ColorPalette`
/// got the synthesized initializer, which assigns both stored properties
/// verbatim.
///
/// Each case here names the operation that would trap on the shape it
/// feeds in, and — where the shape is *accepted* — runs that operation on
/// the decoded value, so a green run is the proof rather than the claim.
@Suite("ColorPalette — decoded on its own")
struct ColorPaletteDecodingTests {

  @Test("its own coded form round-trips")
  func codedFormRoundTrips() throws {
    for palette in [ColorPalette.default, ColorPalette(colors: [.transparent, .white])] {
      let data = try JSONEncoder().encode(palette)
      let decoded = try JSONDecoder().decode(ColorPalette.self, from: data)
      #expect(decoded == palette)
      #expect(decoded.usedCount == palette.usedCount)
      #expect(decoded.colors.count == ColorPalette.capacity)
    }
  }

  @Test("a short colors array is padded, and a high slot does not trap")
  func shortColorsArrayIsPadded() throws {
    // `subscript(_:)` indexes `colors` directly. A synthesized decode of
    // this object leaves a 3-element array, so *any* index above 2 is an
    // out-of-bounds read — including the one this test performs.
    let decoded = try PaletteCorpus.decode([
      "colors": [
        PaletteCorpus.color(0, 0, 0, 0),
        PaletteCorpus.color(255, 0, 0, 255),
        PaletteCorpus.color(0, 255, 0, 255),
      ],
      "usedCount": 3,
    ])

    #expect(decoded.colors.count == ColorPalette.capacity)
    #expect(decoded.usedCount == 3)
    #expect(decoded[200] == EditorColor(red: 0, green: 255, blue: 0, alpha: 255))
    #expect(decoded[PaletteIndex(ColorPalette.capacity - 1)] == decoded[200])
    // The other two would-be traps, run on an accepted value.
    #expect(decoded.usedColors.count == 3)
    #expect(decoded.nearestIndex(to: .white) < ColorPalette.capacity)
  }

  @Test("a negative usedCount is rejected, not taken as a prefix length")
  func negativeUsedCount() throws {
    // `usedColors` is `colors.prefix(usedCount)`, and `Array.prefix` traps
    // on a negative length.
    for negative in [-1, -7, Int.min] {
      #expect(
        PaletteCorpus.decodeError([
          "colors": [PaletteCorpus.color(0, 0, 0, 0), PaletteCorpus.color(1, 2, 3, 255)],
          "usedCount": negative,
        ]) == .invalidPaletteUsedCount(found: negative, available: 2),
        "usedCount \(negative)"
      )
    }
  }

  @Test("a usedCount past the end of the colors is rejected, not scanned")
  func oversizedUsedCount() throws {
    // `nearestIndex(to:)` scans `0..<usedCount` reading `colors[i]`.
    #expect(
      PaletteCorpus.decodeError([
        "colors": [PaletteCorpus.color(0, 0, 0, 0), PaletteCorpus.color(1, 2, 3, 255)],
        "usedCount": 9,
      ]) == .invalidPaletteUsedCount(found: 9, available: 2)
    )
    // Including the shape a synthesized encode of a *valid* palette would
    // have, with only the count corrupted.
    #expect(
      PaletteCorpus.decodeError([
        "colors": [PaletteCorpus.color(0, 0, 0, 0)],
        "usedCount": ColorPalette.capacity + 1,
      ]) == .invalidPaletteUsedCount(found: ColorPalette.capacity + 1, available: 1)
    )
  }

  @Test("a zero usedCount is rejected")
  func zeroUsedCount() throws {
    // `init(colors:)` promises `usedCount` in `1...capacity`; a palette
    // with no used slots renders nothing and matches nothing.
    #expect(
      PaletteCorpus.decodeError([
        "colors": [PaletteCorpus.color(0, 0, 0, 0)],
        "usedCount": 0,
      ]) == .invalidPaletteUsedCount(found: 0, available: 1)
    )
  }

  @Test("an empty colors array is rejected rather than silently substituted")
  func emptyColors() throws {
    // `init(colors:)` would substitute a single transparent slot, which
    // discards the author's palette instead of reporting a damaged file.
    #expect(
      PaletteCorpus.decodeError(["colors": [] as [Any], "usedCount": 0]) == .emptyPalette
    )
  }
}

/// JSON surgery for ``ColorPaletteDecodingTests``.
private enum PaletteCorpus {
  static func color(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> [String: Any] {
    ["red": r, "green": g, "blue": b, "alpha": a]
  }

  static func decode(_ object: [String: Any]) throws -> ColorPalette {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try JSONDecoder().decode(ColorPalette.self, from: data)
  }

  /// Decodes `object`, expecting a rejection. Records an issue and returns
  /// `nil` when it decodes instead, so a case that stops being malformed
  /// fails loudly rather than asserting against `nil`.
  static func decodeError(
    _ object: [String: Any],
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ProjectDecodeError? {
    do {
      _ = try decode(object)
      Issue.record(
        "expected a ProjectDecodeError, but the palette decoded successfully",
        sourceLocation: sourceLocation
      )
      return nil
    } catch let error as ProjectDecodeError {
      return error
    } catch {
      Issue.record("expected a ProjectDecodeError, got \(error)", sourceLocation: sourceLocation)
      return nil
    }
  }
}

// MARK: - Corpus construction

/// Builds malformed files by taking a *valid* encode apart and damaging
/// one thing, so each case differs from a good file in exactly the way
/// its name says.
private enum Corpus {

  /// 4x3, two frames, two layers each, painting palette slot 200 — high
  /// enough that a short decoded palette would trap on it.
  static func subject() -> GIFDocument {
    let size = PixelSize(width: 4, height: 3)
    var painted = PixelBuffer(size: size)
    painted[PixelPoint(x: 1, y: 1)] = 200
    painted[PixelPoint(x: 2, y: 0)] = 1

    let frames = (0..<2).map { frameIndex in
      EditorFrame(
        layers: [
          EditorLayer(name: "Base \(frameIndex)", pixels: painted),
          EditorLayer(name: "Top \(frameIndex)", isVisible: false, pixels: PixelBuffer(size: size)),
        ],
        delayCentiseconds: 8 + frameIndex,
        disposal: .keep
      )
    }
    return GIFDocument(size: size, frames: frames, loopCount: 2)
  }

  static func validEnvelope() throws -> [String: Any] {
    let data = try ProjectFile.data(for: subject())
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ShapeError(detail: "encoded project was not a JSON object")
    }
    return object
  }

  static func serialize(_ envelope: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
  }

  static func mutatingDocument(
    _ envelope: [String: Any],
    _ transform: (inout [String: Any]) -> Void
  ) throws -> [String: Any] {
    var envelope = envelope
    guard var document = envelope["document"] as? [String: Any] else {
      throw ShapeError(detail: "envelope has no document object")
    }
    transform(&document)
    envelope["document"] = document
    return envelope
  }

  static func mutatingFirstLayerPixels(
    _ envelope: [String: Any],
    _ transform: (inout [String: Any]) -> Void
  ) throws -> [String: Any] {
    var thrown: ShapeError?
    let result = try mutatingDocument(envelope) { document in
      guard
        var frames = document["frames"] as? [[String: Any]], !frames.isEmpty,
        var layers = frames[0]["layers"] as? [[String: Any]], !layers.isEmpty,
        var pixels = layers[0]["pixels"] as? [String: Any]
      else {
        thrown = ShapeError(detail: "document has no first-layer pixel object")
        return
      }
      transform(&pixels)
      layers[0]["pixels"] = pixels
      frames[0]["layers"] = layers
      document["frames"] = frames
    }
    if let thrown { throw thrown }
    return result
  }

  /// Decodes `data`, expecting a rejection. Returns `nil` (and records
  /// an issue) when decoding succeeds or throws something else, so a
  /// case that stops being malformed fails loudly instead of quietly
  /// asserting against `nil`.
  static func decodeError(
    _ data: Data,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> ProjectDecodeError? {
    do {
      _ = try ProjectFile.document(from: data)
      Issue.record(
        "expected a ProjectDecodeError, but the file decoded successfully",
        sourceLocation: sourceLocation
      )
      return nil
    } catch let error as ProjectDecodeError {
      return error
    } catch {
      Issue.record("expected a ProjectDecodeError, got \(error)", sourceLocation: sourceLocation)
      return nil
    }
  }

  struct ShapeError: Error {
    let detail: String
  }
}
