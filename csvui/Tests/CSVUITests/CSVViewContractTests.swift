import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import CSVUI

@MainActor
@Suite("CSV view contracts")
struct CSVViewContractTests {
  @Test("grid realization is bounded by the visible two-axis window")
  func boundedGridSlice() throws {
    let model = CSVModel(document: try wideDocument(rows: 10_000, columns: 200))
    model.send(.updateViewport(CSVViewport(width: 80, height: 24)))
    model.send(.moveRows(9_000))
    model.send(.moveColumns(150))
    let slice = CSVGridLayout.slice(state: model.state)

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
    let slice = CSVGridLayout.slice(state: model.state)
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
    let slice = CSVGridLayout.slice(state: model.state)

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
    let slice = CSVGridLayout.slice(state: model.state)

    #expect(model.state.cursor.column == ColumnID(16_383))
    #expect(slice.scrollingColumns.contains(ColumnID(16_383)))
    #expect(slice.counters.realizedScrollingColumns < 20)
    #expect(slice.counters.realizedCells < 20)
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
}
