import Foundation
import Observation
@_spi(Runners) import SwiftTUI
import Synchronization
import Testing

@testable import CSVUI

@MainActor
@Suite("CSV view contracts")
struct CSVViewContractTests {
  @Test("grid and selection presentations are immutable rendered values")
  func immutableGridPresentation() throws {
    func requirePresentationValue<T: Equatable & Sendable>(_: T) {}

    let model = CSVModel(document: try wideDocument(rows: 2, columns: 2))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    let presentation = model.gridPresentation()

    requirePresentationValue(presentation)
    #expect(presentation.rows.count == 2)
    #expect(presentation.rows[0].cells.map(\.text) == [" v0", " v1"])
    #expect(presentation.rows[0].cells[0].role == .body)
    #expect(presentation.rows[0].cells[1].role == .body)
    #expect(presentation.header.cells.map(\.text) == [" c0", " c1"])
    let selection = try #require(model.gridSelectionPresentation())
    requirePresentationValue(selection)
    #expect(selection.address == CSVCellAddress(row: RowID(sourceIndex: 0), column: ColumnID(0)))
    #expect(selection.text == " v0")
  }

  @Test("preformatted grid fits ASCII and wide glyphs to exact cell widths")
  func preformattedGridCellFitting() {
    let ascii = CSVGridTextLayout.fittedText(" abcdef", width: 4)
    #expect(ascii == " ab…")
    #expect(layoutText(for: ascii, width: nil).size.width == 4)

    let cjk = CSVGridTextLayout.fittedText(" 漢字", width: 4)
    #expect(cjk.contains("漢"))
    #expect(layoutText(for: cjk, width: nil).size.width == 4)

    let emoji = CSVGridTextLayout.fittedText(" 🧭x", width: 4)
    #expect(emoji.contains("🧭"))
    #expect(layoutText(for: emoji, width: nil).size.width == 4)
  }

  @Test("unified grid hit map includes headers but dispatches data cells only")
  func unifiedGridHitMap() throws {
    let model = CSVModel(document: try wideDocument(rows: 2, columns: 2))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    let layout = CSVGridTextLayout(presentation: model.gridPresentation())
    let selection = try #require(model.gridSelectionPresentation())
    let x = selection.x

    #expect(layout.hitPath.contains(Point(x: Double(x) + 0.5, y: 0.5)))
    #expect(layout.action(at: Point(x: Double(x) + 0.5, y: 0.5)) == nil)
    #expect(
      layout.action(at: Point(x: Double(x) + 0.5, y: 1.5))
        == .selectCell(
          CSVCellAddress(row: RowID(sourceIndex: 0), column: ColumnID(0)),
          projectedRowOrdinal: 0,
          projectedColumnOrdinal: 0
        )
    )
    #expect(
      layout.action(at: Point(x: Double(x + selection.width) - 0.5, y: 1.5)) != nil
    )
    #expect(!layout.hitPath.contains(Point(x: 0.5, y: 1.5)))
    #expect(!layout.hitPath.contains(Point(x: Double(x) - 0.5, y: 1.5)))
    #expect(
      !layout.hitPath.contains(Point(x: Double(x + selection.width) + 0.5, y: 1.5))
    )
    #expect(!layout.hitPath.contains(Point(x: 79.5, y: 1.5)))
  }

  @Test("unified rich grid preserves base edited and search styles")
  func unifiedGridStyles() async throws {
    let model = CSVModel(document: try wideDocument(rows: 2, columns: 3))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    model.send(.beginEditCell)
    model.send(.updateEditor("edited"))
    model.send(.commitEditor)
    model.send(.beginFind)
    model.send(.updatePrompt("v1"))
    model.send(.submitPrompt)
    await model.waitForIdle()
    let presentation = model.gridPresentation()
    let layout = CSVGridTextLayout(presentation: presentation)
    let artifacts = DefaultRenderer().render(
      Text(layout.content),
      context: .init(identity: Identity(components: [.named("CSVRichGridStyles")])),
      proposal: ProposedSize(width: 80, height: 24)
    )
    let row = artifacts.rasterSurface.cells[1]
    let firstX = presentation.gutterWidth + 2
    let secondX = firstX + presentation.rows[0].cells[0].width + 1
    let thirdX = secondX + presentation.rows[0].cells[1].width + 1

    #expect(row[firstX].style?.foregroundColor == CSVTheme.default.edited.swiftTUIColor)
    #expect(row[firstX].style?.backgroundColor == CSVTheme.default.background.swiftTUIColor)
    #expect(row[secondX].style?.foregroundColor == CSVTheme.default.searchMatch.swiftTUIColor)
    #expect(row[secondX].style?.backgroundColor == CSVTheme.default.background.swiftTUIColor)
    #expect(row[thirdX].style?.foregroundColor == CSVTheme.default.foreground.swiftTUIColor)
    #expect(row[thirdX].style?.backgroundColor == CSVTheme.default.background.swiftTUIColor)
  }

  @Test("grid interaction count is constant across realized row counts")
  func constantGridInteractionCount() throws {
    func interactionCount(height: Int) throws -> Int {
      let model = CSVModel(document: try wideDocument(rows: 100, columns: 8))
      model.send(.updateViewport(CSVViewport(width: 100, height: height)))
      return DefaultRenderer().render(
        CSVRootView(model: model),
        context: .init(identity: Identity(components: [.named("CSVConstantGraph")])),
        proposal: ProposedSize(width: 100, height: height)
      ).semanticSnapshot.interactionRegions.count
    }

    let short = try interactionCount(height: 10)
    let tall = try interactionCount(height: 40)
    #expect(short == tall)
    #expect(tall <= 8)
  }

  @Test("in-viewport cursor movement invalidates selection and status but not grid content")
  func inViewportCursorInvalidation() throws {
    let model = CSVModel(document: try wideDocument(rows: 4, columns: 8))
    model.send(.updateViewport(CSVViewport(width: 100, height: 24)))
    let base = model.gridPresentation()
    let gridRevision = model.gridContentRevision
    let selectionRevision = model.gridSelectionRevision
    let statusRevision = model.statusRevision
    let overlayRevision = model.overlayRevision

    model.send(.moveColumns(1))

    #expect(model.gridContentRevision == gridRevision)
    #expect(model.gridSelectionRevision == selectionRevision + 1)
    #expect(model.statusRevision == statusRevision + 1)
    #expect(model.overlayRevision == overlayRevision + 1)
    #expect(model.gridPresentation() == base)
    #expect(model.gridSelectionPresentation()?.address.column == ColumnID(1))
    #expect(model.statusPresentation().cellStatus.hasPrefix("B1 · c1 ·"))
  }

  @Test("public state remains observable across ignored canonical storage")
  func publicStateObservation() throws {
    let model = CSVModel(document: try wideDocument(rows: 4, columns: 8))
    let callbacks = Mutex(0)
    withObservationTracking {
      _ = model.state.cursor
    } onChange: {
      callbacks.withLock { $0 += 1 }
    }

    model.send(.moveColumns(1))

    #expect(callbacks.withLock { $0 } == 1)
    #expect(model.state.cursor.column == ColumnID(1))
  }

  @Test("local editor typing preserves its overlay and focus subtree")
  func localEditorTypingInvalidation() throws {
    let model = CSVModel(document: try wideDocument(rows: 1, columns: 1))
    model.send(.beginEditCell)
    let overlayRevision = model.overlayRevision
    let overlayCallbacks = Mutex(0)
    withObservationTracking {
      _ = model.overlayPresentation()
    } onChange: {
      overlayCallbacks.withLock { $0 += 1 }
    }
    let publicStateCallbacks = Mutex(0)
    withObservationTracking {
      _ = model.state.editor.text
    } onChange: {
      publicStateCallbacks.withLock { $0 += 1 }
    }

    model.send(.updateEditor("typed"))

    #expect(model.state.editor.text == "typed")
    #expect(publicStateCallbacks.withLock { $0 } == 1)
    #expect(model.overlayRevision == overlayRevision)
    #expect(overlayCallbacks.withLock { $0 } == 0)
  }

  @Test("fast cursor observation cone is constant across viewport heights")
  func constantCursorObservationCone() throws {
    func callbackCount(height: Int) throws -> Int {
      let model = CSVModel(document: try wideDocument(rows: 100, columns: 8))
      model.send(.updateViewport(CSVViewport(width: 100, height: height)))
      let callbacks = Mutex(0)
      func track(_ read: () -> Void) {
        withObservationTracking {
          read()
        } onChange: {
          callbacks.withLock { $0 += 1 }
        }
      }
      track { _ = model.rootStylePresentation() }
      track { _ = model.toolbarPresentation() }
      track { _ = model.gridPresentation() }
      track { _ = model.gridSelectionPresentation() }
      track { _ = model.statusPresentation() }
      track { _ = model.overlayPresentation() }
      track { _ = model.terminationPresentation() }

      model.send(.moveColumns(1))
      return callbacks.withLock { $0 }
    }

    #expect(try callbackCount(height: 10) == 3)
    #expect(try callbackCount(height: 40) == 3)
  }

  @Test("fast navigation changes no non-cursor public state")
  func fastNavigationStateContract() throws {
    let actions: [CSVAction] = [
      .moveRows(1), .moveColumns(1), .pageRows(1),
      .scrollWheel(deltaX: 1, deltaY: 1), .firstRow, .lastRow,
      .firstColumn, .lastColumn,
      .selectCell(CSVCellAddress(row: RowID(sourceIndex: 3), column: ColumnID(2))),
    ]
    let model = CSVModel(document: try wideDocument(rows: 100, columns: 30))
    model.send(.updateViewport(CSVViewport(width: 40, height: 10)))

    for action in actions {
      let previous = model.state
      model.send(action)
      let current = model.state
      var expected = previous
      expected.cursor = current.cursor
      #expect(current == expected, "non-cursor state changed for \(action)")
    }
  }

  @Test("cursor movement that changes a viewport origin invalidates grid content")
  func originChangingCursorInvalidation() throws {
    let model = CSVModel(document: try wideDocument(rows: 100, columns: 30))
    model.send(.updateViewport(CSVViewport(width: 40, height: 10)))
    let gridRevision = model.gridContentRevision
    let previousOrigin = model.state.cursor.scrollingColumnOrigin

    model.send(.moveColumns(20))

    #expect(model.state.cursor.scrollingColumnOrigin > previousOrigin)
    #expect(model.gridContentRevision > gridRevision)
    #expect(model.gridSelectionPresentation()?.address.column == ColumnID(20))
  }

  @Test("cursor reveal refills horizontal and vertical viewport edges")
  func cursorRevealEdges() throws {
    let horizontal = CSVModel(document: try wideDocument(rows: 100, columns: 30))
    horizontal.send(.updateViewport(CSVViewport(width: 40, height: 10)))
    horizontal.send(.moveColumns(20))
    let rightOrigin = horizontal.state.cursor.scrollingColumnOrigin
    let rightSlice = CSVGridLayout.slice(input: layoutInput(horizontal))
    #expect(rightOrigin > 0)
    #expect(rightSlice.scrollingColumns.contains(ColumnID(20)))

    let rightRevision = horizontal.gridContentRevision
    horizontal.send(.moveColumns(-1))
    #expect(horizontal.state.cursor.scrollingColumnOrigin < rightOrigin)
    #expect(horizontal.gridContentRevision > rightRevision)
    #expect(
      CSVGridLayout.slice(input: layoutInput(horizontal)).scrollingColumns.contains(ColumnID(19))
    )

    let vertical = CSVModel(document: try wideDocument(rows: 100, columns: 3))
    vertical.send(.updateViewport(CSVViewport(width: 40, height: 10)))
    let topRevision = vertical.gridContentRevision
    vertical.send(.moveRows(7))
    #expect(vertical.state.cursor.rowOrigin == 1)
    #expect(vertical.gridContentRevision > topRevision)
    #expect(CSVGridLayout.slice(input: layoutInput(vertical)).rows.contains(RowID(sourceIndex: 7)))

    let bottomRevision = vertical.gridContentRevision
    vertical.send(.moveRows(-7))
    #expect(vertical.state.cursor.rowOrigin == 0)
    #expect(vertical.gridContentRevision > bottomRevision)
    #expect(CSVGridLayout.slice(input: layoutInput(vertical)).rows.contains(RowID(sourceIndex: 0)))
  }

  @Test("moving selection restores edited and search styles in the raster")
  func incrementalSelectionStyleRestoration() async throws {
    func renderedCell(
      _ model: CSVModel,
      selection: CSVGridSelectionPresentation
    ) -> RasterCell {
      DefaultRenderer().render(
        CSVRootView(model: model),
        context: .init(identity: Identity(components: [.named("CSVSelectionRestoration")])),
        proposal: ProposedSize(width: 80, height: 24)
      ).rasterSurface.cells[selection.y + 1][selection.x]
    }

    let edited = CSVModel(document: try wideDocument(rows: 4, columns: 3))
    edited.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    edited.send(.beginEditCell)
    edited.send(.updateEditor("edited"))
    edited.send(.commitEditor)
    let editedSelection = try #require(edited.gridSelectionPresentation())
    #expect(
      renderedCell(edited, selection: editedSelection).style?.backgroundColor
        == CSVTheme.default.cursorBackground.swiftTUIColor)
    edited.send(.moveColumns(1))
    let restoredEdited = renderedCell(edited, selection: editedSelection)
    #expect(restoredEdited.style?.foregroundColor == CSVTheme.default.edited.swiftTUIColor)
    #expect(restoredEdited.style?.backgroundColor == CSVTheme.default.background.swiftTUIColor)

    let search = CSVModel(document: try wideDocument(rows: 4, columns: 3))
    search.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    search.send(.beginFind)
    search.send(.updatePrompt("v0"))
    search.send(.submitPrompt)
    await search.waitForIdle()
    let searchSelection = try #require(search.gridSelectionPresentation())
    #expect(
      renderedCell(search, selection: searchSelection).style?.backgroundColor
        == CSVTheme.default.cursorBackground.swiftTUIColor)
    search.send(.moveColumns(1))
    let restoredSearch = renderedCell(search, selection: searchSelection)
    #expect(restoredSearch.style?.foregroundColor == CSVTheme.default.searchMatch.swiftTUIColor)
    #expect(restoredSearch.style?.backgroundColor == CSVTheme.default.background.swiftTUIColor)
  }

  @Test("grid layout accepts only viewport and projection layout inputs")
  func focusedGridLayoutInput() {
    let input = CSVGridLayoutInput(
      visibleRows: (0..<100).map(RowID.init(sourceIndex:)),
      visibleColumns: (0..<20).map(ColumnID.init),
      frozenThroughOrdinal: 1,
      widths: [:],
      rowOrigin: 50,
      scrollingColumnOrigin: 10,
      selectedColumnOrdinal: 12,
      viewport: CSVViewport(width: 80, height: 24),
      dataRecordCount: 100,
      widthSamples: 1_000
    )

    let slice = CSVGridLayout.slice(input: input)
    #expect(slice.rows.first == RowID(sourceIndex: 50))
    #expect(slice.frozenColumns == [ColumnID(0), ColumnID(1)])
    #expect(slice.scrollingColumns.contains(ColumnID(12)))
    #expect(slice.counters.widthSamples == 1_000)
  }

  @Test("selected coordinate uses the cursor projected ordinal")
  func selectedCoordinateOrdinal() throws {
    let model = CSVModel(document: try wideDocument(rows: 20_000, columns: 3))
    model.send(.lastRow)
    model.send(.lastColumn)

    #expect(model.state.cursor.projectedRowOrdinal == 19_999)
    #expect(model.state.cursor.projectedColumnOrdinal == 2)
    #expect(model.statusPresentation().cellStatus.hasPrefix("C20000 · c2 ·"))
  }

  @Test("unprojected structural edits publish rows and ordinals atomically")
  func synchronousStructuralProjection() throws {
    let model = CSVModel(document: try wideDocument(rows: 5, columns: 4))
    model.send(.moveRows(2))
    model.send(.insertRowAbove)

    let inserted = try #require(model.state.cursor.row)
    let ordinal = try #require(model.state.cursor.projectedRowOrdinal)
    #expect(inserted.sourceIndex == nil)
    #expect(model.state.projection.visibleRows[ordinal] == inserted)
    #expect(model.gridPresentation().rows[ordinal].id == .data(inserted))
    #expect(model.gridSelectionPresentation()?.address.row == inserted)

    model.send(.moveColumns(2))
    let hiddenColumn = try #require(model.state.cursor.column)
    model.send(.toggleColumnVisibility(hiddenColumn))
    let selectedColumn = try #require(model.state.cursor.column)
    let selectedColumnOrdinal = try #require(model.state.cursor.projectedColumnOrdinal)
    #expect(model.state.projection.visibleColumns[selectedColumnOrdinal] == selectedColumn)
    #expect(model.gridSelectionPresentation()?.address.column == selectedColumn)
  }

  @Test("presentation roles preserve edit search sort and inserted-row output")
  func gridRoleOracle() async throws {
    func requirePresentationValue<T: Equatable & Sendable>(_: T) {}

    let model = CSVModel(document: try wideDocument(rows: 4, columns: 3))
    model.send(.beginEditCell)
    model.send(.updateEditor("edited"))
    model.send(.commitEditor)
    await model.waitForIdle()
    model.send(.moveColumns(1))
    var presentation = model.gridPresentation()
    #expect(presentation.rows[0].cells[0].role == .edited)
    #expect(presentation.rows[0].cells[0].text == " edited")

    model.send(.beginFind)
    model.send(.updatePrompt("edited"))
    model.send(.submitPrompt)
    await model.waitForIdle()
    model.send(.moveColumns(1))
    presentation = model.gridPresentation()
    #expect(presentation.rows[0].cells[0].role == .searchMatch)

    model.send(.sort(.ascending))
    await model.waitForIdle()
    presentation = model.gridPresentation()
    #expect(presentation.header.cells[1].text == " c1 ↑")

    model.send(.clearSort)
    await model.waitForIdle()
    model.send(.insertRowBelow)
    await model.waitForIdle()
    presentation = model.gridPresentation()
    requirePresentationValue(presentation)
    #expect(presentation.rows.contains { $0.label == "+1" })
    #expect(presentation.gutterForeground == CSVTheme.default.gutter)
  }

  @Test("chrome and overlay presentations preserve prompt and confirmation text")
  func chromeAndOverlayOracle() throws {
    func requirePresentationValue<T: Equatable & Sendable>(_: T) {}

    let promptModel = CSVModel(document: try wideDocument(rows: 1, columns: 1))
    promptModel.send(.beginFind)
    promptModel.send(.updatePrompt("needle"))
    let status = promptModel.statusPresentation()
    requirePresentationValue(status)
    #expect(status.promptPrefix == "/")
    #expect(status.promptText == "needle")

    let confirmationModel = CSVModel(document: try wideDocument(rows: 1, columns: 1))
    confirmationModel.send(.beginEditCell)
    confirmationModel.send(.updateEditor("changed"))
    confirmationModel.send(.commitEditor)
    #expect(!confirmationModel.shouldAllowTermination())
    let overlay = try #require(confirmationModel.overlayPresentation())
    requirePresentationValue(overlay)
    #expect(overlay.title == "Confirm")
    guard case .confirmation(.dirtyQuit, let message, let hint) = overlay.content else {
      Issue.record("expected dirty-quit confirmation")
      return
    }
    #expect(message == "Save changes before quitting?")
    #expect(hint == "S save · D discard · Esc cancel")
  }

  @Test("grid realization is bounded by the visible two-axis window")
  func boundedGridSlice() throws {
    let model = CSVModel(document: try wideDocument(rows: 10_000, columns: 200))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    model.send(.moveRows(9_000))
    model.send(.moveColumns(150))
    let slice = CSVGridLayout.slice(input: layoutInput(model))

    #expect(slice.counters.realizedRows <= model.state.viewport.dataRowCapacity + 2)
    #expect(slice.counters.realizedScrollingColumns < 20)
    #expect(slice.counters.realizedCells == slice.rows.count * slice.allColumns.count)
    #expect(slice.rows.contains(RowID(sourceIndex: 9_000)))
    #expect(slice.scrollingColumns.contains(ColumnID(150)))
  }

  @Test("frozen columns remain while horizontal selection moves")
  func frozenColumns() throws {
    let model = CSVModel(document: try wideDocument(rows: 30, columns: 30))
    model.send(.updateViewport(CSVViewport(width: 60, height: 16)))
    model.send(.moveColumns(2))
    model.send(.freezeThroughCurrentColumn)
    model.send(.moveColumns(20))
    let slice = CSVGridLayout.slice(input: layoutInput(model))
    #expect(slice.frozenColumns == [ColumnID(0), ColumnID(1), ColumnID(2)])
    #expect(slice.scrollingColumns.contains(ColumnID(22)))
  }

  @Test("million-row navigation still realizes one viewport", .timeLimit(.minutes(1)))
  func millionRowViewport() throws {
    var bytes = Data("value\n".utf8)
    bytes.reserveCapacity(2_000_006)
    let row = Data("x\n".utf8)
    for _ in 0..<1_000_000 { bytes.append(row) }
    let document = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "million.csv",
        bytes: bytes
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let model = CSVModel(document: document)
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    model.send(.moveRows(999_999))
    let slice = CSVGridLayout.slice(input: layoutInput(model))

    #expect(model.state.cursor.row == RowID(sourceIndex: 999_999))
    #expect(slice.rows.contains(RowID(sourceIndex: 999_999)))
    #expect(slice.counters.realizedRows <= model.state.viewport.dataRowCapacity)
    #expect(slice.counters.realizedCells == slice.rows.count)
  }

  @Test("maximum-width tables realize only visible columns", .timeLimit(.minutes(1)))
  func maximumWidthViewport() throws {
    let model = CSVModel(document: try wideDocument(rows: 1, columns: 16_384))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    model.send(.moveColumns(16_383))
    let slice = CSVGridLayout.slice(input: layoutInput(model))

    #expect(model.state.cursor.column == ColumnID(16_383))
    #expect(slice.scrollingColumns.contains(ColumnID(16_383)))
    #expect(slice.counters.realizedScrollingColumns < 20)
    #expect(slice.counters.realizedCells < 20)
    #expect(slice.counters.inspectedColumns < 20)
  }

  @Test(
    "editor exposes its text area and Save and Cancel as focus stops",
    arguments: [10, 16, 18, 24]
  )
  func editorFocusStops(height: Int) throws {
    let model = CSVModel(document: try wideDocument(rows: 1, columns: 1))
    model.send(.updateViewport(CSVViewport(width: 80, height: height)))
    model.send(.beginEditCell)
    let artifacts = DefaultRenderer().render(
      CSVRootView(model: model),
      context: .init(identity: Identity(components: [.named("CSVEditorFocusStops")])),
      proposal: ProposedSize(width: 80, height: height)
    )

    #expect(artifacts.semanticSnapshot.focusRegions.count == 3)
    #expect(artifacts.semanticSnapshot.accessibilityNodes.count { $0.role == .button } == 2)
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Save  Ctrl-S"))
    #expect(rendered.contains("Cancel  Esc"))
  }

  @Test("rendered app has persistent toolbar, grid header, and status")
  func renderedChrome() throws {
    let model = CSVModel(document: try wideDocument(rows: 4, columns: 4))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    let artifacts = DefaultRenderer().render(
      CSVRootView(model: model),
      context: .init(identity: Identity(components: [.named("CSVRoot")])),
      proposal: ProposedSize(width: 80, height: 24)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("File"))
    #expect(rendered.contains("Edit"))
    #expect(rendered.contains("View"))
    #expect(rendered.contains("Data"))
    #expect(rendered.contains("Help"))
    #expect(rendered.contains("row"))
    #expect(rendered.contains("A1"))
  }

  @Test("below-floor render keeps the exact recovery message")
  func terminalFloor() throws {
    let model = CSVModel(document: try wideDocument(rows: 1, columns: 1))
    model.send(.updateViewport(CSVViewport(width: 39, height: 9)))
    let artifacts = DefaultRenderer().render(
      CSVRootView(model: model),
      context: .init(identity: Identity(components: [.named("CSVFloor")])),
      proposal: ProposedSize(width: 39, height: 9)
    )
    #expect(
      artifacts.rasterSurface.lines.joined(separator: "\n")
        .contains("terminal too small (need 40×10)")
    )
  }

  @Test("loading is a visible quit-safe surface")
  func loadingSurface() throws {
    let model = CSVModel(document: try wideDocument(rows: 0, columns: 0))
    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "large.csv",
        bytes: Data("name\nAda\n".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let artifacts = DefaultRenderer().render(
      CSVRootView(model: model),
      context: .init(identity: Identity(components: [.named("CSVLoading")])),
      proposal: ProposedSize(width: 80, height: 24)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("loading large.csv"))
    #expect(rendered.contains("Ctrl-C quits safely"))
  }

  @Test("catalog has no duplicate reachable browse chords and every menu row resolves")
  func commandCatalog() {
    var owners: [KeyPress: CSVCommandID] = [:]
    for definition in CSVCommandCatalog.definitions {
      for key in definition.keys {
        let normalized = CSVCommandCatalog.normalize(key)
        if let owner = owners[normalized], owner != definition.id {
          Issue.record("duplicate chord \(normalized): \(owner) and \(definition.id)")
        }
        owners[normalized] = definition.id
        #expect(CSVCommandCatalog.command(for: key)?.id == definition.id)
      }
      if definition.menu != nil {
        #expect(CSVCommandCatalog.definition(definition.id).id == definition.id)
      }
    }
  }

  @Test("menu sort commands are exact while the s chord cycles")
  func sortCommandSemantics() {
    let ascending = CSVCommandCatalog.definition(.sortAscending)
    let descending = CSVCommandCatalog.definition(.sortDescending)
    let cycle = CSVCommandCatalog.command(for: KeyPress(.character("s")))

    #expect(ascending.dispatch == .model(.sort(.ascending)))
    #expect(descending.dispatch == .model(.sort(.descending)))
    #expect(cycle?.id == .cycleSort)
    #expect(ascending.menu == .data)
    #expect(cycle?.menu == nil)
  }

  @Test("read-only command availability explains every save and edit refusal")
  func readOnlyAvailability() throws {
    let document = try wideDocument(rows: 1, columns: 1)
    let state = CSVState(document: document, theme: .default, readOnly: true)
    for id in [
      CSVCommandID.save, .saveAs, .editCell, .renameHeader, .insertRowAbove,
      .insertColumnRight, .deleteRow, .deleteColumn,
    ] {
      let availability = CSVCommandCatalog.definition(id).availability(in: state)
      #expect(!availability.isEnabled)
      #expect(availability.reason == "read-only mode")
    }
  }

  private func wideDocument(rows: Int, columns: Int) throws -> CSVDocument {
    let header = (0..<columns).map { "c\($0)" }.joined(separator: ",")
    let row = (0..<columns).map { "v\($0)" }.joined(separator: ",")
    let source = ([header] + Array(repeating: row, count: rows)).joined(separator: "\n")
    return try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "wide.csv",
        bytes: Data(source.utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
  }

  private func layoutInput(_ model: CSVModel) -> CSVGridLayoutInput {
    CSVGridLayoutInput(
      visibleRows: model.state.projection.visibleRows,
      visibleColumns: model.state.projection.visibleColumns,
      frozenThroughOrdinal: model.state.projection.frozenThrough.flatMap {
        model.state.projection.visibleColumns.firstIndex(of: $0)
      },
      widths: model.state.projection.widths,
      rowOrigin: model.state.cursor.rowOrigin,
      scrollingColumnOrigin: model.state.cursor.scrollingColumnOrigin,
      selectedColumnOrdinal: model.state.cursor.projectedColumnOrdinal,
      viewport: model.state.viewport,
      dataRecordCount: model.state.document.dataRecordCount,
      widthSamples: model.state.counters.widthSamples
    )
  }
}
