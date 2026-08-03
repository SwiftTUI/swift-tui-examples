import Foundation
public import Observation

private enum PendingLifecycle: Sendable {
  case none
  case quit
  case reload
}

private struct CSVProjectionComputation: Sendable {
  let rows: [RowID]
  let rowOrdinalIndex: CSVRowOrdinalIndex?
  let sharesJournalOrder: Bool
}

struct CSVRowOrdinalIndex: Sendable {
  static let maximumBytes = CSVProjectionEngine.maximumWorkspaceBytes
  private static let missingSourceOrdinal = Int32.min
  private static let insertedEntryBudgetBytes = 64

  private let sourceOrdinals: ContiguousArray<Int32>
  private let insertedOrdinals: [UInt64: Int32]
  let storageByteCount: Int

  init(rows: [RowID], maximumBytes: Int = Self.maximumBytes) throws {
    var largestSourceIndex = -1
    var insertedCount = 0
    for row in rows {
      switch row.storage {
      case .source(let sourceIndex):
        largestSourceIndex = max(largestSourceIndex, sourceIndex)
      case .inserted:
        insertedCount += 1
      }
    }

    let sourceSlotCount = largestSourceIndex.addingReportingOverflow(1)
    let sourceBytes = sourceSlotCount.partialValue.multipliedReportingOverflow(
      by: MemoryLayout<Int32>.stride
    )
    let insertedBytes = insertedCount.multipliedReportingOverflow(
      by: Self.insertedEntryBudgetBytes
    )
    let totalBytes = sourceBytes.partialValue.addingReportingOverflow(insertedBytes.partialValue)
    guard largestSourceIndex >= -1,
      rows.count <= Int(Int32.max),
      !sourceSlotCount.overflow,
      !sourceBytes.overflow,
      !insertedBytes.overflow,
      !totalBytes.overflow,
      totalBytes.partialValue <= maximumBytes
    else {
      throw CSVProjectionError.workspaceLimit
    }

    var sourceOrdinals = ContiguousArray(
      repeating: Self.missingSourceOrdinal,
      count: sourceSlotCount.partialValue
    )
    var insertedOrdinals: [UInt64: Int32] = [:]
    insertedOrdinals.reserveCapacity(insertedCount)
    for (ordinal, row) in rows.enumerated() {
      let compactOrdinal = Int32(ordinal)
      switch row.storage {
      case .source(let sourceIndex):
        guard sourceOrdinals.indices.contains(sourceIndex) else {
          throw CSVProjectionError.workspaceLimit
        }
        sourceOrdinals[sourceIndex] = compactOrdinal
      case .inserted(let insertedID):
        insertedOrdinals[insertedID] = compactOrdinal
      }
    }

    self.sourceOrdinals = sourceOrdinals
    self.insertedOrdinals = insertedOrdinals
    storageByteCount = totalBytes.partialValue
  }

  func ordinal(for row: RowID) -> Int? {
    switch row.storage {
    case .source(let sourceIndex):
      guard sourceOrdinals.indices.contains(sourceIndex) else { return nil }
      let ordinal = sourceOrdinals[sourceIndex]
      return ordinal == Self.missingSourceOrdinal ? nil : Int(ordinal)
    case .inserted(let insertedID):
      return insertedOrdinals[insertedID].map(Int.init)
    }
  }
}

private struct PresentationInvalidation: OptionSet {
  let rawValue: UInt8

  static let rootStyle = Self(rawValue: 1 << 0)
  static let toolbar = Self(rawValue: 1 << 1)
  static let gridContent = Self(rawValue: 1 << 2)
  static let gridSelection = Self(rawValue: 1 << 3)
  static let status = Self(rawValue: 1 << 4)
  static let overlay = Self(rawValue: 1 << 5)
  static let termination = Self(rawValue: 1 << 6)
  static let rootFocus = Self(rawValue: 1 << 7)
  static let content: Self = [
    .rootStyle, .toolbar, .gridContent, .status, .overlay, .termination, .rootFocus,
  ]
  static let cursor: Self = [.gridSelection, .status, .overlay]
  static let all: Self = [.content, .cursor]
}

@Observable
@MainActor
public final class CSVModel {
  @ObservationIgnored private var _state: CSVState {
    didSet {
      publicStateRevision &+= 1
      if !defersPresentationInvalidation { invalidatePresentations(.all) }
    }
  }

  public var state: CSVState {
    _ = publicStateRevision
    return _state
  }

  private var publicStateRevision: UInt64 = 0
  private(set) var rootStyleRevision: UInt64 = 0
  private(set) var toolbarRevision: UInt64 = 0
  private(set) var gridContentRevision: UInt64 = 0
  private(set) var gridSelectionRevision: UInt64 = 0
  private(set) var statusRevision: UInt64 = 0
  private(set) var overlayRevision: UInt64 = 0
  private(set) var terminationRevision: UInt64 = 0
  private(set) var rootFocusRevision: UInt64 = 0

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
  @ObservationIgnored private var initialWidthSample: CSVInitialWidthSample
  @ObservationIgnored private var pendingLoadMetrics: CSVLoadPhaseMetrics? = nil
  @ObservationIgnored private var loadMetricsStartedAt: ContinuousClock.Instant? = nil
  @ObservationIgnored private var projectionGeneration: UInt64 = 0
  @ObservationIgnored private var searchGeneration: UInt64 = 0
  @ObservationIgnored private var searchMatchAddresses: Set<CSVCellAddress> = []
  @ObservationIgnored private var journalRowOrdinalIndex: CSVRowOrdinalIndex? = nil
  @ObservationIgnored private var journalColumnOrdinals: [ColumnID: Int]? = nil
  @ObservationIgnored private var projectedRowOrdinalIndex: CSVRowOrdinalIndex? = nil
  @ObservationIgnored private var projectionSharesJournalOrder = true
  @ObservationIgnored private var projectedColumnOrdinals: [ColumnID: Int] = [:]
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
  @ObservationIgnored private var defersPresentationInvalidation = false
  @ObservationIgnored private var documentLoader:
    @Sendable (CSVSourceSnapshot, CSVDelimiter, Bool) throws -> CSVDocumentLoadResult = {
      try CSVDocument.load(source: $0, delimiter: $1, hasHeaders: $2)
    }

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
    initialWidthSample =
      (try? document.initialWidthSample())
      ?? CSVInitialWidthSample(widths: [:], sampleCount: 0)
    _state = CSVState(
      document: document,
      theme: theme,
      readOnly: readOnly,
      diagnostic: initialDiagnostic
    )
    nextColumnID = (document.columnIDs.map(\.rawValue).max() ?? -1) + 1
    refreshJournalOrdinalCaches()
    refreshProjectedColumnOrdinals()
    applyInitialWidthSample(initialWidthSample)
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
    if _state.isLoading {
      if case .updateViewport(let viewport) = action {
        _state.viewport = viewport
      }
      return
    }
    switch action {
    case .updateViewport(let viewport):
      _state.viewport = viewport
      revealCursor()
    case .selectCell, .moveRows, .moveColumns, .pageRows, .scrollWheel, .firstRow, .lastRow,
      .firstColumn, .lastColumn:
      performFastNavigation { applyFastNavigationAction(action) }
    case .openMenu(let menu):
      _state.mode = _state.mode == .menu(menu) ? .browse : .menu(menu)
    case .dismissTransient:
      _state.mode = .browse
      _state.prompt = CSVPromptState()
      _state.editor = CSVEditorState()
    case .openHelp: _state.mode = .help
    case .openPalette:
      _state.mode = .palette
      _state.prompt = CSVPromptState()
    case .openRowDetail:
      if let row = _state.cursor.row { _state.mode = .rowDetail(row) }
    case .beginFind: beginPrompt(.find, initial: _state.searchQuery)
    case .beginFilterCurrent:
      guard let column = _state.cursor.column else { return }
      beginPrompt(.filterCurrent(column), initial: "")
    case .beginFilterAll: beginPrompt(.filterAll, initial: "")
    case .updatePrompt(let text):
      _state.prompt.text = text
      _state.prompt.diagnostic = projectionEngine.validate(query: text)
    case .submitPrompt: submitPrompt()
    case .nextMatch: moveSearchMatch(by: 1)
    case .previousMatch: moveSearchMatch(by: -1)
    case .clearFilter:
      _state.projection.filter = nil
      recomputeProjection()
    case .cycleSort: cycleSort()
    case .sort(let direction):
      guard let column = _state.cursor.column else { return }
      _state.projection.sort = CSVSortSpec(column: column, direction: direction)
      recomputeProjection()
    case .clearSort:
      _state.projection.sort = nil
      recomputeProjection()
    case .increaseWidth: adjustCurrentWidth(by: 2)
    case .decreaseWidth: adjustCurrentWidth(by: -2)
    case .resetWidth: resetCurrentWidth()
    case .freezeThroughCurrentColumn:
      _state.projection.frozenThrough = _state.cursor.column
      _state.cursor.scrollingColumnOrigin = 0
    case .clearFrozenColumns:
      _state.projection.frozenThrough = nil
      revealCursor()
    case .openColumns: _state.mode = .columns
    case .toggleCurrentColumnVisibility: toggleCurrentColumnVisibility()
    case .toggleColumnVisibility(let column): toggleColumnVisibility(column)
    case .resetView: resetView()
    case .beginEditCell: beginEditCell()
    case .beginRenameHeader: beginRenameHeader()
    case .updateEditor(let text): updateLocalEditorText(text)
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
      _state.mode = .saveAs
      if _state.saveAsPath.isEmpty {
        _state.saveAsPath = _state.document.source.displayName
      }
    case .updateSaveAsPath(let path): _state.saveAsPath = path
    case .save:
      if case .confirmation(.dirtyQuit) = _state.mode { pendingLifecycle = .quit }
      if case .confirmation(.dirtyReload) = _state.mode { pendingLifecycle = .reload }
      save()
    case .confirmSaveAs(let overwrite):
      saveAs(overwrite: overwrite)
    case .reload:
      if _state.isDirty {
        _state.mode = .confirmation(.dirtyReload)
      } else {
        reloadSource()
      }
    case .confirmDiscard:
      switch _state.mode {
      case .confirmation(.dirtyQuit):
        _state.allowsNextTermination = true
        _state.mode = .browse
        _state.terminationRequestGeneration &+= 1
        _state.diagnostic = CSVDiagnostic(.information, "discarding changes…")
      case .confirmation(.dirtyReload):
        _state.mode = .browse
        reloadSource()
      default: _state.mode = .browse
      }
    case .cancelConfirmation:
      pendingLifecycle = .none
      _state.mode = .browse
    case .copySucceeded(let label):
      _state.diagnostic = CSVDiagnostic(.information, "copied \(label)")
    case .copyFailed:
      _state.diagnostic = CSVDiagnostic(.error, "clipboard unavailable")
    case .clearDiagnostic: _state.diagnostic = nil
    }
  }

  public func value(row: RowID, column: ColumnID) -> String {
    if let replacement = _state.journal.replacement(row: row, column: column) {
      return replacement
    }
    guard let base = originalColumnOffset(column) else {
      return ""
    }
    do {
      let decoded = try _state.document.decodeSourceRow(row, cache: rowCache)
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
    if let replacement = _state.journal.headerReplacements[column] {
      return replacement.isEmpty ? "(empty)" : replacement
    }
    guard let label = baseHeaderLabels[column] else {
      let current = journalColumnOffset(column) ?? 0
      return "column_\(current + 1)"
    }
    return label
  }

  public func rawHeaderValue(_ column: ColumnID) -> String {
    if let replacement = _state.journal.headerReplacements[column] { return replacement }
    guard let base = originalColumnOffset(column),
      let header = _state.document.header,
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
    _state.journal.replacement(row: row, column: column) != nil
  }

  public func isSearchMatch(row: RowID, column: ColumnID) -> Bool {
    searchMatchAddresses.contains(CSVCellAddress(row: row, column: column))
  }

  func gridPresentation() -> CSVGridPresentation {
    _ = gridContentRevision
    if var metrics = pendingLoadMetrics,
      let started = loadMetricsStartedAt,
      !_state.isLoading,
      !_state.projection.visibleRows.isEmpty
    {
      metrics.firstPopulatedPresentationNanoseconds = CSVLoadMetrics.nanoseconds(
        started.duration(to: .now)
      )
      pendingLoadMetrics = nil
      loadMetricsStartedAt = nil
      CSVLoadMetrics.emit(metrics)
    }
    let input = CSVGridLayoutInput(
      visibleRows: _state.projection.visibleRows,
      visibleColumns: _state.projection.visibleColumns,
      frozenThroughOrdinal: _state.projection.frozenThrough.flatMap(visibleColumnOffset),
      widths: _state.projection.widths,
      rowOrigin: _state.cursor.rowOrigin,
      scrollingColumnOrigin: _state.cursor.scrollingColumnOrigin,
      selectedColumnOrdinal: _state.cursor.column.flatMap(visibleColumnOffset),
      viewport: _state.viewport,
      dataRecordCount: _state.document.dataRecordCount,
      widthSamples: _state.counters.widthSamples
    )
    let slice = CSVGridLayout.slice(input: input)
    let columns = slice.allColumns
    let headerCells = columns.map { column in
      let marker =
        _state.projection.sort?.column == column
        ? " \(_state.projection.sort!.direction.marker)"
        : ""
      return CSVGridCellPresentation(
        id: .header(column),
        address: nil,
        projectedRowOrdinal: nil,
        projectedColumnOrdinal: visibleColumnOffset(column) ?? 0,
        text: " " + headerLabel(column) + marker,
        width: slice.widths[column, default: 4],
        role: .header,
        foreground: _state.theme.headerForeground,
        background: _state.theme.headerBackground
      )
    }
    let rows = slice.rows.map { row in
      let rowOrdinal = visibleRowOffset(row) ?? 0
      let cells = columns.map { column in
        let address = CSVCellAddress(row: row, column: column)
        let role: CSVGridCellRole
        let foreground: CSVThemeColor
        if searchMatchAddresses.contains(address) {
          role = .searchMatch
          foreground = _state.theme.searchMatch
        } else if _state.journal.replacement(row: row, column: column) != nil {
          role = .edited
          foreground = _state.theme.edited
        } else {
          role = .body
          foreground = _state.theme.foreground
        }
        return CSVGridCellPresentation(
          id: .data(address),
          address: address,
          projectedRowOrdinal: rowOrdinal,
          projectedColumnOrdinal: visibleColumnOffset(column) ?? 0,
          text: " " + displayValue(row: row, column: column),
          width: slice.widths[column, default: 4],
          role: role,
          foreground: foreground,
          background: _state.theme.background
        )
      }
      return CSVGridRowPresentation(id: .data(row), label: rowLabel(row), cells: cells)
    }
    return CSVGridPresentation(
      header: CSVGridRowPresentation(id: .header, label: "row", cells: headerCells),
      rows: rows,
      gutterWidth: slice.gutterWidth,
      gutterForeground: _state.theme.gutter,
      gutterBackground: _state.theme.headerBackground,
      border: _state.theme.border,
      counters: slice.counters
    )
  }

  func gridSelectionPresentation() -> CSVGridSelectionPresentation? {
    _ = gridSelectionRevision
    guard !_state.isLoading,
      let row = _state.cursor.row,
      let column = _state.cursor.column
    else { return nil }
    let slice = CSVGridLayout.slice(input: gridLayoutInput())
    guard let rowIndex = slice.rows.firstIndex(of: row),
      let columnIndex = slice.allColumns.firstIndex(of: column)
    else { return nil }
    let columns = slice.allColumns
    let x =
      slice.gutterWidth + 1
      + columns[..<columnIndex].reduce(into: 0) { offset, prior in
        offset += slice.widths[prior, default: 4] + 1
      }
    return CSVGridSelectionPresentation(
      address: CSVCellAddress(row: row, column: column),
      projectedRowOrdinal: visibleRowOffset(row) ?? 0,
      projectedColumnOrdinal: visibleColumnOffset(column) ?? 0,
      text: " " + displayValue(row: row, column: column),
      width: slice.widths[column, default: 4],
      x: x,
      y: rowIndex + 1,
      foreground: _state.theme.cursorForeground,
      background: _state.theme.cursorBackground
    )
  }

  func rootStylePresentation() -> CSVRootStylePresentation {
    _ = rootStyleRevision
    return CSVRootStylePresentation(theme: _state.theme)
  }

  func rootAcceptsFocusPresentation() -> Bool {
    _ = rootFocusRevision
    if case .editing = _state.mode { return false }
    return true
  }

  func toolbarPresentation() -> CSVToolbarPresentation {
    _ = toolbarRevision
    let showShape = _state.viewport.width >= 72
    let toolbarItems = CSVMenu.allCases.map { menu in
      let active = _state.mode == .menu(menu)
      return CSVToolbarItemPresentation(
        menu: menu,
        isActive: active,
        foreground: active ? _state.theme.menuActiveForeground : _state.theme.menuForeground,
        background: active ? _state.theme.menuActiveBackground : _state.theme.menuBackground
      )
    }
    return CSVToolbarPresentation(
      theme: _state.theme,
      items: toolbarItems,
      sourceLabel: showShape ? _state.document.source.displayName : nil,
      dirtyMarker: showShape && _state.isDirty ? "●" : "",
      shapeLabel: showShape ? "\(_state.rowCount) × \(_state.columnCount)" : nil
    )
  }

  func loadingPresentation() -> CSVLoadingPresentation? {
    _ = gridContentRevision
    guard _state.isLoading else { return nil }
    return CSVLoadingPresentation(
      theme: _state.theme,
      message: _state.diagnostic?.message ?? "loading…"
    )
  }

  func statusPresentation() -> CSVStatusPresentation {
    _ = statusRevision
    let prompt: CSVPrompt?
    if case .prompt(let value) = _state.mode { prompt = value } else { prompt = nil }
    return CSVStatusPresentation(
      theme: _state.theme,
      promptPrefix: prompt.map(Self.promptPrefix),
      promptText: _state.prompt.text,
      promptDiagnostic: _state.prompt.diagnostic,
      cellStatus: selectedCellStatus(),
      projectionStatus: currentProjectionStatus(),
      statusColor: currentStatusColor()
    )
  }

  func terminationPresentation() -> CSVTerminationPresentation {
    _ = terminationRevision
    return CSVTerminationPresentation(requestGeneration: _state.terminationRequestGeneration)
  }

  func overlayPresentation() -> CSVOverlayPresentation? {
    _ = overlayRevision
    let title: String
    let content: CSVOverlayContent
    switch _state.mode {
    case .menu(let menu):
      title = menu.rawValue
      content = .menu(
        menu,
        rows: CSVCommandCatalog.definitions(for: menu).map {
          CSVCommandRowPresentation(definition: $0, availability: $0.availability(in: _state))
        }
      )
    case .help:
      title = "Keyboard Reference"
      content = .help(rows: CSVCommandCatalog.definitions)
    case .palette:
      title = "Command Palette"
      let query = _state.prompt.text
      let matches =
        query.isEmpty
        ? CSVCommandCatalog.definitions
        : CSVCommandCatalog.definitions.filter {
          $0.title.range(of: query, options: .caseInsensitive) != nil
        }
      content = .palette(
        query: query,
        rows: matches.prefix(12).map {
          CSVCommandRowPresentation(definition: $0, availability: $0.availability(in: _state))
        }
      )
    case .rowDetail(let row):
      title = "Row \(rowLabel(row))"
      let fields = _state.projection.visibleColumns.map { column in
        let value = value(row: row, column: column)
        let display: String
        if !value.isEmpty {
          display = value
        } else if let base = originalColumnOffset(column),
          let decoded = try? _state.document.decodeSourceRow(row)
        {
          display = decoded.fields.indices.contains(base) ? "(empty)" : "(missing)"
        } else {
          display = "(missing)"
        }
        return CSVRowDetailFieldPresentation(
          column: column,
          header: headerLabel(column),
          value: display
        )
      }
      content = .rowDetail(row: row, fields: fields, readOnly: _state.readOnly)
    case .editing(let address):
      title = "Edit \(headerLabel(address.column))"
      content = .editing(
        address: address,
        rowLabel: rowLabel(address.row),
        columnLabel: headerLabel(address.column),
        text: _state.editor.text
      )
    case .columns:
      title = "Columns"
      content = .columns(
        _state.journal.columnOrder.map { column in
          CSVColumnPresentation(
            column: column,
            label: headerLabel(column),
            isHidden: _state.projection.hiddenColumns.contains(column)
          )
        })
    case .saveAs:
      title = "Save As"
      content = .saveAs(path: _state.saveAsPath)
    case .confirmation(let confirmation):
      title = "Confirm"
      content = .confirmation(
        confirmation,
        message: Self.confirmationMessage(confirmation),
        hint: Self.confirmationHint(confirmation)
      )
    default:
      return nil
    }
    return CSVOverlayPresentation(
      title: title,
      viewport: _state.viewport,
      theme: _state.theme,
      content: content
    )
  }

  @discardableResult
  func performPresentationAction(_ action: CSVPresentationAction) -> Bool {
    switch action {
    case .selectCell(let address, let rowOrdinal, let columnOrdinal):
      let previous = _state.cursor
      performFastNavigation {
        select(
          address,
          projectedRowOrdinal: rowOrdinal,
          projectedColumnOrdinal: columnOrdinal
        )
      }
      return _state.cursor != previous
    case .scrollWheel(let deltaX, let deltaY):
      let previous = _state.cursor
      send(.scrollWheel(deltaX: deltaX, deltaY: deltaY))
      return _state.cursor != previous
    }
  }

  public func copyCellText() -> String? {
    guard let row = _state.cursor.row, let column = _state.cursor.column else { return nil }
    return value(row: row, column: column)
  }

  public func copyRowText() -> String? {
    guard let row = _state.cursor.row else { return nil }
    return try? CSVSerializer().serializeRow(
      row,
      document: _state.document,
      journal: _state.journal
    )
  }

  public func shouldAllowTermination() -> Bool {
    if _state.allowsNextTermination {
      _state.allowsNextTermination = false
      return true
    }
    guard _state.isDirty else { return true }
    _state.mode = .confirmation(.dirtyQuit)
    return false
  }

  public func announce(_ diagnostic: CSVDiagnostic) {
    _state.diagnostic = diagnostic
  }

  @discardableResult
  public func requestQuitFromCommand() -> Bool {
    if _state.isDirty {
      _state.mode = .confirmation(.dirtyQuit)
      return false
    } else {
      _state.terminationRequestGeneration &+= 1
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

  func installDocumentLoaderForTesting(
    _ loader:
      @escaping @Sendable (
        CSVSourceSnapshot, CSVDelimiter, Bool
      ) throws -> CSVDocumentLoadResult
  ) {
    documentLoader = loader
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
    _state.isLoading = true
    _state.diagnostic = CSVDiagnostic(.information, "loading \(source.displayName)…")
    loadMetricsStartedAt = CSVLoadMetrics.isEnabled ? .now : nil
    pendingLoadMetrics = nil
    let documentLoader = documentLoader
    sourceLoadTask = Task { [weak self] in
      let result = await Self.runDetachedLoad {
        try documentLoader(source, delimiter, hasHeaders)
      }
      guard let self, !Task.isCancelled, generation == self.sourceLoadGeneration else { return }
      self._state.isLoading = false
      switch result {
      case .success(let loadResult):
        self.commitInitialLoad(loadResult, diagnostic: initialDiagnostic)
      case .failure(let error):
        self._state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func commitInitialLoad(
    _ result: CSVDocumentLoadResult,
    diagnostic: CSVDiagnostic?
  ) {
    let commitStarted = ContinuousClock.now
    let document = result.document
    _state.document = document
    _state.journal = CSVEditJournal(document: document)
    _state.projection = CSVViewProjection(journal: _state.journal)
    refreshJournalOrdinalCaches()
    projectedRowOrdinalIndex = nil
    projectionSharesJournalOrder = true
    refreshProjectedColumnOrdinals()
    _state.cursor = CSVCursor(
      row: _state.journal.rowOrder.first,
      column: _state.journal.columnOrder.first
    )
    rowCache.removeAll()
    history = CSVHistory()
    updateHistoryAvailability()
    _state.currentRevision = 0
    _state.cleanRevision = 0
    backingBytes = document.source.bytes
    backingIdentity = document.source.identity
    writeBackAuthority = document.source.writeBackAuthority
    baseHeaderLabels = Self.makeBaseHeaderLabels(document: document)
    nextColumnID = (document.columnIDs.map(\.rawValue).max() ?? -1) + 1
    initialWidthSample = result.initialWidths
    applyInitialWidthSample(result.initialWidths)
    _state.diagnostic = diagnostic
    if configuration.watchesDocument,
      case .regularFile(let url) = document.source.origin
    {
      startSourceWatcher(for: url)
    }
    if var metrics = result.metrics {
      metrics.modelCommitNanoseconds = CSVLoadMetrics.nanoseconds(
        commitStarted.duration(to: .now)
      )
      pendingLoadMetrics = metrics
    }
  }

  private func save() {
    guard ensureMutable() else { return }
    guard !_state.isSaving else { return }
    guard _state.isDirty else {
      finishPendingLifecycleAfterSave()
      return
    }
    guard let authority = writeBackAuthority else {
      _state.mode = .saveAs
      if _state.saveAsPath.isEmpty { _state.saveAsPath = _state.document.source.displayName }
      _state.diagnostic = CSVDiagnostic(.information, "choose a path for Save As")
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
    guard ensureMutable(), !_state.isSaving else { return }
    let trimmed = _state.saveAsPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      _state.diagnostic = CSVDiagnostic(.warning, "enter a Save As path")
      return
    }
    let destination = URL(
      fileURLWithPath: trimmed,
      relativeTo: configuration.workingDirectory
    ).standardizedFileURL
    if FileManager.default.fileExists(atPath: destination.path), !overwrite {
      _state.mode = .confirmation(.overwrite(destination))
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
    let document = _state.document
    let journal = _state.journal
    let revision = _state.currentRevision
    _state.isSaving = true
    _state.mode = .browse
    _state.diagnostic = CSVDiagnostic(.information, "saving…")
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
      self._state.isSaving = false
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
        self._state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
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
    _state.document.source.origin = source.origin
    _state.document.source.displayName = source.displayName
    _state.document.source.identity = source.identity
    _state.document.source.writeBackAuthority = source.writeBackAuthority
    _state.document.source.loadGeneration = source.loadGeneration
    _state.cleanRevision = savedRevision
    _state.externalChangePending = false
    _state.saveAsPath = source.displayName
    _state.diagnostic = CSVDiagnostic(
      .information,
      _state.currentRevision == savedRevision
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
      _state.externalChangePending = true
      _state.mode = .confirmation(.externalConflict)
      _state.diagnostic = CSVDiagnostic(.warning, error.localizedDescription)
    case .destinationExists(let url):
      _state.mode = .confirmation(.overwrite(url))
      _state.diagnostic = CSVDiagnostic(.warning, error.localizedDescription)
    default:
      _state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
    }
  }

  private func finishPendingLifecycleAfterSave() {
    switch pendingLifecycle {
    case .none:
      break
    case .quit:
      pendingLifecycle = .none
      _state.mode = .browse
      _state.terminationRequestGeneration &+= 1
      _state.diagnostic = CSVDiagnostic(.information, "saved; quitting…")
    case .reload:
      pendingLifecycle = .none
      reloadSource()
    }
  }

  private func reloadSource() {
    reloadTheme()
    guard case .regularFile(let url) = _state.document.source.origin else {
      _state.diagnostic = CSVDiagnostic(.warning, "standard input cannot be reloaded")
      return
    }
    sourceLoadGeneration &+= 1
    let generation = sourceLoadGeneration
    sourceLoadTask?.cancel()
    let delimiter = _state.document.dialect.delimiter
    let hasHeaders = _state.document.dialect.hasHeaders
    _state.isReloading = true
    _state.diagnostic = CSVDiagnostic(.information, "reloading…")
    loadMetricsStartedAt = CSVLoadMetrics.isEnabled ? .now : nil
    pendingLoadMetrics = nil
    sourceLoadTask = Task { [weak self] in
      let result = await Self.runDetachedLoad {
        let source = try CSVSourceReader().read(fileURL: url, generation: generation)
        try Task.checkCancellation()
        return try CSVDocument.load(
          source: source,
          delimiter: delimiter,
          hasHeaders: hasHeaders
        )
      }
      guard let self, !Task.isCancelled, generation == self.sourceLoadGeneration else { return }
      self._state.isReloading = false
      switch result {
      case .success(let loadResult): self.commitReload(loadResult)
      case .failure(let error):
        self._state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  nonisolated private static func runDetachedLoad(
    _ operation: @escaping @Sendable () throws -> CSVDocumentLoadResult
  ) async -> Result<CSVDocumentLoadResult, any Error> {
    let worker = Task.detached { () -> Result<CSVDocumentLoadResult, any Error> in
      Result {
        try Task.checkCancellation()
        return try operation()
      }
    }
    return await withTaskCancellationHandler {
      await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  private func commitReload(_ result: CSVDocumentLoadResult) {
    let commitStarted = ContinuousClock.now
    let document = result.document
    if document.source.bytes == backingBytes {
      backingIdentity = document.source.identity
      writeBackAuthority = document.source.writeBackAuthority
      _state.document.source.identity = document.source.identity
      _state.document.source.writeBackAuthority = document.source.writeBackAuthority
      _state.externalChangePending = false
      if _state.diagnostic?.message == "reloading…" { _state.diagnostic = nil }
      finishLoadMetrics(result.metrics, commitStarted: commitStarted)
      return
    }

    let oldProjection = _state.projection
    let oldCursor = _state.cursor
    _state.document = document
    _state.journal = CSVEditJournal(document: document)
    _state.projection = CSVViewProjection(journal: _state.journal)
    refreshJournalOrdinalCaches()
    projectedRowOrdinalIndex = nil
    projectionSharesJournalOrder = true
    refreshProjectedColumnOrdinals()
    _state.projection.hiddenColumns = oldProjection.hiddenColumns.intersection(
      Set(_state.journal.columnOrder)
    )
    _state.projection.frozenThrough = oldProjection.frozenThrough.flatMap {
      journalColumnOffset($0) == nil ? nil : $0
    }
    _state.projection.manualWidthOverrides = oldProjection.manualWidthOverrides.intersection(
      Set(_state.journal.columnOrder)
    )
    _state.projection.filter = oldProjection.filter
    _state.projection.sort = oldProjection.sort
    _state.cursor = CSVCursor(
      row: oldCursor.row.flatMap { journalRowOffset($0) == nil ? nil : $0 }
        ?? _state.journal.rowOrder.first,
      column: oldCursor.column.flatMap { journalColumnOffset($0) == nil ? nil : $0 }
        ?? _state.journal.columnOrder.first,
      rowOrigin: oldCursor.rowOrigin,
      scrollingColumnOrigin: oldCursor.scrollingColumnOrigin
    )
    _state.cursor.projectedRowOrdinal = _state.cursor.row.flatMap(visibleRowOffset)
    _state.cursor.projectedColumnOrdinal = _state.cursor.column.flatMap(visibleColumnOffset)
    rowCache.removeAll()
    history = CSVHistory()
    updateHistoryAvailability()
    let revision = nextRevisionID
    nextRevisionID &+= 1
    _state.currentRevision = revision
    _state.cleanRevision = revision
    backingBytes = document.source.bytes
    backingIdentity = document.source.identity
    writeBackAuthority = document.source.writeBackAuthority
    baseHeaderLabels = Self.makeBaseHeaderLabels(document: document)
    _state.externalChangePending = false
    _state.diagnostic = CSVDiagnostic(.information, "reloaded \(document.source.displayName)")
    nextColumnID = (document.columnIDs.map(\.rawValue).max() ?? -1) + 1
    initialWidthSample = result.initialWidths
    applyInitialWidthSample(result.initialWidths)
    for (column, width) in oldProjection.widths where journalColumnOffset(column) != nil {
      _state.projection.widths[column] = width
    }
    recomputeProjection()
    finishLoadMetrics(result.metrics, commitStarted: commitStarted)
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
      if self._state.isDirty || self._state.isSaving {
        self._state.externalChangePending = true
        self._state.diagnostic = CSVDiagnostic(.warning, "source changed outside csvui")
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
        self._state.theme = loaded.theme
        if case .file(let url, _) = selection,
          self._state.diagnostic?.severity == .error,
          self._state.diagnostic?.message.hasPrefix(url.path + ":") == true
        {
          self._state.diagnostic = nil
        }
      case .failure(let error):
        self._state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func beginPrompt(_ prompt: CSVPrompt, initial: String) {
    _state.mode = .prompt(prompt)
    _state.prompt = CSVPromptState(text: initial)
  }

  private func submitPrompt() {
    guard _state.prompt.diagnostic == nil else { return }
    let text = _state.prompt.text
    switch _state.mode {
    case .prompt(.find):
      _state.searchQuery = text
      _state.mode = .browse
      beginSearch()
    case .prompt(.filterCurrent(let column)):
      _state.projection.filter = CSVFilterSpec(scope: .column(column), query: text)
      _state.mode = .browse
      recomputeProjection()
    case .prompt(.filterAll):
      _state.projection.filter = CSVFilterSpec(scope: .allVisibleColumns, query: text)
      _state.mode = .browse
      recomputeProjection()
    case .prompt(.renameHeader(let column)):
      guard ensureMutable() else { return }
      let old = headerLabel(column)
      let changed = performMutation(cost: old.utf8.count + text.utf8.count + 32) {
        $0.renameHeader(column, to: text)
      }
      if changed { incorporateEditedWidth(text, for: column) }
      _state.mode = .browse
    default: break
    }
  }

  private func moveRows(_ amount: Int) {
    guard !_state.projection.visibleRows.isEmpty else { return }
    let current = _state.cursor.row.flatMap(visibleRowOffset) ?? 0
    moveToRow(at: current + amount)
  }

  private func applyFastNavigationAction(_ action: CSVAction) {
    switch action {
    case .selectCell(let address): select(address)
    case .moveRows(let amount): moveRows(amount)
    case .moveColumns(let amount): moveColumns(amount)
    case .pageRows(let pages): moveRows(pages * _state.viewport.dataRowCapacity)
    case .scrollWheel(let deltaX, let deltaY):
      if deltaY != 0 { moveRows(deltaY) }
      if deltaX != 0 { moveColumns(deltaX) }
    case .firstRow: moveToRow(at: 0)
    case .lastRow: moveToRow(at: _state.projection.visibleRows.count - 1)
    case .firstColumn: moveToColumn(at: 0)
    case .lastColumn: moveToColumn(at: _state.projection.visibleColumns.count - 1)
    default: preconditionFailure("non-navigation action reached the fast navigation path")
    }
  }

  private func performFastNavigation(_ mutation: () -> Void) {
    let previousCursor = _state.cursor
    let previousSlice = realizedSliceFacts()
    #if DEBUG
      let previousState = _state
    #endif
    precondition(!defersPresentationInvalidation)
    defersPresentationInvalidation = true
    mutation()
    defersPresentationInvalidation = false
    #if DEBUG
      var expectedState = previousState
      expectedState.cursor = _state.cursor
      precondition(
        expectedState == _state,
        "fast cursor navigation changed non-cursor CSVState"
      )
    #endif
    guard previousCursor != _state.cursor else { return }
    let currentSlice = realizedSliceFacts()
    invalidatePresentations(previousSlice == currentSlice ? .cursor : [.content, .cursor])
  }

  private func updateLocalEditorText(_ text: String) {
    guard text != _state.editor.text else { return }
    precondition(!defersPresentationInvalidation)
    defersPresentationInvalidation = true
    _state.editor.text = text
    defersPresentationInvalidation = false
  }

  private func realizedSliceFacts() -> CSVGridSlice {
    CSVGridLayout.slice(input: gridLayoutInput())
  }

  private func moveToRow(at index: Int) {
    guard !_state.projection.visibleRows.isEmpty else {
      var cursor = _state.cursor
      cursor.row = nil
      cursor.projectedRowOrdinal = nil
      if cursor != _state.cursor { _state.cursor = cursor }
      return
    }
    let ordinal = min(max(0, index), _state.projection.visibleRows.count - 1)
    var cursor = _state.cursor
    cursor.row = _state.projection.visibleRows[ordinal]
    cursor.projectedRowOrdinal = ordinal
    revealCursor(&cursor)
    if cursor != _state.cursor { _state.cursor = cursor }
  }

  private func moveColumns(_ amount: Int) {
    guard !_state.projection.visibleColumns.isEmpty else { return }
    let current = _state.cursor.column.flatMap(visibleColumnOffset) ?? 0
    moveToColumn(at: current + amount)
  }

  private func moveToColumn(at index: Int) {
    guard !_state.projection.visibleColumns.isEmpty else {
      var cursor = _state.cursor
      cursor.column = nil
      cursor.projectedColumnOrdinal = nil
      if cursor != _state.cursor { _state.cursor = cursor }
      return
    }
    let ordinal = min(max(0, index), _state.projection.visibleColumns.count - 1)
    var cursor = _state.cursor
    cursor.column = _state.projection.visibleColumns[ordinal]
    cursor.projectedColumnOrdinal = ordinal
    revealCursor(&cursor)
    if cursor != _state.cursor { _state.cursor = cursor }
  }

  private func revealCursor() {
    var cursor = _state.cursor
    revealCursor(&cursor)
    if cursor != _state.cursor { _state.cursor = cursor }
  }

  private func revealCursor(_ cursor: inout CSVCursor) {
    if let row = cursor.row,
      let rowIndex = cursor.projectedRowOrdinal
        ?? projectedRowOffset(
          row,
          in: _state.projection.visibleRows
        )
    {
      let capacity = _state.viewport.dataRowCapacity
      if rowIndex < cursor.rowOrigin { cursor.rowOrigin = rowIndex }
      if rowIndex >= cursor.rowOrigin + capacity {
        cursor.rowOrigin = rowIndex - capacity + 1
      }
      cursor.rowOrigin = min(
        cursor.rowOrigin,
        max(0, _state.projection.visibleRows.count - capacity)
      )
    }
    guard let column = cursor.column,
      let index = cursor.projectedColumnOrdinal ?? projectedColumnOrdinals[column]
    else { return }
    let frozenCount = currentFrozenColumnCount()
    if index < frozenCount { return }
    let scrollingIndex = index - frozenCount
    if scrollingIndex < cursor.scrollingColumnOrigin {
      cursor.scrollingColumnOrigin = scrollingIndex
    } else {
      let visible = CSVGridLayout.slice(
        input: gridLayoutInput(cursor: cursor, revealsSelectedColumn: false)
      ).scrollingColumns
      if !visible.contains(column) {
        cursor.scrollingColumnOrigin = scrollingIndex
      }
    }
  }

  private func currentFrozenColumnCount() -> Int {
    guard let frozen = _state.projection.frozenThrough,
      let index = visibleColumnOffset(frozen)
    else { return 0 }
    return index + 1
  }

  private func beginSearch() {
    searchGeneration &+= 1
    let generation = searchGeneration
    searchTask?.cancel()
    guard !_state.searchQuery.isEmpty else {
      _state.searchMatches = []
      searchMatchAddresses = []
      _state.selectedSearchMatch = nil
      _state.searchResultsTruncated = false
      _state.isSearching = false
      return
    }
    _state.searchMatches = []
    searchMatchAddresses = []
    _state.selectedSearchMatch = nil
    _state.isSearching = true
    let snapshot = CSVScanSnapshot(document: _state.document, journal: _state.journal)
    let rows = _state.projection.visibleRows
    let columns = _state.projection.visibleColumns
    let query = _state.searchQuery
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
      self._state.isSearching = false
      switch result {
      case .success(let set):
        self._state.searchMatches = set.matches
        self.searchMatchAddresses = Set(set.matches.map(\.address))
        self._state.searchResultsTruncated = set.isTruncated
        self._state.selectedSearchMatch = set.matches.isEmpty ? nil : 0
        if let first = set.matches.first { self.select(first.address) }
      case .failure(let error):
        self.searchMatchAddresses = []
        self._state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func moveSearchMatch(by amount: Int) {
    guard !_state.searchMatches.isEmpty else { return }
    let current = _state.selectedSearchMatch ?? 0
    let count = _state.searchMatches.count
    let next = (current + amount % count + count) % count
    _state.selectedSearchMatch = next
    select(_state.searchMatches[next].address)
  }

  private func select(_ address: CSVCellAddress) {
    guard let rowOrdinal = visibleRowOffset(address.row),
      let columnOrdinal = visibleColumnOffset(address.column)
    else { return }
    select(
      address,
      projectedRowOrdinal: rowOrdinal,
      projectedColumnOrdinal: columnOrdinal
    )
  }

  private func select(
    _ address: CSVCellAddress,
    projectedRowOrdinal rowOrdinal: Int,
    projectedColumnOrdinal columnOrdinal: Int
  ) {
    guard _state.projection.visibleRows.indices.contains(rowOrdinal),
      _state.projection.visibleRows[rowOrdinal] == address.row,
      _state.projection.visibleColumns.indices.contains(columnOrdinal),
      _state.projection.visibleColumns[columnOrdinal] == address.column
    else { return }
    var cursor = _state.cursor
    cursor.row = address.row
    cursor.column = address.column
    cursor.projectedRowOrdinal = rowOrdinal
    cursor.projectedColumnOrdinal = columnOrdinal
    revealCursor(&cursor)
    if cursor != _state.cursor { _state.cursor = cursor }
  }

  private func recomputeProjection() {
    projectionGeneration &+= 1
    let generation = projectionGeneration
    projectionTask?.cancel()
    projectionTask = nil
    let previousRows = _state.projection.visibleRows
    let previousRowIndex: Int
    if let ordinal = _state.cursor.projectedRowOrdinal,
      previousRows.indices.contains(ordinal),
      previousRows[ordinal] == _state.cursor.row
    {
      previousRowIndex = ordinal
    } else {
      previousRowIndex = _state.cursor.row.flatMap(visibleRowOffset) ?? 0
    }
    let previousRow = _state.cursor.row
    let previousColumn = _state.cursor.column
    let baseRows = _state.journal.rowOrder
    let columns = _state.journal.columnOrder.filter {
      !_state.projection.hiddenColumns.contains($0)
    }
    let filter = _state.projection.filter
    let sort = _state.projection.sort
    let requiresRowOrdinalIndex = filter != nil || sort != nil
    _state.projection.visibleColumns = columns
    refreshProjectedColumnOrdinals()
    _state.isFiltering = filter != nil
    _state.isSorting = sort != nil

    guard requiresRowOrdinalIndex else {
      commitProjection(
        CSVProjectionComputation(
          rows: baseRows,
          rowOrdinalIndex: nil,
          sharesJournalOrder: true
        ),
        previousRowIndex: previousRowIndex,
        previousRow: previousRow,
        previousColumn: previousColumn,
        columns: columns
      )
      return
    }

    let snapshot = CSVScanSnapshot(document: _state.document, journal: _state.journal)
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
          let rowOrdinalIndex =
            requiresRowOrdinalIndex ? try CSVRowOrdinalIndex(rows: rows) : nil
          return Result<CSVProjectionComputation, any Error>.success(
            CSVProjectionComputation(
              rows: rows,
              rowOrdinalIndex: rowOrdinalIndex,
              sharesJournalOrder: !requiresRowOrdinalIndex
            )
          )
        } catch {
          return Result<CSVProjectionComputation, any Error>.failure(error)
        }
      }.value
      guard let self, !Task.isCancelled, generation == self.projectionGeneration else { return }
      self._state.isFiltering = false
      self._state.isSorting = false
      switch result {
      case .success(let projection):
        self.commitProjection(
          projection,
          previousRowIndex: previousRowIndex,
          previousRow: previousRow,
          previousColumn: previousColumn,
          columns: columns
        )
      case .failure(let error):
        self._state.diagnostic = CSVDiagnostic(.error, error.localizedDescription)
      }
    }
  }

  private func commitProjection(
    _ projection: CSVProjectionComputation,
    previousRowIndex: Int,
    previousRow: RowID?,
    previousColumn: ColumnID?,
    columns: [ColumnID]
  ) {
    let rows = projection.rows
    _state.projection.visibleRows = rows
    projectedRowOrdinalIndex = projection.rowOrdinalIndex
    projectionSharesJournalOrder = projection.sharesJournalOrder
    if let previousRow, projectedRowOffset(previousRow, in: rows) != nil {
      _state.cursor.row = previousRow
    } else if !rows.isEmpty {
      _state.cursor.row = rows[min(previousRowIndex, rows.count - 1)]
    } else {
      _state.cursor.row = nil
    }
    if let previousColumn, projectedColumnOrdinals[previousColumn] != nil {
      _state.cursor.column = previousColumn
    } else {
      _state.cursor.column = columns.first
    }
    _state.cursor.projectedRowOrdinal = _state.cursor.row.flatMap {
      projectedRowOffset($0, in: rows)
    }
    _state.cursor.projectedColumnOrdinal = _state.cursor.column.flatMap {
      projectedColumnOrdinals[$0]
    }
    revealCursor()
    beginSearch()
  }

  private func cycleSort() {
    guard let column = _state.cursor.column else { return }
    if _state.projection.sort?.column != column {
      _state.projection.sort = CSVSortSpec(column: column, direction: .ascending)
    } else if _state.projection.sort?.direction == .ascending {
      _state.projection.sort = CSVSortSpec(column: column, direction: .descending)
    } else {
      _state.projection.sort = nil
    }
    recomputeProjection()
  }

  private func adjustCurrentWidth(by amount: Int) {
    guard let column = _state.cursor.column else { return }
    let current = _state.projection.widths[column] ?? 12
    _state.projection.widths[column] = min(40, max(4, current + amount))
    _state.projection.manualWidthOverrides.insert(column)
  }

  private func resetCurrentWidth() {
    guard let column = _state.cursor.column else { return }
    _state.projection.manualWidthOverrides.remove(column)
    _state.projection.widths[column] = sampledWidth(for: column)
  }

  private func toggleCurrentColumnVisibility() {
    guard let column = _state.cursor.column else { return }
    toggleColumnVisibility(column)
  }

  private func toggleColumnVisibility(_ column: ColumnID) {
    if _state.projection.hiddenColumns.contains(column) {
      _state.projection.hiddenColumns.remove(column)
    } else {
      guard _state.projection.visibleColumns.count > 1 else {
        _state.diagnostic = CSVDiagnostic(.warning, "at least one column must remain visible")
        return
      }
      _state.projection.hiddenColumns.insert(column)
    }
    recomputeProjection()
  }

  private func resetView() {
    searchGeneration &+= 1
    searchTask?.cancel()
    _state.projection.filter = nil
    _state.projection.sort = nil
    _state.projection.hiddenColumns = []
    _state.projection.frozenThrough = nil
    _state.projection.manualWidthOverrides = []
    sampleCurrentWidths()
    _state.searchQuery = ""
    _state.searchMatches = []
    searchMatchAddresses = []
    _state.selectedSearchMatch = nil
    _state.searchResultsTruncated = false
    _state.isSearching = false
    recomputeProjection()
  }

  private func beginEditCell() {
    guard ensureMutable(), let row = _state.cursor.row, let column = _state.cursor.column else {
      return
    }
    let address = CSVCellAddress(row: row, column: column)
    _state.editor = CSVEditorState(text: value(row: row, column: column))
    _state.mode = .editing(address)
  }

  private func beginRenameHeader() {
    guard ensureMutable() else { return }
    guard _state.document.dialect.hasHeaders, let column = _state.cursor.column else {
      _state.diagnostic = CSVDiagnostic(.warning, "Rename Header requires a header record")
      return
    }
    beginPrompt(.renameHeader(column), initial: rawHeaderValue(column))
  }

  private func commitEditor() {
    guard case .editing(let address) = _state.mode, ensureMutable() else { return }
    let old = value(row: address.row, column: address.column)
    let text = _state.editor.text
    let changed = performMutation(cost: old.utf8.count + text.utf8.count + 64) {
      $0.replace(row: address.row, column: address.column, with: text)
    }
    if changed { incorporateEditedWidth(text, for: address.column) }
    _state.mode = .browse
    _state.editor = CSVEditorState()
  }

  private func insertRow(offset: Int) {
    guard ensureMutable() else { return }
    guard _state.projection.filter == nil, _state.projection.sort == nil else {
      _state.diagnostic = CSVDiagnostic(.warning, "clear filter and sort before inserting a row")
      return
    }
    let current =
      _state.cursor.row.flatMap(journalRowOffset)
      ?? _state.journal.rowOrder.count
    let id = RowID(insertedID: nextInsertedRowID)
    let cost = structuralRowCost()
    guard performMutation(cost: cost, { $0.insertRow(id, at: current + offset) }) else { return }
    nextInsertedRowID &+= 1
    _state.cursor.row = id
    _state.cursor.projectedRowOrdinal = min(current + offset, _state.journal.rowOrder.count - 1)
    recomputeProjection()
  }

  private func deleteCurrentRow() {
    guard ensureMutable(), let row = _state.cursor.row,
      let ordinal = journalRowOffset(row)
    else { return }
    _ = performMutation(cost: structuralRowCost()) { _ = $0.deleteRow(at: ordinal) }
  }

  private func insertColumn(offset: Int) {
    guard ensureMutable() else { return }
    let current =
      _state.cursor.column.flatMap(journalColumnOffset)
      ?? _state.journal.columnOrder.count
    let id = ColumnID(nextColumnID)
    guard
      performMutation(
        cost: structuralColumnCost(),
        {
          $0.insertColumn(id, at: current + offset)
        })
    else { return }
    nextColumnID += 1
    _state.cursor.column = id
    _state.cursor.projectedColumnOrdinal = min(
      current + offset,
      _state.journal.columnOrder.count - 1
    )
    _state.projection.widths[id] = 12
    recomputeProjection()
  }

  private func deleteCurrentColumn() {
    guard ensureMutable(), let column = _state.cursor.column,
      let ordinal = journalColumnOffset(column)
    else { return }
    _ = performMutation(cost: structuralColumnCost()) { _ = $0.deleteColumn(at: ordinal) }
  }

  @discardableResult
  private func performMutation(
    cost: Int,
    _ mutation: (inout CSVEditJournal) -> Void
  ) -> Bool {
    guard cost <= CSVHistory.maximumBytes else {
      _state.diagnostic = CSVDiagnostic(.warning, "edit cannot fit in the undo history budget")
      return false
    }
    let before = _state.journal
    var after = before
    mutation(&after)
    guard after != before else { return false }
    let previousRevision = _state.currentRevision
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
      _state.diagnostic = CSVDiagnostic(.warning, "edit cannot fit in the undo history budget")
      return false
    }
    _state.journal = after
    refreshJournalOrdinalCaches()
    _state.currentRevision = nextRevision
    updateHistoryAvailability()
    recomputeProjection()
    return true
  }

  private func undo() {
    guard let entry = history.undo() else { return }
    _state.journal = entry.before
    refreshJournalOrdinalCaches()
    _state.currentRevision = entry.revisionBefore
    updateHistoryAvailability()
    recomputeProjection()
  }

  private func redo() {
    guard let entry = history.redo() else { return }
    _state.journal = entry.after
    refreshJournalOrdinalCaches()
    _state.currentRevision = entry.revisionAfter
    updateHistoryAvailability()
    recomputeProjection()
  }

  private func updateHistoryAvailability() {
    _state.undoAvailable = !history.undoEntries.isEmpty
    _state.redoAvailable = !history.redoEntries.isEmpty
  }

  private func ensureMutable() -> Bool {
    guard !_state.readOnly else {
      _state.diagnostic = CSVDiagnostic(.warning, "read-only mode disables editing")
      return false
    }
    return true
  }

  private func structuralRowCost() -> Int {
    let (bytes, overflow) = _state.journal.rowOrder.count.multipliedReportingOverflow(
      by: MemoryLayout<RowID>.stride
    )
    return overflow ? .max : bytes + 256
  }

  private func structuralColumnCost() -> Int {
    let (bytes, overflow) = _state.journal.columnOrder.count.multipliedReportingOverflow(
      by: MemoryLayout<ColumnID>.stride
    )
    return overflow ? .max : bytes + 256
  }

  private func applyInitialWidthSample(_ sample: CSVInitialWidthSample) {
    _state.projection.widths = sample.widths
    _state.counters.widthSamples = sample.sampleCount
  }

  private func gridLayoutInput(
    cursor suppliedCursor: CSVCursor? = nil,
    revealsSelectedColumn: Bool = true
  ) -> CSVGridLayoutInput {
    let cursor = suppliedCursor ?? _state.cursor
    return CSVGridLayoutInput(
      visibleRows: _state.projection.visibleRows,
      visibleColumns: _state.projection.visibleColumns,
      frozenThroughOrdinal: _state.projection.frozenThrough.flatMap(visibleColumnOffset),
      widths: _state.projection.widths,
      rowOrigin: cursor.rowOrigin,
      scrollingColumnOrigin: cursor.scrollingColumnOrigin,
      selectedColumnOrdinal:
        revealsSelectedColumn ? cursor.column.flatMap(visibleColumnOffset) : nil,
      viewport: _state.viewport,
      dataRecordCount: _state.document.dataRecordCount,
      widthSamples: _state.counters.widthSamples
    )
  }

  private func invalidatePresentations(_ invalidation: PresentationInvalidation) {
    if invalidation.contains(.rootStyle) { rootStyleRevision &+= 1 }
    if invalidation.contains(.toolbar) { toolbarRevision &+= 1 }
    if invalidation.contains(.gridContent) { gridContentRevision &+= 1 }
    if invalidation.contains(.gridSelection) { gridSelectionRevision &+= 1 }
    if invalidation.contains(.status) { statusRevision &+= 1 }
    if invalidation.contains(.overlay) { overlayRevision &+= 1 }
    if invalidation.contains(.termination) { terminationRevision &+= 1 }
    if invalidation.contains(.rootFocus) { rootFocusRevision &+= 1 }
  }

  private func sampleCurrentWidths() {
    var widths: [ColumnID: Int] = [:]
    let columns = _state.journal.columnOrder
    for column in columns { widths[column] = min(40, max(4, headerLabel(column).count + 2)) }
    let sampleCount = min(1_000, _state.document.dataRecordCount)
    for rowIndex in 0..<sampleCount {
      let row = RowID(sourceIndex: rowIndex)
      guard let decoded = try? _state.document.decodeSourceRow(row) else { continue }
      for (base, field) in decoded.fields.enumerated()
      where _state.journal.originalColumnOrder.indices.contains(base) {
        let column = _state.journal.originalColumnOrder[base]
        let width = Self.visibleControlCharacters(field.value).count + 2
        widths[column] = min(40, max(widths[column, default: 4], width))
      }
    }
    _state.projection.widths = widths
    _state.counters.widthSamples = sampleCount
  }

  private func finishLoadMetrics(
    _ metrics: CSVLoadPhaseMetrics?,
    commitStarted: ContinuousClock.Instant
  ) {
    guard var metrics else { return }
    metrics.modelCommitNanoseconds = CSVLoadMetrics.nanoseconds(
      commitStarted.duration(to: .now)
    )
    pendingLoadMetrics = metrics
  }

  private func sampledWidth(for column: ColumnID) -> Int {
    var width = min(40, max(4, headerLabel(column).count + 2))
    let sampleCount = min(1_000, _state.document.dataRecordCount)
    for rowIndex in 0..<sampleCount {
      let value = value(row: RowID(sourceIndex: rowIndex), column: column)
      width = min(40, max(width, Self.visibleControlCharacters(value).count + 2))
    }
    return width
  }

  private func incorporateEditedWidth(_ value: String, for column: ColumnID) {
    guard !_state.projection.manualWidthOverrides.contains(column) else { return }
    let displayWidth = Self.visibleControlCharacters(value).count + 2
    let current = _state.projection.widths[column, default: 4]
    _state.projection.widths[column] = min(40, max(current, max(4, displayWidth)))
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
    guard _state.journal.originalColumnOrder.indices.contains(offset),
      _state.journal.originalColumnOrder[offset] == column
    else { return nil }
    return offset
  }

  private func journalRowOffset(_ row: RowID) -> Int? {
    if let journalRowOrdinalIndex { return journalRowOrdinalIndex.ordinal(for: row) }
    guard let sourceIndex = row.sourceIndex,
      _state.journal.rowOrder.indices.contains(sourceIndex),
      _state.journal.rowOrder[sourceIndex] == row
    else { return nil }
    return sourceIndex
  }

  private func journalColumnOffset(_ column: ColumnID) -> Int? {
    if let journalColumnOrdinals { return journalColumnOrdinals[column] }
    let ordinal = column.rawValue
    guard _state.journal.columnOrder.indices.contains(ordinal),
      _state.journal.columnOrder[ordinal] == column
    else { return nil }
    return ordinal
  }

  private func refreshJournalOrdinalCaches() {
    if _state.journal.rowOrder == _state.journal.originalRowOrder {
      journalRowOrdinalIndex = nil
    } else {
      journalRowOrdinalIndex = try? CSVRowOrdinalIndex(rows: _state.journal.rowOrder)
    }
    if _state.journal.columnOrder == _state.journal.originalColumnOrder {
      journalColumnOrdinals = nil
    } else {
      journalColumnOrdinals = Dictionary(
        uniqueKeysWithValues: _state.journal.columnOrder.enumerated().map {
          ($0.element, $0.offset)
        }
      )
    }
  }

  private func refreshProjectedColumnOrdinals() {
    projectedColumnOrdinals = Dictionary(
      uniqueKeysWithValues: _state.projection.visibleColumns.enumerated().map {
        ($0.element, $0.offset)
      }
    )
  }

  private func projectedRowOffset(_ row: RowID, in rows: [RowID]) -> Int? {
    if let projectedRowOrdinalIndex { return projectedRowOrdinalIndex.ordinal(for: row) }
    if projectionSharesJournalOrder { return journalRowOffset(row) }
    guard let sourceIndex = row.sourceIndex,
      rows.indices.contains(sourceIndex),
      rows[sourceIndex] == row
    else { return nil }
    return sourceIndex
  }

  private func visibleRowOffset(_ row: RowID) -> Int? {
    if _state.cursor.row == row,
      let ordinal = _state.cursor.projectedRowOrdinal,
      _state.projection.visibleRows.indices.contains(ordinal),
      _state.projection.visibleRows[ordinal] == row
    {
      return ordinal
    }
    return projectedRowOffset(row, in: _state.projection.visibleRows)
  }

  private func visibleColumnOffset(_ column: ColumnID) -> Int? {
    if _state.cursor.column == column,
      let ordinal = _state.cursor.projectedColumnOrdinal,
      _state.projection.visibleColumns.indices.contains(ordinal),
      _state.projection.visibleColumns[ordinal] == column
    {
      return ordinal
    }
    return projectedColumnOrdinals[column]
  }

  private func selectedCellStatus() -> String {
    guard let row = _state.cursor.row, let column = _state.cursor.column else {
      return _state.diagnostic?.message ?? "empty document"
    }
    if let diagnostic = _state.diagnostic { return diagnostic.message }
    let rowPosition = (visibleRowOffset(row) ?? 0) + 1
    let columnPosition = (visibleColumnOffset(column) ?? 0) + 1
    let coordinate = Self.columnCoordinate(columnPosition) + String(rowPosition)
    return "\(coordinate) · \(headerLabel(column)) · \(value(row: row, column: column))"
  }

  private func currentProjectionStatus() -> String {
    var values: [String] = []
    if _state.readOnly { values.append("READ ONLY") }
    if _state.externalChangePending { values.append("EXTERNAL CHANGE") }
    if _state.isSaving { values.append("SAVING…") }
    if _state.isReloading { values.append("RELOADING…") }
    if _state.isFiltering {
      values.append("FILTERING…")
    } else if let filter = _state.projection.filter {
      var label = "FILTER \(_state.projection.visibleRows.count)/\(_state.rowCount)"
      if case .column(let column) = filter.scope,
        _state.projection.hiddenColumns.contains(column)
      {
        label += " HIDDEN COLUMN"
      }
      values.append(label)
    }
    if _state.isSorting {
      values.append("SORTING…")
    } else if let sort = _state.projection.sort {
      values.append("SORT \(headerLabel(sort.column)) \(sort.direction.marker)")
    }
    if _state.isSearching {
      values.append("SEARCHING…")
    } else if !_state.searchQuery.isEmpty {
      values.append(
        "MATCH \(_state.searchMatches.count)\(_state.searchResultsTruncated ? "+" : "")")
    }
    if _state.document.irregularDataRecordCount > 0 {
      values.append("IRREGULAR \(_state.document.irregularDataRecordCount)")
    }
    return values.joined(separator: "  ")
  }

  private func currentStatusColor() -> CSVThemeColor {
    guard let diagnostic = _state.diagnostic else { return _state.theme.muted }
    return switch diagnostic.severity {
    case .information: _state.theme.muted
    case .warning: _state.theme.warning
    case .error: _state.theme.error
    }
  }

  private static func promptPrefix(_ prompt: CSVPrompt) -> String {
    switch prompt {
    case .find: "/"
    case .filterCurrent: "filter column: "
    case .filterAll: "filter all: "
    case .renameHeader: "header: "
    case .goTo: "go to: "
    }
  }

  private static func confirmationHint(_ confirmation: CSVConfirmation) -> String {
    switch confirmation {
    case .dirtyQuit, .dirtyReload: "S save · D discard · Esc cancel"
    case .overwrite: "O overwrite · Esc cancel"
    case .externalConflict: "R reload · A Save As · Esc cancel"
    }
  }

  private static func confirmationMessage(_ confirmation: CSVConfirmation) -> String {
    switch confirmation {
    case .dirtyQuit: "Save changes before quitting?"
    case .dirtyReload: "Reload will discard unsaved changes."
    case .overwrite(let url): "Overwrite \(url.path)?"
    case .externalConflict: "The source changed outside csvui."
    }
  }

  private static func columnCoordinate(_ oneBased: Int) -> String {
    var value = max(1, oneBased)
    var result = ""
    while value > 0 {
      value -= 1
      result.insert(Character(UnicodeScalar(65 + value % 26)!), at: result.startIndex)
      value /= 26
    }
    return result
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
