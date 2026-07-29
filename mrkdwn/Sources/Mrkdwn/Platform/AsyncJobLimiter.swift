import Foundation

actor AsyncJobLimiter {
  private struct Waiter {
    var id: UUID
    var continuation: CheckedContinuation<Bool, Never>
  }

  private let limit: Int
  private var active = 0
  private var peak = 0
  private var waiters: [Waiter] = []

  init(limit: Int) {
    self.limit = max(1, limit)
  }

  func run<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try await operation()
  }

  var peakActiveJobs: Int {
    peak
  }

  private func acquire() async throws {
    if active < limit {
      active += 1
      peak = max(peak, active)
      return
    }
    let id = UUID()
    let acquired = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        waiters.append(Waiter(id: id, continuation: continuation))
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
    guard acquired else { throw CancellationError() }
  }

  private func release() {
    if waiters.isEmpty {
      active -= 1
    } else {
      waiters.removeFirst().continuation.resume(returning: true)
    }
  }

  private func cancelWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(returning: false)
  }
}
