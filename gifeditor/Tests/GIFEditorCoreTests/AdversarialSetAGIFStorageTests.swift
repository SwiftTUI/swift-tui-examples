import EditorGIF
import Foundation
import Testing

@testable import GIFEditorCore

/// Campaign two E1 pass 2: gifeditor storage, PNG/APNG and recovery
/// contracts (e1s163–e1s183).
///
/// Chunk and checksum oracles are written here from the PNG/APNG and RFC
/// 1950/1951 texts rather than read back through this module. File cases
/// use throwaway directories removed on every exit path.
@Suite("Campaign E1 pass 2 GIF storage contracts", .serialized)
struct AdversarialSetAGIFStorageTests {
  @Test(arguments: Array(163...183))
  func storage(id: Int) throws {
    switch id {
    case 163...165: try e1Oversize(id)
    case 166...169: try e1APNG(id)
    case 170, 171: e1Deflate(id)
    case 172...174: try e1Recents(id)
    case 175, 182: try e1ProjectPlanes(id)
    case 176, 177: e1Sniff(id)
    case 178...181: try e1Autosave(id)
    default: e1EmptyFrames()
    }
  }
}

// MARK: - oversized imports (e1s163–e1s165)

private func e1Oversize(_ id: Int) throws {
  let width =
    id == 165 ? ProjectFile.maximumCanvasDimension : ProjectFile.maximumCanvasDimension + 1
  let size = PixelSize(width: width, height: 1)
  let palette = ColorPalette(colors: [
    .transparent, .init(rgbHex: 0xFF0000), .init(rgbHex: 0x0000FF),
  ])
  let pixels = (0..<width).map { PaletteIndex($0 % 2 + 1) }
  let source = GIFDocument(
    size: size, palette: palette,
    frames: [
      EditorFrame(layers: [EditorLayer(name: "E1", pixels: PixelBuffer(size: size, pixels: pixels))]
      )
    ])
  let gif = Data(try GIFEncoder.encode(document: source))
  // The app opens the GIF (KEYBINDINGS.md:218-219) and can serialize it.
  let opened = try DocumentIngestion.ingest(gif).document
  #expect(opened.size == size)
  let project = try ProjectFile.data(for: opened)
  if id == 164 {
    try e1WithDirectory { directory in
      let target = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try AutosaveStore.snapshot(
        document: opened, originalPath: nil, to: target, at: Date(timeIntervalSince1970: 1))
      e1Known(e1OversizeComment) {
        let recovered = try AutosaveStore.recover(from: target)
        #expect(recovered?.document == opened)
      }
    }
    return
  }
  if id == 165 {
    #expect(try DocumentIngestion.ingest(project).document == opened)
  } else {
    e1Known(e1OversizeComment) {
      let reopened = try DocumentIngestion.ingest(project).document
      #expect(reopened == opened)
    }
  }
}

private let e1OversizeComment: Comment =
  "NEW-27: a document opened from a GIF wider than 16384 pixels saves and autosaves to files this build refuses to reopen; GIFLoader admits any GIF canvas while PixelSize decoding enforces ProjectFile's 16384/2^24 limits; contract: ProjectFile.swift:99-106 and :161-178 (lossless project), AutosaveStore.swift:76-77 (lossless recovery), KEYBINDINGS.md:218-219; adjacent STUI-845"

// MARK: - APNG (e1s166–e1s169)

private func e1APNG(_ id: Int) throws {
  let size = PixelSize(width: 2, height: 1)
  let palette = ColorPalette(colors: [.transparent, .init(rgbHex: 0x00FF00)])
  let frameCount = id == 168 ? 3 : id == 169 ? 2 : 1
  var document = GIFDocument(
    size: size, palette: palette,
    frames: (0..<frameCount).map { index in
      EditorFrame(
        layers: [
          EditorLayer(
            name: "E1", pixels: PixelBuffer(size: size, pixels: [1, index % 2 == 0 ? nil : 1]))
        ])
    })
  if id == 166 { document.loopCount = 2_147_483_648 }
  if id == 167 { document.frames[0].delayCentiseconds = 70_000 }
  let chunks = try e1Chunks(APNGEncoder.encode(document: document))
  switch id {
  case 166:
    let actl = try #require(chunks.first { $0.type == "acTL" })
    let plays = e1UInt32(actl.data, at: 4)
    e1Known(
      "NEW-28: an APNG play count above 2^31-1 is written into acTL num_plays; actlPayload clamps only to UInt32; contract: PNG Third Edition 7.1 (four-byte unsigned integers are limited to 2^31-1)"
    ) {
      #expect(plays <= 2_147_483_647)
    }
  case 167:
    let fctl = try #require(chunks.first { $0.type == "fcTL" })
    #expect(fctl.data.count == 26)
    #expect(Int(fctl.data[20]) << 8 | Int(fctl.data[21]) == 65_535)
    #expect(Int(fctl.data[22]) << 8 | Int(fctl.data[23]) == 100)
  case 168:
    let sequence = chunks.filter { $0.type == "fcTL" || $0.type == "fdAT" }.map {
      e1UInt32($0.data, at: 0)
    }
    #expect(sequence == [0, 1, 2, 3, 4])
  default:
    #expect(chunks.map(\.type) == ["IHDR", "acTL", "fcTL", "IDAT", "fcTL", "fdAT", "IEND"])
  }
}

private struct E1Chunk {
  var type: String
  var data: [UInt8]
}

/// Walks the chunk layer of a PNG stream (PNG Third Edition 5.3), checking
/// each chunk's CRC with an independent bitwise CRC-32.
private func e1Chunks(_ bytes: [UInt8]) throws -> [E1Chunk] {
  try #require(Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  var chunks: [E1Chunk] = []
  var offset = 8
  while offset + 12 <= bytes.count {
    let length = Int(e1UInt32(bytes, at: offset))
    try #require(offset + 12 + length <= bytes.count)
    let typeAndData = Array(bytes[(offset + 4)..<(offset + 8 + length)])
    #expect(e1UInt32(bytes, at: offset + 8 + length) == e1BitwiseCRC32(typeAndData))
    chunks.append(
      E1Chunk(
        type: String(decoding: typeAndData.prefix(4), as: UTF8.self),
        data: Array(typeAndData.dropFirst(4))))
    offset += 12 + length
  }
  #expect(offset == bytes.count)
  return chunks
}

private func e1UInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
  (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
}

private func e1BitwiseCRC32(_ bytes: [UInt8]) -> UInt32 {
  var crc: UInt32 = 0xFFFF_FFFF
  for byte in bytes {
    crc ^= UInt32(byte)
    for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
  }
  return crc ^ 0xFFFF_FFFF
}

// MARK: - zlib framing (e1s170, e1s171)

private func e1Deflate(_ id: Int) {
  if id == 170 {
    for count in [5_552, 5_553, 11_104, 11_105] {
      let bytes = [UInt8](repeating: 0xFF, count: count)
      var a: UInt32 = 1
      var b: UInt32 = 0
      for byte in bytes {
        a = (a + UInt32(byte)) % 65_521
        b = (b + a) % 65_521
      }
      #expect(PNGChecksum.adler32(bytes) == (b << 16) | a, "count \(count)")
    }
    return
  }
  let raw = [UInt8](repeating: 7, count: StoredDeflate.maximumBlockLength)
  let stream = StoredDeflate.zlibStream(for: raw)
  #expect(stream.count == 2 + 5 + raw.count + 4)
  #expect(Array(stream[2..<7]) == [0x01, 0xFF, 0xFF, 0x00, 0x00])
}

// MARK: - recents (e1s172–e1s174)

private func e1Recents(_ id: Int) throws {
  try e1WithDirectory { directory in
    let state = directory.appendingPathComponent(RecentDocuments.defaultFileName)
    switch id {
    case 172:
      let urls = (1...15).map { directory.appendingPathComponent("\($0).halfcell") }
      try RecentDocuments(urls: urls, limit: 15).write(to: state)
      let loaded = RecentDocuments.load(from: state, limit: 20, pruningMissingFiles: false)
      #expect(loaded.limit == 20)
      e1Known(e1RecentsComment) {
        #expect(loaded.count == 15)
      }
    case 173:
      let urls = (1...12).map { directory.appendingPathComponent("\($0).halfcell") }
      for url in urls.dropFirst(3) { try Data("x".utf8).write(to: url) }
      try RecentDocuments(urls: urls, limit: 12).write(to: state)
      let loaded = RecentDocuments.load(from: state)
      e1Known(e1RecentsComment) {
        #expect(loaded.urls.map(\.lastPathComponent) == (4...12).map { "\($0).halfcell" })
      }
    default:
      let composed = directory.appendingPathComponent("\u{E9}.halfcell")
      let decomposed = directory.appendingPathComponent("e\u{301}.halfcell")
      try Data("1".utf8).write(to: composed)
      try Data("2".utf8).write(to: decomposed)
      // Oracle from the filesystem: one file (APFS) or two (byte names)?
      let distinct = try FileManager.default.contentsOfDirectory(atPath: directory.path).count
      try #require(distinct == 1 || distinct == 2)
      let recents = RecentDocuments().inserting(composed).inserting(decomposed)
      if distinct == 1 {
        #expect(recents.count == 1)
      } else {
        e1Known(
          "NEW-30: two distinct NFC/NFD-named documents collapse into one recents entry; de-duplication keys on Swift String equality, which is canonical equivalence; contract: RecentDocuments.swift:40 (every distinct document once), POSIX filenames are byte strings"
        ) {
          #expect(recents.count == 2)
        }
      }
    }
  }
}

private let e1RecentsComment: Comment =
  "NEW-29: loading recents keeps at most ten entries before the caller's limit and pruning apply; RecentDocuments.init(from:) re-runs the initializer with defaultLimit; contract: RecentDocuments.swift:98-108 and :121-127 (caller's cap and pruning apply to what the file held)"

// MARK: - project planes and palettes (e1s175, e1s182)

private func e1ProjectPlanes(_ id: Int) throws {
  let size = PixelSize(width: 3, height: 1)
  let document = GIFDocument(
    size: size, palette: ColorPalette(colors: [.transparent, .white]),
    frames: [
      EditorFrame(layers: [
        EditorLayer(name: "E1", pixels: PixelBuffer(size: size, pixels: [1, nil, 1]))
      ])
    ])
  var envelope = try #require(
    JSONSerialization.jsonObject(with: ProjectFile.data(for: document)) as? [String: Any])
  var body = try #require(envelope["document"] as? [String: Any])
  if id == 175 {
    body["palette"] = (0..<300).map { index in
      ["red": index % 256, "green": index / 256, "blue": 7, "alpha": 255]
    }
  } else {
    var frames = try #require(body["frames"] as? [[String: Any]])
    var layers = try #require(frames[0]["layers"] as? [[String: Any]])
    var pixels = try #require(layers[0]["pixels"] as? [String: Any])
    pixels["opaqueMask"] = Data([0xFF]).base64EncodedString()  // bits 3-7 name no pixel
    layers[0]["pixels"] = pixels
    frames[0]["layers"] = layers
    body["frames"] = frames
  }
  envelope["document"] = body
  let bytes = try JSONSerialization.data(withJSONObject: envelope)
  if id == 182 {
    let decoded = try ProjectFile.document(from: bytes)
    #expect(decoded.frames[0].layers[0].pixels.pixels.allSatisfy { $0 != nil })
    return
  }
  e1Known(
    "NEW-31: a project palette of more than 256 colors opens silently truncated to 256; GIFDocument.init(from:) routes the colors through ColorPalette(colors:), which keeps the first 256; contract: ProjectFile.swift:16-19 and :43-46 (malformed projects throw; palettes are never silently discarded)"
  ) {
    #expect(throws: ProjectDecodeError.self) { try ProjectFile.document(from: bytes) }
  }
}

// MARK: - format sniffing (e1s176, e1s177)

private func e1Sniff(_ id: Int) {
  if id == 176 {
    // Probe: RFC 8259 8.1 lets a parser ignore a BOM but does not require it.
    let project = Data([0xEF, 0xBB, 0xBF]) + Data("{\"formatVersion\":1}".utf8)
    #expect(DocumentIngestion.kind(of: project) == nil)
    return
  }
  #expect(
    DocumentIngestion.kind(of: Data((String(repeating: " ", count: 63) + "{").utf8)) == .project)
  #expect(DocumentIngestion.kind(of: Data((String(repeating: " ", count: 64) + "{").utf8)) == nil)
}

// MARK: - autosave classification (e1s178–e1s181)

private func e1Autosave(_ id: Int) throws {
  try e1WithDirectory { directory in
    let target = directory.appendingPathComponent(AutosaveStore.defaultFileName)
    switch id {
    case 178:
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
      #expect(e1RecoveryError(target).map(e1Unreadable) == true)
    case 179:
      try Data().write(to: target)
      #expect(e1RecoveryError(target).map(e1DamagedSnapshot) == true)
    case 180:
      try Data("{\"snapshotVersion\":\"1\"}".utf8).write(to: target)
      #expect(e1RecoveryError(target).map(e1DamagedSnapshot) == true)
    default:
      let size = PixelSize(width: 2, height: 1)
      let document = GIFDocument(
        size: size, palette: ColorPalette(colors: [.transparent, .white]),
        frames: [
          EditorFrame(layers: [
            EditorLayer(name: "E1", pixels: PixelBuffer(size: size, pixels: [1, 1]))
          ])
        ])
      try AutosaveStore.snapshot(
        document: document, originalPath: nil, to: target, at: Date(timeIntervalSince1970: 1))
      var envelope = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any])
      var project = try #require(envelope["project"] as? [String: Any])
      var body = try #require(project["document"] as? [String: Any])
      var frames = try #require(body["frames"] as? [[String: Any]])
      var layers = try #require(frames[0]["layers"] as? [[String: Any]])
      layers[0]["pixels"] = [
        "size": ["width": 1, "height": 1], "indices": "AQ==", "opaqueMask": "AQ==",
      ]
      frames[0]["layers"] = layers
      body["frames"] = frames
      project["document"] = body
      envelope["project"] = project
      try JSONSerialization.data(withJSONObject: envelope).write(to: target)
      #expect(
        e1RecoveryError(target)
          == .damagedDocument(
            .layerSizeMismatch(canvas: size, layer: PixelSize(width: 1, height: 1))))
    }
  }
}

private func e1RecoveryError(_ url: URL) -> AutosaveError? {
  do {
    _ = try AutosaveStore.recover(from: url)
    Issue.record("recovery unexpectedly succeeded")
    return nil
  } catch let error as AutosaveError {
    return error
  } catch {
    Issue.record("unexpected error \(error)")
    return nil
  }
}

private func e1Unreadable(_ error: AutosaveError) -> Bool {
  if case .unreadable = error { true } else { false }
}

private func e1DamagedSnapshot(_ error: AutosaveError) -> Bool {
  if case .damagedSnapshot = error { true } else { false }
}

// MARK: - empty frames (e1s183)

private func e1EmptyFrames() {
  // GIF89a, 5x5 screen with a two-entry global table, one 0x0 image, trailer.
  let bytes: [UInt8] =
    Array("GIF89a".utf8) + [5, 0, 5, 0, 0x80, 0, 0] + [0, 0, 0, 255, 255, 255]
    + [0x2C, 0, 0, 0, 0, 0, 0, 0, 0, 0x00] + [0x02, 0x00] + [0x3B]
  // Corrected oracle (corrections.md, e1s183): the vendored decoder reports
  // the empty stream itself, as GIFLoaderError.decode, before the loader's
  // own `.empty` check; the contract is a reported error, not a trap.
  #expect(throws: GIFLoaderError.self) { try GIFLoader.load(data: Data(bytes)) }
}

// MARK: - fixtures

private func e1Known(_ comment: Comment, _ body: () throws -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_E1_UNMARKED"] == "1" {
    do { try body() } catch { Issue.record(error, comment) }
  } else {
    withKnownIssue(comment) { try body() }
  }
}

private func e1WithDirectory(_ body: (URL) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("e1-gif-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  try body(directory)
}
