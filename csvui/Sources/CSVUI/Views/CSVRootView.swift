import Foundation
public import SwiftTUI

public struct CSVRootView: View {
  private let model: CSVModel
  @Environment(\.clipboardWriteAction) private var clipboardWrite
  @Environment(\.requestTermination) private var requestTermination

  public init(model: CSVModel) { self.model = model }

  public var body: some View {
    let rootAcceptsFocus = model.rootAcceptsFocusPresentation()
    GeometryReader { geometry in
      let viewport = CSVViewport(width: geometry.size.width, height: geometry.size.height)
      ZStack(alignment: .topLeading) {
        CSVRootBackgroundRegion(model: model)
        if viewport.isTooSmall {
          CSVTerminalFloorRegion(model: model)
        } else {
          VStack(alignment: .leading, spacing: 0) {
            CSVToolbarRegion(model: model)
            CSVGridRegion(model: model)
              .frame(
                width: viewport.width,
                height: max(1, viewport.height - 2),
                alignment: .topLeading
              )
            CSVStatusRegion(model: model)
          }
          CSVGridSelectionRegion(model: model)
            .frame(
              width: viewport.width,
              height: max(1, viewport.height - 2),
              alignment: .topLeading
            )
            .offset(y: 1)
        }
        CSVOverlayRegion(model: model, dispatchDefinition: dispatch)
        CSVTerminationRegion(model: model) { requestTermination() }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .focusable(rootAcceptsFocus)
      .onKeyPress(.any, perform: handleKeyPress)
      .task(id: viewport) { @MainActor in
        model.send(.updateViewport(viewport))
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
      if let presentation = model.overlayPresentation(),
        case .palette(_, let rows) = presentation.content,
        let first = rows.first
      {
        dispatch(first.definition)
      }
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
}

private struct CSVRootBackgroundRegion: View {
  let model: CSVModel

  var body: some View {
    CSVRootBackgroundSurface(presentation: model.rootStylePresentation())
  }
}

private struct CSVTerminalFloorRegion: View {
  let model: CSVModel

  var body: some View {
    CSVTerminalFloorSurface(presentation: model.rootStylePresentation())
  }
}

private struct CSVToolbarRegion: View {
  let model: CSVModel

  var body: some View {
    CSVToolbarSurface(
      presentation: model.toolbarPresentation(),
      dispatch: model.send
    )
  }
}

private struct CSVGridRegion: View {
  let model: CSVModel

  @ViewBuilder
  var body: some View {
    if let loading = model.loadingPresentation() {
      CSVLoadingSurface(presentation: loading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    } else {
      CSVGridSurface(
        presentation: model.gridPresentation(),
        dispatch: model.performPresentationAction
      )
    }
  }
}

private struct CSVStatusRegion: View {
  let model: CSVModel

  var body: some View {
    CSVStatusSurface(presentation: model.statusPresentation())
  }
}

private struct CSVGridSelectionRegion: View {
  let model: CSVModel

  @ViewBuilder
  var body: some View {
    if let presentation = model.gridSelectionPresentation() {
      CSVGridSelectionSurface(presentation: presentation)
    } else {
      EmptyView()
    }
  }
}

private struct CSVOverlayRegion: View {
  let model: CSVModel
  let dispatchDefinition: @MainActor (CSVCommandDefinition) -> Void

  @ViewBuilder
  var body: some View {
    if let presentation = model.overlayPresentation() {
      CSVOverlaySurface(
        presentation: presentation,
        dispatchAction: model.send,
        dispatchDefinition: dispatchDefinition
      )
    } else {
      EmptyView()
    }
  }
}

private struct CSVTerminationRegion: View {
  let model: CSVModel
  let requestTermination: @MainActor () -> Bool

  var body: some View {
    let presentation = model.terminationPresentation()
    EmptyView()
      .task(id: presentation.requestGeneration) { @MainActor in
        guard presentation.requestGeneration > 0 else { return }
        _ = requestTermination()
      }
  }
}

private struct CSVRootBackgroundSurface: View {
  let presentation: CSVRootStylePresentation

  var body: some View {
    Text("")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(presentation.theme.background.swiftTUIColor)
  }
}

private struct CSVTerminalFloorSurface: View {
  let presentation: CSVRootStylePresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("csvui").bold().foregroundStyle(presentation.theme.accent.swiftTUIColor)
      Text("terminal too small (need 40×10)")
      Text("resize or press Ctrl-C to quit")
        .foregroundStyle(presentation.theme.muted.swiftTUIColor)
    }
    .padding(1)
    .foregroundStyle(presentation.theme.foreground.swiftTUIColor)
  }
}

private struct CSVToolbarSurface: View {
  let presentation: CSVToolbarPresentation
  let dispatch: @MainActor (CSVAction) -> Void

  var body: some View {
    HStack(spacing: 1) {
      ForEach(presentation.items, id: \.menu) { item in
        Text(item.menu.rawValue)
          .onTapGesture { dispatch(.openMenu(item.menu)) }
          .fixedSize(horizontal: true, vertical: true)
          .foregroundStyle(item.foreground.swiftTUIColor)
          .background(item.background.swiftTUIColor)
      }
      Spacer(minLength: 0)
      if let sourceLabel = presentation.sourceLabel {
        Text(sourceLabel)
          .lineLimit(1)
          .foregroundStyle(presentation.theme.muted.swiftTUIColor)
        Text(presentation.dirtyMarker)
          .foregroundStyle(presentation.theme.edited.swiftTUIColor)
        Text(presentation.shapeLabel ?? "")
          .foregroundStyle(presentation.theme.muted.swiftTUIColor)
      }
    }
    .padding(.horizontal, 1)
    .frame(height: 1, alignment: .topLeading)
    .background(presentation.theme.menuBackground.swiftTUIColor)
  }
}

private struct CSVLoadingSurface: View {
  let presentation: CSVLoadingPresentation

  var body: some View {
    VStack(alignment: .center, spacing: 1) {
      Text("csvui").bold().foregroundStyle(presentation.theme.accent.swiftTUIColor)
      Text(presentation.message)
      Text("q or Ctrl-C quits safely")
        .foregroundStyle(presentation.theme.muted.swiftTUIColor)
    }
    .foregroundStyle(presentation.theme.foreground.swiftTUIColor)
  }
}

private struct CSVGridSelectionSurface: View, Equatable {
  let presentation: CSVGridSelectionPresentation

  var body: some View {
    Text(presentation.text)
      .lineLimit(1)
      .frame(width: presentation.width, alignment: .leading)
      .foregroundStyle(presentation.foreground.swiftTUIColor)
      .background(presentation.background.swiftTUIColor)
      .allowsHitTesting(false)
      .offset(x: presentation.x, y: presentation.y)
  }
}

private struct CSVStatusSurface: View {
  let presentation: CSVStatusPresentation

  @ViewBuilder
  var body: some View {
    if let promptPrefix = presentation.promptPrefix {
      HStack(spacing: 1) {
        Text(promptPrefix + presentation.promptText + "▏")
          .foregroundStyle(presentation.theme.accent.swiftTUIColor)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let diagnostic = presentation.promptDiagnostic {
          Text(diagnostic)
            .foregroundStyle(presentation.theme.error.swiftTUIColor)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 1)
      .frame(height: 1)
      .foregroundStyle(presentation.theme.foreground.swiftTUIColor)
    } else {
      HStack(spacing: 1) {
        Text(presentation.cellStatus).lineLimit(1)
        Spacer(minLength: 0)
        Text(presentation.projectionStatus)
          .foregroundStyle(presentation.statusColor.swiftTUIColor)
          .lineLimit(1)
      }
      .padding(.horizontal, 1)
      .frame(height: 1)
      .foregroundStyle(presentation.theme.foreground.swiftTUIColor)
    }
  }
}

private struct CSVOverlaySurface: View {
  let presentation: CSVOverlayPresentation
  let dispatchAction: @MainActor (CSVAction) -> Void
  let dispatchDefinition: @MainActor (CSVCommandDefinition) -> Void

  @ViewBuilder
  var body: some View {
    switch presentation.content {
    case .menu(let menu, let rows):
      CSVMenuDropdown(rows: rows, theme: presentation.theme, dispatch: dispatchDefinition)
        .offset(x: menuOffset(menu), y: 1)
    case .help(let rows):
      overlayCard { helpContent(rows) }
    case .palette(let query, let rows):
      overlayCard { paletteContent(query: query, rows: rows) }
    case .rowDetail(_, let fields, let readOnly):
      overlayCard { rowDetail(fields: fields, readOnly: readOnly) }
    case .editing(let address, let rowLabel, let columnLabel, let text):
      let usesCompactEditorLayout = presentation.viewport.height < 18
      overlayCard(compact: usesCompactEditorLayout) {
        CSVEditorContent(
          address: address,
          rowLabel: rowLabel,
          columnLabel: columnLabel,
          initialText: text,
          presentation: presentation,
          isCompact: usesCompactEditorLayout,
          dispatch: dispatchAction
        )
      }
    case .columns(let columns):
      overlayCard { columnsContent(columns) }
    case .saveAs(let path):
      overlayCard { saveAsContent(path: path) }
    case .confirmation(let confirmation, let message, let hint):
      overlayCard { confirmationContent(confirmation, message: message, hint: hint) }
    }
  }

  private func helpContent(_ definitions: [CSVCommandDefinition]) -> some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(definitions, id: \.id) { definition in
          HStack(spacing: 1) {
            Text(definition.chord ?? "")
              .frame(width: 12, alignment: .leading)
              .foregroundStyle(presentation.theme.accent.swiftTUIColor)
            Text(definition.title)
          }
        }
        Text("Arrows/hjkl move · PgUp/PgDn page · g/G first/last row · 0/$ first/last column")
          .foregroundStyle(presentation.theme.muted.swiftTUIColor)
        Text("csvui 0.1 · viewer-first CSV/TSV reader and safe editor")
          .foregroundStyle(presentation.theme.muted.swiftTUIColor)
      }
    }
  }

  private func paletteContent(
    query: String,
    rows: [CSVCommandRowPresentation]
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(":" + query + "▏")
        .foregroundStyle(presentation.theme.accent.swiftTUIColor)
      Divider()
      ForEach(rows, id: \.definition.id) { row in
        Button(action: { dispatchDefinition(row.definition) }) {
          HStack(spacing: 1) {
            Text(row.definition.title)
            Spacer(minLength: 1)
            Text(row.definition.chord ?? "")
              .foregroundStyle(presentation.theme.muted.swiftTUIColor)
          }
        }
        .buttonStyle(.plain)
        .disabled(!row.availability.isEnabled)
      }
      if rows.isEmpty { Text("No matching commands") }
    }
  }

  private func rowDetail(
    fields: [CSVRowDetailFieldPresentation],
    readOnly: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 1) {
          ForEach(fields, id: \.column) { field in
            VStack(alignment: .leading, spacing: 0) {
              Text(field.header).bold()
                .foregroundStyle(presentation.theme.accent.swiftTUIColor)
              Text(field.value)
            }
          }
        }
      }
      HStack(spacing: 2) {
        Button("Copy Cell") { dispatchDefinition(CSVCommandCatalog.definition(.copyCell)) }
        Button("Edit Cell") { dispatchDefinition(CSVCommandCatalog.definition(.editCell)) }
          .disabled(readOnly)
      }
    }
  }

  private func columnsContent(_ columns: [CSVColumnPresentation]) -> some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(columns, id: \.column) { column in
          Button("\(column.isHidden ? "○" : "●") \(column.label)") {
            dispatchAction(.toggleColumnVisibility(column.column))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func saveAsContent(path: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Path")
      Text(path + "▏").foregroundStyle(presentation.theme.accent.swiftTUIColor)
      Text("Enter save · Escape cancel")
        .foregroundStyle(presentation.theme.muted.swiftTUIColor)
    }
  }

  private func confirmationContent(
    _ confirmation: CSVConfirmation,
    message: String,
    hint: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(message)
      HStack(spacing: 2) {
        if confirmation == .dirtyQuit || confirmation == .dirtyReload {
          Button("Save") { dispatchAction(.save) }
          Button("Discard") { dispatchAction(.confirmDiscard) }
        } else if case .overwrite = confirmation {
          Button("Overwrite") { dispatchAction(.confirmSaveAs(overwrite: true)) }
        } else if confirmation == .externalConflict {
          Button("Reload") { dispatchAction(.reload) }
          Button("Save As") { dispatchAction(.beginSaveAs) }
        }
        Button("Cancel") { dispatchAction(.cancelConfirmation) }
      }
      Text(hint).foregroundStyle(presentation.theme.muted.swiftTUIColor)
    }
  }

  private func overlayCard<Content: View>(
    compact: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: compact ? 0 : 1) {
      HStack(spacing: 1) {
        Text(presentation.title).bold()
        Spacer(minLength: 0)
        Text("Esc").foregroundStyle(presentation.theme.muted.swiftTUIColor)
      }
      if !compact {
        Divider()
      }
      content()
    }
    .padding(1)
    .frame(
      width: min(76, max(28, presentation.viewport.width - 4)),
      height: min(20, max(8, presentation.viewport.height - 4)),
      alignment: .topLeading
    )
    .foregroundStyle(presentation.theme.foreground.swiftTUIColor)
    .background(presentation.theme.background.swiftTUIColor)
    .border(presentation.theme.border.swiftTUIColor)
    .offset(x: 2, y: 2)
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
}

private struct CSVEditorContent: View {
  let address: CSVCellAddress
  let rowLabel: String
  let columnLabel: String
  let presentation: CSVOverlayPresentation
  let isCompact: Bool
  let dispatch: @MainActor (CSVAction) -> Void
  @State private var text: String
  @FocusState private var focused: Bool

  init(
    address: CSVCellAddress,
    rowLabel: String,
    columnLabel: String,
    initialText: String,
    presentation: CSVOverlayPresentation,
    isCompact: Bool,
    dispatch: @escaping @MainActor (CSVAction) -> Void
  ) {
    self.address = address
    self.rowLabel = rowLabel
    self.columnLabel = columnLabel
    self.presentation = presentation
    self.isCompact = isCompact
    self.dispatch = dispatch
    _text = State(wrappedValue: initialText)
    _focused = FocusState()
    focused = true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: isCompact ? 0 : 1) {
      if !isCompact {
        Text("\(rowLabel) · \(columnLabel)")
          .foregroundStyle(presentation.theme.muted.swiftTUIColor)
      }
      TextEditor(text: $text)
        .focused($focused)
        .frame(
          width: max(20, min(68, presentation.viewport.width - 8)),
          // The overlay card's title, divider, and padding leave fourteen
          // rows for the editor title, text area, and action row at the
          // standard 24-row terminal size. Keep the action row inside that
          // bounded content area instead of letting a tall editor clip the
          // Save and Cancel focus stops below the card.
          height: isCompact
            ? max(1, min(4, presentation.viewport.height - 7))
            : max(4, min(10, presentation.viewport.height - 14))
        )
        .onChange(of: text) { _, newValue in
          dispatch(.updateEditor(newValue))
        }
      HStack(spacing: 2) {
        Button("Save  Ctrl-S") { dispatch(.commitEditor) }
          .buttonStyle(.plain)
        Button("Cancel  Esc") { dispatch(.dismissTransient) }
          .buttonStyle(.plain)
      }
    }
  }
}

private struct CSVMenuDropdown: View {
  let rows: [CSVCommandRowPresentation]
  let theme: CSVTheme
  let dispatch: @MainActor (CSVCommandDefinition) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(rows, id: \.definition.id) { row in
        Button(action: { dispatch(row.definition) }) {
          HStack(spacing: 1) {
            Text(row.definition.title)
            Spacer(minLength: 2)
            Text(row.definition.chord ?? "")
              .foregroundStyle(theme.muted.swiftTUIColor)
          }
        }
        .buttonStyle(.plain)
        .disabled(!row.availability.isEnabled)
      }
    }
    .padding(1)
    .frame(minWidth: 26, alignment: .leading)
    .background(theme.menuBackground.swiftTUIColor)
    .border(theme.border.swiftTUIColor)
  }
}

struct CSVGridTextHitRegion: Equatable, Sendable {
  let rect: CellRect
  let action: CSVPresentationAction?
}

@MainActor
struct CSVGridTextLayout {
  let content: Text.RichContent
  let hitRegions: [CSVGridTextHitRegion]
  let hitPath: Path

  init(presentation: CSVGridPresentation) {
    var interpolation = Text.StringInterpolation(
      literalCapacity: 0,
      interpolationCount: (presentation.rows.count + 1) * (presentation.header.cells.count * 2 + 1)
    )
    var hitRegions: [CSVGridTextHitRegion] = []
    hitRegions.reserveCapacity(
      (presentation.rows.count + 1) * presentation.header.cells.count
    )

    Self.appendRow(
      presentation.header,
      y: 0,
      gutterWidth: presentation.gutterWidth,
      gutterForeground: presentation.gutterForeground,
      gutterBackground: presentation.gutterBackground,
      border: presentation.border,
      interpolation: &interpolation,
      hitRegions: &hitRegions
    )
    for (index, row) in presentation.rows.enumerated() {
      interpolation.appendLiteral("\n")
      Self.appendRow(
        row,
        y: index + 1,
        gutterWidth: presentation.gutterWidth,
        gutterForeground: presentation.gutterForeground,
        gutterBackground: presentation.gutterBackground,
        border: presentation.border,
        interpolation: &interpolation,
        hitRegions: &hitRegions
      )
    }

    var hitPath = Path()
    for region in hitRegions {
      hitPath.addRect(
        Rect(
          origin: Point(
            x: Double(region.rect.origin.x),
            y: Double(region.rect.origin.y)
          ),
          size: Size(
            width: Double(region.rect.size.width),
            height: Double(region.rect.size.height)
          )
        )
      )
    }
    content = Text.RichContent(stringInterpolation: interpolation)
    self.hitRegions = hitRegions
    self.hitPath = hitPath
  }

  func action(at point: Point) -> CSVPresentationAction? {
    hitRegions.first { $0.rect.contains(point) }?.action
  }

  static func fittedText(_ text: String, width: Int) -> String {
    fittedText(text, width: width, trailingAlignment: false)
  }

  private static func fittedText(
    _ text: String,
    width: Int,
    trailingAlignment: Bool
  ) -> String {
    let width = max(1, width)
    let line =
      layoutText(
        for: text,
        width: width,
        lineLimit: 1,
        truncationMode: .tail
      ).lines.first ?? TextLayoutLine()
    let padding = String(repeating: " ", count: max(0, width - line.cellWidth))
    return trailingAlignment ? padding + line.text : line.text + padding
  }

  private static func appendRow(
    _ row: CSVGridRowPresentation,
    y: Int,
    gutterWidth: Int,
    gutterForeground: CSVThemeColor,
    gutterBackground: CSVThemeColor,
    border: CSVThemeColor,
    interpolation: inout Text.StringInterpolation,
    hitRegions: inout [CSVGridTextHitRegion]
  ) {
    appendStyled(
      fittedText(row.label, width: gutterWidth, trailingAlignment: true),
      foreground: gutterForeground,
      background: gutterBackground,
      interpolation: &interpolation
    )
    appendStyled(
      "│",
      foreground: border,
      background: nil,
      interpolation: &interpolation
    )
    var x = gutterWidth + 1
    for cell in row.cells {
      appendStyled(
        fittedText(cell.text, width: cell.width),
        foreground: cell.foreground,
        background: cell.background,
        interpolation: &interpolation
      )
      let action = cell.address.map {
        CSVPresentationAction.selectCell(
          $0,
          projectedRowOrdinal: cell.projectedRowOrdinal ?? 0,
          projectedColumnOrdinal: cell.projectedColumnOrdinal
        )
      }
      hitRegions.append(
        CSVGridTextHitRegion(
          rect: CellRect(
            origin: CellPoint(x: x, y: y),
            size: CellSize(width: cell.width, height: 1)
          ),
          action: action
        )
      )
      x += cell.width
      appendStyled(
        "│",
        foreground: border,
        background: nil,
        interpolation: &interpolation
      )
      x += 1
    }
  }

  private static func appendStyled(
    _ value: String,
    foreground: CSVThemeColor,
    background: CSVThemeColor?,
    interpolation: inout Text.StringInterpolation
  ) {
    var fragment = Text(value).foregroundStyle(foreground.swiftTUIColor)
    if let background {
      fragment = fragment.cellBackground(background.swiftTUIColor)
    }
    interpolation.appendInterpolation(fragment)
  }
}

private struct CSVGridSurface: View {
  let presentation: CSVGridPresentation
  let dispatch: @MainActor (CSVPresentationAction) -> Bool

  var body: some View {
    let layout = CSVGridTextLayout(presentation: presentation)
    Text(layout.content)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(layout.hitPath)
      .gesture(
        SpatialTapGesture().onEnded { value in
          if let action = layout.action(at: value.location) {
            _ = dispatch(action)
          }
        }
      )
      .onScrollWheel { event in
        dispatch(.scrollWheel(deltaX: event.deltaX, deltaY: event.deltaY)) ? .handled : .ignored
      }
  }
}
