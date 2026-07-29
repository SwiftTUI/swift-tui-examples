public import Foundation
import Observation

@Observable
@MainActor
public final class ViewerModel {
  private typealias LatestEffect = @MainActor @Sendable () async -> Void
  typealias SearchOperation =
    @Sendable (SearchIndex, String) async -> SearchResultSet

  private struct SearchRequest: Sendable {
    var index: SearchIndex
    var query: String
    var searchGeneration: UInt64
    var documentGeneration: UInt64
    var scrollsToFirstMatch: Bool
  }

  private enum HistoryMutation: Sendable {
    case none
    case recordCurrent
    case backward(URL)
    case forward(URL)
  }

  private struct ScrollRestorationAnchor: Sendable {
    var headingAnchor: String?
    var blockIdentity: String?
    var intraBlockOffset: Int
    var sourceLine: Int
    var absoluteOffset: Int
  }

  private struct GeometrySourceCandidate: Sendable {
    var entry: MarkdownBlockLayout.GeometryEntry
    var sourceLine: Int
  }

  private enum ScrollCommitPolicy: Sendable {
    case top
    case preserve(ScrollRestorationAnchor)
  }

  private struct GeometryCacheKey: Equatable {
    var contentRevision: UInt64
    var documentWidth: Int
    var layoutRevision: UInt64
  }

  private struct GeometrySnapshot {
    var entries: [MarkdownBlockLayout.GeometryEntry]
    var headings: [MarkdownBlockLayout.GeometryEntry]
    var entriesByID: [BlockID: MarkdownBlockLayout.GeometryEntry]

    init(
      entries: [MarkdownBlockLayout.GeometryEntry],
      headings: [MarkdownBlockLayout.GeometryEntry]
    ) {
      self.entries = entries
      self.headings = headings
      entriesByID = Dictionary(
        entries.map { ($0.blockID, $0) },
        uniquingKeysWith: { first, _ in first }
      )
    }

    func entry(atOrBefore offset: Int) -> MarkdownBlockLayout.GeometryEntry? {
      Self.lastEntry(atOrBefore: offset, in: entries)
    }

    func entry(for id: BlockID) -> MarkdownBlockLayout.GeometryEntry? {
      entriesByID[id]
    }

    func heading(atOrBefore offset: Int) -> MarkdownBlockLayout.GeometryEntry? {
      Self.lastEntry(atOrBefore: offset, in: headings)
    }

    private static func lastEntry(
      atOrBefore offset: Int,
      in entries: [MarkdownBlockLayout.GeometryEntry]
    ) -> MarkdownBlockLayout.GeometryEntry? {
      var lowerBound = 0
      var upperBound = entries.count
      while lowerBound < upperBound {
        let middle = lowerBound + (upperBound - lowerBound) / 2
        if entries[middle].top <= offset {
          lowerBound = middle + 1
        } else {
          upperBound = middle
        }
      }
      guard lowerBound > 0 else { return nil }
      return entries[lowerBound - 1]
    }
  }

  private struct ActiveMermaidRequest {
    var request: MermaidRenderRequest
    var token: UUID
    var effectID: UUID?
  }

  private struct ActiveImageRequest {
    var token: UUID
    var effectID: UUID?
  }

  public private(set) var state: ViewerState

  @ObservationIgnored private let compiler: MarkdownCompiler
  @ObservationIgnored private let linkResolver: LinkResolver
  @ObservationIgnored private let dependencies: ViewerDependencies
  @ObservationIgnored private let searchOperation: SearchOperation
  @ObservationIgnored private let watchesDocument: Bool
  @ObservationIgnored private let mermaidConfiguration: ViewerMermaidConfiguration
  @ObservationIgnored private var lifecycleGeneration: UInt64 = 0
  @ObservationIgnored private var documentGeneration: UInt64 = 0
  @ObservationIgnored private var documentLoadGeneration: UInt64 = 0
  @ObservationIgnored private var themeLoadGeneration: UInt64 = 0
  @ObservationIgnored private var viewportGeneration: UInt64 = 0
  @ObservationIgnored private var watcherGeneration: UInt64 = 0
  @ObservationIgnored private var searchGeneration: UInt64 = 0
  @ObservationIgnored private var layoutRevision: UInt64 = 0
  @ObservationIgnored private var watcherTask: Task<Void, Never>?
  @ObservationIgnored private var watcherReloadTask: Task<Void, Never>?
  @ObservationIgnored private var themeWatcherTask: Task<Void, Never>?
  @ObservationIgnored private var themeWatcherReloadTask: Task<Void, Never>?
  @ObservationIgnored private var viewportTask: Task<Void, Never>?
  @ObservationIgnored private var documentLoadWorkerTask: Task<Void, Never>?
  @ObservationIgnored private var activeDocumentLoadTask: Task<Void, Never>?
  @ObservationIgnored private var pendingDocumentLoadEffect: LatestEffect?
  @ObservationIgnored private var themeLoadWorkerTask: Task<Void, Never>?
  @ObservationIgnored private var activeThemeLoadTask: Task<Void, Never>?
  @ObservationIgnored private var pendingThemeLoadEffect: LatestEffect?
  @ObservationIgnored private var searchWorkerTask: Task<Void, Never>?
  @ObservationIgnored private var activeSearchTask: Task<SearchResultSet, Never>?
  @ObservationIgnored private var pendingSearchRequest: SearchRequest?
  @ObservationIgnored private var effectTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var mermaidEffectTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var imageEffectTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var backHistory: [URL] = []
  @ObservationIgnored private var forwardHistory: [URL] = []
  @ObservationIgnored private var currentHeadingID: BlockID?
  @ObservationIgnored private var themeDiagnosticMessage: String?
  @ObservationIgnored private var geometryCache:
    (key: GeometryCacheKey, snapshot: GeometrySnapshot)?
  @ObservationIgnored private var geometryComputationCount = 0
  @ObservationIgnored private var resourceDescriptors: [BlockID: MarkdownBlockLayout.Descriptor] =
    [:]
  @ObservationIgnored private var visibleResourceIDs: Set<BlockID> = []
  @ObservationIgnored private var visibleResourceRecency: [BlockID] = []
  @ObservationIgnored private var satisfiedVisibleResourceIDs: Set<BlockID> = []
  @ObservationIgnored private var activeMermaidRequests: [BlockID: ActiveMermaidRequest] = [:]
  @ObservationIgnored private var retainedMermaidRequests: [BlockID: MermaidRenderRequest] = [:]
  @ObservationIgnored private var activeImageRequests: [BlockID: ActiveImageRequest] = [:]
  @ObservationIgnored private var hasStarted = false
  @ObservationIgnored private var isShuttingDown = false
  @ObservationIgnored private var mermaidPresentationRecency: [BlockID] = []
  @ObservationIgnored private var mermaidStateRecency: [BlockID] = []
  @ObservationIgnored private var mermaidPresentationCosts: [BlockID: Int] = [:]
  @ObservationIgnored private var mermaidPresentationBytes = 0
  @ObservationIgnored private var imagePresentationRecency: [BlockID] = []
  @ObservationIgnored private var imageStateRecency: [BlockID] = []
  @ObservationIgnored private var imagePresentationCosts: [BlockID: Int] = [:]
  @ObservationIgnored private var imagePresentationBytes = 0

  static let maximumRetainedMermaidPresentations = 32
  static let maximumRetainedMermaidBytes = 4 * 1_024 * 1_024
  static let maximumRetainedImagePresentations = 64
  static let maximumRetainedImageBytes = 64 * 1_024 * 1_024
  static let maximumVisibleResourceIDs = 128
  static let maximumRetainedResourceStates = 128
  static let maximumConcurrentMermaidRequests = 2
  static let maximumConcurrentImageRequests = 4
  static let maximumExternalOpenEffects = 8

  public convenience init(
    snapshot: DocumentSnapshot,
    theme: ViewerTheme,
    themeSelection: ThemeSelection = .builtIn,
    watchesDocument: Bool,
    allowsRemoteImages: Bool,
    mermaidConfiguration: ViewerMermaidConfiguration = .init()
  ) {
    self.init(
      snapshot: snapshot,
      theme: theme,
      watchesDocument: watchesDocument,
      mermaidConfiguration: mermaidConfiguration,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: .live(
        themeSelection: themeSelection,
        allowsRemoteImages: allowsRemoteImages,
        mermaidConfiguration: mermaidConfiguration
      )
    )
  }

  init(
    snapshot: DocumentSnapshot,
    theme: ViewerTheme,
    watchesDocument: Bool,
    mermaidConfiguration: ViewerMermaidConfiguration = .init(),
    compiler: MarkdownCompiler,
    linkResolver: LinkResolver,
    dependencies: ViewerDependencies,
    search: @escaping SearchOperation = { index, query in
      index.results(for: query)
    }
  ) {
    state = ViewerState(snapshot: snapshot, theme: theme)
    self.watchesDocument = watchesDocument
    self.mermaidConfiguration = mermaidConfiguration
    self.compiler = compiler
    self.linkResolver = linkResolver
    self.dependencies = dependencies
    searchOperation = search
  }

  public func start() async {
    guard !hasStarted, !isShuttingDown else { return }
    hasStarted = true
    documentGeneration &+= 1
    let generation = documentGeneration
    await compileAndCommit(
      state.snapshot,
      generation: generation,
      loadGeneration: nil,
      history: .none,
      scroll: .top
    )
    if watchesDocument, let url = state.snapshot.url {
      startWatcher(for: url)
    }
    if let themeURL = dependencies.themeURL {
      startThemeWatcher(for: themeURL)
    }
  }

  public func send(_ action: ViewerAction) {
    guard !isShuttingDown else { return }
    switch action {
    case .openDestination(let destination):
      open(destination)
    case .scrollToHeading(let id):
      currentHeadingID = id
      state.pendingScrollTarget = id
    case .nextHeading:
      moveHeading(by: 1)
    case .previousHeading:
      moveHeading(by: -1)
    case .beginSearch:
      state.searchVisible = true
    case .endSearch:
      state.searchVisible = false
    case .updateSearch(let query):
      updateSearch(query)
    case .nextMatch:
      moveMatch(by: 1)
    case .previousMatch:
      moveMatch(by: -1)
    case .reload:
      reload()
    case .toggleOutline:
      state.outlineVisible.toggle()
    case .toggleHelp:
      state.helpVisible.toggle()
    case .toggleMermaidSource(let id):
      if !state.revealedMermaidSources.insert(id).inserted {
        state.revealedMermaidSources.remove(id)
      }
      invalidateGeometry()
    case .revealNextMermaidSource:
      revealNextMermaidSource()
    case .goBack:
      navigateHistory(backward: true)
    case .goForward:
      navigateHistory(backward: false)
    case .dismissError:
      state.diagnostic = nil
    case .clearScrollTarget:
      state.pendingScrollTarget = nil
    }
  }

  public func updateViewport(_ size: ViewerSize) {
    guard !isShuttingDown else { return }
    guard size != state.viewport else { return }
    let oldWidth = state.viewport.documentWidth
    state.viewport = size
    if size.width < 80 {
      state.outlineVisible = false
    }
    guard oldWidth != size.documentWidth, let document = state.document else { return }
    invalidateGeometry()
    rebuildResourceDescriptors(for: document)
    let visibleMermaidIDs = visibleResourceIDs.filter {
      if case .mermaid? = resourceDescriptors[$0]?.block { return true }
      return false
    }
    satisfiedVisibleResourceIDs.subtract(visibleMermaidIDs)
    cancelMermaidEffects()
    viewportGeneration &+= 1
    let viewportGeneration = viewportGeneration
    let documentGeneration = documentGeneration
    viewportTask?.cancel()
    viewportTask = Task { [weak self] in
      guard let self else { return }
      await self.dependencies.sleep(.milliseconds(30))
      guard !Task.isCancelled,
        viewportGeneration == self.viewportGeneration,
        documentGeneration == self.documentGeneration
      else {
        return
      }
      self.requestVisibleMermaidResources(documentGeneration: documentGeneration)
    }
  }

  func resourceBecameVisible(_ id: BlockID) {
    guard !isShuttingDown, resourceDescriptors[id] != nil else { return }
    if visibleResourceIDs.contains(id) {
      touch(id, in: &visibleResourceRecency)
      requestResource(id, documentGeneration: documentGeneration)
      return
    }
    guard visibleResourceIDs.count < Self.maximumVisibleResourceIDs else { return }
    visibleResourceIDs.insert(id)
    visibleResourceRecency.append(id)
    requestResource(id, documentGeneration: documentGeneration)
  }

  func resourceBecameHidden(_ id: BlockID) {
    visibleResourceIDs.remove(id)
    visibleResourceRecency.removeAll { $0 == id }
    satisfiedVisibleResourceIDs.remove(id)
    cancelActiveResource(id)
    discardNonReadyPresentation(id)
  }

  public func updateDocumentScrollOffset(_ offset: Int) {
    guard !isShuttingDown else { return }
    let clamped = max(0, offset)
    guard state.documentScrollOffset != clamped else { return }
    state.documentScrollOffset = clamped
    guard state.pendingScrollTarget == nil, state.document != nil else {
      return
    }
    currentHeadingID = renderedGeometry().heading(atOrBefore: clamped)?.blockID
  }

  public func shutdown() async {
    guard !isShuttingDown else {
      await cancelAndDrainSearch()
      await cancelAndDrainLatestEffects()
      await drainOwnedEffects()
      return
    }
    isShuttingDown = true
    lifecycleGeneration &+= 1
    documentGeneration &+= 1
    documentLoadGeneration &+= 1
    themeLoadGeneration &+= 1
    viewportGeneration &+= 1
    watcherGeneration &+= 1
    searchGeneration &+= 1

    watcherTask?.cancel()
    watcherReloadTask?.cancel()
    themeWatcherTask?.cancel()
    themeWatcherReloadTask?.cancel()
    viewportTask?.cancel()
    pendingSearchRequest = nil
    activeSearchTask?.cancel()
    searchWorkerTask?.cancel()
    let watcherTask = watcherTask
    let watcherReloadTask = watcherReloadTask
    let themeWatcherTask = themeWatcherTask
    let themeWatcherReloadTask = themeWatcherReloadTask
    let viewportTask = viewportTask
    self.watcherTask = nil
    self.watcherReloadTask = nil
    self.themeWatcherTask = nil
    self.themeWatcherReloadTask = nil
    self.viewportTask = nil
    await watcherTask?.value
    await watcherReloadTask?.value
    await themeWatcherTask?.value
    await themeWatcherReloadTask?.value
    await viewportTask?.value
    await cancelAndDrainSearch()
    await cancelAndDrainLatestEffects()
    await drainOwnedEffects()
  }

  private func compileAndCommit(
    _ snapshot: DocumentSnapshot,
    generation: UInt64,
    loadGeneration: UInt64?,
    history: HistoryMutation,
    scroll: ScrollCommitPolicy
  ) async {
    let compiler = self.compiler
    let compileTask = Task.detached {
      compiler.compile(source: snapshot.source, sourceURL: snapshot.url)
    }
    let compiled = await withTaskCancellationHandler {
      await compileTask.value
    } onCancel: {
      compileTask.cancel()
    }
    guard !isShuttingDown,
      !Task.isCancelled,
      generation == documentGeneration,
      loadGeneration == nil || loadGeneration == documentLoadGeneration
    else {
      return
    }
    let previousURL = state.snapshot.url
    switch history {
    case .none:
      break
    case .recordCurrent:
      if let previousURL, previousURL != snapshot.url {
        backHistory.append(previousURL)
        forwardHistory.removeAll()
      }
    case .backward(let target):
      guard backHistory.last == target else { return }
      backHistory.removeLast()
      if let previousURL { forwardHistory.append(previousURL) }
    case .forward(let target):
      guard forwardHistory.last == target else { return }
      forwardHistory.removeLast()
      if let previousURL { backHistory.append(previousURL) }
    }
    cancelMermaidEffects()
    cancelImageEffects()
    state.snapshot = snapshot
    state.document = compiled
    state.mermaid = [:]
    state.images = [:]
    state.revealedMermaidSources = []
    state.contentRevision &+= 1
    activeMermaidRequests.removeAll(keepingCapacity: true)
    retainedMermaidRequests.removeAll(keepingCapacity: true)
    activeImageRequests.removeAll(keepingCapacity: true)
    clearPresentationAccounting()
    satisfiedVisibleResourceIDs.removeAll(keepingCapacity: true)
    rebuildResourceDescriptors(for: compiled)
    invalidateGeometry()
    requestSearch(
      state.searchQuery,
      in: compiled.searchableText,
      documentGeneration: generation,
      scrollsToFirstMatch: false
    )
    state.canGoBack = !backHistory.isEmpty
    state.canGoForward = !forwardHistory.isEmpty
    state.isReloading = false
    restoreScroll(scroll)
    state.diagnostic =
      themeDiagnosticMessage.map { ViewerDiagnostic(.error, $0) }
      ?? compiled.diagnostics.first.map {
        ViewerDiagnostic(.warning, $0.message)
      }
    requestVisibleResources(documentGeneration: generation)
  }

  private func rebuildResourceDescriptors(for document: CompiledDocument) {
    resourceDescriptors = Dictionary(
      uniqueKeysWithValues: MarkdownBlockLayout.flattened(
        document.blocks,
        offeredWidth: state.viewport.documentWidth
      ).compactMap { descriptor in
        switch descriptor.block {
        case .mermaid(let id, _, _), .image(let id, _, _):
          return (id, descriptor)
        default:
          return nil
        }
      }
    )
    visibleResourceIDs.formIntersection(resourceDescriptors.keys)
    visibleResourceRecency.removeAll { !visibleResourceIDs.contains($0) }
    satisfiedVisibleResourceIDs.formIntersection(resourceDescriptors.keys)
  }

  private func requestVisibleMermaidResources(documentGeneration generation: UInt64) {
    for id in visibleResourceRecency where visibleResourceIDs.contains(id) {
      guard case .mermaid? = resourceDescriptors[id]?.block else { continue }
      requestResource(id, documentGeneration: generation)
    }
  }

  private func requestVisibleResources(documentGeneration generation: UInt64) {
    for id in visibleResourceRecency where visibleResourceIDs.contains(id) {
      requestResource(id, documentGeneration: generation)
    }
  }

  private func requestResource(_ id: BlockID, documentGeneration generation: UInt64) {
    guard !isShuttingDown, generation == documentGeneration,
      !satisfiedVisibleResourceIDs.contains(id),
      let descriptor = resourceDescriptors[id]
    else {
      return
    }
    switch descriptor.block {
    case .mermaid(let id, let value, _):
      requestMermaid(
        id: id,
        value: value,
        offeredWidth: descriptor.offeredWidth,
        documentGeneration: generation
      )
    case .image(let id, let image, _):
      requestImage(id: id, image: image, documentGeneration: generation)
    default:
      break
    }
  }

  private func cancelActiveResource(_ id: BlockID) {
    if let request = activeMermaidRequests.removeValue(forKey: id),
      let effectID = request.effectID
    {
      mermaidEffectTasks[effectID]?.cancel()
    }
    if let request = activeImageRequests.removeValue(forKey: id),
      let effectID = request.effectID
    {
      imageEffectTasks[effectID]?.cancel()
    }
  }

  private func discardNonReadyPresentation(_ id: BlockID) {
    discardNonReadyMermaidPresentation(id)
    discardNonReadyImagePresentation(id)
  }

  private func discardNonReadyMermaidPresentation(_ id: BlockID) {
    switch state.mermaid[id] {
    case .pending?:
      evictMermaidState(id)
    case .reflowing(let previous)?:
      state.mermaid[id] = .ready(previous)
      recordMermaidState(id)
    case .ready?, .unavailable?, nil:
      break
    }
  }

  private func discardNonReadyImagePresentation(_ id: BlockID) {
    switch state.images[id] {
    case .loading?, .blocked?, .failed?, .terminalFallback?:
      evictImageState(id)
    case .ready?, nil:
      break
    }
  }

  private func requestMermaid(
    id: BlockID,
    value: MermaidBlock,
    offeredWidth: Int,
    documentGeneration generation: UInt64
  ) {
    let request = MermaidRenderRequest(
      blockID: id,
      source: value.source,
      width: offeredWidth,
      configuration: mermaidConfiguration
    )
    if activeMermaidRequests[id]?.request == request { return }
    if retainedMermaidRequests[id] == request {
      if case .ready = state.mermaid[id] {
        touch(id, in: &mermaidPresentationRecency)
        touch(id, in: &mermaidStateRecency)
      }
      return
    }
    guard activeMermaidRequests.count < Self.maximumConcurrentMermaidRequests,
      mermaidEffectTasks.count < Self.maximumConcurrentMermaidRequests
    else {
      return
    }

    let token = UUID()
    activeMermaidRequests[id] = ActiveMermaidRequest(
      request: request,
      token: token,
      effectID: nil
    )
    if case .ready(let previous)? = state.mermaid[id] {
      state.mermaid[id] = .reflowing(previous)
    } else if case .reflowing(let previous)? = state.mermaid[id] {
      state.mermaid[id] = .reflowing(previous)
    } else {
      state.mermaid[id] = .pending
    }
    recordMermaidState(id)
    let effectID = spawnMermaidEffect { [weak self] in
      guard let self else { return }
      let presentation = await self.dependencies.renderMermaid(request)
      let wasCancelled = Task.isCancelled
      await self.completeMermaid(
        presentation,
        request: request,
        token: token,
        documentGeneration: generation,
        wasCancelled: wasCancelled
      )
    }
    guard let effectID else {
      activeMermaidRequests.removeValue(forKey: id)
      discardNonReadyMermaidPresentation(id)
      return
    }
    activeMermaidRequests[id]?.effectID = effectID
  }

  private func requestImage(
    id: BlockID,
    image: ImageReference,
    documentGeneration generation: UInt64
  ) {
    if activeImageRequests[id] != nil { return }
    if let presentation = state.images[id] {
      if case .ready = presentation {
        touch(id, in: &imagePresentationRecency)
        touch(id, in: &imageStateRecency)
      }
      return
    }
    guard activeImageRequests.count < Self.maximumConcurrentImageRequests,
      imageEffectTasks.count < Self.maximumConcurrentImageRequests
    else {
      return
    }

    let resolvedURL = try? ResourceLoader.resolveURL(
      image.source,
      relativeTo: state.snapshot.url
    )
    let documentURL = state.snapshot.url
    let token = UUID()
    activeImageRequests[id] = ActiveImageRequest(
      token: token,
      effectID: nil
    )
    state.images[id] = .loading(resolvedURL: resolvedURL)
    recordImageState(id)
    let effectID = spawnImageEffect { [weak self] in
      guard let self else { return }
      let result: Result<LoadedImage, Error>
      do {
        result = .success(
          try await self.dependencies.loadImage(image.source, documentURL)
        )
      } catch {
        result = .failure(error)
      }
      let wasCancelled = Task.isCancelled
      await self.completeImage(
        result,
        id: id,
        token: token,
        resolvedURL: resolvedURL,
        documentGeneration: generation,
        wasCancelled: wasCancelled
      )
    }
    guard let effectID else {
      activeImageRequests.removeValue(forKey: id)
      discardNonReadyImagePresentation(id)
      return
    }
    activeImageRequests[id]?.effectID = effectID
  }

  private func completeMermaid(
    _ presentation: MermaidPresentation,
    request: MermaidRenderRequest,
    token: UUID,
    documentGeneration generation: UInt64,
    wasCancelled: Bool
  ) {
    guard activeMermaidRequests[request.blockID]?.token == token else { return }
    activeMermaidRequests.removeValue(forKey: request.blockID)
    if wasCancelled {
      discardNonReadyMermaidPresentation(request.blockID)
    } else {
      satisfiedVisibleResourceIDs.insert(request.blockID)
      commitMermaid(
        presentation,
        request: request,
        documentGeneration: generation
      )
    }
  }

  private func completeImage(
    _ result: Result<LoadedImage, Error>,
    id: BlockID,
    token: UUID,
    resolvedURL: URL?,
    documentGeneration generation: UInt64,
    wasCancelled: Bool
  ) {
    guard activeImageRequests[id]?.token == token else { return }
    activeImageRequests.removeValue(forKey: id)
    guard !wasCancelled else {
      discardNonReadyImagePresentation(id)
      return
    }
    satisfiedVisibleResourceIDs.insert(id)
    let presentation: ImagePresentation
    switch result {
    case .success(let loaded):
      presentation = .ready(loaded)
    case .failure(let error):
      if case ResourceLoadError.remoteImagesDisabled = error {
        presentation = .blocked(
          resolvedURL: resolvedURL,
          hint: error.localizedDescription
        )
      } else {
        presentation = .failed(
          resolvedURL: resolvedURL,
          diagnostic: error.localizedDescription
        )
      }
    }
    commitImage(presentation, id: id, generation: generation)
  }

  private func commitMermaid(
    _ presentation: MermaidPresentation,
    request: MermaidRenderRequest,
    documentGeneration generation: UInt64
  ) {
    guard !isShuttingDown,
      generation == documentGeneration,
      currentMermaidWidth(for: request.blockID) == request.width
    else {
      return
    }
    retainMermaidPresentation(presentation, id: request.blockID, request: request)
    invalidateGeometry()
  }

  private func commitImage(
    _ presentation: ImagePresentation,
    id: BlockID,
    generation: UInt64
  ) {
    guard !isShuttingDown, generation == documentGeneration else { return }
    retainImagePresentation(presentation, id: id)
    invalidateGeometry()
  }

  private func reload() {
    guard !isShuttingDown else { return }
    guard let url = state.snapshot.url else {
      state.diagnostic = ViewerDiagnostic(.information, "stdin cannot be reloaded")
      return
    }
    state.isReloading = true
    documentLoadGeneration &+= 1
    let loadGeneration = documentLoadGeneration
    themeLoadGeneration &+= 1
    let themeGeneration = themeLoadGeneration
    let scrollAnchor = captureScrollRestorationAnchor()
    replaceDocumentLoadEffect { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await self.dependencies.readDocument(url)
        await self.commitReload(
          snapshot: snapshot,
          loadGeneration: loadGeneration,
          scrollAnchor: scrollAnchor
        )
      } catch {
        self.failReload(error, loadGeneration: loadGeneration)
      }
    }
    replaceThemeLoadEffect { [weak self] in
      guard let self else { return }
      do {
        let loaded = try await self.dependencies.loadTheme()
        self.commitThemeReload(loaded, generation: themeGeneration)
      } catch {
        self.failThemeReload(error, generation: themeGeneration)
      }
    }
  }

  private func commitReload(
    snapshot: DocumentSnapshot,
    loadGeneration: UInt64,
    scrollAnchor: ScrollRestorationAnchor
  ) async {
    guard !isShuttingDown, loadGeneration == documentLoadGeneration else { return }
    documentGeneration &+= 1
    let generation = documentGeneration
    await compileAndCommit(
      snapshot,
      generation: generation,
      loadGeneration: loadGeneration,
      history: .none,
      scroll: .preserve(scrollAnchor)
    )
    guard !isShuttingDown,
      loadGeneration == documentLoadGeneration,
      state.snapshot.url == snapshot.url
    else {
      return
    }
    restartWatcherForCommittedDocument()
  }

  private func failReload(_ error: Error, loadGeneration: UInt64) {
    guard !isShuttingDown, loadGeneration == documentLoadGeneration else { return }
    state.isReloading = false
    state.diagnostic = ViewerDiagnostic(.error, error.localizedDescription)
    restartWatcherForCommittedDocument()
  }

  private func restartWatcherForCommittedDocument() {
    guard watchesDocument, let url = state.snapshot.url else { return }
    startWatcher(for: url)
  }

  private func startWatcher(for url: URL) {
    suspendDocumentWatcher()
    guard !isShuttingDown else { return }
    watcherGeneration &+= 1
    let generation = watcherGeneration
    let changes = dependencies.watchFile(url)
    watcherTask = Task { [weak self] in
      for await _ in changes {
        guard let self,
          !Task.isCancelled,
          !self.isShuttingDown,
          generation == self.watcherGeneration
        else {
          return
        }
        self.scheduleWatcherReload(watcherGeneration: generation)
      }
    }
  }

  private func suspendDocumentWatcher() {
    watcherGeneration &+= 1
    watcherTask?.cancel()
    watcherReloadTask?.cancel()
    watcherTask = nil
    watcherReloadTask = nil
  }

  private func scheduleWatcherReload(watcherGeneration generation: UInt64) {
    watcherReloadTask?.cancel()
    watcherReloadTask = Task { [weak self] in
      guard let self else { return }
      await self.dependencies.sleep(.milliseconds(100))
      guard !Task.isCancelled,
        !self.isShuttingDown,
        generation == self.watcherGeneration
      else {
        return
      }
      self.reload()
    }
  }

  private func startThemeWatcher(for url: URL) {
    themeWatcherTask?.cancel()
    themeWatcherReloadTask?.cancel()
    guard !isShuttingDown else { return }
    let lifecycleGeneration = lifecycleGeneration
    let changes = dependencies.watchFile(url)
    themeWatcherTask = Task { [weak self] in
      for await _ in changes {
        guard let self,
          !Task.isCancelled,
          !self.isShuttingDown,
          lifecycleGeneration == self.lifecycleGeneration
        else {
          return
        }
        self.scheduleThemeWatcherReload()
      }
    }
  }

  private func scheduleThemeWatcherReload() {
    themeWatcherReloadTask?.cancel()
    themeWatcherReloadTask = Task { [weak self] in
      guard let self else { return }
      await self.dependencies.sleep(.milliseconds(100))
      guard !Task.isCancelled, !self.isShuttingDown else { return }
      self.reloadTheme()
    }
  }

  private func reloadTheme() {
    guard !isShuttingDown else { return }
    themeLoadGeneration &+= 1
    let generation = themeLoadGeneration
    replaceThemeLoadEffect { [weak self] in
      guard let self else { return }
      do {
        let loaded = try await self.dependencies.loadTheme()
        self.commitThemeReload(loaded, generation: generation)
      } catch {
        self.failThemeReload(error, generation: generation)
      }
    }
  }

  private func commitThemeReload(_ loaded: LoadedTheme, generation: UInt64) {
    guard !isShuttingDown, generation == themeLoadGeneration else { return }
    state.theme = loaded.theme
    let replacesThemeDiagnostic = state.diagnostic?.message == themeDiagnosticMessage
    themeDiagnosticMessage = nil
    if replacesThemeDiagnostic {
      state.diagnostic = state.document?.diagnostics.first.map {
        ViewerDiagnostic(.warning, $0.message)
      }
    }
  }

  private func failThemeReload(_ error: Error, generation: UInt64) {
    guard !isShuttingDown, generation == themeLoadGeneration else { return }
    themeDiagnosticMessage = error.localizedDescription
    state.diagnostic = ViewerDiagnostic(.error, error.localizedDescription)
  }

  private func open(_ destination: String) {
    switch linkResolver.resolve(destination, relativeTo: state.snapshot.url) {
    case .anchor(let anchor):
      guard let target = state.document?.outline.first(where: { $0.anchor == anchor }) else {
        state.diagnostic = ViewerDiagnostic(.warning, "No heading named #\(anchor)")
        return
      }
      currentHeadingID = target.id
      state.pendingScrollTarget = target.id
    case .markdownDocument(let url, let anchor):
      navigate(to: url, anchor: anchor, history: .recordCurrent)
    case .external(let url), .file(let url):
      spawnEffect { [weak self] in
        guard let self else { return }
        if !(await self.dependencies.openExternal(url)) {
          await self.reportExternalOpenFailure(url)
        }
      }
    case .unsupported(let scheme):
      state.diagnostic = ViewerDiagnostic(.warning, "Unsupported link scheme '\(scheme)'")
    case .invalid(let raw):
      state.diagnostic = ViewerDiagnostic(.warning, "Invalid link '\(raw)'")
    }
  }

  private func navigate(
    to url: URL,
    anchor: String? = nil,
    history: HistoryMutation
  ) {
    guard !isShuttingDown else { return }
    let suspendedWatcherURL = watchesDocument ? state.snapshot.url : nil
    suspendDocumentWatcher()
    documentLoadGeneration &+= 1
    let loadGeneration = documentLoadGeneration
    replaceDocumentLoadEffect { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await self.dependencies.readDocument(url)
        await self.commitNavigation(
          snapshot,
          url: url,
          anchor: anchor,
          history: history,
          loadGeneration: loadGeneration
        )
      } catch {
        self.reportNavigationFailure(
          url,
          error: error,
          loadGeneration: loadGeneration,
          suspendedWatcherURL: suspendedWatcherURL
        )
      }
    }
  }

  private func commitNavigation(
    _ snapshot: DocumentSnapshot,
    url: URL,
    anchor: String?,
    history: HistoryMutation,
    loadGeneration: UInt64
  ) async {
    guard !isShuttingDown, loadGeneration == documentLoadGeneration else { return }
    documentGeneration &+= 1
    let generation = documentGeneration
    await compileAndCommit(
      snapshot,
      generation: generation,
      loadGeneration: loadGeneration,
      history: history,
      scroll: .top
    )
    guard !isShuttingDown,
      loadGeneration == documentLoadGeneration,
      generation == documentGeneration,
      state.snapshot.url == url
    else {
      return
    }
    if let anchor {
      if let target = state.document?.outline.first(where: { $0.anchor == anchor }) {
        currentHeadingID = target.id
        state.pendingScrollTarget = target.id
      } else {
        state.diagnostic = ViewerDiagnostic(.warning, "No heading named #\(anchor)")
      }
    }
    if watchesDocument { startWatcher(for: url) }
  }

  private func reportNavigationFailure(
    _ url: URL,
    error: Error,
    loadGeneration: UInt64,
    suspendedWatcherURL: URL?
  ) {
    guard !isShuttingDown, loadGeneration == documentLoadGeneration else { return }
    state.diagnostic = ViewerDiagnostic(
      .error,
      "Could not open \(url.path): \(error.localizedDescription)"
    )
    if let suspendedWatcherURL, state.snapshot.url == suspendedWatcherURL {
      startWatcher(for: suspendedWatcherURL)
    }
  }

  private func reportExternalOpenFailure(_ url: URL) {
    state.diagnostic = ViewerDiagnostic(
      .error,
      "Could not open \(url.absoluteString)"
    )
  }

  private func navigateHistory(backward: Bool) {
    if backward {
      guard let target = backHistory.last else { return }
      navigate(to: target, history: .backward(target))
    } else {
      guard let target = forwardHistory.last else { return }
      navigate(to: target, history: .forward(target))
    }
  }

  private func updateSearch(_ query: String) {
    state.searchQuery = query
    requestSearch(
      query,
      in: state.document?.searchableText,
      documentGeneration: documentGeneration,
      scrollsToFirstMatch: true
    )
  }

  private func requestSearch(
    _ query: String,
    in index: SearchIndex?,
    documentGeneration: UInt64,
    scrollsToFirstMatch: Bool
  ) {
    searchGeneration &+= 1
    let generation = searchGeneration
    pendingSearchRequest = nil
    activeSearchTask?.cancel()
    state.searchMatches = []
    state.searchResultsTruncated = false
    state.selectedSearchMatch = nil
    if scrollsToFirstMatch {
      state.pendingScrollTarget = nil
    }
    guard !query.isEmpty, let index else {
      state.isSearching = false
      return
    }

    state.isSearching = true
    pendingSearchRequest = SearchRequest(
      index: index,
      query: query,
      searchGeneration: generation,
      documentGeneration: documentGeneration,
      scrollsToFirstMatch: scrollsToFirstMatch
    )
    guard searchWorkerTask == nil else { return }
    searchWorkerTask = Task { [weak self] in
      await self?.runSearchRequests()
    }
  }

  private func runSearchRequests() async {
    while !isShuttingDown, let request = pendingSearchRequest {
      pendingSearchRequest = nil
      let operation = searchOperation
      let task = Task.detached {
        await operation(request.index, request.query)
      }
      activeSearchTask = task
      let result = await withTaskCancellationHandler {
        await task.value
      } onCancel: {
        task.cancel()
      }
      let wasCancelled = task.isCancelled || Task.isCancelled
      activeSearchTask = nil
      guard !wasCancelled,
        !isShuttingDown,
        request.searchGeneration == searchGeneration,
        request.documentGeneration == documentGeneration,
        request.query == state.searchQuery
      else {
        continue
      }

      state.searchMatches = result.matches
      state.searchResultsTruncated = result.isTruncated
      state.selectedSearchMatch = result.matches.isEmpty ? nil : 0
      state.isSearching = false
      if request.scrollsToFirstMatch, let first = result.matches.first {
        currentHeadingID = nil
        state.pendingScrollTarget = first.blockID
      }
    }
    searchWorkerTask = nil
  }

  private func moveMatch(by delta: Int) {
    guard !state.searchMatches.isEmpty else { return }
    let current = state.selectedSearchMatch ?? 0
    let count = state.searchMatches.count
    let next = (current + delta + count) % count
    state.selectedSearchMatch = next
    currentHeadingID = nil
    state.pendingScrollTarget = state.searchMatches[next].blockID
  }

  private func moveHeading(by delta: Int) {
    guard let outline = state.document?.outline, !outline.isEmpty else { return }
    let current =
      currentHeadingID.flatMap { id in
        outline.firstIndex(where: { $0.id == id })
      } ?? (delta > 0 ? -1 : 0)
    let next = min(max(current + delta, 0), outline.count - 1)
    currentHeadingID = outline[next].id
    state.pendingScrollTarget = currentHeadingID
  }

  private func revealNextMermaidSource() {
    guard let document = state.document else { return }
    let next = MarkdownBlockLayout.flattened(
      document.blocks,
      offeredWidth: state.viewport.documentWidth
    ).compactMap { descriptor -> BlockID? in
      if case .mermaid(let id, _, _) = descriptor.block { return id }
      return nil
    }.first {
      !state.revealedMermaidSources.contains($0)
    }
    if let next {
      state.revealedMermaidSources.insert(next)
      invalidateGeometry()
    }
  }

  private func captureScrollRestorationAnchor() -> ScrollRestorationAnchor {
    let offset = state.documentScrollOffset
    guard state.document != nil else {
      return ScrollRestorationAnchor(
        headingAnchor: nil,
        blockIdentity: nil,
        intraBlockOffset: 0,
        sourceLine: 1,
        absoluteOffset: offset
      )
    }
    let geometry = renderedGeometry()
    let visible = geometry.entry(atOrBefore: offset) ?? geometry.entries.first
    let heading =
      geometry.heading(atOrBefore: offset)
      ?? visible.flatMap { geometry.heading(atOrBefore: $0.top) }
    return ScrollRestorationAnchor(
      headingAnchor: heading?.headingAnchor,
      blockIdentity: visible?.stableIdentity,
      intraBlockOffset: visible.map { max(0, offset - $0.top) } ?? 0,
      sourceLine: visible?.sourceLine ?? heading?.sourceLine ?? 1,
      absoluteOffset: offset
    )
  }

  private func restoreScroll(_ policy: ScrollCommitPolicy) {
    switch policy {
    case .top:
      currentHeadingID = nil
      state.pendingScrollTarget = nil
      state.documentScrollOffset = 0
    case .preserve(let anchor):
      let geometry = renderedGeometry().entries
      if let target = anchor.blockIdentity.flatMap({ identity in
        geometry.first(where: { $0.stableIdentity == identity })
      }) {
        currentHeadingID =
          target.headingAnchor == nil
          ? geometry.last(where: {
            $0.headingAnchor != nil && $0.top <= target.top
          })?.blockID
          : target.blockID
        if target.headingAnchor != nil {
          state.pendingScrollTarget = target.blockID
        } else {
          state.pendingScrollTarget = nil
          state.documentScrollOffset =
            target.top + min(anchor.intraBlockOffset, max(0, target.height - 1))
        }
      } else if let target = anchor.headingAnchor.flatMap({ headingAnchor in
        geometry.first(where: { $0.headingAnchor == headingAnchor })
      }) {
        currentHeadingID = target.blockID
        state.pendingScrollTarget = target.blockID
      } else if let target = geometry.compactMap({ entry -> GeometrySourceCandidate? in
        guard let sourceLine = entry.sourceLine else { return nil }
        return GeometrySourceCandidate(entry: entry, sourceLine: sourceLine)
      }).min(by: { lhs, rhs in
        abs(lhs.sourceLine - anchor.sourceLine) < abs(rhs.sourceLine - anchor.sourceLine)
      })?.entry {
        currentHeadingID =
          geometry.last(where: {
            $0.headingAnchor != nil && $0.top <= target.top
          })?.blockID
        state.pendingScrollTarget = nil
        state.documentScrollOffset = target.top
      } else {
        currentHeadingID = nil
        state.pendingScrollTarget = nil
        state.documentScrollOffset = anchor.absoluteOffset
      }
    }
  }

  private func currentMermaidWidth(for id: BlockID) -> Int? {
    guard case .mermaid? = resourceDescriptors[id]?.block else { return nil }
    return resourceDescriptors[id]?.offeredWidth
  }

  private func invalidateGeometry() {
    layoutRevision &+= 1
    geometryCache = nil
  }

  private func renderedGeometry() -> GeometrySnapshot {
    let key = GeometryCacheKey(
      contentRevision: state.contentRevision,
      documentWidth: state.viewport.documentWidth,
      layoutRevision: layoutRevision
    )
    if let geometryCache, geometryCache.key == key {
      return geometryCache.snapshot
    }
    guard let document = state.document else {
      return GeometrySnapshot(entries: [], headings: [])
    }
    let entries = MarkdownBlockLayout.renderedGeometry(
      document.blocks,
      state: state,
      offeredWidth: state.viewport.documentWidth
    )
    let snapshot = GeometrySnapshot(
      entries: entries,
      headings: entries.filter { $0.headingAnchor != nil }
    )
    geometryComputationCount += 1
    geometryCache = (key, snapshot)
    return snapshot
  }

  var renderedGeometryComputationCount: Int {
    geometryComputationCount
  }

  func documentGeometryTop(for id: BlockID) -> Int? {
    renderedGeometry().entry(for: id)?.top
  }

  var retainedPresentationOccupancy:
    (mermaidEntries: Int, mermaidBytes: Int, imageEntries: Int, imageBytes: Int)
  {
    (
      mermaidPresentationCosts.count,
      mermaidPresentationBytes,
      imagePresentationCosts.count,
      imagePresentationBytes
    )
  }

  var ownedEffectCount: Int {
    effectTasks.count + mermaidEffectTasks.count + imageEffectTasks.count
      + (documentLoadWorkerTask == nil ? 0 : 1)
      + (themeLoadWorkerTask == nil ? 0 : 1)
      + (searchWorkerTask == nil ? 0 : 1)
      + (activeSearchTask == nil ? 0 : 1)
  }

  var resourceLifecycleOccupancy:
    (
      visible: Int,
      mermaidStates: Int,
      imageStates: Int,
      activeMermaid: Int,
      activeImages: Int
    )
  {
    (
      visibleResourceIDs.count,
      state.mermaid.count,
      state.images.count,
      activeMermaidRequests.count,
      activeImageRequests.count
    )
  }

  private func retainMermaidPresentation(
    _ presentation: MermaidPresentation,
    id: BlockID,
    request: MermaidRenderRequest
  ) {
    removeMermaidPresentationAccounting(for: id)
    state.mermaid[id] = presentation
    retainedMermaidRequests[id] = request
    recordMermaidState(id)
    guard case .ready = presentation else { return }

    let cost = MermaidRenderCoordinator.estimatedBytes(
      of: presentation,
      request: request
    )
    guard cost <= Self.maximumRetainedMermaidBytes else {
      state.mermaid[id] = .unavailable(
        diagnostic:
          "Diagram exceeds the bounded presentation budget; reveal its source to inspect it."
      )
      recordMermaidState(id)
      return
    }
    mermaidPresentationCosts[id] = cost
    mermaidPresentationBytes = addingSaturated(mermaidPresentationBytes, cost)
    touch(id, in: &mermaidPresentationRecency)

    while mermaidPresentationCosts.count > Self.maximumRetainedMermaidPresentations
      || mermaidPresentationBytes > Self.maximumRetainedMermaidBytes
    {
      guard let oldest = mermaidPresentationRecency.first else { break }
      evictMermaidPresentation(oldest)
    }
  }

  private func retainImagePresentation(
    _ presentation: ImagePresentation,
    id: BlockID
  ) {
    removeImagePresentationAccounting(for: id)
    state.images[id] = presentation
    recordImageState(id)
    guard case .ready(let loaded) = presentation else { return }

    let cost = addingSaturated(loaded.data.count, 128)
    guard cost <= Self.maximumRetainedImageBytes else {
      state.images[id] = .terminalFallback(
        resolvedURL: loaded.url,
        diagnostic: "image exceeds the bounded presentation budget"
      )
      recordImageState(id)
      return
    }
    imagePresentationCosts[id] = cost
    imagePresentationBytes = addingSaturated(imagePresentationBytes, cost)
    touch(id, in: &imagePresentationRecency)

    while imagePresentationCosts.count > Self.maximumRetainedImagePresentations
      || imagePresentationBytes > Self.maximumRetainedImageBytes
    {
      guard let oldest = imagePresentationRecency.first else { break }
      evictImagePresentation(oldest)
    }
  }

  private func recordMermaidState(_ id: BlockID) {
    touch(id, in: &mermaidStateRecency)
    while state.mermaid.count > Self.maximumRetainedResourceStates {
      guard
        let oldest = mermaidStateRecency.first(where: {
          activeMermaidRequests[$0] == nil && !visibleResourceIDs.contains($0)
        })
      else {
        break
      }
      evictMermaidState(oldest)
    }
  }

  private func recordImageState(_ id: BlockID) {
    touch(id, in: &imageStateRecency)
    while state.images.count > Self.maximumRetainedResourceStates {
      guard
        let oldest = imageStateRecency.first(where: {
          activeImageRequests[$0] == nil && !visibleResourceIDs.contains($0)
        })
      else {
        break
      }
      evictImageState(oldest)
    }
  }

  private func evictMermaidPresentation(_ id: BlockID) {
    removeMermaidPresentationAccounting(for: id)
    retainedMermaidRequests.removeValue(forKey: id)
    guard visibleResourceIDs.contains(id) else {
      evictMermaidState(id)
      return
    }
    state.mermaid[id] = .unavailable(
      diagnostic:
        "Diagram was released from the bounded render cache; reveal its source or revisit it."
    )
    recordMermaidState(id)
  }

  private func evictMermaidState(_ id: BlockID) {
    removeMermaidPresentationAccounting(for: id)
    retainedMermaidRequests.removeValue(forKey: id)
    mermaidStateRecency.removeAll { $0 == id }
    state.mermaid.removeValue(forKey: id)
  }

  private func evictImagePresentation(_ id: BlockID) {
    let resolvedURL =
      if case .ready(let loaded)? = state.images[id] {
        loaded.url
      } else {
        nil as URL?
      }
    removeImagePresentationAccounting(for: id)
    guard visibleResourceIDs.contains(id) else {
      evictImageState(id)
      return
    }
    state.images[id] = .terminalFallback(
      resolvedURL: resolvedURL,
      diagnostic: "image was released from the bounded render cache"
    )
    recordImageState(id)
  }

  private func evictImageState(_ id: BlockID) {
    removeImagePresentationAccounting(for: id)
    imageStateRecency.removeAll { $0 == id }
    state.images.removeValue(forKey: id)
  }

  private func removeMermaidPresentationAccounting(for id: BlockID) {
    if let cost = mermaidPresentationCosts.removeValue(forKey: id) {
      mermaidPresentationBytes = max(0, mermaidPresentationBytes - cost)
    }
    mermaidPresentationRecency.removeAll { $0 == id }
  }

  private func removeImagePresentationAccounting(for id: BlockID) {
    if let cost = imagePresentationCosts.removeValue(forKey: id) {
      imagePresentationBytes = max(0, imagePresentationBytes - cost)
    }
    imagePresentationRecency.removeAll { $0 == id }
  }

  private func clearPresentationAccounting() {
    mermaidPresentationRecency.removeAll(keepingCapacity: true)
    mermaidStateRecency.removeAll(keepingCapacity: true)
    mermaidPresentationCosts.removeAll(keepingCapacity: true)
    mermaidPresentationBytes = 0
    imagePresentationRecency.removeAll(keepingCapacity: true)
    imageStateRecency.removeAll(keepingCapacity: true)
    imagePresentationCosts.removeAll(keepingCapacity: true)
    imagePresentationBytes = 0
  }

  private func touch(_ id: BlockID, in recency: inout [BlockID]) {
    recency.removeAll { $0 == id }
    recency.append(id)
  }

  private func addingSaturated(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
  }

  private func spawnEffect(
    _ operation: @escaping @Sendable () async -> Void
  ) {
    guard !isShuttingDown,
      effectTasks.count < Self.maximumExternalOpenEffects
    else {
      return
    }
    let id = UUID()
    let lifecycleGeneration = lifecycleGeneration
    effectTasks[id] = Task { [weak self] in
      guard let self,
        !self.isShuttingDown,
        lifecycleGeneration == self.lifecycleGeneration
      else {
        return
      }
      await operation()
      self.effectFinished(id)
    }
  }

  private func effectFinished(_ id: UUID) {
    effectTasks.removeValue(forKey: id)
  }

  private func replaceDocumentLoadEffect(_ operation: @escaping LatestEffect) {
    guard !isShuttingDown else { return }
    pendingDocumentLoadEffect = operation
    activeDocumentLoadTask?.cancel()
    guard documentLoadWorkerTask == nil else { return }
    documentLoadWorkerTask = Task { [weak self] in
      await self?.runDocumentLoadEffects()
    }
  }

  private func runDocumentLoadEffects() async {
    while !isShuttingDown, let operation = pendingDocumentLoadEffect {
      pendingDocumentLoadEffect = nil
      let task = Task { await operation() }
      activeDocumentLoadTask = task
      await task.value
      activeDocumentLoadTask = nil
    }
    documentLoadWorkerTask = nil
  }

  private func replaceThemeLoadEffect(_ operation: @escaping LatestEffect) {
    guard !isShuttingDown else { return }
    pendingThemeLoadEffect = operation
    activeThemeLoadTask?.cancel()
    guard themeLoadWorkerTask == nil else { return }
    themeLoadWorkerTask = Task { [weak self] in
      await self?.runThemeLoadEffects()
    }
  }

  private func runThemeLoadEffects() async {
    while !isShuttingDown, let operation = pendingThemeLoadEffect {
      pendingThemeLoadEffect = nil
      let task = Task { await operation() }
      activeThemeLoadTask = task
      await task.value
      activeThemeLoadTask = nil
    }
    themeLoadWorkerTask = nil
  }

  private func cancelAndDrainLatestEffects() async {
    pendingDocumentLoadEffect = nil
    pendingThemeLoadEffect = nil
    activeDocumentLoadTask?.cancel()
    activeThemeLoadTask?.cancel()
    documentLoadWorkerTask?.cancel()
    themeLoadWorkerTask?.cancel()
    let documentWorker = documentLoadWorkerTask
    let themeWorker = themeLoadWorkerTask
    await documentWorker?.value
    await themeWorker?.value
    documentLoadWorkerTask = nil
    activeDocumentLoadTask = nil
    themeLoadWorkerTask = nil
    activeThemeLoadTask = nil
  }

  private func cancelAndDrainSearch() async {
    pendingSearchRequest = nil
    activeSearchTask?.cancel()
    searchWorkerTask?.cancel()
    let worker = searchWorkerTask
    await worker?.value
    searchWorkerTask = nil
    activeSearchTask = nil
    state.isSearching = false
  }

  private func spawnMermaidEffect(
    _ operation: @escaping @Sendable () async -> Void
  ) -> UUID? {
    guard !isShuttingDown else { return nil }
    let id = UUID()
    let lifecycleGeneration = lifecycleGeneration
    mermaidEffectTasks[id] = Task { [weak self] in
      guard let self,
        !self.isShuttingDown,
        lifecycleGeneration == self.lifecycleGeneration
      else {
        return
      }
      await operation()
      self.mermaidEffectFinished(id)
    }
    return id
  }

  private func mermaidEffectFinished(_ id: UUID) {
    mermaidEffectTasks.removeValue(forKey: id)
    requestVisibleResources(documentGeneration: documentGeneration)
  }

  private func cancelMermaidEffects() {
    let tasks = Array(mermaidEffectTasks.values)
    for task in tasks { task.cancel() }
    let requestIDs = Array(activeMermaidRequests.keys)
    activeMermaidRequests.removeAll(keepingCapacity: true)
    for id in requestIDs {
      discardNonReadyMermaidPresentation(id)
    }
  }

  private func spawnImageEffect(
    _ operation: @escaping @Sendable () async -> Void
  ) -> UUID? {
    guard !isShuttingDown else { return nil }
    let id = UUID()
    let lifecycleGeneration = lifecycleGeneration
    imageEffectTasks[id] = Task { [weak self] in
      guard let self,
        !self.isShuttingDown,
        lifecycleGeneration == self.lifecycleGeneration
      else {
        return
      }
      await operation()
      self.imageEffectFinished(id)
    }
    return id
  }

  private func imageEffectFinished(_ id: UUID) {
    imageEffectTasks.removeValue(forKey: id)
    requestVisibleResources(documentGeneration: documentGeneration)
  }

  private func cancelImageEffects() {
    let tasks = Array(imageEffectTasks.values)
    for task in tasks { task.cancel() }
    let requestIDs = Array(activeImageRequests.keys)
    activeImageRequests.removeAll(keepingCapacity: true)
    for id in requestIDs {
      discardNonReadyImagePresentation(id)
    }
  }

  private func drainOwnedEffects() async {
    while !effectTasks.isEmpty || !mermaidEffectTasks.isEmpty || !imageEffectTasks.isEmpty {
      let tasks =
        Array(effectTasks.values)
        + Array(mermaidEffectTasks.values)
        + Array(imageEffectTasks.values)
      effectTasks.removeAll()
      mermaidEffectTasks.removeAll()
      imageEffectTasks.removeAll()
      for task in tasks { task.cancel() }
      for task in tasks { await task.value }
    }
  }
}
