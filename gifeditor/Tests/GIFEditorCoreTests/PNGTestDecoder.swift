import Foundation

@testable import GIFEditorCore

/// A small PNG reader that exists only inside the test target.
///
/// It is here so the *always-on* tier of the export tests can assert on
/// decoded pixels — cell placement on a spritesheet, per-frame rasters in
/// an APNG — on a machine with no image tooling installed, which is the
/// condition every CI lane runs under.
///
/// What it is **not**: a substitute for an independent decoder. It is
/// written against the same spec by the same author, so agreement between
/// it and ``PNGEncoder`` proves internal consistency and nothing about
/// conformance. Conformance is pinned by the checked-in goldens (bytes
/// that two unrelated decoders accepted when they were created) and, on a
/// machine that has the tools, by the external round-trips in
/// `ExportExternalDecoderTests`.
///
/// It is deliberately narrow: 8-bit RGBA, filter type 0, stored-block
/// zlib only. Anything else throws rather than guessing, because a
/// silently lenient reader would hide exactly the encoder bug it is
/// supposed to expose.
enum PNGTestDecoder {
  struct Image: Equatable {
    let size: PixelSize
    let rgba: [UInt8]
  }

  struct Unsupported: Error, CustomStringConvertible {
    let detail: String
    var description: String { "test decoder cannot read this PNG: \(detail)" }
  }

  /// Decodes a still image.
  static func decode(_ bytes: [UInt8]) throws -> Image {
    let frames = try decodeFrames(bytes)
    guard frames.count == 1 else {
      throw Unsupported(detail: "expected one image, found \(frames.count)")
    }
    return frames[0]
  }

  /// Decodes every frame: `IDAT` first, then one per `fdAT`.
  ///
  /// Frame geometry comes from `IHDR` rather than from each `fcTL`,
  /// because ``APNGEncoder`` writes every frame full-canvas at the
  /// origin. A test asserts that separately (`frameControlFields`), so
  /// this reader is allowed to assume it.
  static func decodeFrames(_ bytes: [UInt8]) throws -> [Image] {
    let chunks = try PNGChunkReader.chunks(in: bytes)
    guard let header = chunks.first, header.type == "IHDR" else {
      throw Unsupported(detail: "first chunk is not IHDR")
    }
    let width = Int(PNGChunkReader.uint32(header.payload, at: 0))
    let height = Int(PNGChunkReader.uint32(header.payload, at: 4))
    guard header.payload[8] == 8, header.payload[9] == 6 else {
      throw Unsupported(
        detail:
          "only 8-bit RGBA is supported, found depth \(header.payload[8]) type \(header.payload[9])"
      )
    }
    guard header.payload[12] == 0 else {
      throw Unsupported(detail: "interlaced PNGs are not supported")
    }
    let size = PixelSize(width: width, height: height)

    // PNG allows an image's compressed data to be split across several
    // consecutive IDATs; this writer emits one, and joining them anyway
    // costs nothing and removes an assumption.
    let idat = chunks.filter { $0.type == "IDAT" }.flatMap(\.payload)
    var streams = [idat]
    // An fdAT payload is a four-byte sequence number followed by that
    // frame's own complete zlib stream.
    for chunk in chunks where chunk.type == "fdAT" {
      guard chunk.payload.count > 4 else {
        throw Unsupported(detail: "fdAT chunk is too short to hold a sequence number")
      }
      streams.append(Array(chunk.payload.dropFirst(4)))
    }

    return try streams.map { stream in
      Image(size: size, rgba: try unfilter(StoredDeflateReader.inflate(stream), size: size))
    }
  }

  /// Strips the per-scanline filter byte, insisting it is type 0.
  ///
  /// Checking the byte rather than skipping it is the point: a writer
  /// that forgot to emit it produces a raster one byte short per row,
  /// which a lenient reader would happily render as a diagonal shear.
  private static func unfilter(_ raster: [UInt8], size: PixelSize) throws -> [UInt8] {
    let stride = size.width * 4
    guard raster.count == size.height * (stride + 1) else {
      throw Unsupported(
        detail: "raster is \(raster.count) bytes, expected \(size.height * (stride + 1))"
      )
    }
    var rgba = [UInt8]()
    rgba.reserveCapacity(size.area * 4)
    for row in 0..<size.height {
      let start = row * (stride + 1)
      guard raster[start] == 0 else {
        throw Unsupported(detail: "scanline \(row) uses filter type \(raster[start]), expected 0")
      }
      rgba.append(contentsOf: raster[(start + 1)..<(start + 1 + stride)])
    }
    return rgba
  }
}

/// Reads back a zlib stream made entirely of stored blocks.
///
/// Written from the RFC rather than derived from ``StoredDeflate``, and
/// strict about every field that writer has to get right: the header's
/// multiple-of-31 check, `NLEN` being `LEN`'s one's complement, exactly
/// one final block, and an Adler-32 that matches an independently
/// implemented checksum of the inflated bytes.
enum StoredDeflateReader {
  struct Malformed: Error, CustomStringConvertible {
    let detail: String
    var description: String { "not a valid stored-block zlib stream: \(detail)" }
  }

  static func inflate(_ stream: [UInt8]) throws -> [UInt8] {
    guard stream.count >= 6 else { throw Malformed(detail: "shorter than a header plus checksum") }
    let header = UInt32(stream[0]) << 8 | UInt32(stream[1])
    guard stream[0] & 0x0F == 8 else {
      throw Malformed(detail: "compression method is not deflate")
    }
    guard header % 31 == 0 else { throw Malformed(detail: "header check bits are wrong") }
    guard stream[1] & 0x20 == 0 else { throw Malformed(detail: "a preset dictionary is declared") }

    var raw = [UInt8]()
    var offset = 2
    var sawFinalBlock = false
    while !sawFinalBlock {
      guard offset + 5 <= stream.count else { throw Malformed(detail: "truncated block header") }
      let blockHeader = stream[offset]
      guard blockHeader & 0x06 == 0 else {
        throw Malformed(detail: "block type \((blockHeader & 0x06) >> 1) is not stored")
      }
      sawFinalBlock = blockHeader & 0x01 == 1
      let length = UInt16(stream[offset + 1]) | UInt16(stream[offset + 2]) << 8
      let complement = UInt16(stream[offset + 3]) | UInt16(stream[offset + 4]) << 8
      guard complement == ~length else {
        throw Malformed(detail: "NLEN is not the one's complement of LEN")
      }
      offset += 5
      let end = offset + Int(length)
      guard end <= stream.count else { throw Malformed(detail: "truncated block data") }
      raw.append(contentsOf: stream[offset..<end])
      offset = end
    }

    guard offset + 4 == stream.count else {
      throw Malformed(detail: "\(stream.count - offset) trailing bytes after the last block")
    }
    let stored =
      UInt32(stream[offset]) << 24 | UInt32(stream[offset + 1]) << 16
      | UInt32(stream[offset + 2]) << 8 | UInt32(stream[offset + 3])
    let computed = naiveAdler32(raw)
    guard stored == computed else {
      throw Malformed(
        detail: "Adler-32 is \(String(stored, radix: 16)), expected \(String(computed, radix: 16))"
      )
    }
    return raw
  }

  /// Adler-32 the slow, obvious way: reduce modulo 65521 after every
  /// byte, no deferred-modulo window.
  ///
  /// ``PNGChecksum/adler32(_:)`` defers the reduction for 5552 bytes at a
  /// time to keep the inner loop division-free, which is the part of it
  /// that could overflow or drift. Checking that fast version against
  /// this slow one is the whole reason this is spelled out separately
  /// instead of being called.
  static func naiveAdler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in bytes {
      a = (a + UInt32(byte)) % 65_521
      b = (b + a) % 65_521
    }
    return b << 16 | a
  }
}

/// A deliberately naive PNG chunk walker.
///
/// It reads only lengths and types — no CRC arithmetic — so it shares no
/// code with the writer it inspects. Validating the *bytes* is the
/// goldens' and the external decoders' job; this only reports what chunks
/// appear, in what order.
enum PNGChunkReader {
  struct Chunk {
    let type: String
    let payload: [UInt8]
    /// Offset of the first payload byte within the whole file.
    let payloadOffset: Int
  }

  struct MalformedFile: Error, CustomStringConvertible {
    let detail: String
    var description: String { "not a walkable PNG: \(detail)" }
  }

  static func chunks(in bytes: [UInt8]) throws -> [Chunk] {
    guard bytes.count > 8, Array(bytes.prefix(8)) == PNGEncoder.signature else {
      throw MalformedFile(detail: "missing signature")
    }
    var chunks: [Chunk] = []
    var offset = 8
    while offset + 8 <= bytes.count {
      let length = Int(uint32(bytes, at: offset))
      let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
      let payloadOffset = offset + 8
      guard payloadOffset + length + 4 <= bytes.count else {
        throw MalformedFile(detail: "chunk '\(type)' runs past the end of the file")
      }
      chunks.append(
        Chunk(
          type: type,
          payload: Array(bytes[payloadOffset..<(payloadOffset + length)]),
          payloadOffset: payloadOffset
        )
      )
      offset = payloadOffset + length + 4
    }
    guard offset == bytes.count else {
      throw MalformedFile(detail: "trailing bytes after the last chunk")
    }
    return chunks
  }

  static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
      | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
  }
}
