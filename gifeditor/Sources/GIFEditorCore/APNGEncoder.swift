import Foundation

/// Writes an animated PNG from a document, reusing ``PNGEncoder``'s chunk
/// layer verbatim.
///
/// APNG is a still PNG that a non-supporting decoder can still open: the
/// animation lives in three ancillary chunks — `acTL` (how many frames,
/// how many plays), `fcTL` (one per frame: geometry, delay, disposal),
/// and `fdAT` (every frame's pixels *except* the first). Frame zero's
/// pixels are the plain `IDAT`, so a decoder that ignores all three
/// chunks shows the first frame as an ordinary image rather than failing.
///
/// Two shape decisions, both taken because this encoder's input is a
/// *pre-composited* document:
///
/// - **Every frame is written full-canvas**, at offset `(0, 0)` and the
///   full document size. `GIFDocument.flattenedColors(frameIndex:)`
///   already flattens layers into a complete canvas, so there is no
///   changed-rect to exploit here. (Computing one is P1.5's job for GIF,
///   and if it lands, this encoder can consume the same rects.)
/// - **`dispose_op` is `NONE` and `blend_op` is `SOURCE` on every
///   frame.** `SOURCE` means "overwrite the output buffer, alpha
///   included", so a full-canvas frame fully replaces what came before
///   and no disposal is needed to make the next frame correct. Carrying
///   ``EditorFrame/disposal`` through would be writing metadata whose
///   semantics nothing here exercises — it would be inert under
///   full-canvas `SOURCE` frames, and inert-but-authoritative-looking
///   metadata is how decoders end up disagreeing. GIF export remains the
///   place disposal means something.
public enum APNGEncoder {
  /// `dispose_op` / `blend_op` values from the APNG specification. Named
  /// rather than inlined so the two bytes at the end of every `fcTL` are
  /// readable at the call site.
  private enum FrameControl {
    /// Leave the output buffer alone after this frame.
    static let disposeNone: UInt8 = 0
    /// Overwrite the frame's rect, alpha included, rather than compositing
    /// over it.
    static let blendSource: UInt8 = 0
  }

  /// APNG expresses a delay as the exact fraction `delay_num /
  /// delay_den` seconds. ``EditorFrame/delayCentiseconds`` is already
  /// hundredths of a second, so a denominator of 100 makes the numerator
  /// the centisecond count itself — the mapping is an identity, not a
  /// rounding. Writing milliseconds against a denominator of 1000 would
  /// be equally exact but would invent a precision the document does not
  /// have; converting to APNG's other common denominator (1/60 s) would
  /// not be exact at all.
  public static let delayDenominator: UInt16 = 100

  /// Encodes a document as APNG bytes.
  ///
  /// `flattenedColors[i]` is the result of
  /// `document.flattenedColors(frameIndex: i)`, passed in by callers that
  /// already hold composited frames (the editor memoizes them) so they
  /// don't pay to composite twice. This mirrors
  /// ``GIFEncoder/encode(document:flattenedFrames:)``, which takes the
  /// same escape hatch one layer lower — as `[PixelBuffer]`, because the
  /// GIF path wants palette indices where PNG wants resolved colors.
  public static func encode(
    document: GIFDocument,
    flattenedColors: [[EditorColor?]]? = nil
  ) -> [UInt8] {
    let frames =
      flattenedColors
      ?? (0..<document.frames.count).map { document.flattenedColors(frameIndex: $0) }
    precondition(frames.count == document.frames.count, "one color plane per frame")

    let size = document.size
    var bytes = PNGEncoder.signature
    bytes += PNGChunk.bytes(type: "IHDR", payload: PNGChunk.ihdrPayload(size: size))
    bytes += PNGChunk.bytes(
      type: "acTL",
      payload: actlPayload(frameCount: frames.count, loopCount: document.loopCount)
    )

    // One counter shared by every `fcTL` and every `fdAT`, starting at
    // zero and incrementing by one per chunk. A decoder uses it to
    // detect a stream that has been reordered or had a chunk dropped, so
    // a gap or a repeat is a hard error rather than a hint.
    var sequenceNumber: UInt32 = 0

    for (frameIndex, colors) in frames.enumerated() {
      bytes += PNGChunk.bytes(
        type: "fcTL",
        payload: fctlPayload(
          sequenceNumber: sequenceNumber,
          size: size,
          delayCentiseconds: document.frames[frameIndex].delayCentiseconds
        )
      )
      sequenceNumber += 1

      let stream = StoredDeflate.zlibStream(
        for: PNGRaster.filteredScanlines(
          rgba: PNGRaster.rgbaBytes(colors: colors, size: size),
          size: size
        )
      )

      if frameIndex == 0 {
        // Frame zero is the default image: its pixels go in `IDAT`, and
        // `IDAT` carries no sequence number.
        bytes += PNGChunk.bytes(type: "IDAT", payload: stream)
      } else {
        var payload = [UInt8]()
        payload.reserveCapacity(stream.count + 4)
        payload.appendBigEndian(sequenceNumber)
        payload += stream
        bytes += PNGChunk.bytes(type: "fdAT", payload: payload)
        sequenceNumber += 1
      }
    }

    bytes += PNGChunk.bytes(type: "IEND", payload: [])
    return bytes
  }

  /// `acTL`: frame count and play count. It must precede the first
  /// `IDAT` — a decoder that meets `IDAT` first has already committed to
  /// reading a still image.
  ///
  /// `num_plays` of zero means "loop forever", which is the same
  /// convention ``GIFDocument/loopCount`` uses, so the field passes
  /// straight through.
  private static func actlPayload(frameCount: Int, loopCount: Int) -> [UInt8] {
    var payload = [UInt8]()
    payload.reserveCapacity(8)
    payload.appendBigEndian(UInt32(frameCount))
    payload.appendBigEndian(UInt32(clamping: loopCount))
    return payload
  }

  /// `fcTL`: 26 bytes describing where a frame paints, for how long, and
  /// what happens to the buffer afterwards.
  private static func fctlPayload(
    sequenceNumber: UInt32,
    size: PixelSize,
    delayCentiseconds: Int
  ) -> [UInt8] {
    var payload = [UInt8]()
    payload.reserveCapacity(26)
    payload.appendBigEndian(sequenceNumber)
    payload.appendBigEndian(UInt32(size.width))
    payload.appendBigEndian(UInt32(size.height))
    payload.appendBigEndian(UInt32(0))  // x_offset
    payload.appendBigEndian(UInt32(0))  // y_offset
    // Clamped, not rejected, matching how `EditorFrame` treats a delay:
    // a 655-second frame is a nonsense animation, not a damaged file.
    payload.appendBigEndian(UInt16(clamping: delayCentiseconds))
    payload.appendBigEndian(delayDenominator)
    payload.append(FrameControl.disposeNone)
    payload.append(FrameControl.blendSource)
    return payload
  }
}
