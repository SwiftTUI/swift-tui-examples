public import SwiftTUI

public enum CSVCommandID: String, CaseIterable, Equatable, Hashable, Sendable {
  case reload, save, saveAs, quit
  case editCell, renameHeader, undo, redo
  case insertRowAbove, insertRowBelow, deleteRow
  case insertColumnLeft, insertColumnRight, deleteColumn
  case rowDetail, increaseWidth, decreaseWidth, resetWidth
  case freezeThroughColumn, clearFrozenColumns, columns, resetView
  case find, nextMatch, previousMatch
  case filterCurrent, filterAll, clearFilter
  case cycleSort, sortAscending, sortDescending, clearSort
  case copyCell, copyRow, palette, keyboardReference, about
}

public enum CSVCommandDispatch: Equatable, Sendable {
  case model(CSVAction)
  case copyCell
  case copyRow
  case quit
}

public struct CSVCommandAvailability: Equatable, Sendable {
  public var isEnabled: Bool
  public var reason: String?

  public init(_ isEnabled: Bool, reason: String? = nil) {
    self.isEnabled = isEnabled
    self.reason = reason
  }

  public static let enabled = CSVCommandAvailability(true)
}

public struct CSVCommandDefinition: Equatable, Sendable {
  public var id: CSVCommandID
  public var title: String
  public var menu: CSVMenu?
  public var chord: String?
  public var keys: [KeyPress]
  public var dispatch: CSVCommandDispatch

  public init(
    _ id: CSVCommandID,
    _ title: String,
    menu: CSVMenu? = nil,
    chord: String? = nil,
    keys: [KeyPress] = [],
    dispatch: CSVCommandDispatch
  ) {
    self.id = id
    self.title = title
    self.menu = menu
    self.chord = chord
    self.keys = keys
    self.dispatch = dispatch
  }

  public func availability(in state: CSVState) -> CSVCommandAvailability {
    let hasCell = state.cursor.row != nil && state.cursor.column != nil
    let hasRow = state.cursor.row != nil
    let hasColumn = state.cursor.column != nil
    switch id {
    case .save:
      if state.readOnly { return CSVCommandAvailability(false, reason: "read-only mode") }
      return state.isDirty
        ? .enabled
        : CSVCommandAvailability(false, reason: "no unsaved changes")
    case .saveAs:
      return state.readOnly
        ? CSVCommandAvailability(false, reason: "read-only mode")
        : .enabled
    case .editCell:
      if state.readOnly { return CSVCommandAvailability(false, reason: "read-only mode") }
      return CSVCommandAvailability(hasCell, reason: hasCell ? nil : "no selected cell")
    case .deleteRow:
      if state.readOnly { return CSVCommandAvailability(false, reason: "read-only mode") }
      return CSVCommandAvailability(hasRow, reason: hasRow ? nil : "no selected row")
    case .deleteColumn:
      if state.readOnly { return CSVCommandAvailability(false, reason: "read-only mode") }
      return CSVCommandAvailability(hasColumn, reason: hasColumn ? nil : "no selected column")
    case .insertColumnLeft, .insertColumnRight:
      return state.readOnly
        ? CSVCommandAvailability(false, reason: "read-only mode")
        : .enabled
    case .renameHeader:
      if state.readOnly { return CSVCommandAvailability(false, reason: "read-only mode") }
      if !state.document.dialect.hasHeaders {
        return CSVCommandAvailability(false, reason: "document has no header record")
      }
      return CSVCommandAvailability(hasColumn, reason: hasColumn ? nil : "no selected column")
    case .insertRowAbove, .insertRowBelow:
      if state.readOnly { return CSVCommandAvailability(false, reason: "read-only mode") }
      if state.projection.filter != nil || state.projection.sort != nil {
        return CSVCommandAvailability(false, reason: "clear filter and sort first")
      }
      return .enabled
    case .undo:
      return CSVCommandAvailability(state.canUndo, reason: state.canUndo ? nil : "nothing to undo")
    case .redo:
      return CSVCommandAvailability(state.canRedo, reason: state.canRedo ? nil : "nothing to redo")
    case .rowDetail, .copyCell, .copyRow:
      return CSVCommandAvailability(hasCell, reason: hasCell ? nil : "no selected cell")
    case .increaseWidth, .decreaseWidth, .resetWidth, .freezeThroughColumn, .cycleSort,
      .filterCurrent, .sortAscending, .sortDescending:
      return CSVCommandAvailability(hasColumn, reason: hasColumn ? nil : "no selected column")
    case .clearFrozenColumns:
      return CSVCommandAvailability(
        state.projection.frozenThrough != nil,
        reason: state.projection.frozenThrough == nil ? "no frozen data columns" : nil
      )
    case .clearFilter:
      return CSVCommandAvailability(
        state.projection.filter != nil,
        reason: state.projection.filter == nil ? "no active filter" : nil
      )
    case .clearSort:
      return CSVCommandAvailability(
        state.projection.sort != nil,
        reason: state.projection.sort == nil ? "no active sort" : nil
      )
    case .nextMatch, .previousMatch:
      return CSVCommandAvailability(
        !state.searchMatches.isEmpty,
        reason: state.searchMatches.isEmpty ? "no search matches" : nil
      )
    default: return .enabled
    }
  }
}

public enum CSVCommandCatalog {
  public static let runtimeExitKeys: [KeyPress] = [
    KeyPress(.character("c"), modifiers: .ctrl)
  ]

  public static let quitKeys: [KeyPress] = [KeyPress(.character("q"))]

  public static let definitions: [CSVCommandDefinition] = [
    .init(
      .reload, "Reload", menu: .file, chord: "R", keys: [.init(.character("R"))],
      dispatch: .model(.reload)),
    .init(
      .save, "Save", menu: .file, chord: "Ctrl-S", keys: [.init(.character("s"), modifiers: .ctrl)],
      dispatch: .model(.save)),
    .init(.saveAs, "Save As…", menu: .file, dispatch: .model(.beginSaveAs)),
    .init(.quit, "Quit", menu: .file, chord: "q", keys: quitKeys, dispatch: .quit),

    .init(
      .editCell, "Edit Cell…", menu: .edit, chord: "e", keys: [.init(.character("e"))],
      dispatch: .model(.beginEditCell)),
    .init(
      .renameHeader, "Rename Header…", menu: .edit, chord: "^", keys: [.init(.character("^"))],
      dispatch: .model(.beginRenameHeader)),
    .init(
      .undo, "Undo", menu: .edit, chord: "u", keys: [.init(.character("u"))],
      dispatch: .model(.undo)),
    .init(
      .redo, "Redo", menu: .edit, chord: "Ctrl-R", keys: [.init(.character("r"), modifiers: .ctrl)],
      dispatch: .model(.redo)),
    .init(.insertRowAbove, "Insert Row Above", menu: .edit, dispatch: .model(.insertRowAbove)),
    .init(.insertRowBelow, "Insert Row Below", menu: .edit, dispatch: .model(.insertRowBelow)),
    .init(.deleteRow, "Delete Row", menu: .edit, dispatch: .model(.deleteRow)),
    .init(
      .insertColumnLeft, "Insert Column Left", menu: .edit, dispatch: .model(.insertColumnLeft)),
    .init(
      .insertColumnRight, "Insert Column Right", menu: .edit, dispatch: .model(.insertColumnRight)),
    .init(.deleteColumn, "Delete Column", menu: .edit, dispatch: .model(.deleteColumn)),

    .init(
      .rowDetail, "Row Detail…", menu: .view, chord: "Enter", keys: [.init(.return)],
      dispatch: .model(.openRowDetail)),
    .init(
      .decreaseWidth, "Decrease Width", menu: .view, chord: "[", keys: [.init(.character("["))],
      dispatch: .model(.decreaseWidth)),
    .init(
      .increaseWidth, "Increase Width", menu: .view, chord: "]", keys: [.init(.character("]"))],
      dispatch: .model(.increaseWidth)),
    .init(
      .resetWidth, "Reset Width", menu: .view, chord: "=", keys: [.init(.character("="))],
      dispatch: .model(.resetWidth)),
    .init(
      .freezeThroughColumn, "Freeze Through Column", menu: .view, chord: "z",
      keys: [.init(.character("z"))], dispatch: .model(.freezeThroughCurrentColumn)),
    .init(
      .clearFrozenColumns, "Clear Frozen Columns", menu: .view, chord: "Z",
      keys: [.init(.character("Z"))], dispatch: .model(.clearFrozenColumns)),
    .init(.columns, "Columns…", menu: .view, dispatch: .model(.openColumns)),
    .init(
      .resetView, "Reset View", menu: .view, chord: "r", keys: [.init(.character("r"))],
      dispatch: .model(.resetView)),

    .init(
      .find, "Find…", menu: .data, chord: "/", keys: [.init(.character("/"))],
      dispatch: .model(.beginFind)),
    .init(
      .nextMatch, "Next Match", menu: .data, chord: "n", keys: [.init(.character("n"))],
      dispatch: .model(.nextMatch)),
    .init(
      .previousMatch, "Previous Match", menu: .data, chord: "N", keys: [.init(.character("N"))],
      dispatch: .model(.previousMatch)),
    .init(
      .filterCurrent, "Filter Current Column…", menu: .data, chord: "f",
      keys: [.init(.character("f"))], dispatch: .model(.beginFilterCurrent)),
    .init(
      .filterAll, "Filter All Columns…", menu: .data, chord: "F", keys: [.init(.character("F"))],
      dispatch: .model(.beginFilterAll)),
    .init(.clearFilter, "Clear Filter", menu: .data, dispatch: .model(.clearFilter)),
    .init(
      .cycleSort, "Cycle Sort", chord: "s", keys: [.init(.character("s"))],
      dispatch: .model(.cycleSort)),
    .init(.sortAscending, "Sort Ascending", menu: .data, dispatch: .model(.sort(.ascending))),
    .init(.sortDescending, "Sort Descending", menu: .data, dispatch: .model(.sort(.descending))),
    .init(.clearSort, "Clear Sort", menu: .data, dispatch: .model(.clearSort)),

    .init(.copyCell, "Copy Cell", chord: "y", keys: [.init(.character("y"))], dispatch: .copyCell),
    .init(.copyRow, "Copy Row", chord: "Y", keys: [.init(.character("Y"))], dispatch: .copyRow),
    .init(
      .palette, "Command Palette", chord: ":", keys: [.init(.character(":"))],
      dispatch: .model(.openPalette)),
    .init(
      .keyboardReference, "Keyboard Reference", menu: .help, chord: "?",
      keys: [.init(.character("?"))], dispatch: .model(.openHelp)),
    .init(.about, "About csvui", menu: .help, dispatch: .model(.openHelp)),
  ]

  public static func definition(_ id: CSVCommandID) -> CSVCommandDefinition {
    definitions.first { $0.id == id }!
  }

  public static func definitions(for menu: CSVMenu) -> [CSVCommandDefinition] {
    definitions.filter { $0.menu == menu }
  }

  public static func command(for keyPress: KeyPress) -> CSVCommandDefinition? {
    let normalized = normalize(keyPress)
    return definitions.first { definition in
      definition.keys.contains { normalize($0) == normalized }
    }
  }

  public static func normalize(_ keyPress: KeyPress) -> KeyPress {
    guard case .character = keyPress.key else { return keyPress }
    var modifiers = keyPress.modifiers
    modifiers.remove(.shift)
    return KeyPress(keyPress.key, modifiers: modifiers)
  }
}
