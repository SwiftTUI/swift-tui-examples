import Foundation
import SwiftTUITerminal
import Testing

@testable import Sextant

@MainActor
struct BrowserModelTests {
  @Test("initial load selects the first visible item")
  func initialLoadSelectsFirstItem() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let request = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: request)
    let second = fixture.file("second.txt", in: request)

    await fixture.loader.respond(
      to: request.id,
      with: .success(fixture.snapshot(request, [first, second]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }

    #expect(fixture.model.state.trail.count == 1)
    #expect(fixture.model.state.activeDirectory?.directory.snapshot?.items == [first, second])
  }

  @Test("moving reveals a directory while Enter activates the revealed child")
  func revealVersusActivateDirectory() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let rootRequest = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: rootRequest)
    let childID = fixture.directoryID("child")
    let child = fixture.directory("child", target: childID, in: rootRequest)
    await fixture.loader.respond(
      to: rootRequest.id,
      with: .success(fixture.snapshot(rootRequest, [first, child]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }

    fixture.model.send(.moveSelection(.offset(1)))
    let childRequest = try await fixture.loader.waitForRequest(count: 2)
    #expect(fixture.model.state.activeDirectoryID == fixture.rootID)
    #expect(fixture.model.state.focus == .browser(fixture.rootID))
    #expect(fixture.model.state.trail.map(\.id) == [fixture.rootID, childID])

    await fixture.loader.respond(
      to: childRequest.id,
      with: .success(fixture.snapshot(childRequest, []))
    )
    try await waitUntil {
      if case .empty = fixture.model.state.trail[1].directory {
        return true
      }
      return false
    }

    fixture.model.send(.enterSelected)
    #expect(fixture.model.state.activeDirectoryID == childID)
    #expect(fixture.model.state.focus == .browser(childID))
    #expect(await fixture.loader.requests().count == 2)
  }

  @Test("file hover previews without stealing focus and Enter focuses the same preview")
  func filePreviewAndFocus() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let request = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: request)
    let second = fixture.file("second.txt", in: request)
    await fixture.loader.respond(
      to: request.id,
      with: .success(fixture.snapshot(request, [first, second]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }

    fixture.model.send(.moveSelection(.offset(1)))
    let previewRequest = try await fixture.preview.waitForRequest(count: 1)
    #expect(previewRequest.item == second)
    #expect(fixture.model.state.focus == .browser(fixture.rootID))

    await fixture.preview.send(
      .builtIn(
        item: second,
        generation: previewRequest.generation,
        preview: fixture.builtInPreview(for: second)
      ),
      generation: previewRequest.generation
    )
    try await waitUntil {
      if case .builtIn(let item, _, _) = fixture.model.state.preview {
        return item.id == second.id
      }
      return false
    }

    fixture.model.send(.enterSelected)
    #expect(fixture.model.state.focus == .preview)
    #expect(await fixture.preview.requests().count == 1)

    fixture.model.send(.focusBrowser)
    #expect(fixture.model.state.focus == .browser(fixture.rootID))
    #expect(fixture.model.state.activeDirectory?.selectedItemID == second.id)
  }

  @Test("failed external previews can activate their built-in fallback")
  func activateExternalPreviewFallback() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let request = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: request)
    let selected = fixture.file("selected.txt", in: request)
    await fixture.loader.respond(
      to: request.id,
      with: .success(fixture.snapshot(request, [first, selected]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }
    fixture.model.send(.moveSelection(.offset(1)))
    let previewRequest = try await fixture.preview.waitForRequest(count: 1)
    let fallback = fixture.builtInPreview(for: selected)
    await fixture.preview.send(
      .failed(
        item: selected,
        generation: previewRequest.generation,
        adapter: "Fixture adapter",
        failure: .externalExit(7),
        fallback: fallback
      ),
      generation: previewRequest.generation
    )
    try await waitUntil {
      if case .failed(_, _, _, .externalExit(7), _) =
        fixture.model.state.preview
      {
        return true
      }
      return false
    }

    fixture.model.send(.activatePreviewFallback)

    guard
      case .builtIn(
        let item,
        let generation,
        let activePreview
      ) = fixture.model.state.preview
    else {
      Issue.record("expected the built-in fallback to become active")
      return
    }
    #expect(item == selected)
    #expect(generation == previewRequest.generation)
    #expect(activePreview == fallback)
  }

  @Test("path jumps use resolved filesystem identity")
  func pathJumpUsesResolvedIdentity() {
    let destination = URL(fileURLWithPath: "/resolved")
    let expected = FileSystemIdentity.inode(device: 7, inode: 11)
    let fixture = BrowserModelFixture(
      inspectLaunchPath: { url in
        url == destination ? .directory : .missing
      },
      resolveFileSystemIdentity: { url, followsLinks in
        #expect(url == destination)
        #expect(followsLinks)
        return .success(expected)
      }
    )

    fixture.model.send(.jumpToPath(destination.path))

    #expect(fixture.model.state.activeDirectoryID == DirectoryID(identity: expected))
    #expect(fixture.model.state.trail.first?.id == DirectoryID(identity: expected))
  }

  @Test("moving to parent clears only descendants and preserves the parent selection")
  func parentClearsDescendants() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let rootRequest = try await fixture.loader.waitForRequest(count: 1)
    let childID = fixture.directoryID("child")
    let child = fixture.directory("child", target: childID, in: rootRequest)
    await fixture.loader.respond(
      to: rootRequest.id,
      with: .success(fixture.snapshot(rootRequest, [child]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == child.id
    }
    fixture.model.send(.enterSelected)
    let childRequest = try await fixture.loader.waitForRequest(count: 2)

    let grandchildID = fixture.directoryID("grandchild")
    let grandchild = fixture.directory(
      "grandchild",
      target: grandchildID,
      in: childRequest
    )
    await fixture.loader.respond(
      to: childRequest.id,
      with: .success(fixture.snapshot(childRequest, [grandchild]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == grandchild.id
    }
    fixture.model.send(.enterSelected)
    _ = try await fixture.loader.waitForRequest(count: 3)
    #expect(fixture.model.state.trail.count == 3)

    fixture.model.send(.moveToParent)
    #expect(fixture.model.state.trail.map(\.id) == [fixture.rootID, childID])
    #expect(fixture.model.state.activeDirectoryID == childID)
    #expect(fixture.model.state.focus == .browser(childID))
    #expect(fixture.model.state.trail[0].selectedItemID == child.id)
  }

  @Test("a superseded directory result cannot replace the current request")
  func rejectsLateDirectoryResult() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let oldRequest = try await fixture.loader.waitForRequest(count: 1)
    fixture.model.send(.refresh)
    let currentRequest = try await fixture.loader.waitForRequest(count: 2)
    let staleItem = fixture.file("stale.txt", in: oldRequest)

    fixture.model.send(
      .directoryResponse(
        request: oldRequest,
        result: .success(fixture.snapshot(oldRequest, [staleItem]))
      )
    )
    if case .loading(let requestID) = fixture.model.state.trail[0].directory {
      #expect(requestID == currentRequest.id)
    } else {
      Issue.record("Expected the current directory request to remain loading.")
    }

    let currentItem = fixture.file("current.txt", in: currentRequest)
    await fixture.loader.respond(
      to: currentRequest.id,
      with: .success(fixture.snapshot(currentRequest, [currentItem]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == currentItem.id
    }
    #expect(
      fixture.model.state.activeDirectory?.directory.snapshot?.items == [currentItem]
    )
  }

  @Test("a stale preview event cannot replace the current selection preview")
  func rejectsLatePreviewResult() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let request = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: request)
    let second = fixture.file("second.txt", in: request)
    await fixture.loader.respond(
      to: request.id,
      with: .success(fixture.snapshot(request, [first, second]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }

    fixture.model.send(.moveSelection(.offset(1)))
    let oldPreview = try await fixture.preview.waitForRequest(count: 1)
    fixture.model.send(.moveSelection(.offset(-1)))
    let currentPreview = try await fixture.preview.waitForRequest(count: 2)

    await fixture.preview.send(
      .builtIn(
        item: second,
        generation: oldPreview.generation,
        preview: fixture.builtInPreview(for: second)
      ),
      generation: oldPreview.generation
    )
    await Task.yield()
    #expect(fixture.model.state.preview.generation == currentPreview.generation)

    await fixture.preview.send(
      .builtIn(
        item: first,
        generation: currentPreview.generation,
        preview: fixture.builtInPreview(for: first)
      ),
      generation: currentPreview.generation
    )
    try await waitUntil {
      if case .builtIn(let item, _, _) = fixture.model.state.preview {
        return item.id == first.id
      }
      return false
    }
  }

  @Test("shutdown cancels owned effects, awaits adapters, and rejects later actions")
  func shutdownDrainsEffectsAndRejectsActions() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    _ = try await fixture.loader.waitForRequest(count: 1)

    await fixture.model.shutdown()
    #expect(await fixture.loader.cancellationCount() == 1)
    #expect(await fixture.lifecycle.previewCancellationCount() == 1)
    #expect(await fixture.lifecycle.shutdownCount() == 1)

    fixture.model.send(.moveSelection(.last))
    fixture.model.send(.start)
    #expect(await fixture.loader.requests().count == 1)
  }

  @Test("clearing a local filter restores the pre-filter selection")
  func filterRestoresSelection() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let request = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: request)
    let second = fixture.file("second.txt", in: request)
    await fixture.loader.respond(
      to: request.id,
      with: .success(fixture.snapshot(request, [first, second]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }
    fixture.model.send(.moveSelection(.offset(1)))
    fixture.model.send(.showFilter)
    fixture.model.send(.setFilter("first"))
    #expect(fixture.model.state.activeDirectory?.selectedItemID == first.id)

    fixture.model.send(.setFilter(""))

    #expect(fixture.model.state.activeDirectory?.selectedItemID == second.id)
  }

  @Test("a replacement recursive search accepts its own generation")
  func replacementSearchAcceptsNewGeneration() {
    let fixture = BrowserModelFixture()
    let oldGeneration = FilenameSearchGeneration(rawValue: 1)
    let newGeneration = FilenameSearchGeneration(rawValue: 2)
    let old = FilenameSearchResult(
      id: BrowserItemID(identity: .path("/fixture/old")),
      url: URL(fileURLWithPath: "/fixture/old"),
      name: "old",
      kind: .file
    )
    let new = FilenameSearchResult(
      id: BrowserItemID(identity: .path("/fixture/new")),
      url: URL(fileURLWithPath: "/fixture/new"),
      name: "new",
      kind: .file
    )

    fixture.model.send(.setSearchQuery("old"))
    fixture.model.send(.searchResponse(.batch(generation: oldGeneration, results: [old])))
    fixture.model.send(.setSearchQuery("new"))
    fixture.model.send(.searchResponse(.batch(generation: newGeneration, results: [new])))

    #expect(fixture.model.state.search.generation == newGeneration)
    #expect(fixture.model.state.search.results == [new])
  }

  @Test("bookmark mutations return through model state")
  func bookmarkMutation() async throws {
    let fixture = BrowserModelFixture(toggleBookmark: { _ in true })
    fixture.model.send(.start)
    let request = try await fixture.loader.waitForRequest(count: 1)
    let first = fixture.file("first.txt", in: request)
    await fixture.loader.respond(
      to: request.id,
      with: .success(fixture.snapshot(request, [first]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }

    fixture.model.send(.toggleBookmark)
    try await waitUntil {
      fixture.model.state.bookmarks == [first.url.path]
    }

    #expect(fixture.model.state.status == .message("Bookmarked \(first.url.path)."))
  }

  @Test("a loaded child snapshot refreshes the selected directory preview")
  func directorySummaryPreviewReceivesSnapshot() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let rootRequest = try await fixture.loader.waitForRequest(count: 1)
    let childID = fixture.directoryID("child")
    let first = fixture.file("first.txt", in: rootRequest)
    let child = fixture.directory("child", target: childID, in: rootRequest)
    await fixture.loader.respond(
      to: rootRequest.id,
      with: .success(fixture.snapshot(rootRequest, [first, child]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == first.id
    }

    fixture.model.send(.moveSelection(.offset(1)))
    let childRequest = try await fixture.loader.waitForRequest(count: 2)
    let nested = fixture.file("nested.txt", in: childRequest)
    await fixture.loader.respond(
      to: childRequest.id,
      with: .success(fixture.snapshot(childRequest, [nested]))
    )
    let refreshedPreview = try await fixture.preview.waitForRequest(count: 2)

    #expect(refreshedPreview.item == child)
    #expect(refreshedPreview.directorySnapshot?.items == [nested])
  }

  @Test("watch and cache ownership follows the visible column window")
  func visibleColumnWindowOwnsWatchersAndPins() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let rootRequest = try await fixture.loader.waitForRequest(count: 1)
    let childID = fixture.directoryID("child")
    let child = fixture.directory("child", target: childID, in: rootRequest)
    await fixture.loader.respond(
      to: rootRequest.id,
      with: .success(fixture.snapshot(rootRequest, [child]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == child.id
    }
    fixture.model.send(.enterSelected)
    let childRequest = try await fixture.loader.waitForRequest(count: 2)
    let grandchildID = fixture.directoryID("grandchild")
    let grandchild = fixture.directory(
      "grandchild",
      target: grandchildID,
      in: childRequest
    )
    await fixture.loader.respond(
      to: childRequest.id,
      with: .success(fixture.snapshot(childRequest, [grandchild]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == grandchild.id
    }
    fixture.model.send(.enterSelected)
    _ = try await fixture.loader.waitForRequest(count: 3)

    fixture.model.send(.setVisibleDirectoryWindow([]))
    let grandchildURL =
      fixture.root
      .appendingPathComponent("child", isDirectory: true)
      .appendingPathComponent("grandchild", isDirectory: true)
    try await fixture.directoryWindow.waitForLatestWatchedURLs([
      grandchildURL
    ])

    #expect(
      await fixture.directoryWindow.latestWatchedURLs()
        == [grandchildURL]
    )
    #expect(
      await fixture.directoryWindow.latestPinnedIDs()
        == [grandchildID]
    )
  }

  @Test("trail truncation tears down removed child ownership")
  func trailTruncationRefreshesDirectoryOwnership() async throws {
    let fixture = BrowserModelFixture()
    fixture.model.send(.start)
    let rootRequest = try await fixture.loader.waitForRequest(count: 1)
    let childID = fixture.directoryID("child")
    let child = fixture.directory("child", target: childID, in: rootRequest)
    await fixture.loader.respond(
      to: rootRequest.id,
      with: .success(fixture.snapshot(rootRequest, [child]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == child.id
    }
    fixture.model.send(.enterSelected)
    let childRequest = try await fixture.loader.waitForRequest(count: 2)
    let grandchildID = fixture.directoryID("grandchild")
    let grandchild = fixture.directory(
      "grandchild",
      target: grandchildID,
      in: childRequest
    )
    await fixture.loader.respond(
      to: childRequest.id,
      with: .success(fixture.snapshot(childRequest, [grandchild]))
    )
    try await waitUntil {
      fixture.model.state.activeDirectory?.selectedItemID == grandchild.id
    }
    fixture.model.send(.enterSelected)
    _ = try await fixture.loader.waitForRequest(count: 3)
    fixture.model.send(
      .setVisibleDirectoryWindow([childID, grandchildID])
    )
    let childURL =
      fixture.root.appendingPathComponent("child", isDirectory: true)
    let grandchildURL =
      childURL.appendingPathComponent("grandchild", isDirectory: true)
    try await fixture.directoryWindow.waitForLatestWatchedURLs([
      childURL, grandchildURL,
    ])

    fixture.model.send(.moveToParent)
    try await fixture.directoryWindow.waitForLatestWatchedURLs([childURL])

    #expect(fixture.model.state.trail.map(\.id) == [fixture.rootID, childID])
    #expect(await fixture.directoryWindow.latestPinnedIDs() == [childID])
    #expect(
      await fixture.directoryWindow.latestWatchedURLs()
        == [childURL]
    )
  }
}

@MainActor
private final class BrowserModelFixture {
  let root = URL(fileURLWithPath: "/fixture")
  let rootID = DirectoryID(identity: .path("/fixture"))
  let loader = ScriptedDirectoryLoader()
  let preview = ScriptedPreview()
  let lifecycle = RecordingBrowserLifecycle()
  let directoryWindow = RecordingDirectoryWindow()
  let model: BrowserModel

  init(
    toggleBookmark: @escaping @Sendable (URL) async -> Bool? = { _ in nil },
    inspectLaunchPath:
      @escaping @Sendable (URL) -> LaunchPathKind = { _ in .unsupported },
    resolveFileSystemIdentity:
      @escaping @Sendable (URL, Bool) -> Result<
        FileSystemIdentity, FileSystemFailure
      > = { url, _ in .success(.pathFallback(for: url)) }
  ) {
    let loader = loader
    let preview = preview
    let lifecycle = lifecycle
    let directoryWindow = directoryWindow
    model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { request in
          await loader.load(request)
        },
        previewEvents: { item, directorySnapshot, generation in
          await preview.stream(
            item: item,
            directorySnapshot: directorySnapshot,
            generation: generation
          )
        },
        cancelPreview: {
          await lifecycle.recordPreviewCancellation()
        },
        watchEvents: { urls in
          await directoryWindow.watch(urls)
        },
        pinDirectories: { requests in
          await directoryWindow.pin(requests)
        },
        toggleBookmark: toggleBookmark,
        inspectLaunchPath: inspectLaunchPath,
        resolveFileSystemIdentity: resolveFileSystemIdentity,
        shutdown: {
          await lifecycle.recordShutdown()
        }
      )
    )
  }

  func directoryID(_ name: String) -> DirectoryID {
    DirectoryID(identity: .path("/fixture/\(name)"))
  }

  func file(
    _ name: String,
    in request: DirectoryRequest
  ) -> BrowserItem {
    item(name, kind: .file, target: nil, in: request)
  }

  func directory(
    _ name: String,
    target: DirectoryID,
    in request: DirectoryRequest
  ) -> BrowserItem {
    item(name, kind: .directory, target: target, in: request)
  }

  func snapshot(
    _ request: DirectoryRequest,
    _ items: [BrowserItem]
  ) -> DirectorySnapshot {
    DirectorySnapshot(request: request, items: items)
  }

  func builtInPreview(for item: BrowserItem) -> BuiltInPreview {
    BuiltInPreview(
      metadata: PreviewMetadata(
        displayName: item.name,
        path: item.url.path,
        kind: "File"
      ),
      body: .metadataOnly
    )
  }

  private func item(
    _ name: String,
    kind: BrowserItemKind,
    target: DirectoryID?,
    in request: DirectoryRequest
  ) -> BrowserItem {
    let url = request.url.appendingPathComponent(
      name,
      isDirectory: kind.isDirectoryLike
    )
    let identity = FileSystemIdentity.path(url.path)
    return BrowserItem(
      id: BrowserItemID(identity: identity),
      directoryID: request.directoryID,
      targetDirectoryID: target,
      name: name,
      url: url,
      kind: kind,
      listingMetadata: ItemMetadata(
        identity: identity,
        isReadable: true
      )
    )
  }
}

private actor RecordingDirectoryWindow {
  private var watched: [[URL]] = []
  private var pinned: [[DirectoryRequest]] = []
  private var continuation: AsyncStream<DirectoryWatchEvent>.Continuation?

  func watch(_ urls: [URL]) -> AsyncStream<DirectoryWatchEvent> {
    watched.append(urls.map(\.standardizedFileURL))
    return AsyncStream { continuation in
      self.continuation?.finish()
      self.continuation = continuation
    }
  }

  func pin(_ requests: [DirectoryRequest]) {
    pinned.append(requests)
  }

  func latestWatchedURLs() -> [URL] {
    watched.last ?? []
  }

  func latestPinnedIDs() -> [DirectoryID] {
    pinned.last?.map(\.directoryID) ?? []
  }

  func waitForLatestWatchedURLs(_ expected: [URL]) async throws {
    let expected = expected.map(\.standardizedFileURL)
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while watched.last != expected, clock.now < deadline {
      await Task.yield()
    }
    guard watched.last == expected else {
      throw BrowserModelTestFailure.timedOut
    }
  }
}

private actor ScriptedDirectoryLoader {
  private var recordedRequests: [DirectoryRequest] = []
  private var continuations:
    [DirectoryRequestID:
      CheckedContinuation<Result<DirectorySnapshot, FileSystemFailure>, Never>] = [:]
  private var cancelledRequests: Set<DirectoryRequestID> = []

  func load(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    recordedRequests.append(request)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        continuations[request.id] = continuation
      }
    } onCancel: {
      Task {
        await self.cancel(request.id)
      }
    }
  }

  func requests() -> [DirectoryRequest] {
    recordedRequests
  }

  func cancellationCount() -> Int {
    cancelledRequests.count
  }

  func respond(
    to requestID: DirectoryRequestID,
    with result: Result<DirectorySnapshot, FileSystemFailure>
  ) {
    continuations.removeValue(forKey: requestID)?.resume(returning: result)
  }

  func waitForRequest(count: Int) async throws -> DirectoryRequest {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while recordedRequests.count < count, clock.now < deadline {
      await Task.yield()
    }
    guard recordedRequests.count >= count else {
      throw BrowserModelTestFailure.timedOut
    }
    return recordedRequests[count - 1]
  }

  private func cancel(_ requestID: DirectoryRequestID) {
    cancelledRequests.insert(requestID)
    continuations.removeValue(forKey: requestID)?.resume(returning: .failure(.cancelled))
  }
}

private actor ScriptedPreview {
  struct Request: Sendable {
    var item: BrowserItem
    var directorySnapshot: DirectorySnapshot?
    var generation: PreviewGeneration
  }

  private var recordedRequests: [Request] = []
  private var continuations: [PreviewGeneration: AsyncStream<PreviewModelEvent>.Continuation] = [:]

  func stream(
    item: BrowserItem,
    directorySnapshot: DirectorySnapshot?,
    generation: PreviewGeneration
  ) -> AsyncStream<PreviewModelEvent> {
    recordedRequests.append(
      Request(
        item: item,
        directorySnapshot: directorySnapshot,
        generation: generation
      )
    )
    return AsyncStream { continuation in
      continuations[generation] = continuation
    }
  }

  func requests() -> [Request] {
    recordedRequests
  }

  func send(
    _ event: PreviewModelEvent,
    generation: PreviewGeneration
  ) {
    continuations[generation]?.yield(event)
  }

  func waitForRequest(count: Int) async throws -> Request {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while recordedRequests.count < count, clock.now < deadline {
      await Task.yield()
    }
    guard recordedRequests.count >= count else {
      throw BrowserModelTestFailure.timedOut
    }
    return recordedRequests[count - 1]
  }
}

private actor RecordingBrowserLifecycle {
  private var previewCancellations = 0
  private var shutdowns = 0

  func recordPreviewCancellation() {
    previewCancellations += 1
  }

  func recordShutdown() {
    shutdowns += 1
  }

  func previewCancellationCount() -> Int {
    previewCancellations
  }

  func shutdownCount() -> Int {
    shutdowns
  }
}

@MainActor
private func waitUntil(
  _ condition: @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(5)
  while !condition(), clock.now < deadline {
    await Task.yield()
  }
  guard condition() else {
    throw BrowserModelTestFailure.timedOut
  }
}

private enum BrowserModelTestFailure: Error {
  case timedOut
}
