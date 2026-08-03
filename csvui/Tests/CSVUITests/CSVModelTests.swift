import Foundation
import Synchronization
import Testing

@testable import CSVUI

@MainActor
@Suite("CSV model")
struct CSVModelTests {
  @Test("compact row ordinals fit the maximum admitted source shape")
  func compactRowOrdinals() throws {
    let rows = (0..<CSVRecordIndex.maximumRecords).map(RowID.init(sourceIndex:))
    let index = try CSVRowOrdinalIndex(rows: rows)

    #expect(index.storageByteCount == CSVRecordIndex.maximumRecords * MemoryLayout<Int32>.stride)
    #expect(index.storageByteCount < CSVProjectionEngine.maximumWorkspaceBytes)
    #expect(index.ordinal(for: RowID(sourceIndex: 0)) == 0)
    #expect(index.ordinal(for: RowID(sourceIndex: 1_000_000)) == 1_000_000)
    #expect(index.ordinal(for: RowID(sourceIndex: CSVRecordIndex.maximumRecords - 1)) == 1_999_999)
    #expect(index.ordinal(for: RowID(insertedID: 1)) == nil)
  }

  @Test("compact row ordinals reject storage beyond the projection budget")
  func compactRowOrdinalBudget() {
    let firstOutOfBudgetSourceIndex =
      CSVProjectionEngine.maximumWorkspaceBytes / MemoryLayout<Int32>.stride
    #expect(throws: CSVProjectionError.workspaceLimit) {
      try CSVRowOrdinalIndex(rows: [RowID(sourceIndex: firstOutOfBudgetSourceIndex)])
    }
  }

  @Test("navigation keeps cursor identity visible")
  func navigation() throws {
    let model = try makeModel()
    model.send(.updateViewport(CSVViewport(width: 80, height: 10)))
    model.send(.moveRows(5))
    model.send(.moveColumns(2))

    #expect(model.state.cursor.row == RowID(sourceIndex: 5))
    #expect(model.state.cursor.column == ColumnID(2))
    #expect(model.state.cursor.rowOrigin == 0)
    model.send(.pageRows(1))
    #expect(model.state.cursor.row == RowID(sourceIndex: 12))
    #expect(model.state.cursor.rowOrigin > 0)
    model.send(.firstRow)
    model.send(.lastColumn)
    #expect(model.state.cursor.row == RowID(sourceIndex: 0))
    #expect(model.state.cursor.column == ColumnID(2))
  }

  @Test("wheel deltas use the same bounded cursor navigation")
  func wheelNavigation() throws {
    let model = try makeModel()
    model.send(.updateViewport(CSVViewport(width: 80, height: 10)))
    model.send(.scrollWheel(deltaX: 2, deltaY: 4))

    #expect(model.state.cursor.row == RowID(sourceIndex: 4))
    #expect(model.state.cursor.column == ColumnID(2))

    model.send(.scrollWheel(deltaX: 10, deltaY: 100))
    #expect(model.state.cursor.row == RowID(sourceIndex: 19))
    #expect(model.state.cursor.column == ColumnID(2))
  }

  @Test("filter and stable numeric sort preserve row identity")
  func filterAndSort() async throws {
    let model = try makeModel()
    model.send(.beginFilterAll)
    model.send(.updatePrompt("group-a"))
    model.send(.submitPrompt)
    await model.waitForIdle()

    #expect(model.state.projection.visibleRows.count == 7)
    let retained = model.state.projection.visibleRows[2]
    model.send(.selectCell(CSVCellAddress(row: retained, column: ColumnID(1))))
    model.send(.sort(.descending))
    await model.waitForIdle()

    #expect(model.state.cursor.row == retained)
    let values = model.state.projection.visibleRows.map {
      Int(model.value(row: $0, column: ColumnID(1)))!
    }
    #expect(values == values.sorted(by: >))
  }

  @Test("smart-case and regex search move through addresses")
  func search() async throws {
    let model = try makeModel()
    model.send(.beginFind)
    model.send(.updatePrompt("person-1"))
    model.send(.submitPrompt)
    await model.waitForIdle()
    #expect(!model.state.searchMatches.isEmpty)
    #expect(
      model.isSearchMatch(
        row: model.state.searchMatches[0].address.row,
        column: model.state.searchMatches[0].address.column
      )
    )
    let first = model.state.cursor
    model.send(.nextMatch)
    #expect(model.state.cursor != first)

    model.send(.beginFind)
    model.send(.updatePrompt("re:^person-(1|2)$"))
    model.send(.submitPrompt)
    await model.waitForIdle()
    #expect(model.state.searchMatches.count == 2)

    model.send(.resetView)
    await model.waitForIdle()
    #expect(model.state.searchQuery.isEmpty)
    #expect(model.state.searchMatches.isEmpty)
    #expect(model.state.selectedSearchMatch == nil)
    #expect(!model.state.searchResultsTruncated)
    #expect(!model.state.isSearching)
  }

  @Test("edit, undo, redo, and clean revision are model-owned")
  func editHistory() async throws {
    let model = try makeModel()
    model.send(.beginEditCell)
    model.send(.updateEditor("changed, with comma"))
    model.send(.commitEditor)
    await model.waitForIdle()

    #expect(model.state.isDirty)
    #expect(model.value(row: RowID(sourceIndex: 0), column: ColumnID(0)) == "changed, with comma")
    #expect(model.state.canUndo)
    model.send(.undo)
    await model.waitForIdle()
    #expect(model.value(row: RowID(sourceIndex: 0), column: ColumnID(0)) == "person-0")
    #expect(!model.state.isDirty)
    #expect(model.state.canRedo)
    model.send(.redo)
    await model.waitForIdle()
    #expect(model.state.isDirty)
  }

  @Test("edited values expand sampled widths but never replace a manual override")
  func editedWidthPolicy() async throws {
    let model = try makeModel()
    let column = ColumnID(0)
    model.send(.beginEditCell)
    model.send(.updateEditor(String(repeating: "x", count: 30)))
    model.send(.commitEditor)
    await model.waitForIdle()
    #expect(model.state.projection.widths[column] == 32)

    model.send(.decreaseWidth)
    let manualWidth = model.state.projection.widths[column]
    model.send(.beginEditCell)
    model.send(.updateEditor(String(repeating: "y", count: 100)))
    model.send(.commitEditor)
    await model.waitForIdle()
    #expect(model.state.projection.widths[column] == manualWidth)
    #expect(model.state.projection.manualWidthOverrides.contains(column))
  }

  @Test("row insertion is refused under a projection")
  func projectedInsertionRestriction() async throws {
    let model = try makeModel()
    model.send(.sort(.ascending))
    await model.waitForIdle()
    let before = model.state.rowCount
    model.send(.insertRowBelow)
    #expect(model.state.rowCount == before)
    #expect(model.state.diagnostic?.message.contains("clear filter and sort") == true)
  }

  @Test("deep pristine insertion uses the selected ordinal")
  func deepPristineInsertion() async throws {
    let rows = (0..<20_000).map { "row-\($0),\($0)" }
    let document = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "deep.csv",
        bytes: Data((["name,value"] + rows).joined(separator: "\n").utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let model = CSVModel(document: document)
    model.send(.lastRow)
    model.send(.insertRowAbove)
    await model.waitForIdle()

    let inserted = try #require(model.state.cursor.row)
    #expect(inserted.sourceIndex == nil)
    #expect(model.state.journal.rowOrder[19_999] == inserted)
  }

  @Test("filtered and sorted deletion resolves through projected and journal ordinals")
  func projectedDeletionOrdinals() async throws {
    let model = try makeModel()
    model.send(.beginFilterAll)
    model.send(.updatePrompt("group-a"))
    model.send(.submitPrompt)
    await model.waitForIdle()
    model.send(.sort(.descending))
    await model.waitForIdle()
    let selected = try #require(model.state.projection.visibleRows.last)
    model.send(.selectCell(CSVCellAddress(row: selected, column: ColumnID(1))))
    model.send(.deleteRow)
    await model.waitForIdle()

    #expect(!model.state.journal.rowOrder.contains(selected))
    #expect(!model.state.projection.visibleRows.contains(selected))
  }

  @Test("read-only mode disables every mutation entry point")
  func readOnly() async throws {
    let document = try makeDocument()
    let model = CSVModel(document: document, readOnly: true)
    model.send(.beginEditCell)
    model.send(.insertRowBelow)
    model.send(.deleteColumn)
    await model.waitForIdle()
    #expect(!model.state.isDirty)
    #expect(model.state.diagnostic?.message == "read-only mode disables editing")
  }

  @Test("initial indexing commits atomically and retains parse failures in the app")
  func initialLoad() async throws {
    let placeholder = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "loading.csv",
        bytes: Data()
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let model = CSVModel(document: placeholder)
    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "loaded.csv",
        bytes: Data("name,value\nAda,1\n".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    #expect(model.state.isLoading)
    await model.waitForIdle()
    #expect(!model.state.isLoading)
    #expect(model.state.document.source.displayName == "loaded.csv")
    #expect(model.state.rowCount == 1)

    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "broken.csv",
        bytes: Data("name\n\"unclosed".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    await model.waitForIdle()
    #expect(model.state.document.source.displayName == "loaded.csv")
    #expect(model.state.diagnostic?.severity == .error)
    #expect(model.state.diagnostic?.message.contains("unclosed quoted field") == true)
  }

  @Test("superseded initial load cannot commit its width sample")
  func generationSafeInitialWidths() async throws {
    let placeholder = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "loading.csv",
        bytes: Data()
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let model = CSVModel(document: placeholder)
    let slowRows = Array(repeating: String(repeating: "x", count: 38), count: 20_000)
    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "superseded.csv",
        bytes: Data((["value"] + slowRows).joined(separator: "\n").utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "current.csv",
        bytes: Data("value\ny\n".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )

    await model.waitForIdle()
    #expect(model.state.document.source.displayName == "current.csv")
    #expect(model.state.projection.widths[ColumnID(0)] == 7)
    #expect(model.state.counters.widthSamples == 1)
  }

  @Test("superseding a source load cancels its detached parse worker")
  func supersededLoadCancelsDetachedWorker() async throws {
    let placeholder = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "loading.csv",
        bytes: Data()
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let model = CSVModel(document: placeholder)
    let probe = Mutex((started: false, cancelled: false))
    model.installDocumentLoaderForTesting { source, delimiter, hasHeaders in
      if source.displayName == "superseded.csv" {
        probe.withLock { $0.started = true }
        do {
          while true {
            try Task.checkCancellation()
            for _ in 0..<10_000 { _ = 1 &+ 1 }
          }
        } catch {
          probe.withLock { $0.cancelled = true }
          throw error
        }
      }
      return try CSVDocument.load(
        source: source,
        delimiter: delimiter,
        hasHeaders: hasHeaders
      )
    }

    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "superseded.csv",
        bytes: Data("value\nx\n".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    while !probe.withLock({ $0.started }) { await Task.yield() }
    model.loadInitial(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "current.csv",
        bytes: Data("value\ny\n".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )

    await model.waitForIdle()
    #expect(probe.withLock { $0.cancelled })
    #expect(model.state.document.source.displayName == "current.csv")
  }

  private func makeModel() throws -> CSVModel {
    CSVModel(document: try makeDocument())
  }

  private func makeDocument() throws -> CSVDocument {
    let rows = (0..<20).map { "person-\($0),\($0),group-\($0 % 3 == 0 ? "a" : "b")" }
    let source = (["name,score,group"] + rows).joined(separator: "\n") + "\n"
    return try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "people.csv",
        bytes: Data(source.utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
  }
}
