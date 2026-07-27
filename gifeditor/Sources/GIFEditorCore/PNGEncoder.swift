import Foundation

/// A dependency-free PNG writer for straight-alpha 8-bit RGBA images.
///
/// PNG carries its pixel data in `IDAT` as a *zlib* stream, and zlib
/// permits **stored** — literally uncompressed — deflate blocks. A
/// conformant PNG can therefore be written with no compressor at all: a
/// two-byte zlib header, the filtered scanlines chopped into 64 KiB
/// stored blocks, an Adler-32 over the *uncompressed* bytes, and a CRC-32
/// per chunk.
///
/// That is the whole trade this type makes. A stored-block PNG costs
/// roughly 1.01–1.05x the raw raster (5 bytes per 64 KiB block, one
/// filter byte per scanline, ~60 bytes of chunk framing) where a real
/// deflate of the same pixel-art raster would land far below 1x. For a
/// spritesheet handed to a game-dev pipeline that difference is
/// uninteresting, and it buys the package staying dependency-free: no
/// zlib linkage, no vendored inflate/deflate, nothing to keep in sync
/// with a platform's system library. Add a real compressor from measured
/// need — the seam for it is ``StoredDeflate/zlibStream(for:)``, which is
/// the only thing that would have to change.
///
/// What is *not* negotiable is getting the framing right. A subtly wrong
/// length/complement pair or a checksum over the wrong span produces a
/// file some decoders accept and others reject, so every artifact this
/// writer produces is asserted against an external decoder in the tests
/// rather than against this module's own reader.
public enum PNGEncoder {
  /// The eight-byte PNG signature. The high bit in the first byte and the
  /// CRLF/LF pair exist so a file mangled by a text-mode transfer fails
  /// the signature check instead of decoding to garbage.
  public static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

  /// Encodes one composited frame's colors, where `nil` is transparent.
  ///
  /// `colors` is the array ``GIFDocument/flattenedColors(frameIndex:)``
  /// returns, so the export path and the renderer consume the document
  /// through the same seam.
  public static func encode(colors: [EditorColor?], size: PixelSize) -> [UInt8] {
    encode(rgba: PNGRaster.rgbaBytes(colors: colors, size: size), size: size)
  }

  /// Encodes straight-alpha RGBA8 bytes, four per pixel, row-major.
  public static func encode(rgba: [UInt8], size: PixelSize) -> [UInt8] {
    precondition(
      rgba.count == size.area * 4,
      "RGBA byte count must be four per pixel"
    )
    var bytes = signature
    bytes.reserveCapacity(rgba.count + size.height + 80)
    bytes += PNGChunk.bytes(type: "IHDR", payload: PNGChunk.ihdrPayload(size: size))
    bytes += PNGChunk.bytes(
      type: "IDAT",
      payload: StoredDeflate.zlibStream(for: PNGRaster.filteredScanlines(rgba: rgba, size: size))
    )
    bytes += PNGChunk.bytes(type: "IEND", payload: [])
    return bytes
  }

  /// Encodes a single document frame as a still PNG.
  public static func encode(document: GIFDocument, frameIndex: Int) -> [UInt8] {
    precondition(document.frames.indices.contains(frameIndex), "frame index out of range")
    return encode(
      colors: document.flattenedColors(frameIndex: frameIndex),
      size: document.size
    )
  }
}

// MARK: - Raster

/// Turns composited colors into the two byte layouts PNG cares about:
/// the flat RGBA raster, and that raster with a filter-type byte in front
/// of every scanline.
enum PNGRaster {
  /// Straight-alpha RGBA8, four bytes per pixel, row-major.
  ///
  /// A `nil` pixel writes `(0, 0, 0, 0)`. It could carry any RGB — the
  /// alpha byte is what makes it transparent — but zeroing all four keeps
  /// the raster byte-stable, which is what lets the golden-ish tests
  /// compare whole rasters rather than "every pixel except the invisible
  /// ones".
  static func rgbaBytes(colors: [EditorColor?], size: PixelSize) -> [UInt8] {
    precondition(colors.count == size.area, "color count must match the canvas size")
    var bytes = [UInt8](repeating: 0, count: size.area * 4)
    for (offset, color) in colors.enumerated() {
      guard let color, color.alpha > 0 else { continue }
      let base = offset * 4
      bytes[base] = color.red
      bytes[base + 1] = color.green
      bytes[base + 2] = color.blue
      bytes[base + 3] = color.alpha
    }
    return bytes
  }

  /// Prefixes every scanline with filter type 0 (`None`).
  ///
  /// PNG's other four filters (Sub/Up/Average/Paeth) exist to make the
  /// row more compressible; with a stored-block IDAT there is nothing
  /// downstream to exploit them, so they would cost a pass over the
  /// raster and buy exactly nothing. The filter *byte* is still
  /// mandatory — one per row, not one per image — and forgetting it
  /// shifts every scanline by one byte, which is the classic way a
  /// hand-rolled PNG comes out looking sheared.
  static func filteredScanlines(rgba: [UInt8], size: PixelSize) -> [UInt8] {
    let stride = size.width * 4
    var raster = [UInt8]()
    raster.reserveCapacity(rgba.count + size.height)
    for row in 0..<size.height {
      raster.append(0)
      let start = row * stride
      raster.append(contentsOf: rgba[start..<(start + stride)])
    }
    return raster
  }
}

// MARK: - Chunks

/// The chunk layer: `length | type | data | CRC`, shared by the still
/// writer and the APNG writer so both spell the framing exactly once.
enum PNGChunk {
  /// Serializes one chunk.
  ///
  /// The CRC covers the type bytes *and* the data, but never the length
  /// field — the single most common way a hand-written PNG comes out
  /// unreadable in half the decoders that see it.
  static func bytes(type: String, payload: [UInt8]) -> [UInt8] {
    let typeBytes = Array(type.utf8)
    precondition(typeBytes.count == 4, "PNG chunk types are four ASCII bytes")

    var chunk = [UInt8]()
    chunk.reserveCapacity(payload.count + 12)
    chunk.appendBigEndian(UInt32(payload.count))
    chunk += typeBytes
    chunk += payload

    var crc = PNGCRC32()
    crc.update(typeBytes)
    crc.update(payload)
    chunk.appendBigEndian(crc.checksum)
    return chunk
  }

  /// The image header: dimensions, then the five bytes that pin the
  /// pixel format. Color type 6 is truecolor-with-alpha, which is the
  /// only format this writer emits — an indexed (`PLTE`) PNG would be
  /// smaller for pixel art, but it would also need its own transparency
  /// chunk and its own palette-order contract, and the export targets
  /// here (spritesheet, APNG) all want straight RGBA anyway.
  static func ihdrPayload(size: PixelSize) -> [UInt8] {
    var payload = [UInt8]()
    payload.reserveCapacity(13)
    payload.appendBigEndian(UInt32(size.width))
    payload.appendBigEndian(UInt32(size.height))
    payload.append(8)  // bit depth
    payload.append(6)  // color type: truecolor + alpha
    payload.append(0)  // compression method: deflate
    payload.append(0)  // filter method: adaptive, one type byte per scanline
    payload.append(0)  // interlace method: none
    return payload
  }
}

// MARK: - Compression

/// A zlib stream built entirely from stored (uncompressed) deflate
/// blocks.
///
/// The three things that have to be exactly right, and what each is:
///
/// - **Header.** `0x78 0x01`: compression method 8 (deflate) with a 32 KiB
///   window in the low byte, and a check byte chosen so the two bytes read
///   as a big-endian 16-bit value are a multiple of 31 with no preset
///   dictionary. `0x7801` is 30721, which is 31 x 991.
/// - **Block framing.** Each block opens with one byte — bit 0 is
///   `BFINAL`, bits 1–2 are `BTYPE` (`00` = stored) — after which a stored
///   block skips to the next byte boundary. Everything here is written a
///   whole byte at a time, so that boundary is already met. Then `LEN` and
///   its one's complement `NLEN`, both little-endian, then `LEN` raw
///   bytes. `LEN` is 16 bits, hence the 65535-byte ceiling and the loop.
/// - **Adler-32.** Computed over the *uncompressed* data and written
///   big-endian, unlike everything else in the block framing. Checksumming
///   the framed output instead is a mistake no decoder will tell you
///   about beyond "corrupt stream".
enum StoredDeflate {
  /// The largest payload a single stored block can carry: `LEN` is a
  /// 16-bit field.
  static let maximumBlockLength = 65_535

  static func zlibStream(for raw: [UInt8]) -> [UInt8] {
    var stream: [UInt8] = [0x78, 0x01]
    stream.reserveCapacity(raw.count + (raw.count / maximumBlockLength + 1) * 5 + 6)

    var offset = 0
    // `repeat` rather than `while`: an empty payload still owes the
    // stream one final, empty stored block, or the decoder reaches the
    // Adler-32 while still waiting for a block header.
    repeat {
      let length = min(maximumBlockLength, raw.count - offset)
      let isFinal = offset + length >= raw.count
      stream.append(isFinal ? 0x01 : 0x00)
      let len = UInt16(length)
      stream.appendLittleEndian(len)
      stream.appendLittleEndian(~len)
      stream.append(contentsOf: raw[offset..<(offset + length)])
      offset += length
    } while offset < raw.count

    stream.appendBigEndian(PNGChecksum.adler32(raw))
    return stream
  }
}

// MARK: - Checksums

/// Both checksums a PNG needs, spelled out because the package takes no
/// dependencies. They are different algorithms with different framing and
/// are easy to transpose: CRC-32 guards each *chunk* and is written
/// big-endian after the chunk data; Adler-32 guards the *uncompressed*
/// bytes of a zlib stream and is written big-endian after the last block.
enum PNGChecksum {
  /// CRC-32 (ISO 3309 / ITU-T V.42) as PNG specifies: reflected input and
  /// output, polynomial `0xEDB88320`, pre- and post-inverted.
  static func crc32(_ bytes: some Sequence<UInt8>) -> UInt32 {
    var crc = PNGCRC32()
    crc.update(bytes)
    return crc.checksum
  }

  /// Adler-32 (RFC 1950): `b << 16 | a`, where `a` is 1 plus the sum of
  /// the bytes and `b` is the running sum of `a`, both modulo 65521.
  ///
  /// The modulo is deferred for 5552 bytes at a time — zlib's `NMAX`, the
  /// largest run for which the unreduced accumulators provably stay
  /// inside 32 bits — so the inner loop is two adds and no division.
  static func adler32(_ bytes: [UInt8]) -> UInt32 {
    let base: UInt32 = 65_521
    let nmax = 5_552
    var a: UInt32 = 1
    var b: UInt32 = 0
    var offset = 0
    while offset < bytes.count {
      let end = min(offset + nmax, bytes.count)
      for index in offset..<end {
        a &+= UInt32(bytes[index])
        b &+= a
      }
      a %= base
      b %= base
      offset = end
    }
    return (b << 16) | a
  }
}

/// Running CRC-32, so a chunk's type and its (possibly multi-megabyte)
/// payload can be fed in without first materializing a joined copy.
struct PNGCRC32 {
  private var state: UInt32 = 0xFFFF_FFFF

  mutating func update(_ bytes: some Sequence<UInt8>) {
    var state = self.state
    for byte in bytes {
      state = Self.table[Int((state ^ UInt32(byte)) & 0xFF)] ^ (state >> 8)
    }
    self.state = state
  }

  var checksum: UInt32 { state ^ 0xFFFF_FFFF }

  private static let table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }
}

// MARK: - Byte writing

extension Array where Element == UInt8 {
  /// PNG writes every multi-byte integer big-endian. Deflate's `LEN` /
  /// `NLEN` pair is the one exception, which is why both spellings exist
  /// here rather than one being assumed.
  mutating func appendBigEndian(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value >> 24))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func appendBigEndian(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func appendLittleEndian(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value))
    append(UInt8(truncatingIfNeeded: value >> 8))
  }
}
