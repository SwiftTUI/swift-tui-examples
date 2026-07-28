import Foundation
import Observation

struct BrowserModelDependencies: Sendable {
  var loadDirectory:
    @Sendable (DirectoryRequest) async -> Result<DirectorySnapshot, FileSystemFailure>
  var previewEvents:
    @Sendable (BrowserItem, DirectorySnapshot?, PreviewGeneration) async
      -> AsyncStream<PreviewModelEvent>
  var cancelPreview: @Sendable () async -> Void
  var watchEvents: @Sendable ([URL]) async -> AsyncStream<DirectoryWatchEvent>
  var invalidateDirectory: @Sendable (DirectoryID) async -> Void
  var pinDirectories: @Sendable ([DirectoryRequest]) async -> Void
  var markHelpSeen: @Sendable () async -> Void
  var recordRecent: @Sendable (URL) async -> Void
  var toggleBookmark: @Sendable (URL) async -> Bool?
  var performHandoff: @Sendable (BrowserHandoffRequest) async -> Result<Void, HandoffFailure>
  var resolveEditor: @Sendable () -> Result<[String], HandoffFailure>
  var searchEvents:
    @Sendable (URL, String, DirectoryPolicy) async -> AsyncStream<
      FilenameSearchEvent
    >
  var inspectLaunchPath: @Sendable (URL) -> LaunchPathKind
  var resolveFileSystemIdentity:
    @Sendable (URL, Bool) -> Result<FileSystemIdentity, FileSystemFailure>
  var shutdown: @Sendable () async -> Void

  init(
    loadDirectory:
      @escaping @Sendable (DirectoryRequest) async -> Result<
        DirectorySnapshot, FileSystemFailure
      >,
    previewEvents:
      @escaping @Sendable (BrowserItem, DirectorySnapshot?, PreviewGeneration) async
      -> AsyncStream<PreviewModelEvent> = { _, _, _ in
        AsyncStream { $0.finish() }
      },
    cancelPreview: @escaping @Sendable () async -> Void = {},
    watchEvents:
      @escaping @Sendable ([URL]) async -> AsyncStream<DirectoryWatchEvent> = {
        _ in AsyncStream { $0.finish() }
      },
    invalidateDirectory:
      @escaping @Sendable (DirectoryID) async -> Void = { _ in },
    pinDirectories:
      @escaping @Sendable ([DirectoryRequest]) async -> Void = { _ in },
    markHelpSeen: @escaping @Sendable () async -> Void = {},
    recordRecent: @escaping @Sendable (URL) async -> Void = { _ in },
    toggleBookmark: @escaping @Sendable (URL) async -> Bool? = { _ in nil },
    performHandoff:
      @escaping @Sendable (BrowserHandoffRequest) async -> Result<
        Void, HandoffFailure
      > = { _ in .failure(.unavailable("Handoff is unavailable.")) },
    resolveEditor:
      @escaping @Sendable () -> Result<[String], HandoffFailure> = {
        .failure(.unavailable("No editor is configured."))
      },
    searchEvents:
      @escaping @Sendable (URL, String, DirectoryPolicy) async -> AsyncStream<
        FilenameSearchEvent
      > = { _, _, _ in AsyncStream { $0.finish() } },
    inspectLaunchPath:
      @escaping @Sendable (URL) -> LaunchPathKind = { _ in .unsupported },
    resolveFileSystemIdentity:
      @escaping @Sendable (URL, Bool) -> Result<
        FileSystemIdentity, FileSystemFailure
      > = { url, _ in .success(.pathFallback(for: url)) },
    shutdown: @escaping @Sendable () async -> Void = {}
  ) {
    self.loadDirectory = loadDirectory
    self.previewEvents = previewEvents
    self.cancelPreview = cancelPreview
    self.watchEvents = watchEvents
    self.invalidateDirectory = invalidateDirectory
    self.pinDirectories = pinDirectories
    self.markHelpSeen = markHelpSeen
    self.recordRecent = recordRecent
    self.toggleBookmark = toggleBookmark
    self.performHandoff = performHandoff
    self.resolveEditor = resolveEditor
    self.searchEvents = searchEvents
    self.inspectLaunchPath = inspectLaunchPath
    self.resolveFileSystemIdentity = resolveFileSystemIdentity
    self.shutdown = shutdown
  }
}

@MainActor
@Observable
final class BrowserModel {
  private(set) var state: BrowserState

  @ObservationIgnored private let dependencies: BrowserModelDependencies
  @ObservationIgnored private var nextDirectoryRequestValue: UInt64 = 0
  @ObservationIgnored private var nextPreviewGenerationValue: UInt64 = 0
  @ObservationIgnored private var nextSearchRequestValue: UInt64 = 0
  @ObservationIgnored private var nextEffectValue: UInt64 = 0
  @ObservationIgnored private var nextWatcherSubscriptionValue: UInt64 = 0
  @ObservationIgnored private var directoryTasks: [DirectoryRequestID: Task<Void, Never>] = [:]
  @ObservationIgnored private var directoryTaskOwners: [DirectoryRequestID: DirectoryID] = [:]
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  @ObservationIgnored private var previewCancellationTask: Task<Void, Never>?
  @ObservationIgnored private var watcherTask: Task<Void, Never>?
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var effectTasks: [UInt64: Task<Void, Never>] = [:]
  @ObservationIgnored private var selectionHistory: [DirectoryID: SelectionAnchor] = [:]
  @ObservationIgnored private var isShuttingDown = false
  @ObservationIgnored private var didStart = false
  @ObservationIgnored private var pendingInitialSelectionURL: URL?
  @ObservationIgnored private var prefilterSelectionID: BrowserItemID?
  @ObservationIgnored private var visibleDirectoryWindow: [DirectoryID] = []
  @ObservationIgnored private var subscribedDirectoryRequests: [DirectoryRequest]?

  init(
    root: URL,
    rootID: DirectoryID,
    policy: DirectoryPolicy,
    initialSelectionURL: URL? = nil,
    hasSeenHelp: Bool = false,
    bookmarks: [String] = [],
    recents: [String] = [],
    dependencies: BrowserModelDependencies
  ) {
    let root = root.standardizedFileURL
    self.dependencies = dependencies
    pendingInitialSelectionURL = initialSelectionURL?.standardizedFileURL
    self.state = BrowserState(
      root: root,
      trail: [
        BrowserTrailNode(
          id: rootID,
          url: root,
          directory: .notRequested,
          selectedItemID: nil
        )
      ],
      activeDirectoryID: rootID,
      focus: .browser(rootID),
      filter: DirectoryFilter(),
      policy: policy,
      preview: .welcome,
      overlay: .none,
      status: .none,
      hasSeenHelp: hasSeenHelp,
      search: BrowserSearchState(),
      bookmarks: bookmarks,
      recents: recents
    )
  }

  func send(_ action: BrowserAction) {
    guard !isShuttingDown else {
      return
    }

    switch action {
    case .start:
      guard !didStart else {
        return
      }
      didStart = true
      requestDirectory(state.activeDirectoryID)
      updateWatcherSubscription()
      recordRecent(state.root)

    case .moveSelection(let movement):
      moveSelection(movement)

    case .selectItem(let directoryID, let itemID):
      selectItem(directoryID: directoryID, itemID: itemID, activatesSelection: false)

    case .advanceIntoSelected:
      // Right-arrow advances into directories only. A file's preview is
      // Return's job, so this is deliberately a no-op on one.
      guard let selected = state.selectedItem,
        selected.kind.isDirectoryLike
      else {
        return
      }
      applySelection(selected, activatesSelection: true)

    case .enterSelected:
      guard let selected = state.selectedItem else {
        return
      }
      applySelection(selected, activatesSelection: true)

    case .moveToParent:
      moveToParent()

    case .focusPreview:
      guard state.preview.item != nil else {
        return
      }
      updateState { $0.focus = .preview }

    case .focusBrowser:
      updateState { state in
        state.focus = .browser(state.activeDirectoryID)
      }

    case .activatePreviewFallback:
      guard
        case .failed(
          let item,
          let generation,
          _,
          _,
          let fallback?
        ) = state.preview
      else {
        return
      }
      updateState {
        $0.preview = .builtIn(
          item: item,
          generation: generation,
          preview: fallback
        )
      }

    case .runtimeFocusChanged(let focus):
      guard let focus else {
        return
      }
      updateState { $0.focus = focus }

    case .setVisibleDirectoryWindow(let directoryIDs):
      setVisibleDirectoryWindow(directoryIDs)

    case .refresh:
      requestDirectory(state.activeDirectoryID, force: true)

    case .setHidden(let isHiddenShown):
      guard state.policy.showsHiddenFiles != isHiddenShown else {
        return
      }
      updateState { $0.policy.showsHiddenFiles = isHiddenShown }
      subscribedDirectoryRequests = nil
      updateWatcherSubscription()
      requestDirectory(state.activeDirectoryID, force: true)

    case .setSort(let sort):
      guard state.policy.sort != sort else {
        return
      }
      updateState { $0.policy.sort = sort }
      subscribedDirectoryRequests = nil
      updateWatcherSubscription()
      requestDirectory(state.activeDirectoryID, force: true)

    case .showFilter:
      if state.filter.query.isEmpty {
        prefilterSelectionID = state.activeDirectory?.selectedItemID
      }
      updateState { state in
        state.overlay = .filter
        state.focus = .filter
      }

    case .setFilter(let query):
      setFilter(query)

    case .showHelp:
      updateState { state in
        state.overlay = .help
        state.focus = .help
        state.hasSeenHelp = true
      }
      let dependencies = dependencies
      launchEffect {
        await dependencies.markHelpSeen()
      }

    case .showPalette:
      updateState { state in
        state.overlay = .palette
        state.focus = .palette
      }

    case .showSearch:
      updateState { state in
        state.overlay = .search
        state.focus = .palette
      }

    case .setSearchQuery(let query):
      setSearchQuery(query)

    case .searchResponse(let event):
      receiveSearchEvent(event)

    case .activateSearchResult(let index):
      guard state.search.results.indices.contains(index) else {
        return
      }
      let result = state.search.results[index]
      jump(to: result.url, kind: result.kind.isDirectoryLike ? .directory : .file)

    case .jumpToPath(let path):
      jump(toPath: path)

    case .toggleBookmark:
      guard let item = state.selectedItem else {
        updateState { $0.status = .failure("Select an item first.") }
        return
      }
      let path = item.url.standardizedFileURL.path
      let dependencies = dependencies
      launchEffect { [weak self] in
        let isBookmarked = await dependencies.toggleBookmark(item.url)
        self?.send(
          .bookmarkResponse(path: path, isBookmarked: isBookmarked)
        )
      }

    case .bookmarkResponse(let path, let isBookmarked):
      guard let isBookmarked else {
        updateState { $0.status = .failure("Could not update bookmarks.") }
        return
      }
      updateState { state in
        state.bookmarks.removeAll { $0 == path }
        if isBookmarked {
          state.bookmarks.append(path)
          state.status = .message("Bookmarked \(path).")
        } else {
          state.status = .message("Removed bookmark for \(path).")
        }
      }

    case .performHandoff(let command):
      guard let item = state.selectedItem else {
        updateState { $0.status = .failure("Select an item first.") }
        return
      }
      let request: BrowserHandoffRequest
      switch command {
      case .open:
        request = .open(item.url)
      case .edit:
        switch dependencies.resolveEditor() {
        case .success(let editor):
          request = .edit(command: editor, url: item.url)
        case .failure(let failure):
          updateState {
            $0.status = .failure(Self.handoffFailureLabel(failure))
          }
          return
        }
      case .reveal:
        request = .reveal(item.url)
      case .copyAbsolutePath:
        request = .copy(item.url.standardizedFileURL.path)
      case .copyRelativePath:
        guard let relativePath = rootRelativePath(for: item.url) else {
          updateState {
            $0.status = .failure("Selection is outside the launch root.")
          }
          return
        }
        request = .copy(relativePath)
      }
      let dependencies = dependencies
      launchEffect { [weak self] in
        let result = await dependencies.performHandoff(request)
        self?.send(
          .handoffResponse(
            command: command,
            itemName: item.name,
            result: result
          )
        )
      }

    case .handoffResponse(let command, let itemName, let result):
      let status: BrowserStatus =
        switch result {
        case .success:
          .message(Self.handoffSuccessLabel(command, itemName: itemName))
        case .failure(let failure):
          .failure(Self.handoffFailureLabel(failure))
        }
      updateState { $0.status = status }

    case .reportStatus(let status):
      updateState { $0.status = status }

    case .filesystemChanged(let event):
      handleFileSystemChange(event)

    case .reloadAfterInvalidation(let directoryID):
      guard directoryID == state.activeDirectoryID else {
        return
      }
      requestDirectory(directoryID, force: true)

    case .directoryResponse(let request, let result):
      receiveDirectoryResponse(request: request, result: result)

    case .previewResponse(let event):
      receivePreviewEvent(event)

    case .dismissOverlay:
      updateState { state in
        state.overlay = .none
        state.focus = .browser(state.activeDirectoryID)
      }
    }
  }

  func shutdown() async {
    guard !isShuttingDown else {
      await waitForOwnedTasks()
      return
    }
    isShuttingDown = true

    let directoryTasks = Array(directoryTasks.values)
    self.directoryTasks.removeAll()
    directoryTaskOwners.removeAll()
    for task in directoryTasks {
      task.cancel()
    }

    let previewTask = previewTask
    self.previewTask = nil
    previewTask?.cancel()

    let previewCancellationTask = previewCancellationTask
    self.previewCancellationTask = nil
    previewCancellationTask?.cancel()

    let watcherTask = watcherTask
    self.watcherTask = nil
    nextWatcherSubscriptionValue &+= 1
    watcherTask?.cancel()
    subscribedDirectoryRequests = nil
    visibleDirectoryWindow.removeAll()

    let searchTask = searchTask
    self.searchTask = nil
    searchTask?.cancel()

    let effectTasks = Array(effectTasks.values)
    self.effectTasks.removeAll()
    for task in effectTasks {
      task.cancel()
    }

    for task in directoryTasks {
      await task.value
    }
    await previewTask?.value
    await previewCancellationTask?.value
    await watcherTask?.value
    await searchTask?.value
    for task in effectTasks {
      await task.value
    }
    await dependencies.cancelPreview()
    await dependencies.shutdown()
  }

  private func waitForOwnedTasks() async {
    let directoryTasks = Array(directoryTasks.values)
    let previewTask = previewTask
    let previewCancellationTask = previewCancellationTask
    let watcherTask = watcherTask
    let searchTask = searchTask
    let effectTasks = Array(effectTasks.values)
    for task in directoryTasks {
      await task.value
    }
    await previewTask?.value
    await previewCancellationTask?.value
    await watcherTask?.value
    await searchTask?.value
    for task in effectTasks {
      await task.value
    }
  }

  private func moveSelection(_ movement: SelectionMovement) {
    guard let activeIndex = state.activeDirectoryIndex,
      let snapshot = state.trail[activeIndex].directory.snapshot
    else {
      return
    }
    let items = filteredItems(in: snapshot)
    guard !items.isEmpty else {
      clearSelectionAndDescendants(at: activeIndex)
      return
    }

    let selectedID = state.trail[activeIndex].selectedItemID
    let currentIndex = selectedID.flatMap { id in
      items.firstIndex { $0.id == id }
    }
    let nextIndex: Int
    switch movement {
    case .offset(let offset):
      let origin = currentIndex ?? (offset >= 0 ? -1 : items.count)
      nextIndex = min(max(origin + offset, 0), items.count - 1)
    case .first:
      nextIndex = 0
    case .last:
      nextIndex = items.count - 1
    }
    selectItem(
      directoryID: state.trail[activeIndex].id,
      itemID: items[nextIndex].id,
      activatesSelection: false
    )
  }

  private func selectItem(
    directoryID: DirectoryID,
    itemID: BrowserItemID,
    activatesSelection: Bool
  ) {
    guard directoryID == state.activeDirectoryID,
      let directoryIndex = state.trail.firstIndex(where: { $0.id == directoryID }),
      let snapshot = state.trail[directoryIndex].directory.snapshot,
      let itemIndex = snapshot.items.firstIndex(where: { $0.id == itemID })
    else {
      return
    }

    let item = snapshot.items[itemIndex]
    if state.trail[directoryIndex].selectedItemID == item.id {
      if activatesSelection {
        applySelection(item, activatesSelection: true)
      }
      return
    }
    selectionHistory[directoryID] = SelectionAnchor(
      itemID: item.id,
      url: item.url,
      sortedIndex: itemIndex
    )
    updateState { state in
      state.trail[directoryIndex].selectedItemID = item.id
    }
    applySelection(item, activatesSelection: activatesSelection)
  }

  private func setFilter(_ query: String) {
    guard let activeIndex = state.activeDirectoryIndex,
      let snapshot = state.trail[activeIndex].directory.snapshot
    else {
      updateState { $0.filter.query = query }
      return
    }

    updateState { $0.filter.query = query }
    let items = filteredItems(in: snapshot)
    let currentID = state.trail[activeIndex].selectedItemID
    let selectedID: BrowserItemID?
    if query.isEmpty,
      let original = prefilterSelectionID,
      snapshot.items.contains(where: { $0.id == original })
    {
      selectedID = original
      prefilterSelectionID = nil
    } else if let currentID, items.contains(where: { $0.id == currentID }) {
      selectedID = currentID
    } else {
      selectedID = items.first?.id
    }

    guard selectedID != currentID else {
      return
    }
    guard let selectedID else {
      clearSelectionAndDescendants(at: activeIndex)
      return
    }
    selectItem(
      directoryID: state.activeDirectoryID,
      itemID: selectedID,
      activatesSelection: false
    )
  }

  private func applySelection(
    _ item: BrowserItem,
    activatesSelection: Bool
  ) {
    guard let activeIndex = state.activeDirectoryIndex else {
      return
    }

    if item.kind.isDirectoryLike {
      guard let childID = item.targetDirectoryID else {
        updateState {
          $0.status = .failure("The selected directory is no longer available.")
        }
        return
      }
      if state.trail.indices.contains(activeIndex + 1),
        state.trail[activeIndex + 1].id == childID,
        state.trail[activeIndex + 1].url == item.url.standardizedFileURL
      {
        let childSnapshot = state.trail[activeIndex + 1].directory.snapshot
        if activatesSelection {
          updateState { state in
            state.activeDirectoryID = childID
            state.focus = .browser(childID)
          }
          updateWatcherSubscription()
        }
        requestPreview(
          item,
          directorySnapshot: childSnapshot,
          shouldFocus: false
        )
        return
      }

      truncateTrail(after: activeIndex)

      updateState { state in
        state.trail.append(
          BrowserTrailNode(
            id: childID,
            url: item.url.standardizedFileURL,
            directory: .notRequested,
            selectedItemID: nil
          )
        )
        if activatesSelection {
          state.activeDirectoryID = childID
          state.focus = .browser(childID)
        } else {
          state.focus = .browser(state.activeDirectoryID)
        }
      }
      updateWatcherSubscription()
      requestPreview(item, directorySnapshot: nil, shouldFocus: false)
      requestDirectory(childID)
      return
    }

    truncateTrail(after: activeIndex)
    if state.preview.item?.id == item.id {
      if activatesSelection {
        updateState { $0.focus = .preview }
      }
      return
    }
    requestPreview(item, shouldFocus: activatesSelection)
  }

  private func moveToParent() {
    guard let activeIndex = state.activeDirectoryIndex else {
      return
    }
    guard activeIndex > 0 else {
      climbAboveTrail()
      return
    }
    let parentIndex = activeIndex - 1
    let parentID = state.trail[parentIndex].id
    truncateTrail(after: parentIndex)
    clearPreview()
    updateState { state in
      state.activeDirectoryID = parentID
      state.focus = .browser(parentID)
    }
  }

  /// Grows the trail upward past the directory Sextant was launched in.
  ///
  /// The launch root stays where it is: `state.root` still anchors
  /// root-relative path copies and recursive search, so climbing here browses
  /// above the launch directory without silently widening either of those.
  /// Unlike ``moveToParent()``'s in-trail case this keeps every descendant —
  /// nothing below the new node has been invalidated.
  private func climbAboveTrail() {
    guard let first = state.trail.first else {
      return
    }
    let parentURL = first.url.deletingLastPathComponent().standardizedFileURL
    guard parentURL != first.url else {
      return  // already at the filesystem root
    }

    let parentIdentity: FileSystemIdentity =
      switch dependencies.resolveFileSystemIdentity(parentURL, true) {
      case .success(let identity):
        identity
      case .failure:
        .pathFallback(for: parentURL)
      }
    let parentID = DirectoryID(identity: parentIdentity)
    guard !state.trail.contains(where: { $0.id == parentID }) else {
      return
    }

    // The prepended node becomes `trail.first`, which is the only node
    // `receiveDirectoryResponse` honours a pending selection URL for — so this
    // lands the selection on the directory we just climbed out of.
    pendingInitialSelectionURL = first.url
    updateState { state in
      state.trail.insert(
        BrowserTrailNode(
          id: parentID,
          url: parentURL,
          directory: .notRequested,
          selectedItemID: nil
        ),
        at: 0
      )
      state.activeDirectoryID = parentID
      state.focus = .browser(parentID)
    }
    updateWatcherSubscription()
    requestDirectory(parentID)
  }

  private func clearSelectionAndDescendants(at directoryIndex: Int) {
    let directoryID = state.trail[directoryIndex].id
    selectionHistory[directoryID] = nil
    updateState { state in
      state.trail[directoryIndex].selectedItemID = nil
    }
    truncateTrail(after: directoryIndex)
    clearPreview()
  }

  private func truncateTrail(after retainedIndex: Int) {
    guard state.trail.indices.contains(retainedIndex),
      retainedIndex + 1 < state.trail.count
    else {
      return
    }
    let retainedIDs = Set(state.trail.prefix(retainedIndex + 1).map(\.id))
    let abandonedRequests = directoryTaskOwners.compactMap { requestID, owner in
      retainedIDs.contains(owner) ? nil : requestID
    }
    for requestID in abandonedRequests {
      directoryTasks.removeValue(forKey: requestID)?.cancel()
      directoryTaskOwners[requestID] = nil
    }
    updateState { state in
      state.trail.removeSubrange((retainedIndex + 1)...)
      if !retainedIDs.contains(state.activeDirectoryID) {
        state.activeDirectoryID = state.trail[retainedIndex].id
      }
    }
    visibleDirectoryWindow.removeAll { !retainedIDs.contains($0) }
    updateWatcherSubscription()
  }

  private func requestDirectory(
    _ directoryID: DirectoryID,
    force: Bool = false
  ) {
    guard let directoryIndex = state.trail.firstIndex(where: { $0.id == directoryID }) else {
      return
    }

    if !force {
      switch state.trail[directoryIndex].directory {
      case .loading, .loaded, .empty, .stale:
        return
      case .notRequested, .failed:
        break
      }
    }

    cancelDirectoryRequest(for: directoryID)
    let requestID = nextDirectoryRequestID()
    let request = DirectoryRequest(
      id: requestID,
      directoryID: directoryID,
      url: state.trail[directoryIndex].url,
      policy: state.policy
    )
    updateState { state in
      let current = state.trail[directoryIndex].directory
      if let snapshot = current.snapshot {
        state.trail[directoryIndex].directory = .stale(
          snapshot: snapshot,
          refresh: .loading(requestID)
        )
      } else {
        state.trail[directoryIndex].directory = .loading(requestID)
      }
    }

    let dependencies = dependencies
    let task = Task { @MainActor [weak self] in
      let result = await dependencies.loadDirectory(request)
      guard !Task.isCancelled else {
        return
      }
      self?.send(.directoryResponse(request: request, result: result))
    }
    directoryTasks[requestID] = task
    directoryTaskOwners[requestID] = directoryID
  }

  private func cancelDirectoryRequest(for directoryID: DirectoryID) {
    let matching = directoryTaskOwners.compactMap { requestID, owner in
      owner == directoryID ? requestID : nil
    }
    for requestID in matching {
      directoryTasks.removeValue(forKey: requestID)?.cancel()
      directoryTaskOwners[requestID] = nil
    }
  }

  private func receiveDirectoryResponse(
    request: DirectoryRequest,
    result: Result<DirectorySnapshot, FileSystemFailure>
  ) {
    directoryTasks[request.id] = nil
    directoryTaskOwners[request.id] = nil
    guard
      let directoryIndex = state.trail.firstIndex(where: {
        $0.id == request.directoryID
      }), isCurrent(request.id, for: state.trail[directoryIndex].directory)
    else {
      return
    }

    switch result {
    case .success(let snapshot):
      let initialSelectionURL =
        request.directoryID == state.trail.first?.id
        ? pendingInitialSelectionURL
        : nil
      var selectedItemID = restoredSelection(
        in: snapshot,
        previous: state.trail[directoryIndex],
        preferredURL: initialSelectionURL
      )
      if request.directoryID == state.activeDirectoryID,
        !state.filter.query.isEmpty
      {
        let matches = filteredItems(in: snapshot)
        if selectedItemID.map({ selectedID in
          matches.contains { $0.id == selectedID }
        }) != true {
          selectedItemID = matches.first?.id
        }
      }
      updateState { state in
        state.trail[directoryIndex].directory =
          snapshot.items.isEmpty ? .empty(snapshot) : .loaded(snapshot)
        state.trail[directoryIndex].selectedItemID = selectedItemID
      }
      if let selectedItemID,
        let itemIndex = snapshot.items.firstIndex(where: { $0.id == selectedItemID })
      {
        let item = snapshot.items[itemIndex]
        selectionHistory[request.directoryID] = SelectionAnchor(
          itemID: item.id,
          url: item.url,
          sortedIndex: itemIndex
        )
      } else {
        selectionHistory[request.directoryID] = nil
      }
      reconcileDescendant(
        after: directoryIndex,
        selectedItemID: selectedItemID,
        snapshot: snapshot
      )
      updateWatcherSubscription()
      if let initialSelectionURL {
        pendingInitialSelectionURL = nil
        if let selected = snapshot.items.first(where: {
          $0.url.standardizedFileURL == initialSelectionURL
        }) {
          requestPreview(selected, shouldFocus: false)
        }
      }
      refreshParentDirectoryPreview(
        loadedDirectoryIndex: directoryIndex,
        snapshot: snapshot
      )

    case .failure(let failure):
      updateState { state in
        switch state.trail[directoryIndex].directory {
        case .stale(let snapshot, _):
          state.trail[directoryIndex].directory = .stale(
            snapshot: snapshot,
            refresh: .failed(failure)
          )
        default:
          state.trail[directoryIndex].directory = .failed(failure)
          state.trail[directoryIndex].selectedItemID = nil
        }
      }
    }
  }

  private func reconcileDescendant(
    after directoryIndex: Int,
    selectedItemID: BrowserItemID?,
    snapshot: DirectorySnapshot
  ) {
    guard state.trail.indices.contains(directoryIndex + 1) else {
      return
    }
    let selectedItem = selectedItemID.flatMap { selectedID in
      snapshot.items.first { $0.id == selectedID }
    }
    guard selectedItem?.targetDirectoryID == state.trail[directoryIndex + 1].id,
      selectedItem?.url.standardizedFileURL == state.trail[directoryIndex + 1].url
    else {
      truncateTrail(after: directoryIndex)
      clearPreview()
      return
    }
  }

  private func refreshParentDirectoryPreview(
    loadedDirectoryIndex: Int,
    snapshot: DirectorySnapshot
  ) {
    guard loadedDirectoryIndex > 0 else {
      return
    }
    let parentIndex = loadedDirectoryIndex - 1
    guard state.trail.indices.contains(parentIndex),
      state.activeDirectoryID == state.trail[parentIndex].id,
      let parentSnapshot = state.trail[parentIndex].directory.snapshot,
      let selectedID = state.trail[parentIndex].selectedItemID,
      let selected = parentSnapshot.items.first(where: { $0.id == selectedID }),
      selected.targetDirectoryID == state.trail[loadedDirectoryIndex].id
    else {
      return
    }
    requestPreview(
      selected,
      directorySnapshot: snapshot,
      shouldFocus: false
    )
  }

  private func restoredSelection(
    in snapshot: DirectorySnapshot,
    previous: BrowserTrailNode,
    preferredURL: URL? = nil
  ) -> BrowserItemID? {
    guard !snapshot.items.isEmpty else {
      return nil
    }
    if let preferredURL,
      let preferred = snapshot.items.first(where: {
        $0.url.standardizedFileURL == preferredURL
      })
    {
      return preferred.id
    }

    let previousSnapshot = previous.directory.snapshot
    let anchor =
      selectionHistory[previous.id]
      ?? previous.selectedItemID.flatMap { selectedID in
        guard
          let previousIndex = previousSnapshot?.items.firstIndex(where: {
            $0.id == selectedID
          }), let previousItem = previousSnapshot?.items[previousIndex]
        else {
          return nil
        }
        return SelectionAnchor(
          itemID: previousItem.id,
          url: previousItem.url,
          sortedIndex: previousIndex
        )
      }

    guard let anchor else {
      return snapshot.items[0].id
    }
    if let identityMatch = snapshot.items.first(where: { $0.id == anchor.itemID }) {
      return identityMatch.id
    }
    if let urlMatch = snapshot.items.first(where: { $0.url == anchor.url }) {
      return urlMatch.id
    }
    let nearestIndex = min(max(anchor.sortedIndex, 0), snapshot.items.count - 1)
    return snapshot.items[nearestIndex].id
  }

  private func isCurrent(
    _ requestID: DirectoryRequestID,
    for directory: BrowserDirectoryState
  ) -> Bool {
    switch directory {
    case .loading(let current):
      current == requestID
    case .stale(_, .loading(let current)):
      current == requestID
    case .notRequested, .loaded, .empty, .stale, .failed:
      false
    }
  }

  private func requestPreview(
    _ item: BrowserItem,
    directorySnapshot: DirectorySnapshot? = nil,
    shouldFocus: Bool
  ) {
    let generation = nextPreviewGeneration()
    previewTask?.cancel()
    updateState { state in
      state.preview = .loading(item: item, generation: generation)
      if shouldFocus {
        state.focus = .preview
      } else {
        state.focus = .browser(state.activeDirectoryID)
      }
    }

    let dependencies = dependencies
    previewTask = Task { @MainActor [weak self] in
      let events = await dependencies.previewEvents(
        item,
        directorySnapshot,
        generation
      )
      for await event in events {
        guard !Task.isCancelled else {
          return
        }
        self?.send(.previewResponse(event))
      }
    }
  }

  private func clearPreview() {
    _ = nextPreviewGeneration()
    previewTask?.cancel()
    previewTask = nil
    let precedingCancellation = previewCancellationTask
    let dependencies = dependencies
    previewCancellationTask = Task {
      await precedingCancellation?.value
      await dependencies.cancelPreview()
    }
    updateState { state in
      state.preview = .welcome
      if state.focus == .preview {
        state.focus = .browser(state.activeDirectoryID)
      }
    }
  }

  private func receivePreviewEvent(_ event: PreviewModelEvent) {
    let generation: PreviewGeneration
    switch event {
    case .builtIn(_, let value, _),
      .unavailable(_, let value, _),
      .failed(_, let value, _, _, _),
      .cleared(let value):
      generation = value
    case .external(let preview):
      generation = preview.generation
    }

    guard state.preview.generation == generation else {
      return
    }
    updateState { state in
      switch event {
      case .builtIn(let item, let generation, let preview):
        state.preview = .builtIn(item: item, generation: generation, preview: preview)
      case .external(let preview):
        state.preview = .external(preview)
      case .unavailable(let item, let generation, let reason):
        state.preview = .unavailable(
          item: item,
          generation: generation,
          reason: reason
        )
      case .failed(
        let item,
        let generation,
        let adapter,
        let failure,
        let fallback
      ):
        state.preview = .failed(
          item: item,
          generation: generation,
          adapter: adapter,
          failure: failure,
          fallback: fallback
        )
      case .cleared:
        state.preview = .welcome
      }
    }
  }

  private func nextDirectoryRequestID() -> DirectoryRequestID {
    nextDirectoryRequestValue &+= 1
    return DirectoryRequestID(rawValue: nextDirectoryRequestValue)
  }

  private func nextPreviewGeneration() -> PreviewGeneration {
    nextPreviewGenerationValue &+= 1
    return PreviewGeneration(rawValue: nextPreviewGenerationValue)
  }

  private func updateState(_ update: (inout BrowserState) -> Void) {
    var next = state
    update(&next)
    state = next
  }

  private func updateWatcherSubscription() {
    var desiredIDs = visibleDirectoryWindow
    if !desiredIDs.contains(state.activeDirectoryID) {
      desiredIDs.append(state.activeDirectoryID)
    }
    let desiredIDSet = Set(desiredIDs)
    let visibleNodes = state.trail.filter { desiredIDSet.contains($0.id) }
    let pinnedRequests = visibleNodes.map {
      DirectoryRequest(
        id: DirectoryRequestID(rawValue: 0),
        directoryID: $0.id,
        url: $0.url,
        policy: state.policy
      )
    }
    guard pinnedRequests != subscribedDirectoryRequests else {
      return
    }
    subscribedDirectoryRequests = pinnedRequests
    watcherTask?.cancel()
    nextWatcherSubscriptionValue &+= 1
    let subscriptionValue = nextWatcherSubscriptionValue
    let directories = visibleNodes.map(\.url)
    let dependencies = dependencies
    watcherTask = Task { @MainActor [weak self] in
      guard self?.nextWatcherSubscriptionValue == subscriptionValue,
        !Task.isCancelled
      else {
        return
      }
      await dependencies.pinDirectories(pinnedRequests)
      guard self?.nextWatcherSubscriptionValue == subscriptionValue,
        !Task.isCancelled
      else {
        return
      }
      let events = await dependencies.watchEvents(directories)
      for await event in events {
        guard self?.nextWatcherSubscriptionValue == subscriptionValue,
          !Task.isCancelled
        else {
          return
        }
        self?.send(.filesystemChanged(event))
      }
    }
  }

  private func setVisibleDirectoryWindow(_ directoryIDs: [DirectoryID]) {
    let trailIDs = Set(state.trail.map(\.id))
    var seen: Set<DirectoryID> = []
    let normalized = directoryIDs.filter {
      trailIDs.contains($0) && seen.insert($0).inserted
    }
    guard normalized != visibleDirectoryWindow else {
      return
    }
    visibleDirectoryWindow = normalized
    updateWatcherSubscription()
  }

  private func handleFileSystemChange(_ event: DirectoryWatchEvent) {
    let changed = event.changedDirectories
    let affected = state.trail.filter {
      changed.contains($0.url.standardizedFileURL)
    }
    guard !affected.isEmpty else {
      return
    }
    let dependencies = dependencies
    let activeWasAffected = affected.contains {
      $0.id == state.activeDirectoryID
    }
    let activeDirectoryID = state.activeDirectoryID
    launchEffect { [weak self] in
      for directory in affected {
        await dependencies.invalidateDirectory(directory.id)
      }
      guard activeWasAffected, !Task.isCancelled else {
        return
      }
      self?.send(.reloadAfterInvalidation(activeDirectoryID))
    }
  }

  private func setSearchQuery(_ query: String) {
    searchTask?.cancel()
    searchTask = nil
    nextSearchRequestValue &+= 1
    let requestValue = nextSearchRequestValue
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    updateState { state in
      state.search.query = query
      state.search.results = []
      state.search.generation = nil
      state.search.wasTruncated = false
      state.search.isSearching = !trimmed.isEmpty
    }
    guard !trimmed.isEmpty else {
      updateState {
        $0.search.generation = nil
        $0.search.isSearching = false
      }
      return
    }
    if isPathLike(trimmed) {
      updateState {
        $0.search.generation = nil
        $0.search.isSearching = false
        $0.status = .message("Press Return to jump to this path.")
      }
      return
    }

    let dependencies = dependencies
    let root = state.root
    let policy = state.policy
    searchTask = Task { @MainActor [weak self] in
      let events = await dependencies.searchEvents(root, trimmed, policy)
      for await event in events {
        guard !Task.isCancelled else {
          return
        }
        guard self?.nextSearchRequestValue == requestValue else {
          return
        }
        self?.send(.searchResponse(event))
      }
    }
  }

  private func receiveSearchEvent(_ event: FilenameSearchEvent) {
    let generation: FilenameSearchGeneration
    switch event {
    case .batch(let value, _), .finished(let value, _, _):
      generation = value
    }
    if let current = state.search.generation, current != generation {
      return
    }
    updateState { state in
      if state.search.generation == nil {
        state.search.generation = generation
      }
      switch event {
      case .batch(_, let results):
        state.search.results.append(contentsOf: results)
      case .finished(_, _, let wasTruncated):
        state.search.isSearching = false
        state.search.wasTruncated = wasTruncated
      }
    }
  }

  private func jump(toPath path: String) {
    let expanded = (path as NSString).expandingTildeInPath
    let url =
      (expanded as NSString).isAbsolutePath
      ? URL(fileURLWithPath: expanded)
      : (state.activeDirectory?.url ?? state.root)
        .appendingPathComponent(expanded)
    let standardized = url.standardizedFileURL
    jump(
      to: standardized,
      kind: dependencies.inspectLaunchPath(standardized)
    )
  }

  private func jump(to url: URL, kind: LaunchPathKind) {
    let directoryURL: URL
    let selectedFileURL: URL?
    switch kind {
    case .directory:
      directoryURL = url.standardizedFileURL
      selectedFileURL = nil
    case .file:
      directoryURL = url.deletingLastPathComponent().standardizedFileURL
      selectedFileURL = url.standardizedFileURL
    case .missing:
      updateState { $0.status = .failure("Path does not exist: \(url.path)") }
      return
    case .unreadable:
      updateState { $0.status = .failure("Path is not readable: \(url.path)") }
      return
    case .unsupported:
      updateState { $0.status = .failure("Unsupported path: \(url.path)") }
      return
    }

    for task in directoryTasks.values {
      task.cancel()
    }
    directoryTasks.removeAll()
    directoryTaskOwners.removeAll()
    clearPreview()
    searchTask?.cancel()
    searchTask = nil
    let directoryIdentity: FileSystemIdentity =
      switch dependencies.resolveFileSystemIdentity(directoryURL, true) {
      case .success(let identity):
        identity
      case .failure:
        .pathFallback(for: directoryURL)
      }
    let directoryID = DirectoryID(identity: directoryIdentity)
    pendingInitialSelectionURL = selectedFileURL
    updateState { state in
      state.trail = [
        BrowserTrailNode(
          id: directoryID,
          url: directoryURL,
          directory: .notRequested,
          selectedItemID: nil
        )
      ]
      state.activeDirectoryID = directoryID
      state.focus = .browser(directoryID)
      state.overlay = .none
      state.search = BrowserSearchState()
      state.status = .message("Jumped to \(directoryURL.path)")
    }
    visibleDirectoryWindow = [directoryID]
    subscribedDirectoryRequests = nil
    updateWatcherSubscription()
    requestDirectory(directoryID)
    recordRecent(url)
  }

  private func isPathLike(_ query: String) -> Bool {
    query.hasPrefix("/")
      || query.hasPrefix(".")
      || query.hasPrefix("~")
  }

  private func filteredItems(in snapshot: DirectorySnapshot) -> [BrowserItem] {
    let query = state.filter.query
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !query.isEmpty else {
      return snapshot.items
    }
    return snapshot.items.filter {
      $0.name.lowercased().contains(query)
    }
  }

  private func rootRelativePath(for url: URL) -> String? {
    let selected = url.standardizedFileURL.path
    let root = state.root.standardizedFileURL.path
    if selected == root {
      return "."
    }
    let prefix = root.hasSuffix("/") ? root : root + "/"
    guard selected.hasPrefix(prefix) else {
      return nil
    }
    return String(selected.dropFirst(prefix.count))
  }

  nonisolated private static func handoffSuccessLabel(
    _ command: BrowserHandoffCommand,
    itemName: String
  ) -> String {
    switch command {
    case .open:
      "Opened \(itemName)."
    case .edit:
      "Opened \(itemName) in the editor."
    case .reveal:
      "Revealed \(itemName)."
    case .copyAbsolutePath:
      "Copied absolute path."
    case .copyRelativePath:
      "Copied root-relative path."
    }
  }

  nonisolated private static func handoffFailureLabel(
    _ failure: HandoffFailure
  ) -> String {
    switch failure {
    case .unavailable(let message),
      .invalidEditor(let message),
      .launchFailed(let message):
      message
    case .nonzeroExit(let command, let status):
      "\(command) exited with status \(status)."
    }
  }

  private func recordRecent(_ url: URL) {
    let path = url.standardizedFileURL.path
    updateState { state in
      state.recents.removeAll { $0 == path }
      state.recents.insert(path, at: 0)
      state.recents = Array(state.recents.prefix(50))
    }
    let dependencies = dependencies
    launchEffect {
      await dependencies.recordRecent(url)
    }
  }

  private func launchEffect(
    _ operation: @escaping @MainActor @Sendable () async -> Void
  ) {
    nextEffectValue &+= 1
    let effectID = nextEffectValue
    let task = Task { @MainActor [weak self] in
      await operation()
      self?.effectTasks[effectID] = nil
    }
    effectTasks[effectID] = task
  }
}
