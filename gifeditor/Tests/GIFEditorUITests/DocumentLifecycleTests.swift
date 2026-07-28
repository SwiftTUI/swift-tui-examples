import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// Runs `body` with a fresh temporary directory that stands in for
/// `~/.config/halfcell/`, and removes it afterwards.
func withTemporaryStateDirectory<T>(_ body: (URL) throws -> T) throws -> T {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-ui-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try body(directory)
}

@MainActor
func withTemporaryLifecycleDirectory<T>(
  _ body: @MainActor (URL) async throws -> T
) async throws -> T {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-lifecycle-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try await body(directory)
}

/// A layered document whose authoring structure would be lost by GIF export.
func layeredDocument() -> GIFDocument {
  let size = PixelSize(width: 4, height: 4)
  func frame(fill: PaletteIndex, delay: Int) -> EditorFrame {
    EditorFrame(
      layers: [
        EditorLayer(name: "Background", pixels: PixelBuffer(size: size, fill: fill)),
        EditorLayer(name: "Sparkle", isVisible: false, pixels: PixelBuffer(size: size, fill: 3)),
      ],
      delayCentiseconds: delay
    )
  }
  return GIFDocument(
    size: size,
    frames: [frame(fill: 1, delay: 7), frame(fill: 2, delay: 11)],
    loopCount: 5
  )
}

private actor BlockingAutosaveWriter {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func write(
    document: GIFDocument,
    originalPath: URL?,
    target: URL,
    timestamp: Date
  ) async throws {
    _ = (document, originalPath, target, timestamp)
    started = true
    for waiter in startWaiters {
      waiter.resume()
    }
    startWaiters.removeAll()
    await withCheckedContinuation { continuation in
      releaseWaiter = continuation
    }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

@MainActor
@Suite("Document lifecycle")
struct DocumentLifecycleTests {
  private func dirty(_ lifecycle: DocumentLifecycle, at point: PixelPoint = .zero) {
    lifecycle.session.dispatch(.setPrimaryColor(9))
    lifecycle.session.dispatch(.moveCursor(dx: point.x, dy: point.y))
    lifecycle.session.dispatch(.applyActiveTool)
    #expect(lifecycle.session.isDirty)
  }

  @Test("Origin and project backing give Save distinct authority")
  func saveAuthorityIsExplicit() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let untitled = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      #expect(untitled.defaultProjectSaveURL.lastPathComponent == "untitled.halfcell")
      #expect(await untitled.dispatch(.requestSave) == .changed)
      #expect(untitled.fileSheet == .saveAs)

      let gif = directory.appendingPathComponent("nyan.gif")
      let imported = DocumentLifecycle(
        document: layeredDocument(),
        origin: DocumentOrigin(source: .file(gif), kind: .gif),
        stateDirectory: directory
      )
      #expect(imported.defaultProjectSaveURL.lastPathComponent == "nyan.halfcell")
      #expect(imported.saveFallThroughReason?.contains("flatten") == true)
      #expect(await imported.dispatch(.requestSave) == .changed)
      #expect(imported.fileSheet == .saveAs)

      let project = directory.appendingPathComponent("session.halfcell")
      let backed = DocumentLifecycle(
        document: layeredDocument(),
        origin: DocumentOrigin(source: .file(project), kind: .project),
        projectBacking: ProjectBacking(project),
        stateDirectory: directory
      )
      dirty(backed)
      #expect(await backed.dispatch(.requestSave) == .changed)
      #expect(FileManager.default.fileExists(atPath: project.path))
      #expect(!backed.session.isDirty)
      #expect(backed.projectBacking == ProjectBacking(project))
    }
  }

  @Test("GIF export is a copy and cannot change project backing")
  func gifExportDoesNotSaveTheProject() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let project = directory.appendingPathComponent("session.halfcell")
      let lifecycle = DocumentLifecycle(
        document: layeredDocument(),
        origin: DocumentOrigin(source: .file(project), kind: .project),
        projectBacking: ProjectBacking(project),
        stateDirectory: directory
      )
      dirty(lifecycle)

      let gif = directory.appendingPathComponent("export.gif")
      #expect(await lifecycle.exportGIF(to: gif, overwriteExisting: true))
      #expect(FileManager.default.fileExists(atPath: gif.path))
      #expect(lifecycle.session.isDirty)
      #expect(lifecycle.projectBacking == ProjectBacking(project))
    }
  }

  @Test("Save As and Open round-trip layers and replace the editing session")
  func saveAndOpenRoundTrip() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let target = directory.appendingPathComponent("round-trip.halfcell")
      let lifecycle = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      dirty(lifecycle, at: PixelPoint(x: 2, y: 2))
      lifecycle.session.dispatch(.sortPalette)
      let expected = lifecycle.session.document

      #expect(await lifecycle.dispatch(.requestSaveAs) == .changed)
      #expect(
        await lifecycle.dispatch(.saveAs(target, overwriteExisting: false)) == .changed
      )
      #expect(lifecycle.projectBacking == ProjectBacking(target))
      #expect(!lifecycle.session.isDirty)

      let savedSession = ObjectIdentifier(lifecycle.session)
      #expect(await lifecycle.dispatch(.request(.open)) == .changed)
      #expect(await lifecycle.dispatch(.open(target)) == .changed)

      #expect(ObjectIdentifier(lifecycle.session) != savedSession)
      #expect(lifecycle.session.document == expected)
      #expect(!lifecycle.session.isDirty)
      #expect(lifecycle.origin == DocumentOrigin(source: .file(target), kind: .project))
      #expect(lifecycle.projectBacking == ProjectBacking(target))
    }
  }

  @Test("Opening a GIF records provenance without granting write-back")
  func openingGIFCreatesAnImport() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let gif = directory.appendingPathComponent("art.gif")
      let source = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      #expect(await source.exportGIF(to: gif, overwriteExisting: true))

      let lifecycle = DocumentLifecycle(
        document: GIFDocument.blank(size: PixelSize(width: 2, height: 2)),
        stateDirectory: directory
      )
      #expect(await lifecycle.dispatch(.request(.open)) == .changed)
      #expect(await lifecycle.dispatch(.open(gif)) == .changed)

      #expect(lifecycle.origin == DocumentOrigin(source: .file(gif), kind: .gif))
      #expect(lifecycle.projectBacking == nil)
      #expect(lifecycle.session.document.frames.allSatisfy { $0.layers.count == 1 })
      #expect(await lifecycle.dispatch(.requestSave) == .changed)
      #expect(lifecycle.fileSheet == .saveAs)
    }
  }

  @Test("A dirty destructive intent is suspended until its exact resolution")
  func dirtyIntentIsSerialized() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let lifecycle = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      dirty(lifecycle)
      let oldSession = ObjectIdentifier(lifecycle.session)

      #expect(await lifecycle.dispatch(.request(.new)) == .changed)
      #expect(lifecycle.state == .awaitingDirtyDecision(.new))
      #expect(await lifecycle.dispatch(.request(.open)) == .noChange)

      #expect(await lifecycle.dispatch(.dirtyDecision(.discard)) == .changed)
      #expect(lifecycle.state == .presenting(.new, suspended: nil))
      #expect(
        await lifecycle.dispatch(.create(PixelSize(width: 8, height: 6))) == .changed
      )

      #expect(ObjectIdentifier(lifecycle.session) != oldSession)
      #expect(lifecycle.session.document.size == PixelSize(width: 8, height: 6))
      #expect(!lifecycle.session.isDirty)
      #expect(lifecycle.origin == nil)
      #expect(lifecycle.projectBacking == nil)
      #expect(lifecycle.state == .ready)
    }
  }

  @Test("Saving a dirty document resumes only the suspended intent")
  func saveThenResume() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let lifecycle = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      dirty(lifecycle)
      let target = directory.appendingPathComponent("before-new.halfcell")

      #expect(await lifecycle.dispatch(.request(.new)) == .changed)
      #expect(await lifecycle.dispatch(.dirtyDecision(.save)) == .changed)
      #expect(lifecycle.state == .presenting(.saveAs, suspended: .new))
      #expect(
        await lifecycle.dispatch(.saveAs(target, overwriteExisting: false)) == .changed
      )

      #expect(FileManager.default.fileExists(atPath: target.path))
      #expect(lifecycle.state == .presenting(.new, suspended: nil))
    }
  }

  @Test("A failed save keeps the destructive intent guarded")
  func failedSavePreservesGuard() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let lifecycle = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      dirty(lifecycle)
      let impossible = directory
        .appendingPathComponent("missing")
        .appendingPathComponent("session.halfcell")

      _ = await lifecycle.dispatch(.request(.new))
      _ = await lifecycle.dispatch(.dirtyDecision(.save))
      guard case .failed = await lifecycle.dispatch(
        .saveAs(impossible, overwriteExisting: false)
      ) else {
        Issue.record("expected the write to fail")
        return
      }

      #expect(lifecycle.state == .awaitingDirtyDecision(.new))
      #expect(lifecycle.session.isDirty)
    }
  }

  @Test("Open and Save As expose renderable progress states")
  func progressStatesAreObservable() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let source = directory.appendingPathComponent("source.halfcell")
      try ProjectFile.data(for: layeredDocument()).write(to: source)
      let lifecycle = DocumentLifecycle(
        document: GIFDocument.blank(size: PixelSize(width: 2, height: 2)),
        stateDirectory: directory
      )

      _ = await lifecycle.dispatch(.request(.open))
      var sawOpeningSheet = false
      _ = await lifecycle.dispatch(
        .open(source),
        onTransition: {
          sawOpeningSheet =
            sawOpeningSheet || (lifecycle.fileSheet == .open && lifecycle.isOpening)
        }
      )
      #expect(sawOpeningSheet)

      let target = directory.appendingPathComponent("saved.halfcell")
      _ = await lifecycle.dispatch(.requestSaveAs)
      var sawSavingSheet = false
      _ = await lifecycle.dispatch(
        .saveAs(target, overwriteExisting: false),
        onTransition: {
          sawSavingSheet =
            sawSavingSheet || (lifecycle.fileSheet == .saveAs && lifecycle.isSaving)
        }
      )
      #expect(sawSavingSheet)
    }
  }

  @Test("Recents and autosave belong to the lifecycle")
  func recentsAndAutosave() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let project = directory.appendingPathComponent("session.halfcell")
      let lifecycle = DocumentLifecycle(
        document: layeredDocument(),
        origin: DocumentOrigin(source: .file(project), kind: .project),
        projectBacking: ProjectBacking(project),
        stateDirectory: directory
      )

      #expect(await lifecycle.dispatch(.autosave(Date())) == .noChange)
      dirty(lifecycle)
      let stamp = Date(timeIntervalSince1970: 1_753_574_400)
      #expect(await lifecycle.dispatch(.autosave(stamp)) == .changed)
      let recovered = try #require(try AutosaveStore.recover(from: lifecycle.autosaveURL))
      #expect(recovered.savedAt == stamp)
      #expect(recovered.originalPath == project)
      #expect(recovered.document == lifecycle.session.document)

      #expect(await lifecycle.dispatch(.requestSave) == .changed)
      #expect(!AutosaveStore.snapshotExists(at: lifecycle.autosaveURL))
      #expect(lifecycle.recentDocuments.urls == [project])

      let next = DocumentLifecycle(
        document: GIFDocument.blank(size: PixelSize(width: 2, height: 2)),
        stateDirectory: directory
      )
      #expect(next.recentDocuments.urls == [project])
    }
  }

  @Test("Autosaves coalesce and document replacement waits for the writer")
  func autosavesAreSerialized() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let writer = BlockingAutosaveWriter()
      let lifecycle = DocumentLifecycle(
        document: layeredDocument(),
        stateDirectory: directory,
        startsDirty: true,
        autosaveWriter: { document, originalPath, target, timestamp in
          try await writer.write(
            document: document,
            originalPath: originalPath,
            target: target,
            timestamp: timestamp
          )
        }
      )

      let firstAutosave = Task { @MainActor in
        await lifecycle.dispatch(.autosave(Date()))
      }
      await writer.waitUntilStarted()
      #expect(await lifecycle.dispatch(.autosave(Date())) == .noChange)

      #expect(await lifecycle.dispatch(.request(.new)) == .changed)
      #expect(await lifecycle.dispatch(.dirtyDecision(.discard)) == .changed)
      let create = Task { @MainActor in
        await lifecycle.dispatch(.create(PixelSize(width: 7, height: 5)))
      }
      await Task.yield()
      #expect(lifecycle.state == .settling(.new))
      #expect(await lifecycle.dispatch(.cancelPresentation) == .noChange)

      await writer.release()
      #expect(await firstAutosave.value == .changed)
      #expect(await create.value == .changed)
      #expect(lifecycle.session.document.size == PixelSize(width: 7, height: 5))
      #expect(lifecycle.state == .ready)
    }
  }

  @Test("Launch recognizes project bytes and grants project backing")
  func launchProject() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let project = directory.appendingPathComponent("renamed.data")
      let expected = layeredDocument()
      try ProjectFile.data(for: expected).write(to: project)

      let lifecycle = await DocumentLifecycle.launch(
        path: project.path,
        stateDirectory: directory
      )

      #expect(lifecycle.session.document == expected)
      #expect(lifecycle.origin == DocumentOrigin(source: .file(project), kind: .project))
      #expect(lifecycle.projectBacking == ProjectBacking(project))
      #expect(lifecycle.recoverySnapshot == nil)
      #expect(lifecycle.recentDocuments.urls == [project])
    }
  }

  @Test("Recovery resolution stays inside the lifecycle")
  func launchRecovery() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let fallbackURL = directory.appendingPathComponent("fallback.halfcell")
      let fallback = GIFDocument.blank(size: PixelSize(width: 2, height: 2))
      try ProjectFile.data(for: fallback).write(to: fallbackURL)

      let recovered = layeredDocument()
      let autosaveURL = GIFDocumentIO.autosaveURL(inStateDirectory: directory)
      try AutosaveStore.snapshot(
        document: recovered,
        originalPath: fallbackURL,
        to: autosaveURL,
        at: Date(timeIntervalSince1970: 1_753_574_400)
      )

      let lifecycle = await DocumentLifecycle.launch(
        path: fallbackURL.path,
        stateDirectory: directory
      )
      #expect(lifecycle.recoverySnapshot?.document == recovered)
      #expect(lifecycle.session.document == fallback)

      lifecycle.resolveRecovery(.recover)
      #expect(lifecycle.recoverySnapshot == nil)
      #expect(lifecycle.session.document == recovered)
      #expect(lifecycle.session.isDirty)
      #expect(lifecycle.origin == DocumentOrigin(source: .file(fallbackURL)))
      #expect(lifecycle.projectBacking == nil)
    }
  }

  @Test("Discarding recovery preserves the prepared launch document")
  func discardRecovery() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let autosaveURL = GIFDocumentIO.autosaveURL(inStateDirectory: directory)
      try AutosaveStore.snapshot(
        document: layeredDocument(),
        originalPath: nil,
        to: autosaveURL,
        at: Date()
      )

      let lifecycle = await DocumentLifecycle.launch(
        path: nil,
        stateDirectory: directory
      )
      let fallback = lifecycle.session.document
      lifecycle.resolveRecovery(.discard)

      #expect(lifecycle.recoverySnapshot == nil)
      #expect(lifecycle.session.document == fallback)
      #expect(!lifecycle.session.isDirty)
      #expect(!AutosaveStore.snapshotExists(at: autosaveURL))
    }
  }

  @Test("Quit authorization expires at the next edit generation")
  func quitAuthorizationIsGenerationBound() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let lifecycle = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      dirty(lifecycle)

      _ = await lifecycle.dispatch(.request(.quit))
      #expect(lifecycle.state == .awaitingDirtyDecision(.quit))
      #expect(await lifecycle.dispatch(.dirtyDecision(.discard)) == .readyToQuit)
      #expect(lifecycle.allowsQuit)

      lifecycle.session.dispatch(.moveCursor(dx: 1, dy: 1))
      lifecycle.session.dispatch(.applyActiveTool)
      #expect(!lifecycle.allowsQuit)
      #expect(await lifecycle.dispatch(.requestSaveAs) == .changed)
      #expect(lifecycle.fileSheet == .saveAs)
    }
  }

  @Test("Discard and quit clears recovery and later commands revoke the arm")
  func discardQuitClearsAndCanBeRevoked() async throws {
    try await withTemporaryLifecycleDirectory { directory in
      let lifecycle = DocumentLifecycle(document: layeredDocument(), stateDirectory: directory)
      dirty(lifecycle)
      _ = await lifecycle.dispatch(.autosave(Date()))
      #expect(AutosaveStore.snapshotExists(at: lifecycle.autosaveURL))

      _ = await lifecycle.dispatch(.request(.quit))
      #expect(await lifecycle.dispatch(.dirtyDecision(.discard)) == .readyToQuit)
      #expect(lifecycle.allowsQuit)
      #expect(!AutosaveStore.snapshotExists(at: lifecycle.autosaveURL))
      #expect(await lifecycle.dispatch(.autosave(Date())) == .noChange)
      #expect(lifecycle.allowsQuit)
      #expect(!AutosaveStore.snapshotExists(at: lifecycle.autosaveURL))

      #expect(await lifecycle.dispatch(.requestSaveAs) == .changed)
      #expect(!lifecycle.allowsQuit)
      #expect(lifecycle.fileSheet == .saveAs)
    }
  }

  @Test("The unsaved-changes prompt names the suspended verb")
  func unsavedChangesMessageNamesTheVerb() {
    #expect(EditorView.unsavedChangesMessage(for: .new).contains("new document"))
    #expect(EditorView.unsavedChangesMessage(for: .open).contains("another document"))
    #expect(
      EditorView.unsavedChangesMessage(for: .openRecent(URL(fileURLWithPath: "/a.halfcell")))
        .contains("another document")
    )
    #expect(EditorView.unsavedChangesMessage(for: .quit).contains("Quitting"))
  }
}
