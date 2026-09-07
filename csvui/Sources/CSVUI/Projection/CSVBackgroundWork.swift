/// Executes CPU work off the caller's actor while preserving cancellation ownership.
func runCSVBackgroundWork<Value: Sendable>(
  _ operation: @escaping @Sendable () async throws -> Value
) async -> Result<Value, any Error> {
  guard !Task.isCancelled else { return .failure(CancellationError()) }
  let worker = Task.detached {
    do {
      try Task.checkCancellation()
      return Result<Value, any Error>.success(try await operation())
    } catch {
      return Result<Value, any Error>.failure(error)
    }
  }
  return await withTaskCancellationHandler {
    await worker.value
  } onCancel: {
    worker.cancel()
  }
}

/// The model owns requests; these operations own the row work for each request.
struct CSVProjectionOperations: Sendable {
  var search:
    @Sendable (CSVScanSnapshot, [RowID], [ColumnID], String) async throws
      -> CSVSearchResultSet = {
        try await CSVProjectionEngine().search(snapshot: $0, rows: $1, columns: $2, query: $3)
      }
  var filter:
    @Sendable (CSVScanSnapshot, [RowID], [ColumnID], CSVFilterSpec) async throws
      -> [RowID] = {
        try await CSVProjectionEngine().filter(snapshot: $0, rows: $1, visibleColumns: $2, spec: $3)
      }
  var sort: @Sendable (CSVScanSnapshot, [RowID], CSVSortSpec) async throws -> [RowID] = {
    try await CSVProjectionEngine().sort(snapshot: $0, rows: $1, spec: $2)
  }
}
