import Foundation
import Testing

@testable import Sextant

@MainActor
@Suite("Browser handoff ownership")
struct BrowserHandoffTests {
  @Test("semantic commands resolve selected-item requests inside the model")
  func semanticRequests() async throws {
    let recorder = HandoffRequestRecorder()
    let model = makeHandoffModel(
      perform: { request in
        await recorder.record(request)
        return .success(())
      },
      resolveEditor: { .success(["editor", "--wait"]) }
    )
    model.send(.start)
    try await waitUntil { model.state.selectedItem != nil }

    model.send(.performHandoff(.open))
    model.send(.performHandoff(.edit))
    model.send(.performHandoff(.reveal))
    model.send(.performHandoff(.copyAbsolutePath))
    model.send(.performHandoff(.copyRelativePath))
    try await waitUntil { await recorder.requests.count == 5 }

    let file = URL(fileURLWithPath: "/fixture/file.txt")
    #expect(
      await recorder.requests == [
        .open(file),
        .edit(command: ["editor", "--wait"], url: file),
        .reveal(file),
        .copy("/fixture/file.txt"),
        .copy("file.txt"),
      ]
    )
    await model.shutdown()
  }

  @Test("the model maps editor resolution and handoff failures to status")
  func failureStatus() async throws {
    let model = makeHandoffModel(
      perform: { _ in
        .failure(.nonzeroExit(command: "opener", status: 9))
      },
      resolveEditor: {
        .failure(.invalidEditor("EDITOR could not be parsed."))
      }
    )
    model.send(.start)
    try await waitUntil { model.state.selectedItem != nil }

    model.send(.performHandoff(.edit))
    #expect(model.state.status == .failure("EDITOR could not be parsed."))

    model.send(.performHandoff(.open))
    try await waitUntil {
      model.state.status == .failure("opener exited with status 9.")
    }
    await model.shutdown()
  }

  @Test("shutdown escalates from TERM to KILL for a stubborn handoff child")
  func stubbornChildShutdown() async throws {
    let marker = FileManager.default.temporaryDirectory
      .appendingPathComponent("sextant-handoff-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let model = makeHandoffModel(
      perform: { _ in
        return await runHandoffProcess(
          "/bin/sh",
          arguments: [
            "-c",
            "trap '' TERM; /usr/bin/touch \"$1\"; while :; do :; done",
            "sextant-stubborn-child",
            marker.path,
          ],
          terminationGracePeriod: .milliseconds(100)
        )
      }
    )
    model.send(.start)
    try await waitUntil { model.state.selectedItem != nil }
    model.send(.performHandoff(.open))
    try await waitUntil {
      FileManager.default.fileExists(atPath: marker.path)
    }

    let clock = ContinuousClock()
    let start = clock.now
    await model.shutdown()
    let elapsed = start.duration(to: clock.now)

    // The child traps TERM and never exits on its own, so `shutdown()`
    // returning at all is the proof that the escalation reached SIGKILL, and
    // the lower bound is the proof it waited out the grace period first. Both
    // hold on any machine. How *promptly* the kill lands is a wall-clock claim
    // about an idle one: alone this shutdown measures ~0.11 s, but beside the
    // other 22 suites — one of which is this test's own spinning child — CI
    // measured 10.4 s.
    #expect(elapsed >= .milliseconds(80))
    if sextantWallClockBudgetsEnabled {
      #expect(elapsed < .seconds(1))
    }
  }
}

@MainActor
private func makeHandoffModel(
  perform:
    @escaping @Sendable (BrowserHandoffRequest) async -> Result<
      Void, HandoffFailure
    >,
  resolveEditor:
    @escaping @Sendable () -> Result<[String], HandoffFailure> = {
      .success(["editor"])
    }
) -> BrowserModel {
  let root = URL(fileURLWithPath: "/fixture", isDirectory: true)
  let rootID = DirectoryID(identity: .path(root.path))
  return BrowserModel(
    root: root,
    rootID: rootID,
    policy: DirectoryPolicy(),
    dependencies: BrowserModelDependencies(
      loadDirectory: { request in
        let url = request.url.appendingPathComponent("file.txt")
        let identity = FileSystemIdentity.path(url.path)
        let item = BrowserItem(
          id: BrowserItemID(identity: identity),
          directoryID: request.directoryID,
          name: "file.txt",
          url: url,
          kind: .file,
          listingMetadata: ItemMetadata(
            identity: identity,
            isReadable: true
          )
        )
        return .success(
          DirectorySnapshot(request: request, items: [item])
        )
      },
      performHandoff: perform,
      resolveEditor: resolveEditor
    )
  )
}

private actor HandoffRequestRecorder {
  private(set) var requests: [BrowserHandoffRequest] = []

  func record(_ request: BrowserHandoffRequest) {
    requests.append(request)
  }
}

@MainActor
private func waitUntil(
  timeout: Duration = .seconds(2),
  _ condition: @escaping @MainActor () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while clock.now < deadline {
    if await condition() {
      return
    }
    await Task.yield()
  }
  Issue.record("condition did not become true before \(timeout)")
}
