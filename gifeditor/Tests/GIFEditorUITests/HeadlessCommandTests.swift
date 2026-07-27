import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditor

/// The headless subcommands (`info`, `optimize`, `export`), exercised
/// through the pure functions their `ParsableCommand` wrappers call.
///
/// The wrappers themselves are three lines each — parse, call, print — and
/// an executable target is not straightforward to reach from a test bundle.
/// Everything worth asserting therefore lives below `run()`: a function of
/// already-resolved inputs that returns a value. What is *not* covered here
/// is the argument grammar itself, which is swift-argument-parser's.
///
/// Every fixture is a real checked-in file, and there is no
/// "fixture missing, skip" branch anywhere: a missing fixture fails the
/// test rather than turning it into a silent no-op. Nothing here shells out
/// — the Linux gate container has no image tooling on `PATH`, and a suite
/// that quietly skips there is a suite that is not run.
@Suite("Headless subcommands")
struct HeadlessCommandTests {

  // MARK: - info

  @Test("info reports a GIF's shape from its bytes")
  func infoDescribesAGIF() throws {
    let url = try Self.fixtureURL("nyan.gif")
    let report = try HeadlessInfo.report(contentsOf: url)
    let fileSize = try Self.byteCount(of: url)

    #expect(report.format == .gif)
    #expect(report.formatVersion == nil)
    #expect(report.byteCount == fileSize)
    #expect(report.canvas.width > 0)
    #expect(report.canvas.height > 0)
    #expect(report.frameCount > 1)
    #expect(report.frames.count == report.frameCount)
    #expect(report.paletteColorCount > 0)
    #expect(report.paletteColorCount <= ColorPalette.capacity)

    // The importer flattens each GIF frame into a single layer, so the
    // per-frame layer count is the one thing here that is knowable
    // without opening the file.
    #expect(report.frames.allSatisfy { $0.layerCount == 1 })
    #expect(report.frames.map(\.index) == Array(0..<report.frameCount))
    #expect(report.frames.allSatisfy { $0.delayCentiseconds > 0 })
    #expect(report.frames.allSatisfy { $0.delayMilliseconds == $0.delayCentiseconds * 10 })
  }

  @Test("info reports a project's layer stack and format version")
  func infoDescribesAProject() throws {
    let url = try Self.goldenProjectURL()
    let report = try HeadlessInfo.report(contentsOf: url)
    let fileSize = try Self.byteCount(of: url)

    #expect(report.format == .project)
    #expect(report.formatVersion == ProjectFile.currentFormatVersion)
    #expect(report.byteCount == fileSize)
    #expect(report.frameCount >= 1)
    #expect(report.frames.count == report.frameCount)

    // Read the document independently and cross-check the counts, so the
    // report is pinned to the file rather than to itself.
    let document = try ProjectFile.document(from: Data(contentsOf: url))
    #expect(report.canvas == document.size)
    #expect(report.loopCount == document.loopCount)
    #expect(report.paletteColorCount == document.palette.usedColors.count)
    #expect(report.frames.map(\.layerCount) == document.frames.map { $0.layers.count })
    #expect(report.frames.map(\.delayCentiseconds) == document.frames.map(\.delayCentiseconds))
  }

  @Test("info --json parses as JSON and carries the documented keys")
  func infoJSONHasTheDocumentedShape() throws {
    let url = try Self.fixtureURL("nyan.gif")
    let report = try HeadlessInfo.report(contentsOf: url)
    let text = try HeadlessRun.jsonText(for: report)

    // Asserted through JSONSerialization rather than by decoding the type
    // back through its own `Codable`: the contract is the *bytes* a script
    // reads, and a round trip through `FileInfoReport` would agree with
    // any key names the type happened to use.
    let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
    let object = try #require(parsed as? [String: Any])

    #expect(object["format"] as? String == "gif")
    #expect(object["path"] as? String == url.path)
    #expect(object["byteCount"] as? Int == report.byteCount)
    #expect(object["frameCount"] as? Int == report.frameCount)
    #expect(object["loopCount"] as? Int == report.loopCount)
    #expect(object["paletteColorCount"] as? Int == report.paletteColorCount)
    // Absent, not null: a GIF has no project format version, and a script
    // testing `"formatVersion" in obj` is how it tells the two apart.
    #expect(object["formatVersion"] == nil)

    let canvas = try #require(object["canvas"] as? [String: Any])
    #expect(canvas["width"] as? Int == report.canvas.width)
    #expect(canvas["height"] as? Int == report.canvas.height)

    let frames = try #require(object["frames"] as? [[String: Any]])
    #expect(frames.count == report.frameCount)
    let first = try #require(frames.first)
    #expect(first["index"] as? Int == 0)
    #expect(first["layerCount"] as? Int == 1)
    #expect(first["delayCentiseconds"] as? Int == report.frames[0].delayCentiseconds)
    #expect(first["delayMilliseconds"] as? Int == report.frames[0].delayCentiseconds * 10)
  }

  @Test("info --json on a project carries the format version")
  func infoJSONReportsTheProjectVersion() throws {
    let report = try HeadlessInfo.report(contentsOf: try Self.goldenProjectURL())
    let parsed = try JSONSerialization.jsonObject(
      with: Data(try HeadlessRun.jsonText(for: report).utf8)
    )
    let object = try #require(parsed as? [String: Any])
    #expect(object["format"] as? String == "project")
    #expect(object["formatVersion"] as? Int == ProjectFile.currentFormatVersion)
  }

  @Test("info's text rendering names the file and every frame")
  func infoTextListsEveryFrame() throws {
    let report = try HeadlessInfo.report(contentsOf: try Self.fixtureURL("nyan.gif"))
    let text = HeadlessInfo.text(for: report)

    #expect(text.hasPrefix("nyan.gif"))
    #expect(text.contains("canvas"))
    #expect(text.contains("\(report.canvas.width)x\(report.canvas.height)"))
    #expect(text.contains("\(report.paletteColorCount) colors"))

    // The frame table is everything after the blank separator line, minus
    // its own header row.
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let separator = try #require(lines.firstIndex(where: { $0.isEmpty }))
    let table = lines[lines.index(after: separator)...]
    #expect(table.count == report.frameCount + 1)
    #expect(table.first?.contains("delay") == true)
  }

  @Test(
    "A loop count reads as prose",
    arguments: [(0, "forever"), (1, "once"), (3, "3 times")]
  )
  func loopCountsReadAsProse(loopCount: Int, expected: String) {
    #expect(HeadlessInfo.loopDescription(loopCount) == expected)
  }

  // MARK: - optimize

  @Test("optimize shrinks a fixture that benefits from a re-encode")
  func optimizeShrinksTheMultiPaletteFixture() throws {
    // `multi-palette-gradient.gif` carries a 256-entry *local* colour table
    // on each of its four frames — about 3 KB of palette in a 7.8 KB file.
    // The re-encode consolidates them into one global table, and that is
    // where the saving comes from; delta coding contributes nothing here
    // because every frame differs everywhere. Measured 2026-07-26:
    // 7838 -> 3019 bytes, 61.5% saved.
    let url = try Self.fixtureURL("Fixtures", "multi-palette-gradient.gif")
    let data = try Data(contentsOf: url)
    let (bytes, report) = try HeadlessOptimize.optimize(data: data, url: url)

    #expect(report.inputByteCount == data.count)
    #expect(report.outputByteCount == bytes.count)
    #expect(report.savedByteCount > 0, "the re-encode should shrink this fixture")
    #expect(report.outputByteCount < report.inputByteCount)
    #expect(report.savedPercent > 50)
    #expect(report.frameCoding == .delta)
  }

  @Test("A re-encode can grow an input that was already tightly coded, and says so")
  func optimizeReportsGrowthHonestly() throws {
    // Not a bug, and worth a test rather than a footnote. `finite-loop-3`
    // is 99 bytes of which almost all are header, colour table and the
    // looping block. The import adds the reserved transparent slot, so
    // four authored colours become five used ones and the table pads from
    // 4 entries to 8 — twelve bytes of palette that 16 pixels cannot earn
    // back at any coding. Measured 2026-07-27: 99 -> 113 bytes, the same
    // under `delta` and `full`. The report has to state the growth rather
    // than round it away.
    let url = try Self.fixtureURL("Fixtures", "finite-loop-3.gif")
    let data = try Data(contentsOf: url)
    let (_, report) = try HeadlessOptimize.optimize(data: data, url: url)

    #expect(report.savedByteCount < 0)
    #expect(report.savedPercent < 0)
    let text = HeadlessOptimize.text(
      for: report,
      input: url,
      output: URL(fileURLWithPath: "/tmp/out.gif")
    )
    #expect(text.contains("grew by \(-report.savedByteCount) bytes"))
    #expect(!text.contains("saved"))
  }

  @Test(
    "A re-encode shrinks the sample GIFs now that the colour table is trimmed",
    arguments: ["nyan.gif", "abom_eat.gif", "abom_h.gif"]
  )
  func optimizeShrinksTheSampleGIFs(fixture: String) throws {
    // These three used to *grow* under re-encode, because every export
    // carried a full 256-entry global colour table whatever the document
    // held. `GIFEncoder` now writes only the palette in use, and all
    // three import to a handful of colours. Measured 2026-07-27:
    //   nyan.gif       4919 -> 3725  (-24.3%, 15 palette slots used)
    //   abom_eat.gif   3056 -> 1924  (-37.0%, 13 slots)
    //   abom_h.gif      510 ->  499  ( -2.2%,  7 slots)
    // abom_h is the thin one on purpose: two frames whose bytes are
    // mostly palette, where delta coding's extra image descriptor eats
    // most of what the smaller table won back.
    let url = try Self.fixtureURL(fixture)
    let data = try Data(contentsOf: url)
    let (bytes, report) = try HeadlessOptimize.optimize(data: data, url: url)

    #expect(report.savedByteCount > 0)
    #expect(report.savedPercent > 0)
    #expect(bytes.count < data.count)
    let text = HeadlessOptimize.text(
      for: report,
      input: url,
      output: URL(fileURLWithPath: "/tmp/out.gif")
    )
    #expect(text.contains("saved \(report.savedByteCount) bytes"))
    #expect(!text.contains("grew by"))

    // Smaller, and not by throwing anything away.
    try Self.expectRendersIdentically(input: data, output: Data(bytes))
  }

  @Test("optimize's output renders identically to its input")
  func optimizeIsPixelIdentical() throws {
    let url = try Self.fixtureURL("Fixtures", "multi-palette-gradient.gif")
    let data = try Data(contentsOf: url)
    let (bytes, _) = try HeadlessOptimize.optimize(data: data, url: url)
    try Self.expectRendersIdentically(input: data, output: Data(bytes))
  }

  @Test(
    "Both frame codings render identically, including where delta grows the file",
    arguments: [
      ("nyan.gif", FrameCodingOption.delta),
      ("nyan.gif", FrameCodingOption.full),
      ("abom_eat.gif", FrameCodingOption.delta),
      ("abom_eat.gif", FrameCodingOption.full),
      // abom_h.gif gets *larger* under delta coding. That is a size
      // result, not a fidelity one, and this row exists to keep the
      // distinction pinned.
      ("abom_h.gif", FrameCodingOption.delta),
      ("abom_h.gif", FrameCodingOption.full),
    ]
  )
  func everyCodingRoundTripsFaithfully(fixture: String, coding: FrameCodingOption) throws {
    let url = try Self.fixtureURL(fixture)
    let data = try Data(contentsOf: url)
    let (bytes, _) = try HeadlessOptimize.optimize(data: data, url: url, frameCoding: coding)
    try Self.expectRendersIdentically(input: data, output: Data(bytes))
  }

  @Test(
    "optimize preserves the loop count the input declared",
    arguments: [
      // Carries a NETSCAPE block declaring 0 — forever.
      ["nyan.gif"],
      // Carries none at all, which the format defines as playing once.
      // The re-encode writes an explicit `1`, which is the same animation
      // said out loud, so the assertion is on the effective count rather
      // than on the bytes.
      ["Fixtures", "multi-palette-gradient.gif"],
    ]
  )
  func optimizePreservesTheLoopCount(fixture: [String]) throws {
    let url = try Self.fixtureURL(components: fixture)
    let data = try Data(contentsOf: url)
    let (bytes, _) = try HeadlessOptimize.optimize(data: data, url: url)

    // Without the probe the importer's dropped loop count would make every
    // optimized GIF loop forever regardless of what it said going in.
    let before = HeadlessInput.gifLoopCount(in: data) ?? HeadlessInput.playsOnce
    let after = HeadlessInput.gifLoopCount(in: Data(bytes)) ?? HeadlessInput.playsOnce
    #expect(after == before)
  }

  @Test("optimize writes to the path it is given and reports the change")
  func optimizeWritesItsOutput() throws {
    try Self.withTemporaryDirectory { directory in
      let input = try Self.fixtureURL("Fixtures", "multi-palette-gradient.gif")
      // A nested directory that does not exist yet: the writer creates the
      // parent rather than failing on a path the caller clearly meant.
      let output = directory.appendingPathComponent("out/optimized.gif")
      let report = try HeadlessOptimize.run(input: input, output: output)

      #expect(FileManager.default.fileExists(atPath: output.path))
      let written = try Self.byteCount(of: output)
      #expect(written == report.outputByteCount)

      let text = HeadlessOptimize.text(for: report, input: input, output: output)
      #expect(text.contains("multi-palette-gradient.gif"))
      #expect(text.contains("\(report.inputByteCount) bytes"))
      #expect(text.contains("\(report.outputByteCount) bytes"))
      #expect(text.contains("saved"))
    }
  }

  @Test("optimize refuses a project file rather than comparing JSON to GIF")
  func optimizeRefusesAProject() throws {
    let url = try Self.goldenProjectURL()
    let data = try Data(contentsOf: url)
    let error = Self.headlessError {
      _ = try HeadlessOptimize.optimize(data: data, url: url)
    }
    guard case .wrongFormat = try #require(error) else {
      Issue.record("expected wrongFormat, got \(String(describing: error))")
      return
    }
    #expect(error?.exitCode == HeadlessExitStatus.dataError)
  }

  // MARK: - export

  @Test("export writes a spritesheet and a sidecar that describes it")
  func exportWritesASpritesheet() throws {
    try Self.withTemporaryDirectory { directory in
      let input = try Self.fixtureURL("nyan.gif")
      let report = try HeadlessExport.run(
        input: input,
        format: .spritesheet,
        output: directory.appendingPathComponent("sheet").path
      )

      #expect(report.format == .spritesheet)
      #expect(report.files.count == 2)
      #expect(report.totalByteCount == report.files.reduce(0) { $0 + $1.byteCount })

      let png = try #require(report.files.first { $0.path.hasSuffix(".png") })
      let sidecar = try #require(report.files.first { $0.path.hasSuffix(".json") })
      #expect(png.byteCount > 0)
      let pngBytes = try Data(contentsOf: URL(fileURLWithPath: png.path))
      #expect(Array(pngBytes.prefix(8)) == PNGEncoder.signature)

      let sidecarBytes = try Data(contentsOf: URL(fileURLWithPath: sidecar.path))
      let parsed = try JSONSerialization.jsonObject(with: sidecarBytes)
      let object = try #require(parsed as? [String: Any])
      #expect(object["format"] as? String == SpritesheetMetadata.formatIdentifier)
      let frames = try #require(object["frames"] as? [[String: Any]])
      #expect(frames.count == object["frameCount"] as? Int)
    }
  }

  @Test("export --columns reaches the layout rule")
  func exportSurfacesTheColumnOverride() throws {
    try Self.withTemporaryDirectory { directory in
      let report = try HeadlessExport.run(
        input: try Self.fixtureURL("nyan.gif"),
        format: .spritesheet,
        output: directory.appendingPathComponent("sheet").path,
        columns: 2
      )
      let sidecar = try #require(report.files.first { $0.path.hasSuffix(".json") })
      let sidecarBytes = try Data(contentsOf: URL(fileURLWithPath: sidecar.path))
      let object = try #require(
        try JSONSerialization.jsonObject(with: sidecarBytes) as? [String: Any]
      )
      #expect(object["columns"] as? Int == 2)
    }
  }

  @Test("export --frames writes one zero-padded PNG per frame")
  func exportWritesAFrameSequence() throws {
    try Self.withTemporaryDirectory { directory in
      let input = try Self.fixtureURL("nyan.gif")
      let frameCount = try HeadlessInfo.report(contentsOf: input).frameCount
      let destination = directory.appendingPathComponent("frames")
      let report = try HeadlessExport.run(input: input, format: .frames, output: destination.path)

      #expect(report.files.count == frameCount)
      #expect(report.files.allSatisfy { $0.byteCount > 0 })

      let names = report.files.map { URL(fileURLWithPath: $0.path).lastPathComponent }
      #expect(names.first == "nyan-000.png")
      // Lexicographic order is frame order — the entire point of padding.
      #expect(names == names.sorted())
    }
  }

  @Test("export --apng writes one animated PNG")
  func exportWritesAnAPNG() throws {
    try Self.withTemporaryDirectory { directory in
      let destination = directory.appendingPathComponent("nyan.png")
      let report = try HeadlessExport.run(
        input: try Self.fixtureURL("nyan.gif"),
        format: .apng,
        output: destination.path
      )

      #expect(report.files.count == 1)
      let bytes = [UInt8](try Data(contentsOf: destination))
      #expect(Array(bytes.prefix(8)) == PNGEncoder.signature)
      #expect(Self.containsChunk("acTL", in: bytes), "an APNG declares its frame count")
      #expect(Self.containsChunk("fcTL", in: bytes))
    }
  }

  @Test("export reads a project as happily as a GIF")
  func exportAcceptsAProject() throws {
    try Self.withTemporaryDirectory { directory in
      let destination = directory.appendingPathComponent("project.png")
      let report = try HeadlessExport.run(
        input: try Self.goldenProjectURL(),
        format: .apng,
        output: destination.path
      )
      #expect(report.files.count == 1)
      #expect(report.files[0].byteCount > 0)
    }
  }

  @Test("Default destinations are derived from the input name")
  func defaultDestinationsFollowTheInput() {
    let input = URL(fileURLWithPath: "/tmp/pixels/walk.gif")
    #expect(
      HeadlessExport.defaultDestination(for: .spritesheet, input: input).path
        == "/tmp/pixels/walk-sheet"
    )
    #expect(
      HeadlessExport.defaultDestination(for: .frames, input: input).path
        == "/tmp/pixels/walk-frames"
    )
    #expect(
      HeadlessExport.defaultDestination(for: .apng, input: input).path == "/tmp/pixels/walk.png")

    // A project exports under its own stem too, so `walk.halfcell` and
    // `walk.gif` cannot silently write over each other's frame sequence.
    let project = URL(fileURLWithPath: "/tmp/pixels/walk.halfcell")
    #expect(HeadlessExport.baseName(for: project) == "walk")
    #expect(
      HeadlessExport.defaultDestination(for: .apng, input: project).path
        == "/tmp/pixels/walk.png")
  }

  @Test("An explicit output that names an existing directory gets the derived name")
  func explicitDirectoryOutputKeepsTheDerivedName() throws {
    try Self.withTemporaryDirectory { directory in
      let input = URL(fileURLWithPath: "/tmp/pixels/walk.gif")
      let resolved = HeadlessExport.resolveDestination(
        for: .apng,
        input: input,
        output: directory.path
      )
      #expect(resolved.lastPathComponent == "walk.png")
      #expect(resolved.deletingLastPathComponent().path == directory.path)

      // `--frames` already wants a directory, so it is taken literally.
      #expect(
        HeadlessExport.resolveDestination(for: .frames, input: input, output: directory.path).path
          == directory.path
      )
    }
  }

  // MARK: - Error paths

  @Test("A missing file exits with the no-input code")
  func missingFileIsNoInput() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-absent-\(UUID().uuidString).gif")
    let error = Self.headlessError { _ = try HeadlessInfo.report(contentsOf: url) }
    guard case .fileNotFound = try #require(error) else {
      Issue.record("expected fileNotFound, got \(String(describing: error))")
      return
    }
    #expect(error?.exitCode == HeadlessExitStatus.noInput)
    #expect(HeadlessExitStatus.noInput == 66)
  }

  @Test("A file that is neither GIF nor project exits with the data-error code")
  func unrecognizedFileIsADataError() throws {
    try Self.withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("notes.txt")
      try Data("this is not a GIF and not a project\n".utf8).write(to: url)

      let error = Self.headlessError { _ = try HeadlessInfo.report(contentsOf: url) }
      guard case .unrecognizedFormat = try #require(error) else {
        Issue.record("expected unrecognizedFormat, got \(String(describing: error))")
        return
      }
      #expect(error?.exitCode == HeadlessExitStatus.dataError)
      #expect(HeadlessExitStatus.dataError == 65)
      #expect(error?.description.contains("halfcell") == true)
    }
  }

  @Test("A file that announces a format and then fails to decode is reported as damaged")
  func damagedFilesAreReportedNotTrapped() throws {
    try Self.withTemporaryDirectory { directory in
      let truncatedGIF = directory.appendingPathComponent("truncated.gif")
      try Data(Array("GIF89a".utf8) + [0x01, 0x02, 0x03]).write(to: truncatedGIF)
      let gifError = Self.headlessError { _ = try HeadlessInfo.report(contentsOf: truncatedGIF) }
      guard case .damaged = try #require(gifError) else {
        Issue.record("expected damaged, got \(String(describing: gifError))")
        return
      }
      #expect(gifError?.exitCode == HeadlessExitStatus.dataError)

      let brokenProject = directory.appendingPathComponent("broken.halfcell")
      try Data("{ \"formatVersion\": 99 }".utf8).write(to: brokenProject)
      let projectError = Self.headlessError {
        _ = try HeadlessInfo.report(contentsOf: brokenProject)
      }
      guard case .damaged = try #require(projectError) else {
        Issue.record("expected damaged, got \(String(describing: projectError))")
        return
      }
      #expect(projectError?.exitCode == HeadlessExitStatus.dataError)
    }
  }

  @Test("An empty file is unrecognized rather than a crash")
  func emptyFileIsUnrecognized() throws {
    try Self.withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("empty.gif")
      try Data().write(to: url)
      let error = Self.headlessError { _ = try HeadlessInfo.report(contentsOf: url) }
      guard case .unrecognizedFormat = try #require(error) else {
        Issue.record("expected unrecognizedFormat, got \(String(describing: error))")
        return
      }
    }
  }

  @Test("The three failure kinds do not share an exit code")
  func exitCodesAreDistinct() {
    let url = URL(fileURLWithPath: "/tmp/x.gif")
    let codes = Set([
      HeadlessError.fileNotFound(url).exitCode,
      HeadlessError.unrecognizedFormat(url).exitCode,
      HeadlessError.operationFailed(detail: "disk full").exitCode,
    ])
    #expect(codes.count == 3)
    #expect(codes == [66, 65, 70])
    #expect(HeadlessExitStatus.success == 0)
  }

  // MARK: - Sniffing

  @Test("The sniff routes on bytes, not on the extension")
  func sniffRoutesOnBytes() throws {
    let gif = try Data(contentsOf: try Self.fixtureURL("nyan.gif"))
    let project = try Data(contentsOf: try Self.goldenProjectURL())
    #expect(HeadlessInput.fileKind(of: gif) == .gif)
    #expect(HeadlessInput.fileKind(of: project) == .project)
    #expect(HeadlessInput.fileKind(of: Data("\n\n  { \"formatVersion\": 1 }".utf8)) == .project)
    #expect(HeadlessInput.fileKind(of: Data("PNG".utf8)) == nil)
    #expect(HeadlessInput.fileKind(of: Data()) == nil)
  }

  @Test("A GIF with no NETSCAPE block reports no loop count")
  func loopProbeReturnsNilWithoutTheBlock() throws {
    // The fixture that genuinely carries no application extension. The
    // two degenerate inputs below are not GIFs at all, which is the same
    // answer to the only question the probe asks.
    let none = try Data(contentsOf: try Self.fixtureURL("Fixtures", "multi-palette-gradient.gif"))
    #expect(HeadlessInput.gifLoopCount(in: none) == nil)
    #expect(
      HeadlessInput.gifLoopCount(in: Data(Array("GIF89a".utf8) + [UInt8](repeating: 0, count: 32)))
        == nil)
    #expect(HeadlessInput.gifLoopCount(in: Data()) == nil)
  }

  @Test("The loop probe reads the count the block declares")
  func loopProbeReadsTheDeclaredCount() throws {
    // Real files, because the probe parses the GIF's block structure
    // rather than scanning its bytes for the block's signature — see
    // `GIFLoader.declaredLoopCount(in:)`.
    let finite = try Data(contentsOf: try Self.fixtureURL("Fixtures", "finite-loop-3.gif"))
    #expect(HeadlessInput.gifLoopCount(in: finite) == 3)
    let forever = try Data(contentsOf: try Self.fixtureURL("nyan.gif"))
    #expect(HeadlessInput.gifLoopCount(in: forever) == 0)
    // The CLI's spelling of the absent-block default is the loader's.
    #expect(HeadlessInput.playsOnce == GIFLoader.playsOnce)
  }

  // MARK: - Fixtures and helpers

  /// Resolved relative to this source file rather than the working
  /// directory. The package declares no test resources, so the sample GIFs
  /// sit at the package root and `Fixtures/` beside `Sources/`.
  static func fixtureURL(_ components: String...) throws -> URL {
    try fixtureURL(components: components)
  }

  static func fixtureURL(components: [String]) throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorUITests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
    let url = components.reduce(packageRoot) { $0.appendingPathComponent($1) }
    guard FileManager.default.fileExists(atPath: url.path) else {
      Issue.record("fixture \(components.joined(separator: "/")) is missing at \(url.path)")
      throw CocoaError(.fileNoSuchFile)
    }
    return url
  }

  static func goldenProjectURL() throws -> URL {
    try fixtureURL("Fixtures", "project-v1-golden.halfcell")
  }

  static func byteCount(of url: URL) throws -> Int {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return try #require(values.fileSize)
  }

  static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-headless-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
  }

  /// Runs `body` and returns the ``HeadlessError`` it threw, recording an
  /// issue when it threw something else or nothing at all.
  ///
  /// `#expect(throws:)` would assert the case but not let the exit code be
  /// read off the value, and the exit code is half of what these paths
  /// promise.
  static func headlessError(_ body: () throws -> Void) -> HeadlessError? {
    do {
      try body()
      Issue.record("expected a HeadlessError, but the call succeeded")
      return nil
    } catch let error as HeadlessError {
      return error
    } catch {
      Issue.record("expected a HeadlessError, got \(error)")
      return nil
    }
  }

  /// Decodes both GIFs and asserts that every frame composites to the same
  /// pixels with the same delays — the claim `optimize` makes when it says
  /// the output is a no-op round trip.
  static func expectRendersIdentically(input: Data, output: Data) throws {
    let before = try GIFLoader.load(data: input)
    let after = try GIFLoader.load(data: output)

    #expect(after.size == before.size)
    #expect(after.frames.count == before.frames.count)
    #expect(after.frames.map(\.delayCentiseconds) == before.frames.map(\.delayCentiseconds))
    guard after.frames.count == before.frames.count else { return }
    for index in before.frames.indices {
      #expect(
        after.flattenedColors(frameIndex: index) == before.flattenedColors(frameIndex: index),
        "frame \(index) does not composite to the same pixels"
      )
    }
  }

  /// True when `bytes` carries a PNG chunk of `type`. A chunk is a
  /// big-endian length, the four-character type, the payload and a CRC, so
  /// finding the type is a literal search over a stream this test wrote.
  static func containsChunk(_ type: String, in bytes: [UInt8]) -> Bool {
    let needle = Array(type.utf8)
    guard bytes.count >= needle.count else { return false }
    for start in 0...(bytes.count - needle.count)
    where needle.indices.allSatisfy({ bytes[start + $0] == needle[$0] }) {
      return true
    }
    return false
  }
}
