import Foundation

enum CSVGridCellID: Equatable, Hashable, Sendable {
  case header(ColumnID)
  case data(CSVCellAddress)
}

enum CSVGridCellRole: Equatable, Sendable {
  case header
  case body
  case selected
  case searchMatch
  case edited
}

struct CSVGridCellPresentation: Equatable, Sendable {
  let id: CSVGridCellID
  let address: CSVCellAddress?
  let projectedRowOrdinal: Int?
  let projectedColumnOrdinal: Int
  let text: String
  let width: Int
  let role: CSVGridCellRole
  let foreground: CSVThemeColor
  let background: CSVThemeColor

  init(
    id: CSVGridCellID,
    address: CSVCellAddress?,
    projectedRowOrdinal: Int?,
    projectedColumnOrdinal: Int,
    text: String,
    width: Int,
    role: CSVGridCellRole,
    foreground: CSVThemeColor,
    background: CSVThemeColor
  ) {
    self.id = id
    self.address = address
    self.projectedRowOrdinal = projectedRowOrdinal
    self.projectedColumnOrdinal = projectedColumnOrdinal
    self.text = text
    self.width = max(1, width)
    self.role = role
    self.foreground = foreground
    self.background = background
  }
}

enum CSVGridRowID: Equatable, Hashable, Sendable {
  case header
  case data(RowID)
}

struct CSVGridRowPresentation: Equatable, Sendable {
  let id: CSVGridRowID
  let label: String
  let cells: [CSVGridCellPresentation]
}

struct CSVGridPresentation: Equatable, Sendable {
  let header: CSVGridRowPresentation
  let rows: [CSVGridRowPresentation]
  let gutterWidth: Int
  let gutterForeground: CSVThemeColor
  let gutterBackground: CSVThemeColor
  let border: CSVThemeColor
  let counters: CSVStructuralCounters
}

struct CSVGridSelectionPresentation: Equatable, Sendable {
  let address: CSVCellAddress
  let projectedRowOrdinal: Int
  let projectedColumnOrdinal: Int
  let text: String
  let width: Int
  let x: Int
  let y: Int
  let foreground: CSVThemeColor
  let background: CSVThemeColor
}

struct CSVToolbarItemPresentation: Equatable, Sendable {
  let menu: CSVMenu
  let isActive: Bool
  let foreground: CSVThemeColor
  let background: CSVThemeColor
}

struct CSVRootStylePresentation: Equatable, Sendable {
  let theme: CSVTheme
}

struct CSVToolbarPresentation: Equatable, Sendable {
  let theme: CSVTheme
  let items: [CSVToolbarItemPresentation]
  let sourceLabel: String?
  let dirtyMarker: String
  let shapeLabel: String?
}

struct CSVLoadingPresentation: Equatable, Sendable {
  let theme: CSVTheme
  let message: String
}

struct CSVStatusPresentation: Equatable, Sendable {
  let theme: CSVTheme
  let promptPrefix: String?
  let promptText: String
  let promptDiagnostic: String?
  let cellStatus: String
  let projectionStatus: String
  let statusColor: CSVThemeColor
}

struct CSVTerminationPresentation: Equatable, Sendable {
  let requestGeneration: UInt64
}

struct CSVCommandRowPresentation: Equatable, Sendable {
  let definition: CSVCommandDefinition
  let availability: CSVCommandAvailability
}

struct CSVRowDetailFieldPresentation: Equatable, Sendable {
  let column: ColumnID
  let header: String
  let value: String
}

struct CSVColumnPresentation: Equatable, Sendable {
  let column: ColumnID
  let label: String
  let isHidden: Bool
}

enum CSVOverlayContent: Equatable, Sendable {
  case menu(CSVMenu, rows: [CSVCommandRowPresentation])
  case help(rows: [CSVCommandDefinition])
  case palette(query: String, rows: [CSVCommandRowPresentation])
  case rowDetail(row: RowID, fields: [CSVRowDetailFieldPresentation], readOnly: Bool)
  case editing(address: CSVCellAddress, rowLabel: String, columnLabel: String, text: String)
  case columns([CSVColumnPresentation])
  case saveAs(path: String)
  case confirmation(CSVConfirmation, message: String, hint: String)
}

struct CSVOverlayPresentation: Equatable, Sendable {
  let title: String
  let viewport: CSVViewport
  let theme: CSVTheme
  let content: CSVOverlayContent
}

enum CSVPresentationAction: Equatable, Sendable {
  case selectCell(CSVCellAddress, projectedRowOrdinal: Int, projectedColumnOrdinal: Int)
  case scrollWheel(deltaX: Int, deltaY: Int)
}
