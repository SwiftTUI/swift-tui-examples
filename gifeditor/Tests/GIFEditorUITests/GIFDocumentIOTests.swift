import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// File transport delegates recognition and decoding to Core, while this
/// adapter owns read/write failures and persistence behavior. The routing
/// tests use real checked-in fixtures so they exercise the adapter boundary.
///
/// There is no "fixture missing, skip" branch anywhere here. This suite
/// has been bitten before by a `#filePath` walk that went one directory
/// too far and turned two tests into silent no-ops, so a missing
/// fixture fails the test.
@Suite("GIF editor document IO")
struct GIFDocumentIOTests {

  // MARK: - Opening

  @Test("Opening a GIF routes to the importer")
  func openImportsAGIF() throws {
    let url = try Self.fixtureURL("nyan.gif")
    let ingested = try GIFDocumentIO.openIngested(contentsOf: url)
    let document = ingested.document

    #expect(document.frames.count > 1)
    #expect(ingested.provenance == DocumentProvenance(source: .file(url), kind: .gif))
    // The importer's shape: one flattened layer per frame.
    #expect(document.frames.allSatisfy { $0.layers.count == 1 })
    #expect(document.frames.allSatisfy { $0.layers[0].name == "Imported" })
  }

  @Test("Opening a project routes to the project decoder and reports provenance")
  func openDecodesAProject() throws {
    let url = try Self.goldenProjectURL()
    let ingested = try GIFDocumentIO.openIngested(contentsOf: url)
    let document = ingested.document

    #expect(document.size == PixelSize(width: 4, height: 4))
    #expect(document.frames.count == 2)
    #expect(document.frames[0].layers.map(\.name) == ["Background", "Sparkle"])
    #expect(document.frames[0].layers.map(\.isVisible) == [true, false])
    #expect(document.loopCount == 3)
    #expect(ingested.provenance == DocumentProvenance(source: .file(url), kind: .project))
  }

  @Test("Routing is on bytes, not on the extension")
  func openRoutesOnBytesNotExtension() throws {
    try Self.withTemporaryDirectory { directory in
      // A GIF someone renamed to get it into a file list still imports.
      let disguisedGIF = directory.appendingPathComponent("renamed.halfcell")
      try Data(contentsOf: try Self.fixtureURL("nyan.gif")).write(to: disguisedGIF)
      let imported = try GIFDocumentIO.open(contentsOf: disguisedGIF)
      #expect(imported.frames.allSatisfy { $0.layers[0].name == "Imported" })

      // And a project saved without an extension still decodes.
      let bareProject = directory.appendingPathComponent("no-extension")
      try Data(contentsOf: try Self.goldenProjectURL()).write(to: bareProject)
      let decoded = try GIFDocumentIO.open(contentsOf: bareProject)
      #expect(decoded.frames[0].layers.map(\.name) == ["Background", "Sparkle"])
    }
  }

  @Test("A file that is neither format is refused before a decoder sees it")
  func openRejectsAnUnrecognizedFile() throws {
    try Self.withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("notes.txt")
      try Data("just some text I had lying around".utf8).write(to: url)

      do {
        _ = try GIFDocumentIO.open(contentsOf: url)
        Issue.record("expected an error for a file that is neither a GIF nor a project")
      } catch let error as GIFDocumentIO.OpenError {
        guard case .unrecognizedFormat = error else {
          Issue.record("expected .unrecognizedFormat, got \(error)")
          return
        }
        // The message has to name what the file is not; a JSON parse
        // error about a byte offset would be the confusing outcome this
        // case exists to avoid.
        #expect(error.description.contains("notes.txt"))
        #expect(error.description.contains(ProjectFile.fileExtension))
      }
    }
  }

  @Test("A damaged project is mapped to the adapter's open error")
  func openReportsProjectDecodeErrors() throws {
    try Self.withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("damaged.halfcell")
      // Sniffs as a project (it opens with `{`) and then fails the
      // hardened decode — the two outcomes must stay distinguishable.
      try Data("{\"formatVersion\": 1, \"document\": {}}".utf8).write(to: url)

      do {
        _ = try GIFDocumentIO.open(contentsOf: url)
        Issue.record("expected a damaged project to fail")
      } catch let error as GIFDocumentIO.OpenError {
        guard case .malformed(_, kind: .project, detail: let detail) = error else {
          Issue.record("expected .malformed(project), got \(error)")
          return
        }
        #expect(!detail.isEmpty)
      }
    }
  }

  @Test("A file that is not there is refused as unreadable")
  func openRejectsAMissingFile() throws {
    try Self.withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("never-existed.halfcell")
      do {
        _ = try GIFDocumentIO.open(contentsOf: url)
        Issue.record("expected an error for a missing file")
      } catch let error as GIFDocumentIO.OpenError {
        guard case .unreadable = error else {
          Issue.record("expected .unreadable, got \(error)")
          return
        }
      }
    }
  }

  @Test("Opening off the main actor produces the same document")
  func openOffMainMatchesOpen() async throws {
    let url = try Self.goldenProjectURL()
    let onMain = try GIFDocumentIO.open(contentsOf: url)
    let offMain = try await GIFDocumentIO.openOffMain(contentsOf: url)
    #expect(offMain == onMain)
  }

  // MARK: - Saving projects

  @Test("A saved project reopens with its layers intact")
  func projectSaveRoundTrips() throws {
    try Self.withTemporaryDirectory { directory in
      let target = directory.appendingPathComponent("session.halfcell")
      let document = try GIFDocumentIO.open(contentsOf: try Self.goldenProjectURL())

      let outcome = GIFDocumentIO.saveProject(
        document: document,
        to: target,
        overwriteExisting: false
      )
      guard case .saved = outcome else {
        Issue.record("expected .saved, got \(outcome)")
        return
      }

      let reopened = try GIFDocumentIO.open(contentsOf: target)
      #expect(reopened.frames.count == document.frames.count)
      #expect(reopened.frames[0].layers.map(\.name) == ["Background", "Sparkle"])
      #expect(reopened.frames[0].layers.map(\.isVisible) == [true, false])
      #expect(reopened.palette.usedColors == document.palette.usedColors)
      #expect(reopened == document)
    }
  }

  @Test("Saving over an existing file asks first")
  func projectSaveAsksBeforeClobbering() throws {
    try Self.withTemporaryDirectory { directory in
      let target = directory.appendingPathComponent("occupied.halfcell")
      try Data("existing content".utf8).write(to: target)
      let document = GIFDocument.blank(size: PixelSize(width: 3, height: 3))

      let refused = GIFDocumentIO.saveProject(
        document: document,
        to: target,
        overwriteExisting: false
      )
      guard case .needsOverwriteConfirmation = refused else {
        Issue.record("expected .needsOverwriteConfirmation, got \(refused)")
        return
      }
      let untouched = try Data(contentsOf: target)
      #expect(untouched == Data("existing content".utf8))

      let confirmed = GIFDocumentIO.saveProject(
        document: document,
        to: target,
        overwriteExisting: true
      )
      guard case .saved = confirmed else {
        Issue.record("expected .saved, got \(confirmed)")
        return
      }
      let overwritten = try GIFDocumentIO.open(contentsOf: target)
      #expect(overwritten.size == document.size)
    }
  }

  @Test("Saving into a directory that is not there fails rather than trapping")
  func projectSaveReportsWriteFailures() throws {
    try Self.withTemporaryDirectory { directory in
      let target =
        directory
        .appendingPathComponent("no-such-directory")
        .appendingPathComponent("session.halfcell")

      let outcome = GIFDocumentIO.saveProject(
        document: GIFDocument.blank(size: PixelSize(width: 2, height: 2)),
        to: target,
        overwriteExisting: true
      )
      guard case .failed = outcome else {
        Issue.record("expected .failed, got \(outcome)")
        return
      }
    }
  }

  @Test("Saving off the main actor writes the same bytes")
  func projectSaveOffMainMatchesSave() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let document = try GIFDocumentIO.open(contentsOf: try Self.goldenProjectURL())
    let onMainTarget = directory.appendingPathComponent("on-main.halfcell")
    let offMainTarget = directory.appendingPathComponent("off-main.halfcell")

    _ = GIFDocumentIO.saveProject(document: document, to: onMainTarget, overwriteExisting: true)
    let outcome = await GIFDocumentIO.saveProjectOffMain(
      document: document,
      to: offMainTarget,
      overwriteExisting: true
    )
    guard case .saved = outcome else {
      Issue.record("expected .saved, got \(outcome)")
      return
    }

    let offMainBytes = try Data(contentsOf: offMainTarget)
    let onMainBytes = try Data(contentsOf: onMainTarget)
    #expect(offMainBytes == onMainBytes)
  }

  // MARK: - Save targets

  @Test("Save As pre-fills a project path derived from wherever the document came from")
  func defaultProjectSaveURLReExtensions() {
    #expect(
      GIFDocumentIO.defaultProjectSaveURL(sourceURL: nil, backing: nil).lastPathComponent
        == "untitled.halfcell"
    )

    #expect(
      GIFDocumentIO.defaultProjectSaveURL(
        sourceURL: URL(fileURLWithPath: "/art/nyan.gif"),
        backing: nil
      ).path == "/art/nyan.halfcell"
    )

    #expect(
      GIFDocumentIO.defaultProjectSaveURL(
        sourceURL: URL(fileURLWithPath: "/imports/source.gif"),
        backing: URL(fileURLWithPath: "/art/session.halfcell")
      ).path == "/art/session.halfcell"
    )
  }

  @Test("Export pre-fills a GIF path without targeting a project file")
  func defaultExportURLReExtensions() {
    #expect(GIFDocumentIO.defaultSaveURL(sourceURL: nil).lastPathComponent == "untitled.gif")
    #expect(
      GIFDocumentIO.defaultSaveURL(
        sourceURL: URL(fileURLWithPath: "/art/session.halfcell")
      ).path == "/art/session.gif"
    )
    #expect(
      GIFDocumentIO.defaultSaveURL(
        sourceURL: URL(fileURLWithPath: "/imports/nyan.gif")
      ).path == "/imports/nyan.gif"
    )
  }

  @Test("The state directory is derived from the home directory it is handed")
  func stateDirectoryIsRelativeToTheGivenHome() {
    let directory = GIFDocumentIO.stateDirectory(homeDirectory: "/home/pixel")
    #expect(directory.path == "/home/pixel/.config/halfcell")
    #expect(
      directory.appendingPathComponent(RecentDocuments.defaultFileName).lastPathComponent
        == "recents.json"
    )
  }

  // MARK: - Fixtures

  /// Resolved relative to this source file rather than the working
  /// directory. The package declares no test resources, so the sample
  /// GIFs sit at the package root and `Fixtures/` beside `Sources/`.
  static func fixtureURL(_ components: String...) throws -> URL {
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

  static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
  }
}
