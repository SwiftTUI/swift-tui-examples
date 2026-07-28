import Foundation
import Testing

@testable import GIFEditorCore

@Suite("Autosave store")
struct AutosaveStoreTests {

  /// A fixed instant rather than `Date()`: the store takes its
  /// timestamp as an argument precisely so these assertions can be
  /// exact instead of "within a second or two of now".
  static let snapshotDate = Date(timeIntervalSince1970: 1_753_574_400)

  // MARK: - Lossless recovery

  @Test("A layered document recovers field for field")
  func recoversALayeredDocumentLosslessly() throws {
    try withTemporaryDirectory { directory in
      let original = Self.layeredDocument()
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)

      try AutosaveStore.snapshot(
        document: original,
        originalPath: directory.appendingPathComponent("session.halfcell"),
        to: recoveryURL,
        at: Self.snapshotDate
      )
      let snapshot = try #require(try AutosaveStore.recover(from: recoveryURL))
      let recovered = snapshot.document

      // Everything the GIF encoder would have destroyed, asserted one
      // field at a time — a bare `==` would pass just as happily on a
      // document that had never had layers to lose.
      #expect(recovered.size == original.size)
      #expect(recovered.loopCount == original.loopCount)
      #expect(recovered.palette.usedCount == original.palette.usedCount)
      #expect(recovered.palette.usedColors == original.palette.usedColors)
      try #require(recovered.frames.count == 3)

      for (frameIndex, expectedFrame) in original.frames.enumerated() {
        let frame = recovered.frames[frameIndex]
        #expect(frame.id == expectedFrame.id, "frame \(frameIndex) id")
        #expect(
          frame.delayCentiseconds == expectedFrame.delayCentiseconds,
          "frame \(frameIndex) delay"
        )
        #expect(frame.disposal == expectedFrame.disposal, "frame \(frameIndex) disposal")
        try #require(frame.layers.count == 3, "frame \(frameIndex) layer count")

        for (layerIndex, expectedLayer) in expectedFrame.layers.enumerated() {
          let label = "frame \(frameIndex) layer \(layerIndex)"
          let layer = frame.layers[layerIndex]
          #expect(layer.id == expectedLayer.id, "\(label) id")
          #expect(layer.name == expectedLayer.name, "\(label) name")
          #expect(layer.isVisible == expectedLayer.isVisible, "\(label) visibility")
          #expect(layer.pixels.size == expectedLayer.pixels.size, "\(label) size")
          #expect(layer.pixels.pixels == expectedLayer.pixels.pixels, "\(label) pixels")
        }
      }

      #expect(recovered == original)
    }
  }

  @Test("Recovery carries the document it was for and when it was taken")
  func recoveryCarriesItsMetadata() throws {
    try withTemporaryDirectory { directory in
      let documentURL = directory.appendingPathComponent("session.halfcell")
      let original = Self.layeredDocument()
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)

      try AutosaveStore.snapshot(
        document: original,
        originalPath: documentURL,
        to: recoveryURL,
        at: Self.snapshotDate
      )
      let snapshot = try #require(try AutosaveStore.recover(from: recoveryURL))

      #expect(snapshot.savedAt == Self.snapshotDate)
      #expect(snapshot.originalPath == documentURL)
      #expect(snapshot.document == original)
    }
  }

  @Test("A never-saved document recovers with no original path")
  func unsavedDocumentRecoversWithoutAPath() throws {
    try withTemporaryDirectory { directory in
      let original = Self.layeredDocument()
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)

      try AutosaveStore.snapshot(
        document: original,
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )
      let snapshot = try #require(try AutosaveStore.recover(from: recoveryURL))

      #expect(snapshot.originalPath == nil)
      #expect(snapshot.document.frames.count == 3)
    }
  }

  @Test("The recovery file is the documented envelope around a stripped project")
  func recoveryFileIsTheDocumentedEnvelope() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try AutosaveStore.snapshot(
        document: Self.layeredDocument(),
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )

      let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: recoveryURL))
      let envelope = try #require(object as? [String: Any])
      #expect(envelope["snapshotVersion"] as? Int == AutosaveStore.currentSnapshotVersion)
      #expect(envelope["savedAt"] as? Double == Self.snapshotDate.timeIntervalSince1970)
      let project = try #require(envelope["project"] as? [String: Any])
      #expect(project["formatVersion"] as? Int == ProjectFile.currentFormatVersion)
      let document = try #require(project["document"] as? [String: Any])
      #expect(document["path"] == nil, "the project payload still strips its own path")
    }
  }

  // MARK: - Absence and clearing

  @Test("No recovery file means nothing to recover, not an error")
  func absentRecoveryFileReturnsNil() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      #expect(!AutosaveStore.snapshotExists(at: recoveryURL))
      let recovered = try AutosaveStore.recover(from: recoveryURL)
      #expect(recovered == nil)
    }
  }

  @Test("Clearing discards the recovery file, and clearing twice is fine")
  func clearingDiscardsTheRecoveryFile() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try AutosaveStore.snapshot(
        document: Self.layeredDocument(),
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )
      #expect(AutosaveStore.snapshotExists(at: recoveryURL))

      try AutosaveStore.clear(at: recoveryURL)
      #expect(!AutosaveStore.snapshotExists(at: recoveryURL))
      let afterClear = try AutosaveStore.recover(from: recoveryURL)
      #expect(afterClear == nil)

      // Idempotent: "make sure there is no stale recovery file" is the
      // caller's intent, and it should not have to check first.
      try AutosaveStore.clear(at: recoveryURL)
      #expect(!AutosaveStore.snapshotExists(at: recoveryURL))
    }
  }

  // MARK: - Damaged files

  @Test("A truncated recovery file reports failure rather than trapping")
  func truncatedRecoveryFileReportsFailure() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try AutosaveStore.snapshot(
        document: Self.layeredDocument(),
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )

      let whole = try Data(contentsOf: recoveryURL)
      #expect(whole.count > 200, "the fixture must be long enough for a half to be a truncation")
      try whole.prefix(whole.count / 2).write(to: recoveryURL)

      #expect(throws: AutosaveError.self) {
        _ = try AutosaveStore.recover(from: recoveryURL)
      }
    }
  }

  @Test("A recovery file from a future build is refused by version, not misread")
  func futureSnapshotVersionIsRefused() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try AutosaveStore.snapshot(
        document: Self.layeredDocument(),
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )
      let future = AutosaveStore.currentSnapshotVersion + 1
      try Self.rewriting(recoveryURL) { envelope in
        envelope["snapshotVersion"] = future
      }

      #expect(
        throws: AutosaveError.unsupportedSnapshotVersion(
          found: future,
          supported: AutosaveStore.currentSnapshotVersion
        )
      ) {
        _ = try AutosaveStore.recover(from: recoveryURL)
      }
    }
  }

  @Test("A damaged project inside an intact envelope is reported as such")
  func damagedProjectInsideAValidEnvelope() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try AutosaveStore.snapshot(
        document: Self.layeredDocument(),
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )
      try Self.rewriting(recoveryURL) { envelope in
        var project = envelope["project"] as? [String: Any] ?? [:]
        var document = project["document"] as? [String: Any] ?? [:]
        document["frames"] = [Any]()
        project["document"] = document
        envelope["project"] = project
      }

      #expect(throws: AutosaveError.damagedDocument(.emptyFrameList)) {
        _ = try AutosaveStore.recover(from: recoveryURL)
      }
    }
  }

  @Test("Bytes that are not the envelope at all are reported, not decoded")
  func nonEnvelopeBytesAreReported() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)
      try Data("this is not a recovery file".utf8).write(to: recoveryURL)

      #expect(throws: AutosaveError.self) {
        _ = try AutosaveStore.recover(from: recoveryURL)
      }
    }
  }

  // MARK: - Atomicity

  @Test("Overwriting a snapshot leaves no debris and no tail of the old file")
  func overwritingASnapshotLeavesNoDebris() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL = directory.appendingPathComponent(AutosaveStore.defaultFileName)

      // A large document first, then a much smaller one. A writer that
      // truncated and streamed would leave a window where the file is a
      // prefix; one that did not truncate would leave the tail of the
      // larger file behind. Neither survives the rename.
      let large = Self.layeredDocument(size: PixelSize(width: 32, height: 32))
      try AutosaveStore.snapshot(
        document: large,
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )
      let largeByteCount = try Data(contentsOf: recoveryURL).count

      let small = GIFDocument.blank(size: PixelSize(width: 2, height: 2))
      try AutosaveStore.snapshot(
        document: small,
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )

      let smallByteCount = try Data(contentsOf: recoveryURL).count
      #expect(smallByteCount < largeByteCount)

      let snapshot = try #require(try AutosaveStore.recover(from: recoveryURL))
      #expect(snapshot.document.size == small.size)
      #expect(snapshot.document.frames.count == 1)

      let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      #expect(
        contents == [AutosaveStore.defaultFileName],
        "an atomic write must not leave a temporary sibling behind; found \(contents)"
      )
    }
  }

  @Test("Snapshotting creates the state directory it was pointed at")
  func snapshotCreatesTheStateDirectory() throws {
    try withTemporaryDirectory { directory in
      let recoveryURL =
        directory
        .appendingPathComponent(".config")
        .appendingPathComponent("halfcell")
        .appendingPathComponent(AutosaveStore.defaultFileName)

      try AutosaveStore.snapshot(
        document: Self.layeredDocument(),
        originalPath: nil,
        to: recoveryURL,
        at: Self.snapshotDate
      )

      let recovered = try AutosaveStore.recover(from: recoveryURL)
      #expect(recovered != nil)
    }
  }

  // MARK: - Fixtures

  /// Three frames of three named layers each, with mixed visibility, a
  /// non-default palette, mixed delays and disposals, and a non-zero
  /// loop count — every field the GIF encoder would flatten away.
  static func layeredDocument(
    size: PixelSize = PixelSize(width: 6, height: 4)
  ) -> GIFDocument {
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0x1B_1B2E),
      EditorColor(rgbHex: 0xFF_005D),
      EditorColor(rgbHex: 0x00_C896),
      EditorColor(rgbHex: 0xF7_D51D),
      EditorColor(red: 9, green: 8, blue: 7, alpha: 200),
    ])

    let disposals: [EditorFrame.FrameDisposal] = [.background, .keep, .previous]
    let frames = (0..<3).map { frameIndex -> EditorFrame in
      let layers = (0..<3).map { layerIndex -> EditorLayer in
        var pixels = PixelBuffer(size: size)
        for offset in 0..<size.area where (offset + frameIndex + layerIndex) % 3 == 0 {
          pixels.pixels[offset] = PaletteIndex((offset + layerIndex) % 6)
        }
        return EditorLayer(
          id: UUID(uuidString: "0000000\(frameIndex)-0000-4000-8000-00000000000\(layerIndex)")!,
          name: ["Background", "Ink", "Highlight"][layerIndex],
          // Layer 1 of frame 1 is hidden: visibility must survive, and a
          // uniform `true` would not prove it.
          isVisible: !(frameIndex == 1 && layerIndex == 1),
          pixels: pixels
        )
      }
      return EditorFrame(
        id: UUID(uuidString: "1111111\(frameIndex)-1111-4111-8111-111111111111")!,
        layers: layers,
        delayCentiseconds: 5 + frameIndex * 4,
        disposal: disposals[frameIndex]
      )
    }

    return GIFDocument(
      size: size,
      palette: palette,
      frames: frames,
      loopCount: 5
    )
  }

  /// Reads the recovery file back as JSON, lets `mutate` damage it, and
  /// writes it out again — the cheapest way to build "intact envelope,
  /// broken payload" fixtures without hand-writing base64.
  static func rewriting(
    _ url: URL,
    _ mutate: (inout [String: Any]) -> Void
  ) throws {
    let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
    guard var envelope = object as? [String: Any] else {
      throw CocoaError(.propertyListReadCorrupt)
    }
    mutate(&envelope)
    try JSONSerialization.data(withJSONObject: envelope).write(to: url)
  }
}
