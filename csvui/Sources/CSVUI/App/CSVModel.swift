import Foundation
public import Observation

private enum PendingLifecycle: Sendable {
  case none
  case quit
  case reload
}

@Observable
@MainActor
public final class CSVModel {
  public private(set) var state: CSVState

  @ObservationIgnored private let rowCache = CSVRowCache()
  @ObservationIgnored private let projectionEngine = CSVProjectionEngine()
  @ObservationIgnored private let configuration: CSVModelConfiguration
  @ObservationIgnored private var history = CSVHistory()
  @ObservationIgnored private var nextInsertedRowID: UInt64 = 1
  @ObservationIgnored private var nextColumnID: Int
  @ObservationIgnored private var nextRevisionID: UInt64 = 1
  @ObservationIgnored private var backingBytes: Data
  @ObservationIgnored private var backingIdentity: CSVSourceIdentity?
  @ObservationIgnored private var writeBackAuthority: CSVWriteBackAuthority?
  @ObservationIgnored private var baseHeaderLabels: [ColumnID: String]
  @ObservationIgnored private var projectionGeneration: UInt64 = 0
  @ObservationIgnored private var searchGeneration: UInt64 = 0
  @ObservationIgnored private var searchMatchAddresses: Set<CSVCellAddress> = []
  @ObservationIgnored private var sourceLoadGeneration: UInt64 = 0
  @ObservationIgnored private var sourceWatcherGeneration: UInt64 = 0
  @ObservationIgnored private var themeLoadGeneration: UInt64 = 0
  @ObservationIgnored private var saveGeneration: UInt64 = 0
  @ObservationIgnored private var projectionTask: Task<Void, Never>?
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var sourceLoadTask: Task<Void, Never>?
  @ObservationIgnored private var sourceWatcherTask: Task<Void, Never>?
  @ObservationIgnored private var sourceWatcherReloadTask: Task<Void, Never>?
  @ObservationIgnored private var themeWatcherTask: Task<Void, Never>?
  @ObservationIgnored private var themeWatcherReloadTask: Task<Void, Never>?
  @ObservationIgnored private var themeLoadTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var pendingLifecycle: PendingLifecycle = .none
  @ObservationIgnored private var isShuttingDown = false

  public init(
    document: CSVDocument,
    theme: CSVTheme = .default,
    readOnly: Bool = false,
    initialDiagnostic: CSVDiagnostic? = nil,
    configuration: CSVModelConfiguration = CSVModelConfiguration()
  ) {
    self.configuration = configuration
    backingBytes = document.source.bytes
    backingIdentity = document.source.identity
    writeBackAuthority = document.source.writeBackAuthority
    baseHeaderLabels = Self.makeBaseHeaderLabels(document: document)
    state = CSVState(
      document: document,
      theme: theme,
      readOnly: readOnly,
      diagnostic: initialDiagnostic
    )
    nextColumnID = (document.columnIDs.map(\.rawValue).max() ?? -1) + 1
    sampleInitialWidths()
    if configuration.watchesDocument,
      case .regularFile(let url) = document.source.origin
    {
      startSourceWatcher(for: url)
    }
    if case .file(let url, _) = configuration.themeSelection {
      startThemeWatcher(for: url)
    }
  }

  public func send(_ action: CSVAction) {
    guard !isShuttingDown else { return }
    if state.isLoading {
      if case .updateViewport(let viewport) = action {
        state.viewport = viewport
      }
      return
    }
    switch action {
    case .updateViewport(let viewport):
      state.viewport = viewport
      revealCursor()
    case .selectCell(let address): select(address)
    case .moveRows(let amount): moveRows(amount)
    case .moveColumns(let amount): moveColumns(amount)
    case .pageRows(let pages): moveRows(pages * state.viewport.dataRowCapacity)
    case .scrollWheel(let deltaX, let deltaY):
      if deltaY != 0 { moveRows(deltaY) }
      if deltaX != 0 { moveColumns(deltaX) }
    case .firstRow: moveToRow(at: 0)
    case .lastRow: moveToRow(at: state.projection.visibleRows.count - 1)
    case .firstColumn: moveToColumn(at: 0)
    case .lastColumn: moveToColumn(at: state.projection.visibleColumns.count - 1)
    case .openMenu(let menu):
      state.mode = state.mode == .menu(menu) ? .browse : .menu(menu)
    case .dismissTransient:
      state.mode = .browse
      state.prompt = CSVPromptState()
      state.editor = CSVEditorState()
    case .openHelp: state.mode = .help
    case .openPalette:
      state.mode = .palette
      state.prompt = CSVPromptState()
    case .openRowDetail:
      if let row = state.cursor.row { state.mode = .rowDetail(row) }
    case .beginFind: beginPrompt(.find, initial: state.searchQuery)
    case .beginFilterCurrent:
      guard let column = state.cursor.column else { return }
      beginPrompt(.filterCurrent(column), initial: "")
    case .beginFilterAll: beginPrompt(.filterAll, initial: "")
    case .updatePrompt(let text):
      state.prompt.text = text
      state.prompt.diagnostic = projectionEngine.validate(query: text)
    case .submitPrompt: submitPrompt()
    case .nextMatch: moveSearchMatch(by: 1)
    case .previousMatch: moveSearchMatch(by: -1)
    case .clearFilter:
      state.projection.filter = nil
      recomputeProjection()
    case .cycleSort: cycleSort()
    case .sort(let direction):
      guard let column = state.cursor.column else { return }
      state.projection.sort = CSVSortSpec(column: column, direction: direction)
      recomputeProjection()
    case .clearSort:
      state.projection.sort = nil
      recomputeProjection()
    case .increaseWidth: adjustCurrentWidth(by: 2)
    case .decreaseWidth: adjustCurrentWidth(by: -2)
    case .resetWidth: resetCurrentWidth()
    case .freezeThroughCurrentColumn:
      state.projection.frozenThrough = state.cursor.column
      state.cursor.scrollingColumnOrigin = 0
    case .clearFrozenColumns:
      state.projection.frozenThrough = nil
      revealCursor()
    case .openColumns: state.mode = .columns
    case .toggleCurrentColumnVisibility: toggleCurrentColumnVisibility()
    case .toggleColumnVisibility(let column): toggleColumnVisibility(column)
    case .resetView: resetView()
    case .beginEditCell: beginEditCell()
    case .beginRenameHeader: beginRenameHeader()
    case .updateEditor(let text): state.editor.text = text
    case .commitEditor: commitEditor()
    case .insertRowAbove: insertRow(offset: 0)
    case .insertRowBelow: insertRow(offset: 1)
    case .deleteRow: deleteCurrentRow()
    case .insertColumnLeft: insertColumn(offset: 0)
    case .insertColumnRight: insertColumn(offset: 1)
    case .deleteColumn: deleteCurrentColumn()
    case .undo: undo()
    case .redo: redo()
    case .beginSaveAs:
      state.mode = .saveAs
      if state.saveAsPath.isEmpty {
        state.saveAsPath = state.document.source.displayName
      }
    case .updateSaveAsPath(let path): state.saveAsPath = path
    case .save:
      if case .confirmation(.dirtyQuit) = state.mode { pendingLifecycle = .quit }
      if case .confirmation(.dirtyReload) = state.mode { pendingLifecycle = .reload }
      save()
    case .confirmSaveAs(let overwrite):
      saveAs(overwrite: overwrite)
    case .reload:
      if state.isDirty {
        state.mode = .confirmation(.dirtyReload)
      } else {
        reloadSource()
      }
    case .confirmDiscard:
      switch state.mode {
      case .confirmation(.dirtyQuit):
        state.allowsNextTermination = true
        state.mode = .browse
        state.terminationRequestGeneration &+= 1
        state.diagnostic = CSVDiagnostic(.information, "discarding changes…")
      case .confirmation(.dirtyReload):
        state.mode = .browse
        reloadSource()
      default: state.mode = .browse
      }
    case .cancelConfirmation:
      pendingLifecycle = .none
      state.mode = .browse
    case .copySucceeded(let label):
      state.diagnostic = CSVDiagnostic(.information, "copied \(label)")
    case .copyFailed:
      state.diagnostic = CSVDiagnostic(.error, "clipboard unavailable")
    case .clearDiagnostic: state.diagnostic = nil
    }
  }

  public func value(row: RowID, column: ColumnID) -> String {
    if let replacement = state.journal.replacement(row: row, column: column) {
      return replacement
    }
    guard let base = originalColumnOffset(column) else {
      return ""
    }
    do {
      let decoded = try state.document.decodeSourceRow(row, cache: rowCache)
      return decoded?.fields.indices.contains(base) == true
        ? decoded!.fields[base].value
        : ""
    } catch {
      return ""
    }
  }

  public func displayValue(row: RowID, column: ColumnID) -> String {
    Self.visibleControlCharacters(value(row: row, column: column))
  }

  public func headerLabel(_ column: ColumnID) -> String {
    if let replacement = state.journal.headerReplacements[column] {
      return replacement.isEmpty ? "(empty)" : replacement
    }
    guard let label = baseHeaderLabels[column] else {
      let current = state.journal.columnOrder.firstIndex(of: column) ?? 0
      return "column_\(current + 1)"
    }
    return label
  }

  public func rawHeaderValue(_ column: ColumnID) -> String {
    if let replacement = state.journal.headerReplacements[column] { return replacement }
    guard let base = originalColumnOffset(column),
      let header = state.document.header,
      header.fields.indices.contains(base)
    else { return "" }
    return header.fields[base].value
  }

  public func rowLabel(_ row: RowID) -> String {
    switch row.storage {
    case .source(let source): return String(source + 1)
    case .inserted(let id): return "+\(id)"
    }
  }

  public func isEdited(row: RowID, column: ColumnID) -> Bool {
    state.journal.replacement(row: row, column: column) != nil
  }

  public func isSearchMatch(row: RowID, column: ColumnID) -> Bool {
    searchMatchAddresses.contains(CSVCellAddress(row: row, column: column))
  }

  public func copyCellText() -> String? {
    guard let row = state.cursor.row, let column = state.cursor.column else { return nil }
    return value(row: row, column: column)
  }

  public func copyRowText() -> String? {
    guard let row = state.cursor.row else { return nil }
    return try? CSVSerializer().serializeRow(
      row,
      document: state.document,
      journal: state.journal
    )
  }

  public func shouldAllowTermination() -> Bool {
    if state.allowsNextTermination {
      state.allowsNextTermination = false
      return true
    }
    guard state.isDirty else { return true }
    state.mode = .confirmation(.dirtyQuit)
    return false
  }

  public func announce(_ diagnostic: CSVDiagnostic) {
    state.diagnostic = diagnostic
  }

  @discardableResult
  public func requestQuitFromCommand() -> Bool {
    if state.isDirty {
      state.mode = .confirmation(.dirtyQuit)
      return false
    } else {
      state.terminationRequestGeneration &+= 1
      return true
    }
  }

  public func shutdown() async {
    guard !isShuttingDown else { return }
    isShuttingDown = true
    projectionGeneration &+= 1
    searchGeneration &+= 1
    sourceLoadGeneration &+= 1
    sourceWatcherGeneration &+= 1
    themeLoadGeneration &+= 1
    saveGeneration &+= 1
    projectionTask?.cancel()
    searchTask?.cancel()
    sourceLoadTask?.cancel()
    sourceWatcherTask?.cancel()
    sourceWatcherReloadTask?.cancel()
    themeWatcherTask?.cancel()
    themeWatcherReloadTask?.cancel()
    themeLoadTask?.cancel()
    saveTask?.cancel()
    let projectionTask = projectionTask
    let searchTask = searchTask
    let sourceLoadTask = sourceLoadTask
    let sourceWatcherTask = sourceWatcherTask
    let sourceWatcherReloadTask = sourceWatcherReloadTask
    let themeWatcherTask = themeWatcherTask
    let themeWatcherReloadTask = themeWatcherReloadTask
    let themeLoadTask = themeLoadTask
    let saveTask = saveTask
    self.projectionTask = nil
    self.searchTask = nil
    self.sourceLoadTask = nil
    self.sourceWatcherTask = nil
    self.sourceWatcherReloadTask = nil
    self.themeWatcherTask = nil
    self.themeWatcherReloadTask = nil
    self.themeLoadTask = nil
    self.saveTask = nil
    await projectionTask?.value
    await searchTask?.value
    await sourceLoadTask?.value
    await sourceWatcherTask?.value
    await sourceWatcherReloadTask?.value
    await themeWatcherTask?.value
    await themeWatcherReloadTask?.value
    await themeLoadTask?.value
    await saveTask?.value
  }

  public func waitForIdle() async {
    await projectionTask?.value
    await searchTask?.value
    await sourceLoadTask?.value
    await sourceWatcherReloadTask?.value
    await themeWatcherReloadTask?.value
    await themeLoadTask?.value
    await saveTask?.value
  }

  public func loadInitial(
    source: CSVSourceSnapshot,
    delimiter: CSVDelimiter,
    hasHeaders: Bool,
    initialDiagnostic: CSVDiagnostic? = nil
  ) {
    sourceLoadGeneration &+= 1
    let generation = sourceLoadGeneration
    sourceLoadTask?.cancel()
    state.isLoading = true
    state.diagnostic = CSVDiagnostic(.information, "loading \(source.displayName)…")
    sourceLoadTask = Task { [weak self] in
      let result: Result<CSVDocument, any Error> = await Task.detached {
        Result {
          try Task.checkCancellation()
          return try CSVDocument.parse(
            source: source,
            delimiter: delimiter,
            hasHeaders: hasHeaders
          )
        }
      }.value
      guard let self, !Task.isCancelled, generation == self.sourceLoadGeneration else { return }
      self.state.isLoading = false
      switch result {
      case .success(let document):
        self.commitInitialLoad(document, diagnostic: initialDiagnostic)
      case .failure(let error):
        self.state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func commitInitialLoad(
    _ document: CSVDocument,
    diagnostic: CSVDiagnostic?
  ) {
    state.document = document
    state.journal = CSVEditJournal(document: document)
    state.projection = CSVViewProjection(journal: state.journal)
    state.cursor = CSVCursor(
      row: state.journal.rowOrder.first,
      column: state.journal.columnOrder.first
    )
    rowCache.removeAll()
    history = CSVHistory()
    updateHistoryAvailability()
    state.currentRevision = 0
    state.cleanRevision = 0
    backingBytes = document.source.bytes
    backingIdentity = document.source.identity
    writeBackAuthority = document.source.writeBackAuthority
    baseHeaderLabels = Self.makeBaseHeaderLabels(document: document)
    nextColumnID = (document.columnIDs.map(\.rawValue).max() ?? -1) + 1
    sampleInitialWidths()
    state.diagnostic = diagnostic
    if configuration.watchesDocument,
      case .regularFile(let url) = document.source.origin
    {
      startSourceWatcher(for: url)
    }
  }

  private func save() {
    guard ensureMutable() else { return }
    guard !state.isSaving else { return }
    guard state.isDirty else {
      finishPendingLifecycleAfterSave()
      return
    }
    guard let authority = writeBackAuthority else {
      state.mode = .saveAs
      if state.saveAsPath.isEmpty { state.saveAsPath = state.document.source.displayName }
      state.diagnostic = CSVDiagnostic(.information, "choose a path for Save As")
      return
    }
    startSave(
      destination: authority.destination,
      expectedBytes: backingBytes,
      expectedIdentity: authority.identity,
      overwrite: true
    )
  }

  private func saveAs(overwrite: Bool) {
    guard ensureMutable(), !state.isSaving else { return }
    let trimmed = state.saveAsPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      state.diagnostic = CSVDiagnostic(.warning, "enter a Save As path")
      return
    }
    let destination = URL(
      fileURLWithPath: trimmed,
      relativeTo: configuration.workingDirectory
    ).standardizedFileURL
    if FileManager.default.fileExists(atPath: destination.path), !overwrite {
      state.mode = .confirmation(.overwrite(destination))
      return
    }
    startSave(
      destination: destination,
      expectedBytes: nil,
      expectedIdentity: nil,
      overwrite: overwrite
    )
  }

  private func startSave(
    destination: URL,
    expectedBytes: Data?,
    expectedIdentity: CSVSourceIdentity?,
    overwrite: Bool
  ) {
    saveGeneration &+= 1
    let generation = saveGeneration
    saveTask?.cancel()
    let document = state.document
    let journal = state.journal
    let revision = state.currentRevision
    state.isSaving = true
    state.mode = .browse
    state.diagnostic = CSVDiagnostic(.information, "saving…")
    saveTask = Task { [weak self] in
      let result: Result<(Data, CSVFileWriteResult), any Error> = await Task.detached {
        let bytes = try CSVSerializer().serialize(document: document, journal: journal)
        try Task.checkCancellation()
        let write = try CSVFileWriter().write(
          CSVFileWriteRequest(
            destination: destination,
            bytes: bytes,
            expectedBytes: expectedBytes,
            expectedIdentity: expectedIdentity,
            overwrite: overwrite
          )
        )
        return (bytes, write)
      }.result
      guard let self, !Task.isCancelled, generation == self.saveGeneration else { return }
      self.state.isSaving = false
      switch result {
      case .success(let (bytes, write)):
        self.commitSave(
          bytes: bytes,
          source: write.source,
          savedRevision: revision
        )
      case .failure(let error as CSVFileWriteError):
        self.failSave(error)
      case .failure(let error):
        self.state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func commitSave(
    bytes: Data,
    source: CSVSourceSnapshot,
    savedRevision: UInt64
  ) {
    backingBytes = bytes
    backingIdentity = source.identity
    writeBackAuthority = source.writeBackAuthority
    state.document.source.origin = source.origin
    state.document.source.displayName = source.displayName
    state.document.source.identity = source.identity
    state.document.source.writeBackAuthority = source.writeBackAuthority
    state.document.source.loadGeneration = source.loadGeneration
    state.cleanRevision = savedRevision
    state.externalChangePending = false
    state.saveAsPath = source.displayName
    state.diagnostic = CSVDiagnostic(
      .information,
      state.currentRevision == savedRevision
        ? "saved \(source.displayName)"
        : "saved revision \(savedRevision); newer edits remain"
    )
    if configuration.watchesDocument, case .regularFile(let url) = source.origin {
      startSourceWatcher(for: url)
    }
    finishPendingLifecycleAfterSave()
  }

  private func failSave(_ error: CSVFileWriteError) {
    switch error {
    case .sourceChanged:
      state.externalChangePending = true
      state.mode = .confirmation(.externalConflict)
      state.diagnostic = CSVDiagnostic(.warning, error.localizedDescription)
    case .destinationExists(let url):
      state.mode = .confirmation(.overwrite(url))
      state.diagnostic = CSVDiagnostic(.warning, error.localizedDescription)
    default:
      state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
    }
  }

  private func finishPendingLifecycleAfterSave() {
    switch pendingLifecycle {
    case .none:
      break
    case .quit:
      pendingLifecycle = .none
      state.mode = .browse
      state.terminationRequestGeneration &+= 1
      state.diagnostic = CSVDiagnostic(.information, "saved; quitting…")
    case .reload:
      pendingLifecycle = .none
      reloadSource()
    }
  }

  private func reloadSource() {
    reloadTheme()
    guard case .regularFile(let url) = state.document.source.origin else {
      state.diagnostic = CSVDiagnostic(.warning, "standard input cannot be reloaded")
      return
    }
    sourceLoadGeneration &+= 1
    let generation = sourceLoadGeneration
    sourceLoadTask?.cancel()
    let delimiter = state.document.dialect.delimiter
    let hasHeaders = state.document.dialect.hasHeaders
    state.isReloading = true
    state.diagnostic = CSVDiagnostic(.information, "reloading…")
    sourceLoadTask = Task { [weak self] in
      let result: Result<CSVDocument, any Error> = await Task.detached {
        let source = try CSVSourceReader().read(fileURL: url, generation: generation)
        try Task.checkCancellation()
        return try CSVDocument.parse(
          source: source,
          delimiter: delimiter,
          hasHeaders: hasHeaders
        )
      }.result
      guard let self, !Task.isCancelled, generation == self.sourceLoadGeneration else { return }
      self.state.isReloading = false
      switch result {
      case .success(let document): self.commitReload(document)
      case .failure(let error):
        self.state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func commitReload(_ document: CSVDocument) {
    if document.source.bytes == backingBytes {
      backingIdentity = document.source.identity
      writeBackAuthority = document.source.writeBackAuthority
      state.document.source.identity = document.source.identity
      state.document.source.writeBackAuthority = document.source.writeBackAuthority
      state.externalChangePending = false
      if state.diagnostic?.message == "reloading…" { state.diagnostic = nil }
      return
    }

    let oldProjection = state.projection
    let oldCursor = state.cursor
    state.document = document
    state.journal = CSVEditJournal(document: document)
    state.projection = CSVViewProjection(journal: state.journal)
    state.projection.hiddenColumns = oldProjection.hiddenColumns.intersection(
      Set(state.journal.columnOrder)
    )
    state.projection.frozenThrough = oldProjection.frozenThrough.flatMap {
      state.journal.columnOrder.contains($0) ? $0 : nil
    }
    state.projection.manualWidthOverrides = oldProjection.manualWidthOverrides.intersection(
      Set(state.journal.columnOrder)
    )
    state.projection.filter = oldProjection.filter
    state.projection.sort = oldProjection.sort
    state.cursor = CSVCursor(
      row: oldCursor.row.flatMap { state.journal.rowOrder.contains($0) ? $0 : nil }
        ?? state.journal.rowOrder.first,
      column: oldCursor.column.flatMap { state.journal.columnOrder.contains($0) ? $0 : nil }
        ?? state.journal.columnOrder.first,
      rowOrigin: oldCursor.rowOrigin,
      scrollingColumnOrigin: oldCursor.scrollingColumnOrigin
    )
    rowCache.removeAll()
    history = CSVHistory()
    updateHistoryAvailability()
    let revision = nextRevisionID
    nextRevisionID &+= 1
    state.currentRevision = revision
    state.cleanRevision = revision
    backingBytes = document.source.bytes
    backingIdentity = document.source.identity
    writeBackAuthority = document.source.writeBackAuthority
    baseHeaderLabels = Self.makeBaseHeaderLabels(document: document)
    state.externalChangePending = false
    state.diagnostic = CSVDiagnostic(.information, "reloaded \(document.source.displayName)")
    nextColumnID = (document.columnIDs.map(\.rawValue).max() ?? -1) + 1
    sampleInitialWidths()
    for (column, width) in oldProjection.widths where state.journal.columnOrder.contains(column) {
      state.projection.widths[column] = width
    }
    recomputeProjection()
  }

  private func startSourceWatcher(for url: URL) {
    sourceWatcherGeneration &+= 1
    let generation = sourceWatcherGeneration
    sourceWatcherTask?.cancel()
    sourceWatcherReloadTask?.cancel()
    let changes = CSVFileWatcher().changes(to: url)
    sourceWatcherTask = Task { [weak self] in
      for await _ in changes {
        guard let self, !Task.isCancelled,
          generation == self.sourceWatcherGeneration,
          !self.isShuttingDown
        else { return }
        self.scheduleSourceWatcherReload(generation: generation)
      }
    }
  }

  private func scheduleSourceWatcherReload(generation: UInt64) {
    sourceWatcherReloadTask?.cancel()
    sourceWatcherReloadTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      guard let self, !Task.isCancelled,
        generation == self.sourceWatcherGeneration,
        !self.isShuttingDown
      else { return }
      if self.state.isDirty || self.state.isSaving {
        self.state.externalChangePending = true
        self.state.diagnostic = CSVDiagnostic(.warning, "source changed outside csvui")
      } else {
        self.reloadSource()
      }
    }
  }

  private func startThemeWatcher(for url: URL) {
    themeWatcherTask?.cancel()
    themeWatcherReloadTask?.cancel()
    let changes = CSVFileWatcher().changes(to: url)
    themeWatcherTask = Task { [weak self] in
      for await _ in changes {
        guard let self, !Task.isCancelled, !self.isShuttingDown else { return }
        self.scheduleThemeReload()
      }
    }
  }

  private func scheduleThemeReload() {
    themeWatcherReloadTask?.cancel()
    themeWatcherReloadTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      guard let self, !Task.isCancelled, !self.isShuttingDown else { return }
      self.reloadTheme()
    }
  }

  private func reloadTheme() {
    guard case .file = configuration.themeSelection else { return }
    themeLoadGeneration &+= 1
    let generation = themeLoadGeneration
    themeLoadTask?.cancel()
    let selection = configuration.themeSelection
    themeLoadTask = Task { [weak self] in
      let result = await Task.detached { Result { try CSVThemeRepository().load(selection) } }.value
      guard let self, !Task.isCancelled, generation == self.themeLoadGeneration else { return }
      switch result {
      case .success(let loaded):
        self.state.theme = loaded.theme
        if case .file(let url, _) = selection,
          self.state.diagnostic?.severity == .error,
          self.state.diagnostic?.message.hasPrefix(url.path + ":") == true
        {
          self.state.diagnostic = nil
        }
      case .failure(let error):
        self.state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func beginPrompt(_ prompt: CSVPrompt, initial: String) {
    state.mode = .prompt(prompt)
    state.prompt = CSVPromptState(text: initial)
  }

  private func submitPrompt() {
    guard state.prompt.diagnostic == nil else { return }
    let text = state.prompt.text
    switch state.mode {
    case .prompt(.find):
      state.searchQuery = text
      state.mode = .browse
      beginSearch()
    case .prompt(.filterCurrent(let column)):
      state.projection.filter = CSVFilterSpec(scope: .column(column), query: text)
      state.mode = .browse
      recomputeProjection()
    case .prompt(.filterAll):
      state.projection.filter = CSVFilterSpec(scope: .allVisibleColumns, query: text)
      state.mode = .browse
      recomputeProjection()
    case .prompt(.renameHeader(let column)):
      guard ensureMutable() else { return }
      let old = headerLabel(column)
      let changed = performMutation(cost: old.utf8.count + text.utf8.count + 32) {
        $0.renameHeader(column, to: text)
      }
      if changed { incorporateEditedWidth(text, for: column) }
      state.mode = .browse
    default: break
    }
  }

  private func moveRows(_ amount: Int) {
    guard !state.projection.visibleRows.isEmpty else { return }
    let current = state.cursor.row.flatMap(visibleRowOffset) ?? 0
    moveToRow(at: current + amount)
  }

  private func moveToRow(at index: Int) {
    guard !state.projection.visibleRows.isEmpty else {
      state.cursor.row = nil
      return
    }
    state.cursor.row =
      state.projection.visibleRows[
        min(max(0, index), state.projection.visibleRows.count - 1)
      ]
    revealCursor()
  }

  private func moveColumns(_ amount: Int) {
    guard !state.projection.visibleColumns.isEmpty else { return }
    let current =
      state.cursor.column.flatMap {
        state.projection.visibleColumns.firstIndex(of: $0)
      } ?? 0
    moveToColumn(at: current + amount)
  }

  private func moveToColumn(at index: Int) {
    guard !state.projection.visibleColumns.isEmpty else {
      state.cursor.column = nil
      return
    }
    state.cursor.column =
      state.projection.visibleColumns[
        min(max(0, index), state.projection.visibleColumns.count - 1)
      ]
    revealCursor()
  }

  private func revealCursor() {
    if let row = state.cursor.row,
      let rowIndex = visibleRowOffset(row)
    {
      let capacity = state.viewport.dataRowCapacity
      if rowIndex < state.cursor.rowOrigin { state.cursor.rowOrigin = rowIndex }
      if rowIndex >= state.cursor.rowOrigin + capacity {
        state.cursor.rowOrigin = rowIndex - capacity + 1
      }
      state.cursor.rowOrigin = min(
        state.cursor.rowOrigin,
        max(0, state.projection.visibleRows.count - capacity)
      )
    }
    guard let column = state.cursor.column,
      let index = state.projection.visibleColumns.firstIndex(of: column)
    else { return }
    let frozenCount = currentFrozenColumnCount()
    if index < frozenCount { return }
    let scrollingIndex = index - frozenCount
    if scrollingIndex < state.cursor.scrollingColumnOrigin {
      state.cursor.scrollingColumnOrigin = scrollingIndex
    }
  }

  private func currentFrozenColumnCount() -> Int {
    guard let frozen = state.projection.frozenThrough,
      let index = state.projection.visibleColumns.firstIndex(of: frozen)
    else { return 0 }
    return index + 1
  }

  private func beginSearch() {
    searchGeneration &+= 1
    let generation = searchGeneration
    searchTask?.cancel()
    guard !state.searchQuery.isEmpty else {
      state.searchMatches = []
      searchMatchAddresses = []
      state.selectedSearchMatch = nil
      state.searchResultsTruncated = false
      state.isSearching = false
      return
    }
    state.searchMatches = []
    searchMatchAddresses = []
    state.selectedSearchMatch = nil
    state.isSearching = true
    let snapshot = CSVScanSnapshot(document: state.document, journal: state.journal)
    let rows = state.projection.visibleRows
    let columns = state.projection.visibleColumns
    let query = state.searchQuery
    searchTask = Task { [weak self] in
      let result: Result<CSVSearchResultSet, any Error> = await Task.detached {
        do {
          return .success(
            try await CSVProjectionEngine().search(
              snapshot: snapshot,
              rows: rows,
              columns: columns,
              query: query
            )
          )
        } catch {
          return .failure(error)
        }
      }.value
      guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
      self.state.isSearching = false
      switch result {
      case .success(let set):
        self.state.searchMatches = set.matches
        self.searchMatchAddresses = Set(set.matches.map(\.address))
        self.state.searchResultsTruncated = set.isTruncated
        self.state.selectedSearchMatch = set.matches.isEmpty ? nil : 0
        if let first = set.matches.first { self.select(first.address) }
      case .failure(let error):
        self.searchMatchAddresses = []
        self.state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func moveSearchMatch(by amount: Int) {
    guard !state.searchMatches.isEmpty else { return }
    let current = state.selectedSearchMatch ?? 0
    let count = state.searchMatches.count
    let next = (current + amount % count + count) % count
    state.selectedSearchMatch = next
    select(state.searchMatches[next].address)
  }

  private func select(_ address: CSVCellAddress) {
    guard visibleRowOffset(address.row) != nil,
      state.projection.visibleColumns.contains(address.column)
    else { return }
    state.cursor.row = address.row
    state.cursor.column = address.column
    revealCursor()
  }

  private func recomputeProjection() {
    projectionGeneration &+= 1
    let generation = projectionGeneration
    projectionTask?.cancel()
    let previousRows = state.projection.visibleRows
    let previousRowIndex = state.cursor.row.flatMap { previousRows.firstIndex(of: $0) } ?? 0
    let previousRow = state.cursor.row
    let previousColumn = state.cursor.column
    let snapshot = CSVScanSnapshot(document: state.document, journal: state.journal)
    let baseRows = state.journal.rowOrder
    let columns = state.journal.columnOrder.filter { !state.projection.hiddenColumns.contains($0) }
    let filter = state.projection.filter
    let sort = state.projection.sort
    state.projection.visibleColumns = columns
    state.isFiltering = filter != nil
    state.isSorting = sort != nil

    projectionTask = Task { [weak self] in
      let result = await Task.detached {
        do {
          var rows = baseRows
          if let filter {
            rows = try await CSVProjectionEngine().filter(
              snapshot: snapshot,
              rows: rows,
              visibleColumns: columns,
              spec: filter
            )
          }
          if let sort {
            rows = try await CSVProjectionEngine().sort(
              snapshot: snapshot,
              rows: rows,
              spec: sort
            )
          }
          return Result<[RowID], any Error>.success(rows)
        } catch {
          return Result<[RowID], any Error>.failure(error)
        }
      }.value
      guard let self, !Task.isCancelled, generation == self.projectionGeneration else { return }
      self.state.isFiltering = false
      self.state.isSorting = false
      switch result {
      case .success(let rows):
        self.state.projection.visibleRows = rows
        if let previousRow, rows.contains(previousRow) {
          self.state.cursor.row = previousRow
        } else if !rows.isEmpty {
          self.state.cursor.row = rows[min(previousRowIndex, rows.count - 1)]
        } else {
          self.state.cursor.row = nil
        }
        if let previousColumn, columns.contains(previousColumn) {
          self.state.cursor.column = previousColumn
        } else {
          self.state.cursor.column = columns.first
        }
        self.revealCursor()
        self.beginSearch()
      case .failure(let error):
        self.state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func cycleSort() {
    guard let column = state.cursor.column else { return }
    if state.projection.sort?.column != column {
      state.projection.sort = CSVSortSpec(column: column, direction: .ascending)
    } else if state.projection.sort?.direction == .ascending {
      state.projection.sort = CSVSortSpec(column: column, direction: .descending)
    } else {
      state.projection.sort = nil
    }
    recomputeProjection()
  }

  private func adjustCurrentWidth(by amount: Int) {
    guard let column = state.cursor.column else { return }
    let current = state.projection.widths[column] ?? 12
    state.projection.widths[column] = min(40, max(4, current + amount))
    state.projection.manualWidthOverrides.insert(column)
  }

  private func resetCurrentWidth() {
    guard let column = state.cursor.column else { return }
    state.projection.manualWidthOverrides.remove(column)
    state.projection.widths[column] = sampledWidth(for: column)
  }

  private func toggleCurrentColumnVisibility() {
    guard let column = state.cursor.column else { return }
    toggleColumnVisibility(column)
  }

  private func toggleColumnVisibility(_ column: ColumnID) {
    if state.projection.hiddenColumns.contains(column) {
      state.projection.hiddenColumns.remove(column)
    } else {
      guard state.projection.visibleColumns.count > 1 else {
        state.diagnostic = CSVDiagnostic(.warning, "at least one column must remain visible")
        return
      }
      state.projection.hiddenColumns.insert(column)
    }
    recomputeProjection()
  }

  private func resetView() {
    searchGeneration &+= 1
    searchTask?.cancel()
    state.projection.filter = nil
    state.projection.sort = nil
    state.projection.hiddenColumns = []
    state.projection.frozenThrough = nil
    state.projection.manualWidthOverrides = []
    sampleInitialWidths()
    state.searchQuery = ""
    state.searchMatches = []
    searchMatchAddresses = []
    state.selectedSearchMatch = nil
    state.searchResultsTruncated = false
    state.isSearching = false
    recomputeProjection()
  }

  private func beginEditCell() {
    guard ensureMutable(), let row = state.cursor.row, let column = state.cursor.column else {
      return
    }
    let address = CSVCellAddress(row: row, column: column)
    state.editor = CSVEditorState(text: value(row: row, column: column))
    state.mode = .editing(address)
  }

  private func beginRenameHeader() {
    guard ensureMutable() else { return }
    guard state.document.dialect.hasHeaders, let column = state.cursor.column else {
      state.diagnostic = CSVDiagnostic(.warning, "Rename Header requires a header record")
      return
    }
    beginPrompt(.renameHeader(column), initial: rawHeaderValue(column))
  }

  private func commitEditor() {
    guard case .editing(let address) = state.mode, ensureMutable() else { return }
    let old = value(row: address.row, column: address.column)
    let text = state.editor.text
    let changed = performMutation(cost: old.utf8.count + text.utf8.count + 64) {
      $0.replace(row: address.row, column: address.column, with: text)
    }
    if changed { incorporateEditedWidth(text, for: address.column) }
    state.mode = .browse
    state.editor = CSVEditorState()
  }

  private func insertRow(offset: Int) {
    guard ensureMutable() else { return }
    guard state.projection.filter == nil, state.projection.sort == nil else {
      state.diagnostic = CSVDiagnostic(.warning, "clear filter and sort before inserting a row")
      return
    }
    let current =
      state.cursor.row.flatMap { state.journal.rowOrder.firstIndex(of: $0) }
      ?? state.journal.rowOrder.count
    let id = RowID(insertedID: nextInsertedRowID)
    let cost = structuralRowCost()
    guard performMutation(cost: cost, { $0.insertRow(id, at: current + offset) }) else { return }
    nextInsertedRowID &+= 1
    state.cursor.row = id
  }

  private func deleteCurrentRow() {
    guard ensureMutable(), let row = state.cursor.row else { return }
    _ = performMutation(cost: structuralRowCost()) { _ = $0.deleteRow(row) }
  }

  private func insertColumn(offset: Int) {
    guard ensureMutable() else { return }
    let current =
      state.cursor.column.flatMap { state.journal.columnOrder.firstIndex(of: $0) }
      ?? state.journal.columnOrder.count
    let id = ColumnID(nextColumnID)
    guard
      performMutation(
        cost: structuralColumnCost(),
        {
          $0.insertColumn(id, at: current + offset)
        })
    else { return }
    nextColumnID += 1
    state.cursor.column = id
    state.projection.widths[id] = 12
  }

  private func deleteCurrentColumn() {
    guard ensureMutable(), let column = state.cursor.column else { return }
    _ = performMutation(cost: structuralColumnCost()) { _ = $0.deleteColumn(column) }
  }

  @discardableResult
  private func performMutation(
    cost: Int,
    _ mutation: (inout CSVEditJournal) -> Void
  ) -> Bool {
    guard cost <= CSVHistory.maximumBytes else {
      state.diagnostic = CSVDiagnostic(.warning, "edit cannot fit in the undo history budget")
      return false
    }
    let before = state.journal
    var after = before
    mutation(&after)
    guard after != before else { return false }
    let previousRevision = state.currentRevision
    let nextRevision = nextRevisionID
    nextRevisionID &+= 1
    let entry = CSVHistory.Entry(
      before: before,
      after: after,
      revisionBefore: previousRevision,
      revisionAfter: nextRevision,
      byteCost: max(1, cost)
    )
    guard history.record(entry) else {
      state.diagnostic = CSVDiagnostic(.warning, "edit cannot fit in the undo history budget")
      return false
    }
    state.journal = after
    state.currentRevision = nextRevision
    updateHistoryAvailability()
    recomputeProjection()
    return true
  }

  private func undo() {
    guard let entry = history.undo() else { return }
    state.journal = entry.before
    state.currentRevision = entry.revisionBefore
    updateHistoryAvailability()
    recomputeProjection()
  }

  private func redo() {
    guard let entry = history.redo() else { return }
    state.journal = entry.after
    state.currentRevision = entry.revisionAfter
    updateHistoryAvailability()
    recomputeProjection()
  }

  private func updateHistoryAvailability() {
    state.undoAvailable = !history.undoEntries.isEmpty
    state.redoAvailable = !history.redoEntries.isEmpty
  }

  private func ensureMutable() -> Bool {
    guard !state.readOnly else {
      state.diagnostic = CSVDiagnostic(.warning, "read-only mode disables editing")
      return false
    }
    return true
  }

  private func structuralRowCost() -> Int {
    let (bytes, overflow) = state.journal.rowOrder.count.multipliedReportingOverflow(
      by: MemoryLayout<RowID>.stride
    )
    return overflow ? .max : bytes + 256
  }

  private func structuralColumnCost() -> Int {
    let (bytes, overflow) = state.journal.columnOrder.count.multipliedReportingOverflow(
      by: MemoryLayout<ColumnID>.stride
    )
    return overflow ? .max : bytes + 256
  }

  private func sampleInitialWidths() {
    var widths: [ColumnID: Int] = [:]
    let columns = state.journal.columnOrder
    for column in columns { widths[column] = min(40, max(4, headerLabel(column).count + 2)) }
    let sampleCount = min(1_000, state.document.dataRecordCount)
    for rowIndex in 0..<sampleCount {
      let row = RowID(sourceIndex: rowIndex)
      guard let decoded = try? state.document.decodeSourceRow(row) else { continue }
      for (base, field) in decoded.fields.enumerated()
      where state.journal.originalColumnOrder.indices.contains(base) {
        let column = state.journal.originalColumnOrder[base]
        let width = Self.visibleControlCharacters(field.value).count + 2
        widths[column] = min(40, max(widths[column, default: 4], width))
      }
    }
    state.projection.widths = widths
    state.counters.widthSamples = sampleCount
  }

  private func sampledWidth(for column: ColumnID) -> Int {
    var width = min(40, max(4, headerLabel(column).count + 2))
    let sampleCount = min(1_000, state.document.dataRecordCount)
    for rowIndex in 0..<sampleCount {
      let value = value(row: RowID(sourceIndex: rowIndex), column: column)
      width = min(40, max(width, Self.visibleControlCharacters(value).count + 2))
    }
    return width
  }

  private func incorporateEditedWidth(_ value: String, for column: ColumnID) {
    guard !state.projection.manualWidthOverrides.contains(column) else { return }
    let displayWidth = Self.visibleControlCharacters(value).count + 2
    let current = state.projection.widths[column, default: 4]
    state.projection.widths[column] = min(40, max(current, max(4, displayWidth)))
  }

  private static func visibleControlCharacters(_ source: String) -> String {
    var result = ""
    for scalar in source.unicodeScalars {
      switch scalar.value {
      case 0x09: result.append("⇥")
      case 0x0A: result.append("↵")
      case 0x0D: result.append("␍")
      case 0x00...0x1F, 0x7F: result.append("�")
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  private func originalColumnOffset(_ column: ColumnID) -> Int? {
    let offset = column.rawValue
    guard state.journal.originalColumnOrder.indices.contains(offset),
      state.journal.originalColumnOrder[offset] == column
    else { return nil }
    return offset
  }

  private func visibleRowOffset(_ row: RowID) -> Int? {
    if state.projection.filter == nil,
      state.projection.sort == nil,
      state.journal.insertedRows.isEmpty,
      state.journal.rowOrder.count == state.document.dataRecordCount,
      let sourceIndex = row.sourceIndex,
      state.projection.visibleRows.indices.contains(sourceIndex),
      state.projection.visibleRows[sourceIndex] == row
    {
      return sourceIndex
    }
    return state.projection.visibleRows.firstIndex(of: row)
  }

  private static func makeBaseHeaderLabels(document: CSVDocument) -> [ColumnID: String] {
    var labels: [ColumnID: String] = [:]
    labels.reserveCapacity(document.columnIDs.count)
    var duplicateCounts: [String: Int] = [:]
    for (offset, column) in document.columnIDs.enumerated() {
      guard document.dialect.hasHeaders,
        let header = document.header,
        header.fields.indices.contains(offset),
        !header.fields[offset].value.isEmpty
      else {
        labels[column] = "column_\(offset + 1)"
        continue
      }
      let value = header.fields[offset].value
      let duplicate = duplicateCounts[value, default: 0]
      labels[column] = duplicate == 0 ? value : "\(value) [\(duplicate + 1)]"
      duplicateCounts[value] = duplicate + 1
    }
    return labels
  }
}
