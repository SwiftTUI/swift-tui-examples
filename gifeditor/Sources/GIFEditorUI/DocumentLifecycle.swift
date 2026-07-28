import Foundation
import GIFEditorCore

typealias DocumentAutosaveWriter =
  @Sendable (GIFDocument, URL?, URL, Date) async throws -> Void

/// A document-replacing verb the editor may have to hold back.
///
/// New, Open and Quit each destroy unsaved work, so each one is captured
/// as a value while the unsaved-changes guard asks the author what to do
/// about it, and is then performed (or dropped) by their answer. One
/// enum rather than a boolean per verb: there is exactly one pending
/// intent at a time, and the compiler should be the thing that knows it.
enum PendingDocumentAction: Hashable, Sendable {
  case new
  case open
  case openRecent(URL)
  case quit
}

/// Which file-lifecycle sheet is up.
///
/// A single `.sheet(item:)` rather than one `isPresented` sheet per
/// verb. The three are mutually exclusive by construction, and an enum
/// makes that a fact rather than three booleans that could disagree.
/// The unsaved-changes guard deliberately does *not* live here: it is a
/// `confirmationDialog`, a different presentation kind, so the guard can
/// hand off to a sheet without the two fighting over one slot.
enum FileSheet: Identifiable, Equatable, Sendable {
  case new
  case open
  case saveAs

  var id: String {
    switch self {
    case .new: "new"
    case .open: "open"
    case .saveAs: "save-as"
    }
  }
}

/// The File menu's verbs, bundled so the menu views take one parameter
/// rather than six.
///
/// Every field is the same closure shape the keybindings call, so a menu
/// item and its shortcut are guaranteed to run the same code rather than
/// two implementations that drift.
struct FileMenuActions: Sendable {
  var new: @MainActor @Sendable () -> Void
  var open: @MainActor @Sendable () -> Void
  var openRecent: @MainActor @Sendable (URL) -> Void
  var save: @MainActor @Sendable () -> Void
  var saveAs: @MainActor @Sendable () -> Void
  var exportGIF: @MainActor @Sendable () -> Void

  /// Does nothing, for the render tests that exercise menu *layout*
  /// rather than behavior.
  static let inert = FileMenuActions(
    new: {},
    open: {},
    openRecent: { _ in },
    save: {},
    saveAs: {},
    exportGIF: {}
  )
}

/// Durable project destination authorized for plain Save.
public struct ProjectBacking: Hashable, Sendable {
  public let url: URL

  public init(_ url: URL) {
    self.url = url
  }
}

/// Where externally supplied bytes came from, without granting write-back
/// authority to that source.
public struct DocumentOrigin: Hashable, Sendable {
  public let source: DocumentSourceMetadata
  public let kind: DocumentKind?

  public init(source: DocumentSourceMetadata, kind: DocumentKind? = nil) {
    self.source = source
    self.kind = kind
  }

  init(_ provenance: DocumentProvenance) {
    source = provenance.source
    kind = provenance.kind
  }
}

/// Serialized document workflow. It owns exactly one Editing session and one
/// suspended destructive action; views only present the state it exposes.
@MainActor
public final class DocumentLifecycle {
  public enum RecoveryDecision: Sendable {
    case recover
    case discard
  }

  enum State: Equatable, Sendable {
    case ready
    case awaitingDirtyDecision(PendingDocumentAction)
    case presenting(FileSheet, suspended: PendingDocumentAction?)
    case settling(PendingDocumentAction)
    case opening(
      URL,
      suspended: PendingDocumentAction?,
      presentedSheet: FileSheet?
    )
    case saving(
      URL,
      suspended: PendingDocumentAction?,
      presentedSheet: FileSheet?
    )
    case quitArmed(EditingGeneration)
  }

  enum Intent: Sendable {
    case request(PendingDocumentAction)
    case requestSave
    case requestSaveAs
    case dirtyDecision(DirtyDecision)
    case create(PixelSize)
    case open(URL)
    case saveAs(URL, overwriteExisting: Bool)
    case cancelPresentation
    case autosave(Date)
  }

  enum DirtyDecision: Sendable {
    case save
    case discard
    case cancel
  }

  enum Outcome: Hashable, Sendable {
    case changed
    case noChange
    case readyToQuit
    case failed(String)
  }

  public private(set) var session: EditingSession
  private(set) var state: State = .ready
  public private(set) var origin: DocumentOrigin?
  public private(set) var projectBacking: ProjectBacking?
  private(set) var recentDocuments: RecentDocuments
  private(set) var openErrorMessage: String?
  public private(set) var recoverySnapshot: AutosaveSnapshot?
  private var transitionObservers:
    [UUID: @MainActor @Sendable () -> Void] = [:]
  private var autosaveOperation: (id: UUID, task: Task<Void, any Error>)?
  private let autosaveWriter: DocumentAutosaveWriter

  public let stateDirectory: URL

  init(
    document: GIFDocument,
    origin: DocumentOrigin? = nil,
    projectBacking: ProjectBacking? = nil,
    initialStatusMessage: String = "",
    stateDirectory: URL? = nil,
    startsDirty: Bool = false,
    recoverySnapshot: AutosaveSnapshot? = nil,
    autosaveWriter: DocumentAutosaveWriter? = nil
  ) {
    let directory = stateDirectory ?? GIFDocumentIO.stateDirectory()
    self.stateDirectory = directory
    self.origin = origin
    self.projectBacking = projectBacking
    self.recoverySnapshot = recoverySnapshot
    self.autosaveWriter =
      autosaveWriter
      ?? { document, originalPath, target, timestamp in
        try await Task.detached(priority: .utility) {
          try AutosaveStore.snapshot(
            document: document,
            originalPath: originalPath,
            to: target,
            at: timestamp
          )
        }.value
      }
    recentDocuments = RecentDocuments.load(
      from: GIFDocumentIO.recentsURL(inStateDirectory: directory)
    )
    session = EditingSession(
      document: document,
      initialStatusMessage: initialStatusMessage,
      startsDirty: startsDirty
    )
  }

  /// Resolves launch input and recovery before the editor view exists.
  ///
  /// File recognition and recovery decoding run off the main actor. The
  /// returned lifecycle is then the single owner passed into `EditorView`.
  public nonisolated static func launch(
    path: String?,
    stateDirectory: URL? = nil
  ) async -> DocumentLifecycle {
    let directory = stateDirectory ?? GIFDocumentIO.stateDirectory()
    let preparation = await Task.detached(priority: .userInitiated) {
      prepareLaunch(path: path, stateDirectory: directory)
    }.value

    return await MainActor.run {
      let lifecycle = DocumentLifecycle(
        document: preparation.document,
        origin: preparation.origin,
        projectBacking: preparation.projectBacking,
        initialStatusMessage: preparation.statusMessage,
        stateDirectory: directory,
        recoverySnapshot: preparation.recoverySnapshot
      )
      if preparation.didOpenRequestedDocument, let url = preparation.origin?.source.url {
        lifecycle.noteRecentDocument(url)
      }
      return lifecycle
    }
  }

  public func resolveRecovery(_ decision: RecoveryDecision) {
    guard let snapshot = recoverySnapshot else { return }
    switch decision {
    case .recover:
      replaceSession(
        with: snapshot.document,
        origin: snapshot.originalPath.map { DocumentOrigin(source: .file($0)) },
        backing: nil,
        startsDirty: true
      )
      session.announce("Recovered unsaved changes")
    case .discard:
      try? AutosaveStore.clear(at: autosaveURL)
    }
    recoverySnapshot = nil
  }

  /// Writes a flattened GIF copy without changing project backing or the
  /// Editing session's clean generation.
  @discardableResult
  func exportGIF(to target: URL, overwriteExisting: Bool) async -> Bool {
    let document = session.document
    session.announce("Exporting...")
    switch await GIFDocumentIO.saveOffMain(
      document: document,
      to: target,
      overwriteExisting: overwriteExisting
    ) {
    case .needsOverwriteConfirmation:
      session.announce("Confirm overwrite before exporting")
      return false
    case .saved:
      session.announce("Exported GIF to \(target.path)")
      return true
    case .failed(let error):
      session.announce("Export failed: \(error)")
      return false
    }
  }

  var pendingAction: PendingDocumentAction? {
    switch state {
    case .awaitingDirtyDecision(let action):
      return action
    case .settling(let action):
      return action
    case .presenting(_, let suspended),
      .opening(_, let suspended, _),
      .saving(_, let suspended, _):
      return suspended
    case .ready, .quitArmed:
      return nil
    }
  }

  var fileSheet: FileSheet? {
    switch state {
    case .presenting(let sheet, _):
      return sheet
    case .opening(_, _, let sheet), .saving(_, _, let sheet):
      return sheet
    case .ready, .awaitingDirtyDecision, .settling, .quitArmed:
      return nil
    }
  }

  var isUnsavedChangesPresented: Bool {
    if case .awaitingDirtyDecision = state { return true }
    return false
  }

  var isOpening: Bool {
    if case .opening = state { return true }
    return false
  }

  var isSaving: Bool {
    if case .saving = state { return true }
    return false
  }

  var sourceURL: URL? {
    origin?.source.url
  }

  var documentTitle: String {
    projectBacking?.url.lastPathComponent
      ?? sourceURL?.lastPathComponent
      ?? "untitled"
  }

  var defaultExportURL: URL {
    GIFDocumentIO.defaultSaveURL(sourceURL: sourceURL)
  }

  var defaultProjectSaveURL: URL {
    GIFDocumentIO.defaultProjectSaveURL(
      sourceURL: sourceURL,
      backing: projectBacking?.url
    )
  }

  var saveFallThroughReason: String? {
    guard projectBacking == nil, let sourceURL else { return nil }
    return
      "\(sourceURL.lastPathComponent) is an import — saving there would flatten every layer."
  }

  var allowsQuit: Bool {
    guard case .quitArmed(let generation) = state else { return false }
    return generation == session.generation
  }

  var autosaveURL: URL {
    GIFDocumentIO.autosaveURL(inStateDirectory: stateDirectory)
  }

  @discardableResult
  func dispatch(
    _ intent: Intent,
    onTransition: @escaping @MainActor @Sendable () -> Void = {}
  ) async -> Outcome {
    let observerID = UUID()
    transitionObservers[observerID] = onTransition
    defer { transitionObservers[observerID] = nil }
    prepareForDispatch(intent)

    switch intent {
    case .request(let action):
      return await request(action)
    case .requestSave:
      guard state == .ready else { return .noChange }
      return await beginSave(suspended: nil)
    case .requestSaveAs:
      guard state == .ready else { return .noChange }
      transition(to: .presenting(.saveAs, suspended: nil))
      return .changed
    case .dirtyDecision(let decision):
      return await resolveDirtyDecision(decision)
    case .create(let size):
      guard case .presenting(.new, _) = state else { return .noChange }
      transition(to: .settling(.new))
      await settleAutosave()
      replaceSession(with: .blank(size: size), origin: nil, backing: nil)
      try? AutosaveStore.clear(at: autosaveURL)
      session.announce("New \(size.width)×\(size.height) document")
      transition(to: .ready)
      return .changed
    case .open(let url):
      let suspended: PendingDocumentAction?
      let presentedSheet: FileSheet?
      switch state {
      case .presenting(.open, let pending):
        suspended = pending
        presentedSheet = .open
      case .ready:
        suspended = nil
        presentedSheet = nil
      default:
        return .noChange
      }
      return await open(url, suspended: suspended, presentedSheet: presentedSheet)
    case .saveAs(let url, let overwriteExisting):
      guard case .presenting(.saveAs, let suspended) = state else { return .noChange }
      return await save(
        to: url,
        overwriteExisting: overwriteExisting,
        suspended: suspended,
        presentedSheet: .saveAs
      )
    case .cancelPresentation:
      switch state {
      case .presenting, .awaitingDirtyDecision:
        transition(to: .ready)
        openErrorMessage = nil
        return .changed
      case .ready, .settling, .opening, .saving, .quitArmed:
        return .noChange
      }
    case .autosave(let timestamp):
      guard
        state == .ready,
        session.isDirty,
        autosaveOperation == nil
      else {
        return .noChange
      }
      let document = session.document
      let originalPath = projectBacking?.url ?? sourceURL
      let target = autosaveURL
      let id = UUID()
      let writer = autosaveWriter
      let task = Task {
        try await writer(document, originalPath, target, timestamp)
      }
      autosaveOperation = (id, task)
      defer {
        if autosaveOperation?.id == id {
          autosaveOperation = nil
        }
      }
      do {
        try await task.value
        return .changed
      } catch {
        return .failed(String(describing: error))
      }
    }
  }

  private func request(_ action: PendingDocumentAction) async -> Outcome {
    guard state == .ready else { return .noChange }
    if session.isDirty {
      transition(to: .awaitingDirtyDecision(action))
      session.announce("Unsaved changes — save or discard before continuing")
      return .changed
    }
    return await perform(action)
  }

  private func resolveDirtyDecision(_ decision: DirtyDecision) async -> Outcome {
    guard case .awaitingDirtyDecision(let suspended) = state else { return .noChange }
    switch decision {
    case .save:
      return await beginSave(suspended: suspended)
    case .discard:
      return await perform(suspended)
    case .cancel:
      transition(to: .ready)
      return .changed
    }
  }

  private func perform(_ action: PendingDocumentAction) async -> Outcome {
    switch action {
    case .new:
      transition(to: .presenting(.new, suspended: nil))
      return .changed
    case .open:
      openErrorMessage = nil
      transition(to: .presenting(.open, suspended: nil))
      return .changed
    case .openRecent(let url):
      return await open(url, suspended: nil, presentedSheet: nil)
    case .quit:
      let target = autosaveURL
      transition(to: .settling(.quit))
      await settleAutosave()
      try? await Task.detached(priority: .utility) {
        try AutosaveStore.clear(at: target)
      }.value
      transition(to: .quitArmed(session.generation))
      session.announce("Changes discarded — press the exit key again to quit")
      return .readyToQuit
    }
  }

  private func beginSave(suspended: PendingDocumentAction?) async -> Outcome {
    guard let target = projectBacking?.url else {
      transition(to: .presenting(.saveAs, suspended: suspended))
      return .changed
    }
    return await save(
      to: target,
      overwriteExisting: true,
      suspended: suspended,
      presentedSheet: nil
    )
  }

  private func save(
    to target: URL,
    overwriteExisting: Bool,
    suspended: PendingDocumentAction?,
    presentedSheet: FileSheet?
  ) async -> Outcome {
    let snapshot = session.makeSaveSnapshot()
    transition(
      to: .saving(
        target,
        suspended: suspended,
        presentedSheet: presentedSheet
      )
    )
    await settleAutosave()
    session.announce("Saving…")
    let write = await GIFDocumentIO.saveProjectOffMain(
      document: snapshot.document,
      to: target,
      overwriteExisting: overwriteExisting
    )

    switch write {
    case .needsOverwriteConfirmation:
      session.announce("Confirm overwrite before saving")
      transition(to: .presenting(.saveAs, suspended: suspended))
      return .noChange
    case .failed(let error):
      session.announce("Save failed: \(error)")
      transition(
        to:
          suspended.map(State.awaitingDirtyDecision)
          ?? (presentedSheet == .saveAs ? .presenting(.saveAs, suspended: nil) : .ready)
      )
      return .failed(String(describing: error))
    case .saved:
      let acknowledgement = session.acknowledgeSave(snapshot)
      guard acknowledgement != .rejected else {
        session.announce("Ignored an obsolete save completion")
        transition(to: suspended.map(State.awaitingDirtyDecision) ?? .ready)
        return .noChange
      }
      projectBacking = ProjectBacking(target)
      origin = DocumentOrigin(source: .file(target), kind: .project)
      noteRecentDocument(target)
      if acknowledgement == .current {
        try? AutosaveStore.clear(at: autosaveURL)
        session.announce("Saved to \(target.path)")
        transition(to: .ready)
        if let suspended {
          return await perform(suspended)
        }
        return .changed
      }

      session.announce("Saved to \(target.path); newer changes remain unsaved")
      transition(to: suspended.map(State.awaitingDirtyDecision) ?? .ready)
      return .changed
    }
  }

  private func open(
    _ url: URL,
    suspended: PendingDocumentAction?,
    presentedSheet: FileSheet?
  ) async -> Outcome {
    transition(
      to: .opening(
        url,
        suspended: suspended,
        presentedSheet: presentedSheet
      )
    )
    await settleAutosave()
    openErrorMessage = nil
    session.announce("Opening \(url.lastPathComponent)…")
    do {
      let ingested = try await GIFDocumentIO.openIngestedOffMain(contentsOf: url)
      let backing = ingested.kind == .project ? ProjectBacking(url) : nil
      replaceSession(
        with: ingested.document,
        origin: DocumentOrigin(ingested.provenance),
        backing: backing
      )
      noteRecentDocument(url)
      try? AutosaveStore.clear(at: autosaveURL)
      session.announce("Opened \(url.path)")
      transition(to: .ready)
      return .changed
    } catch {
      let message = "Open failed: \(error)"
      session.announce(message)
      openErrorMessage = message
      transition(to: .presenting(.open, suspended: suspended))
      return .failed(message)
    }
  }

  private func replaceSession(
    with document: GIFDocument,
    origin: DocumentOrigin?,
    backing: ProjectBacking?,
    startsDirty: Bool = false
  ) {
    session = EditingSession(
      document: document,
      startsDirty: startsDirty
    )
    self.origin = origin
    projectBacking = backing
  }

  private func noteRecentDocument(_ url: URL) {
    recentDocuments.insert(url)
    try? recentDocuments.write(to: GIFDocumentIO.recentsURL(inStateDirectory: stateDirectory))
  }

  private func prepareForDispatch(_ intent: Intent) {
    guard case .quitArmed(let generation) = state else { return }
    if case .request(.quit) = intent, generation == session.generation {
      return
    }
    if case .autosave = intent, generation == session.generation {
      return
    }
    transition(to: .ready)
  }

  private func transition(to newState: State) {
    state = newState
    for observer in transitionObservers.values {
      observer()
    }
  }

  /// Waits for a snapshot already being written before a destructive file
  /// operation proceeds. `AutosaveStore.snapshot` is atomic but its encoder
  /// is synchronous, so cancellation is advisory; awaiting completion is
  /// what guarantees a later clear cannot be followed by a stale rename.
  private func settleAutosave() async {
    guard let operation = autosaveOperation else { return }
    operation.task.cancel()
    _ = try? await operation.task.value
    if autosaveOperation?.id == operation.id {
      autosaveOperation = nil
    }
  }

  private nonisolated static func prepareLaunch(
    path: String?,
    stateDirectory: URL
  ) -> LifecycleLaunchPreparation {
    let loaded: LifecycleLaunchPreparation
    if let path {
      let url = URL(fileURLWithPath: path)
      do {
        let ingested = try GIFDocumentIO.openIngested(contentsOf: url)
        loaded = LifecycleLaunchPreparation(
          document: ingested.document,
          origin: DocumentOrigin(ingested.provenance),
          projectBacking: ingested.kind == .project ? ProjectBacking(url) : nil,
          statusMessage: "Loaded \(url.path)",
          recoverySnapshot: nil,
          didOpenRequestedDocument: true
        )
      } catch {
        loaded = LifecycleLaunchPreparation(
          document: GIFDocument.blank(size: PixelSize(width: 32, height: 32)),
          origin: DocumentOrigin(source: .file(url)),
          projectBacking: nil,
          statusMessage: "Load failed: \(error)",
          recoverySnapshot: nil,
          didOpenRequestedDocument: false
        )
      }
    } else {
      loaded = LifecycleLaunchPreparation(
        document: GIFDocument.blank(size: PixelSize(width: 32, height: 32)),
        origin: nil,
        projectBacking: nil,
        statusMessage: "",
        recoverySnapshot: nil,
        didOpenRequestedDocument: false
      )
    }

    var prepared = loaded
    let autosaveURL = GIFDocumentIO.autosaveURL(inStateDirectory: stateDirectory)
    do {
      prepared.recoverySnapshot = try AutosaveStore.recover(from: autosaveURL)
    } catch {
      // Preserve damaged recovery bytes. Deleting the only copy of
      // unrecovered work is never a launch-time default.
      prepared.statusMessage =
        "Recovery file at \(autosaveURL.path) is damaged and was left in place — \(error)"
    }
    return prepared
  }
}

private struct LifecycleLaunchPreparation: Sendable {
  var document: GIFDocument
  var origin: DocumentOrigin?
  var projectBacking: ProjectBacking?
  var statusMessage: String
  var recoverySnapshot: AutosaveSnapshot?
  var didOpenRequestedDocument: Bool
}
