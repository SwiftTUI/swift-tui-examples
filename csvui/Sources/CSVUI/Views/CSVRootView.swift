import Foundation
public import SwiftTUI

public struct CSVRootView: View {
  private let model: CSVModel
  @Environment(\.clipboardWriteAction) private var clipboardWrite
  @Environment(\.requestTermination) private var requestTermination
  @FocusState private var editorFocused: Bool

  public init(model: CSVModel) { self.model = model }

  public var body: some View {
    GeometryReader { geometry in
      let viewport = CSVViewport(width: geometry.size.width, height: geometry.size.height)
      ZStack(alignment: .topLeading) {
        if viewport.isTooSmall {
          terminalTooSmall
        } else {
          VStack(alignment: .leading, spacing: 0) {
            toolbar
            if model.state.isLoading {
              loadingSurface
                .frame(
                  width: viewport.width,
                  height: max(1, viewport.height - 2),
                  alignment: .center
                )
            } else {
              CSVGridView(model: model)
                .frame(
                  width: viewport.width,
                  height: max(1, viewport.height - 2),
                  alignment: .topLeading
                )
            }
            statusRow
          }
          .disabled(model.state.mode != .browse)
        }
        transientOverlay
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .foregroundStyle(model.state.theme.foreground.swiftTUIColor)
      .background(model.state.theme.background.swiftTUIColor)
      .focusable(!isEditingCell)
      .onKeyPress(.any, perform: handleKeyPress)
      .task(id: viewport) { @MainActor in
        model.send(.updateViewport(viewport))
      }
      .task(id: model.state.terminationRequestGeneration) { @MainActor in
        guard model.state.terminationRequestGeneration > 0 else { return }
        _ = requestTermination()
      }
      .onTerminationRequest { request in
        if case .inputEnded = request { return .allow }
        return model.shouldAllowTermination() ? .allow : .cancel
      }
    }
    .panel(id: "csvui")
    .keyCommand("Save", key: .character("s"), modifiers: .ctrl) {
      handleSaveCommand()
    }
  }

  public func shutdown() async { await model.shutdown() }

  private var isEditingCell: Bool {
    if case .editing = model.state.mode { return true }
    return false
  }

  private var terminalTooSmall: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("csvui").bold().foregroundStyle(model.state.theme.accent.swiftTUIColor)
      Text("terminal too small (need 40×10)")
      Text("resize or press Ctrl-C to quit")
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
    }
    .padding(1)
  }

  private var loadingSurface: some View {
    VStack(alignment: .center, spacing: 1) {
      Text("csvui").bold().foregroundStyle(model.state.theme.accent.swiftTUIColor)
      Text(model.state.diagnostic?.message ?? "loading…")
      Text("q or Ctrl-C quits safely")
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
    }
  }

  private var toolbar: some View {
    HStack(spacing: 1) {
      ForEach(CSVMenu.allCases, id: \.self) { menu in
        Button(menu.rawValue) { model.send(.openMenu(menu)) }
          .buttonStyle(.plain)
          .fixedSize(horizontal: true, vertical: true)
          .foregroundStyle(
            model.state.mode == .menu(menu)
              ? model.state.theme.menuActiveForeground.swiftTUIColor
              : model.state.theme.menuForeground.swiftTUIColor
          )
          .background(
            model.state.mode == .menu(menu)
              ? model.state.theme.menuActiveBackground.swiftTUIColor
              : model.state.theme.menuBackground.swiftTUIColor
          )
      }
      Spacer(minLength: 0)
      if model.state.viewport.width >= 72 {
        Text(model.state.document.source.displayName)
          .lineLimit(1)
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
        Text(model.state.isDirty ? "●" : "")
          .foregroundStyle(model.state.theme.edited.swiftTUIColor)
        Text("\(model.state.rowCount) × \(model.state.columnCount)")
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
      }
    }
    .padding(.horizontal, 1)
    .frame(height: 1, alignment: .topLeading)
    .background(model.state.theme.menuBackground.swiftTUIColor)
  }

  @ViewBuilder
  private var statusRow: some View {
    if case .prompt(let prompt) = model.state.mode {
      HStack(spacing: 1) {
        Text(promptPrefix(prompt) + model.state.prompt.text + "▏")
          .foregroundStyle(model.state.theme.accent.swiftTUIColor)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let diagnostic = model.state.prompt.diagnostic {
          Text(diagnostic)
            .foregroundStyle(model.state.theme.error.swiftTUIColor)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 1)
      .frame(height: 1)
    } else {
      HStack(spacing: 1) {
        Text(cellStatus)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(projectionStatus)
          .foregroundStyle(statusColor)
          .lineLimit(1)
      }
      .padding(.horizontal, 1)
      .frame(height: 1)
    }
  }

  private var cellStatus: String {
    guard let row = model.state.cursor.row, let column = model.state.cursor.column else {
      return model.state.diagnostic?.message ?? "empty document"
    }
    if let diagnostic = model.state.diagnostic { return diagnostic.message }
    let rowPosition = (model.state.projection.visibleRows.firstIndex(of: row) ?? 0) + 1
    let columnPosition = (model.state.projection.visibleColumns.firstIndex(of: column) ?? 0) + 1
    let coordinate = Self.columnCoordinate(columnPosition) + String(rowPosition)
    return "\(coordinate) · \(model.headerLabel(column)) · \(model.value(row: row, column: column))"
  }

  private var projectionStatus: String {
    var values: [String] = []
    if model.state.readOnly { values.append("READ ONLY") }
    if model.state.externalChangePending { values.append("EXTERNAL CHANGE") }
    if model.state.isSaving { values.append("SAVING…") }
    if model.state.isReloading { values.append("RELOADING…") }
    if model.state.isFiltering {
      values.append("FILTERING…")
    } else if let filter = model.state.projection.filter {
      var label = "FILTER \(model.state.projection.visibleRows.count)/\(model.state.rowCount)"
      if case .column(let column) = filter.scope,
        model.state.projection.hiddenColumns.contains(column)
      {
        label += " HIDDEN COLUMN"
      }
      values.append(label)
    }
    if model.state.isSorting {
      values.append("SORTING…")
    } else if let sort = model.state.projection.sort {
      values.append("SORT \(model.headerLabel(sort.column)) \(sort.direction.marker)")
    }
    if model.state.isSearching {
      values.append("SEARCHING…")
    } else if !model.state.searchQuery.isEmpty {
      values.append(
        "MATCH \(model.state.searchMatches.count)\(model.state.searchResultsTruncated ? "+" : "")")
    }
    if model.state.document.irregularDataRecordCount > 0 {
      values.append("IRREGULAR \(model.state.document.irregularDataRecordCount)")
    }
    return values.joined(separator: "  ")
  }

  private var statusColor: Color {
    guard let diagnostic = model.state.diagnostic else {
      return model.state.theme.muted.swiftTUIColor
    }
    return switch diagnostic.severity {
    case .information: model.state.theme.muted.swiftTUIColor
    case .warning: model.state.theme.warning.swiftTUIColor
    case .error: model.state.theme.error.swiftTUIColor
    }
  }

  @ViewBuilder
  private var transientOverlay: some View {
    switch model.state.mode {
    case .menu(let menu):
      CSVMenuDropdown(menu: menu, model: model, dispatch: dispatch)
        .offset(x: menuOffset(menu), y: 1)
    case .help:
      overlayCard(title: "Keyboard Reference") { helpContent }
    case .palette:
      overlayCard(title: "Command Palette") { paletteContent }
    case .rowDetail(let row):
      overlayCard(title: "Row \(model.rowLabel(row))") { rowDetail(row) }
    case .editing(let address):
      overlayCard(title: "Edit \(model.headerLabel(address.column))") {
        editorContent(address)
      }
    case .columns:
      overlayCard(title: "Columns") { columnsContent }
    case .saveAs:
      overlayCard(title: "Save As") { saveAsContent }
    case .confirmation(let confirmation):
      overlayCard(title: "Confirm") { confirmationContent(confirmation) }
    default:
      EmptyView()
    }
  }

  private var helpContent: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(CSVCommandCatalog.definitions, id: \.id) { definition in
          HStack(spacing: 1) {
            Text(definition.chord ?? "")
              .frame(width: 12, alignment: .leading)
              .foregroundStyle(model.state.theme.accent.swiftTUIColor)
            Text(definition.title)
          }
        }
        Text("Arrows/hjkl move · PgUp/PgDn page · g/G first/last row · 0/$ first/last column")
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
        Text("csvui 0.1 · viewer-first CSV/TSV reader and safe editor")
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
      }
    }
  }

  private var paletteContent: some View {
    let matches = paletteMatches
    return VStack(alignment: .leading, spacing: 0) {
      Text(":" + model.state.prompt.text + "▏")
        .foregroundStyle(model.state.theme.accent.swiftTUIColor)
      Divider()
      ForEach(Array(matches.prefix(12)), id: \.id) { definition in
        let availability = definition.availability(in: model.state)
        Button(action: { dispatch(definition) }) {
          HStack(spacing: 1) {
            Text(definition.title)
            Spacer(minLength: 1)
            Text(definition.chord ?? "")
              .foregroundStyle(model.state.theme.muted.swiftTUIColor)
          }
        }
        .buttonStyle(.plain)
        .disabled(!availability.isEnabled)
      }
      if matches.isEmpty { Text("No matching commands") }
    }
  }

  private var paletteMatches: [CSVCommandDefinition] {
    let query = model.state.prompt.text
    guard !query.isEmpty else { return CSVCommandCatalog.definitions }
    return CSVCommandCatalog.definitions.filter {
      $0.title.range(of: query, options: .caseInsensitive) != nil
    }
  }

  private func rowDetail(_ row: RowID) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 1) {
          ForEach(model.state.projection.visibleColumns, id: \.self) { column in
            VStack(alignment: .leading, spacing: 0) {
              Text(model.headerLabel(column)).bold()
                .foregroundStyle(model.state.theme.accent.swiftTUIColor)
              Text(detailValue(row: row, column: column))
            }
          }
        }
      }
      HStack(spacing: 2) {
        Button("Copy Cell") { dispatch(CSVCommandCatalog.definition(.copyCell)) }
        Button("Edit Cell") { dispatch(CSVCommandCatalog.definition(.editCell)) }
          .disabled(model.state.readOnly)
      }
    }
  }

  private func detailValue(row: RowID, column: ColumnID) -> String {
    let value = model.value(row: row, column: column)
    if !value.isEmpty { return value }
    guard let base = model.state.journal.originalColumnOrder.firstIndex(of: column),
      let decoded = try? model.state.document.decodeSourceRow(row)
    else { return "(missing)" }
    return decoded.fields.indices.contains(base) ? "(empty)" : "(missing)"
  }

  private func editorContent(_ address: CSVCellAddress) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(model.rowLabel(address.row)) · \(model.headerLabel(address.column))")
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
      TextEditor(
        text: Binding(
          get: { model.state.editor.text },
          set: { model.send(.updateEditor($0)) }
        )
      )
      .focused($editorFocused)
      .defaultFocus($editorFocused, true)
      .frame(
        width: max(20, min(68, model.state.viewport.width - 8)),
        height: max(4, min(12, model.state.viewport.height - 10))
      )
      HStack(spacing: 2) {
        Button("Save  Ctrl-S") { model.send(.commitEditor) }
        Button("Cancel  Esc") { model.send(.dismissTransient) }
      }
    }
  }

  private var columnsContent: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(model.state.journal.columnOrder, id: \.self) { column in
          let hidden = model.state.projection.hiddenColumns.contains(column)
          Button("\(hidden ? "○" : "●") \(model.headerLabel(column))") {
            model.send(.toggleColumnVisibility(column))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var saveAsContent: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Path")
      Text(model.state.saveAsPath + "▏")
        .foregroundStyle(model.state.theme.accent.swiftTUIColor)
      Text("Enter save · Escape cancel")
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
    }
  }

  private func confirmationContent(_ confirmation: CSVConfirmation) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(confirmationMessage(confirmation))
      HStack(spacing: 2) {
        if confirmation == .dirtyQuit || confirmation == .dirtyReload {
          Button("Save") { model.send(.save) }
          Button("Discard") { model.send(.confirmDiscard) }
        } else if case .overwrite = confirmation {
          Button("Overwrite") { model.send(.confirmSaveAs(overwrite: true)) }
        } else if confirmation == .externalConflict {
          Button("Reload") { model.send(.reload) }
          Button("Save As") { model.send(.beginSaveAs) }
        }
        Button("Cancel") { model.send(.cancelConfirmation) }
      }
      Text(confirmationHint(confirmation))
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
    }
  }

  private func confirmationHint(_ confirmation: CSVConfirmation) -> String {
    switch confirmation {
    case .dirtyQuit, .dirtyReload: "S save · D discard · Esc cancel"
    case .overwrite: "O overwrite · Esc cancel"
    case .externalConflict: "R reload · A Save As · Esc cancel"
    }
  }

  private func confirmationMessage(_ confirmation: CSVConfirmation) -> String {
    switch confirmation {
    case .dirtyQuit: "Save changes before quitting?"
    case .dirtyReload: "Reload will discard unsaved changes."
    case .overwrite(let url): "Overwrite \(url.path)?"
    case .externalConflict: "The source changed outside csvui."
    }
  }

  private func overlayCard<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 1) {
        Text(title).bold()
        Spacer(minLength: 0)
        Text("Esc").foregroundStyle(model.state.theme.muted.swiftTUIColor)
      }
      Divider()
      content()
    }
    .padding(1)
    .frame(
      width: min(76, max(28, model.state.viewport.width - 4)),
      height: min(20, max(8, model.state.viewport.height - 4)),
      alignment: .topLeading
    )
    .background(model.state.theme.background.swiftTUIColor)
    .border(model.state.theme.border.swiftTUIColor)
    .offset(x: 2, y: 2)
  }

  private func handleKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    if CSVCommandCatalog.runtimeExitKeys.contains(keyPress), model.state.mode == .browse {
      return .ignored
    }
    switch model.state.mode {
    case .browse: return handleBrowseKey(keyPress)
    case .prompt: return handlePromptKey(keyPress)
    case .palette: return handlePaletteKey(keyPress)
    case .editing:
      if keyPress.key == .escape {
        model.send(.dismissTransient)
        return .handled
      }
      if keyPress == KeyPress(.character("s"), modifiers: .ctrl) {
        model.send(.commitEditor)
        return .handled
      }
      return .ignored
    case .menu(let menu): return handleMenuKey(keyPress, menu: menu)
    case .confirmation: return handleConfirmationKey(keyPress)
    case .saveAs: return handleSaveAsKey(keyPress)
    case .help, .rowDetail, .columns:
      if keyPress.key == .escape || keyPress.key == .return {
        model.send(.dismissTransient)
      }
      return .handled
    }
  }

  private func handleSaveCommand() {
    if case .editing = model.state.mode {
      model.send(.commitEditor)
    } else if model.state.mode == .browse {
      model.send(.save)
    }
  }

  private func handleBrowseKey(_ keyPress: KeyPress) -> KeyPressResult {
    switch keyPress {
    case KeyPress(.character("h")), KeyPress(.arrowLeft): model.send(.moveColumns(-1))
    case KeyPress(.character("l")), KeyPress(.arrowRight): model.send(.moveColumns(1))
    case KeyPress(.character("j")), KeyPress(.arrowDown): model.send(.moveRows(1))
    case KeyPress(.character("k")), KeyPress(.arrowUp): model.send(.moveRows(-1))
    case KeyPress(.pageDown), KeyPress(.character("f"), modifiers: .ctrl): model.send(.pageRows(1))
    case KeyPress(.pageUp), KeyPress(.character("b"), modifiers: .ctrl): model.send(.pageRows(-1))
    case KeyPress(.character("d"), modifiers: .ctrl):
      model.send(.moveRows(max(1, model.state.viewport.dataRowCapacity / 2)))
    case KeyPress(.character("u"), modifiers: .ctrl):
      model.send(.moveRows(-max(1, model.state.viewport.dataRowCapacity / 2)))
    case KeyPress(.character("g")): model.send(.firstRow)
    case KeyPress(.character("G")): model.send(.lastRow)
    case KeyPress(.character("0")), KeyPress(.home): model.send(.firstColumn)
    case KeyPress(.character("$")), KeyPress(.end): model.send(.lastColumn)
    default:
      guard let command = CSVCommandCatalog.command(for: keyPress) else { return .ignored }
      dispatch(command)
    }
    return .handled
  }

  private func handlePromptKey(_ keyPress: KeyPress) -> KeyPressResult {
    if CSVCommandCatalog.runtimeExitKeys.contains(keyPress) { return .ignored }
    switch keyPress.key {
    case .escape: model.send(.dismissTransient)
    case .return: model.send(.submitPrompt)
    case .backspace: model.send(.updatePrompt(String(model.state.prompt.text.dropLast())))
    case .space: model.send(.updatePrompt(model.state.prompt.text + " "))
    case .character(let character) where keyPress.modifiers.isEmpty || keyPress.modifiers == .shift:
      model.send(.updatePrompt(model.state.prompt.text + String(character)))
    default: break
    }
    return .handled
  }

  private func handlePaletteKey(_ keyPress: KeyPress) -> KeyPressResult {
    if keyPress.key == .return {
      if let first = paletteMatches.first { dispatch(first) }
      return .handled
    }
    return handlePromptKey(keyPress)
  }

  private func handleMenuKey(_ keyPress: KeyPress, menu: CSVMenu) -> KeyPressResult {
    if keyPress.key == .escape {
      model.send(.dismissTransient)
      return .handled
    }
    if keyPress.key == .arrowRight || keyPress.key == .arrowLeft {
      let menus = CSVMenu.allCases
      let index = menus.firstIndex(of: menu) ?? 0
      let delta = keyPress.key == .arrowRight ? 1 : -1
      model.send(.openMenu(menus[(index + delta + menus.count) % menus.count]))
      return .handled
    }
    return .ignored
  }

  private func handleConfirmationKey(_ keyPress: KeyPress) -> KeyPressResult {
    guard case .confirmation(let confirmation) = model.state.mode else { return .handled }
    switch keyPress.key {
    case .escape: model.send(.cancelConfirmation)
    case .character("d"), .character("D"):
      if confirmation == .dirtyQuit || confirmation == .dirtyReload {
        model.send(.confirmDiscard)
        if confirmation == .dirtyQuit { _ = requestTermination() }
      }
    case .character("s"), .character("S"):
      if confirmation == .dirtyQuit || confirmation == .dirtyReload { model.send(.save) }
    case .character("o"), .character("O"):
      if case .overwrite = confirmation { model.send(.confirmSaveAs(overwrite: true)) }
    case .character("r"), .character("R"):
      if confirmation == .externalConflict { model.send(.reload) }
    case .character("a"), .character("A"):
      if confirmation == .externalConflict { model.send(.beginSaveAs) }
    default: break
    }
    return .handled
  }

  private func handleSaveAsKey(_ keyPress: KeyPress) -> KeyPressResult {
    switch keyPress.key {
    case .escape: model.send(.dismissTransient)
    case .return: model.send(.confirmSaveAs(overwrite: false))
    case .backspace: model.send(.updateSaveAsPath(String(model.state.saveAsPath.dropLast())))
    case .space: model.send(.updateSaveAsPath(model.state.saveAsPath + " "))
    case .character(let character) where keyPress.modifiers.isEmpty || keyPress.modifiers == .shift:
      model.send(.updateSaveAsPath(model.state.saveAsPath + String(character)))
    default: break
    }
    return .handled
  }

  private func dispatch(_ definition: CSVCommandDefinition) {
    let availability = definition.availability(in: model.state)
    guard availability.isEnabled else {
      model.announce(CSVDiagnostic(.warning, availability.reason ?? "command unavailable"))
      return
    }
    if case .menu = model.state.mode { model.send(.dismissTransient) }
    if case .palette = model.state.mode { model.send(.dismissTransient) }
    switch definition.dispatch {
    case .model(let action): model.send(action)
    case .copyCell:
      guard let text = model.copyCellText(), clipboardWrite(text) else {
        model.send(.copyFailed)
        return
      }
      model.send(.copySucceeded("cell"))
    case .copyRow:
      guard let text = model.copyRowText(), clipboardWrite(text) else {
        model.send(.copyFailed)
        return
      }
      model.send(.copySucceeded("row"))
    case .quit:
      if model.requestQuitFromCommand() { _ = requestTermination() }
    }
  }

  private func promptPrefix(_ prompt: CSVPrompt) -> String {
    switch prompt {
    case .find: "/"
    case .filterCurrent: "filter column: "
    case .filterAll: "filter all: "
    case .renameHeader: "header: "
    case .goTo: "go to: "
    }
  }

  private func menuOffset(_ menu: CSVMenu) -> Int {
    switch menu {
    case .file: 1
    case .edit: 7
    case .view: 13
    case .data: 19
    case .help: 25
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
}

private struct CSVMenuDropdown: View {
  let menu: CSVMenu
  let model: CSVModel
  let dispatch: @MainActor (CSVCommandDefinition) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(CSVCommandCatalog.definitions(for: menu), id: \.id) { definition in
        let availability = definition.availability(in: model.state)
        Button(action: { dispatch(definition) }) {
          HStack(spacing: 1) {
            Text(definition.title)
            Spacer(minLength: 2)
            Text(definition.chord ?? "")
              .foregroundStyle(model.state.theme.muted.swiftTUIColor)
          }
        }
        .buttonStyle(.plain)
        .disabled(!availability.isEnabled)
      }
    }
    .padding(1)
    .frame(minWidth: 26, alignment: .leading)
    .background(model.state.theme.menuBackground.swiftTUIColor)
    .border(model.state.theme.border.swiftTUIColor)
  }
}

private struct CSVGridView: View {
  let model: CSVModel

  var body: some View {
    let slice = CSVGridLayout.slice(state: model.state)
    VStack(alignment: .leading, spacing: 0) {
      gridRow(slice: slice, row: nil)
      ForEach(slice.rows, id: \.self) { row in
        gridRow(slice: slice, row: row)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onScrollWheel { event in
      let previous = model.state.cursor
      model.send(.scrollWheel(deltaX: event.deltaX, deltaY: event.deltaY))
      return model.state.cursor == previous ? .ignored : .handled
    }
  }

  private func gridRow(slice: CSVGridSlice, row: RowID?) -> some View {
    HStack(spacing: 0) {
      Text(row.map(model.rowLabel) ?? "row")
        .frame(width: slice.gutterWidth, alignment: .trailing)
        .foregroundStyle(model.state.theme.gutter.swiftTUIColor)
        .background(model.state.theme.headerBackground.swiftTUIColor)
      Text("│").foregroundStyle(model.state.theme.border.swiftTUIColor)
      ForEach(slice.frozenColumns, id: \.self) { column in
        cell(row: row, column: column, width: slice.widths[column, default: 4])
        Text("│").foregroundStyle(model.state.theme.border.swiftTUIColor)
      }
      ForEach(slice.scrollingColumns, id: \.self) { column in
        cell(row: row, column: column, width: slice.widths[column, default: 4])
        Text("│").foregroundStyle(model.state.theme.border.swiftTUIColor)
      }
      Spacer(minLength: 0)
    }
    .frame(height: 1)
  }

  private func cell(row: RowID?, column: ColumnID, width: Int) -> some View {
    let selected =
      row != nil && row == model.state.cursor.row && column == model.state.cursor.column
    let searchMatch = row.map { model.isSearchMatch(row: $0, column: column) } ?? false
    let text: String
    if let row {
      text = model.displayValue(row: row, column: column)
    } else {
      let marker =
        model.state.projection.sort?.column == column
        ? " \(model.state.projection.sort!.direction.marker)"
        : ""
      text = model.headerLabel(column) + marker
    }
    return Text(" " + text)
      .lineLimit(1)
      .frame(width: max(1, width), alignment: .leading)
      .foregroundStyle(
        selected
          ? model.state.theme.cursorForeground.swiftTUIColor
          : row == nil
            ? model.state.theme.headerForeground.swiftTUIColor
            : searchMatch
              ? model.state.theme.searchMatch.swiftTUIColor
              : model.isEdited(row: row!, column: column)
                ? model.state.theme.edited.swiftTUIColor
                : model.state.theme.foreground.swiftTUIColor
      )
      .background(
        selected
          ? model.state.theme.cursorBackground.swiftTUIColor
          : row == nil
            ? model.state.theme.headerBackground.swiftTUIColor
            : model.state.theme.background.swiftTUIColor
      )
      .onTapGesture {
        if let row { model.send(.selectCell(CSVCellAddress(row: row, column: column))) }
      }
  }
}
