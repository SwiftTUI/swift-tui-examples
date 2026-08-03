public import Foundation

public struct CSVViewport: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int = 80, height: Int = 24) {
    self.width = max(0, width)
    self.height = max(0, height)
  }

  public var isTooSmall: Bool { width < 40 || height < 10 }
  public var dataRowCapacity: Int { max(1, height - 3) }
}

public struct CSVCursor: Equatable, Sendable {
  public var row: RowID?
  public var column: ColumnID?
  public var rowOrigin: Int
  public var scrollingColumnOrigin: Int
  public var projectedRowOrdinal: Int?
  public var projectedColumnOrdinal: Int?

  public init(
    row: RowID? = nil,
    column: ColumnID? = nil,
    rowOrigin: Int = 0,
    scrollingColumnOrigin: Int = 0,
    projectedRowOrdinal: Int? = nil,
    projectedColumnOrdinal: Int? = nil
  ) {
    self.row = row
    self.column = column
    self.rowOrigin = max(0, rowOrigin)
    self.scrollingColumnOrigin = max(0, scrollingColumnOrigin)
    self.projectedRowOrdinal = projectedRowOrdinal ?? (row == nil ? nil : 0)
    self.projectedColumnOrdinal = projectedColumnOrdinal ?? (column == nil ? nil : 0)
  }
}

public enum CSVSortDirection: String, Equatable, Sendable {
  case ascending
  case descending

  public var marker: String { self == .ascending ? "↑" : "↓" }
}

public struct CSVSortSpec: Equatable, Sendable {
  public var column: ColumnID
  public var direction: CSVSortDirection

  public init(column: ColumnID, direction: CSVSortDirection) {
    self.column = column
    self.direction = direction
  }
}

public enum CSVFilterScope: Equatable, Sendable {
  case column(ColumnID)
  case allVisibleColumns
}

public struct CSVFilterSpec: Equatable, Sendable {
  public var scope: CSVFilterScope
  public var query: String

  public init(scope: CSVFilterScope, query: String) {
    self.scope = scope
    self.query = query
  }
}

public struct CSVSearchMatch: Equatable, Sendable {
  public var address: CSVCellAddress

  public init(address: CSVCellAddress) { self.address = address }
}

public struct CSVViewProjection: Equatable, Sendable {
  public var visibleRows: [RowID]
  public var visibleColumns: [ColumnID]
  public var hiddenColumns: Set<ColumnID>
  public var frozenThrough: ColumnID?
  public var widths: [ColumnID: Int]
  public var manualWidthOverrides: Set<ColumnID>
  public var filter: CSVFilterSpec?
  public var sort: CSVSortSpec?

  public init(journal: CSVEditJournal) {
    visibleRows = journal.rowOrder
    visibleColumns = journal.columnOrder
    hiddenColumns = []
    frozenThrough = nil
    widths = [:]
    manualWidthOverrides = []
    filter = nil
    sort = nil
  }
}

public enum CSVMenu: String, CaseIterable, Equatable, Sendable {
  case file = "File"
  case edit = "Edit"
  case view = "View"
  case data = "Data"
  case help = "Help"
}

public enum CSVPrompt: Equatable, Sendable {
  case find
  case filterCurrent(ColumnID)
  case filterAll
  case renameHeader(ColumnID)
  case goTo
}

public enum CSVConfirmation: Equatable, Sendable {
  case dirtyQuit
  case dirtyReload
  case overwrite(URL)
  case externalConflict
}

public enum CSVInteractionMode: Equatable, Sendable {
  case browse
  case menu(CSVMenu)
  case prompt(CSVPrompt)
  case palette
  case rowDetail(RowID)
  case editing(CSVCellAddress)
  case columns
  case saveAs
  case confirmation(CSVConfirmation)
  case help
}

public struct CSVPromptState: Equatable, Sendable {
  public var text: String
  public var diagnostic: String?

  public init(text: String = "", diagnostic: String? = nil) {
    self.text = text
    self.diagnostic = diagnostic
  }
}

public struct CSVEditorState: Equatable, Sendable {
  public var text: String

  public init(text: String = "") { self.text = text }
}

public enum CSVDiagnosticSeverity: Equatable, Sendable {
  case information
  case warning
  case error
}

public struct CSVDiagnostic: Equatable, Sendable {
  public var severity: CSVDiagnosticSeverity
  public var message: String

  public init(_ severity: CSVDiagnosticSeverity, _ message: String) {
    self.severity = severity
    self.message = message
  }
}

public struct CSVStructuralCounters: Equatable, Sendable {
  public var realizedRows: Int
  public var realizedScrollingColumns: Int
  public var realizedFrozenColumns: Int
  public var realizedCells: Int
  public var decodedRows: Int
  public var widthSamples: Int
  public var inspectedColumns: Int

  public init(
    realizedRows: Int = 0,
    realizedScrollingColumns: Int = 0,
    realizedFrozenColumns: Int = 0,
    realizedCells: Int = 0,
    decodedRows: Int = 0,
    widthSamples: Int = 0,
    inspectedColumns: Int = 0
  ) {
    self.realizedRows = realizedRows
    self.realizedScrollingColumns = realizedScrollingColumns
    self.realizedFrozenColumns = realizedFrozenColumns
    self.realizedCells = realizedCells
    self.decodedRows = decodedRows
    self.widthSamples = widthSamples
    self.inspectedColumns = inspectedColumns
  }
}

public struct CSVModelConfiguration: Equatable, Sendable {
  public var watchesDocument: Bool
  public var themeSelection: CSVThemeSelection
  public var workingDirectory: URL

  public init(
    watchesDocument: Bool = false,
    themeSelection: CSVThemeSelection = .builtIn,
    workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) {
    self.watchesDocument = watchesDocument
    self.themeSelection = themeSelection
    self.workingDirectory = workingDirectory.standardizedFileURL
  }
}

public struct CSVState: Equatable, Sendable {
  public var document: CSVDocument
  public var journal: CSVEditJournal
  public var projection: CSVViewProjection
  public var cursor: CSVCursor
  public var mode: CSVInteractionMode
  public var prompt: CSVPromptState
  public var editor: CSVEditorState
  public var theme: CSVTheme
  public var viewport: CSVViewport
  public var readOnly: Bool
  public var searchQuery: String
  public var searchMatches: [CSVSearchMatch]
  public var selectedSearchMatch: Int?
  public var searchResultsTruncated: Bool
  public var isSearching: Bool
  public var isLoading: Bool
  public var isFiltering: Bool
  public var isSorting: Bool
  public var isSaving: Bool
  public var isReloading: Bool
  public var diagnostic: CSVDiagnostic?
  public var currentRevision: UInt64
  public var cleanRevision: UInt64
  public var undoAvailable: Bool
  public var redoAvailable: Bool
  public var externalChangePending: Bool
  public var allowsNextTermination: Bool
  public var terminationRequestGeneration: UInt64
  public var saveAsPath: String
  public var counters: CSVStructuralCounters

  public init(
    document: CSVDocument,
    theme: CSVTheme,
    readOnly: Bool,
    diagnostic: CSVDiagnostic? = nil
  ) {
    let journal = CSVEditJournal(document: document)
    self.document = document
    self.journal = journal
    projection = CSVViewProjection(journal: journal)
    cursor = CSVCursor(row: journal.rowOrder.first, column: journal.columnOrder.first)
    mode = .browse
    prompt = CSVPromptState()
    editor = CSVEditorState()
    self.theme = theme
    viewport = CSVViewport()
    self.readOnly = readOnly
    searchQuery = ""
    searchMatches = []
    selectedSearchMatch = nil
    searchResultsTruncated = false
    isSearching = false
    isLoading = false
    isFiltering = false
    isSorting = false
    isSaving = false
    isReloading = false
    self.diagnostic = diagnostic
    currentRevision = 0
    cleanRevision = 0
    undoAvailable = false
    redoAvailable = false
    externalChangePending = false
    allowsNextTermination = false
    terminationRequestGeneration = 0
    saveAsPath = ""
    counters = CSVStructuralCounters()
  }

  public var isDirty: Bool { currentRevision != cleanRevision }
  public var canUndo: Bool { undoAvailable }
  public var canRedo: Bool { redoAvailable }
  public var rowCount: Int { journal.rowOrder.count }
  public var columnCount: Int { journal.columnOrder.count }
}
