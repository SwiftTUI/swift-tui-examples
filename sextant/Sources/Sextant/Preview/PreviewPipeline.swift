import Foundation

enum PreviewPipelineMode: Equatable, Sendable {
  case automatic
  case builtIn
  case external
  case off
}

actor PreviewPipeline {
  private struct Request {
    var item: BrowserItem
    var continuation: AsyncStream<PreviewModelEvent>.Continuation
    var external: ExternalPreviewState?
  }

  private let builtInPreviewer: BuiltInPreviewer
  private let resolver: PreviewResolver
  private let executableCache: PreviewExecutableCache
  private let mode: PreviewPipelineMode
  private let clock: PreviewClock
  private let processClient: PreviewProcessClient

  private var requests: [UInt64: Request] = [:]
  private var coordinator: PreviewCoordinator?
  private var latestGeneration: UInt64?
  private var isShuttingDown = false

  init(
    fileSystem: any FileSystemClient,
    resolver: PreviewResolver = PreviewResolver(),
    executableCache: PreviewExecutableCache,
    mode: PreviewPipelineMode = .automatic,
    clock: PreviewClock = .continuous,
    processClient: PreviewProcessClient = .live
  ) {
    builtInPreviewer = BuiltInPreviewer(fileSystem: fileSystem)
    self.resolver = resolver
    self.executableCache = executableCache
    self.mode = mode
    self.clock = clock
    self.processClient = processClient
  }

  func events(
    for item: BrowserItem,
    generation: PreviewGeneration,
    directorySnapshot: DirectorySnapshot? = nil
  ) async -> AsyncStream<PreviewModelEvent> {
    let rawGeneration = generation.rawValue
    guard !isShuttingDown,
      latestGeneration.map({ rawGeneration > $0 }) ?? true
    else {
      return finishedStream()
    }

    latestGeneration = rawGeneration
    let stream = AsyncStream<PreviewModelEvent> { continuation in
      continuation.onTermination = { [weak self] _ in
        Task {
          await self?.removeRequest(rawGeneration)
        }
      }
      requests[rawGeneration] = Request(
        item: item,
        continuation: continuation,
        external: nil
      )
    }
    finishRequests(olderThan: rawGeneration)

    if mode == .off {
      requests[rawGeneration]?.continuation.yield(
        .unavailable(
          item: item,
          generation: generation,
          reason: .previewDisabled
        )
      )
      finishRequest(rawGeneration)
      return stream
    }

    let fallback = await builtInPreviewer.preview(
      item: item,
      directorySnapshot: directorySnapshot
    )
    guard owns(rawGeneration) else {
      return stream
    }

    let resolution = await resolvedPreview(item: item, fallback: fallback)
    guard owns(rawGeneration) else {
      return stream
    }

    switch resolution {
    case .external(let launch):
      let coordinator = previewCoordinator()
      await coordinator.select(
        generation: rawGeneration,
        launch: launch,
        fallback: fallback
      )
    case .builtIn:
      let coordinator = previewCoordinator()
      await coordinator.select(
        generation: rawGeneration,
        launch: nil,
        fallback: fallback
      )
    case .unavailable(let failure):
      // The two branches above hand the selection to the coordinator, which
      // replaces the running child itself once its debounce window closes.
      // Nothing downstream of here does, so this is the one path that has to
      // tear the child down.
      await coordinator?.cancelCurrent()
      publishResolutionFailure(
        failure,
        rawGeneration: rawGeneration,
        fallback: fallback
      )
    }
    return stream
  }

  func cancelCurrent() async {
    finishAllRequests()
    await coordinator?.cancelCurrent()
  }

  func shutdown() async {
    isShuttingDown = true
    finishAllRequests()
    await coordinator?.shutdown()
  }

  private func resolvedPreview(
    item: BrowserItem,
    fallback: BuiltInPreview
  ) async -> PreviewResolution {
    guard mode != .builtIn else {
      return .builtIn
    }
    guard let classification = classification(of: fallback) else {
      return mode == .external
        ? .unavailable(.noMatchingAdapter)
        : .builtIn
    }
    let available = await executableCache.availability(for: resolver.adapters)
    return resolver.resolve(
      url: item.url,
      classification: classification,
      byteCount: fallback.metadata.size,
      availableExecutables: available,
      requiresExternal: mode == .external
    )
  }

  private func classification(
    of preview: BuiltInPreview
  ) -> PreviewContentClassification? {
    switch preview.body {
    case .text(let text):
      .text(text.encoding)
    case .hexadecimal:
      .binary
    case .directorySummary, .metadataOnly, .unavailable, .failed:
      nil
    }
  }

  private func previewCoordinator() -> PreviewCoordinator {
    if let coordinator {
      return coordinator
    }
    let coordinator = PreviewCoordinator(
      clock: clock,
      processClient: processClient
    ) { [weak self] event in
      await self?.receive(event)
    }
    self.coordinator = coordinator
    return coordinator
  }

  private func receive(_ event: PreviewCoordinatorEvent) {
    switch event {
    case .builtIn(let rawGeneration, let preview):
      guard owns(rawGeneration),
        let request = requests[rawGeneration]
      else {
        return
      }
      let generation = PreviewGeneration(rawValue: rawGeneration)
      request.continuation.yield(
        .builtIn(
          item: request.item,
          generation: generation,
          preview: preview
        )
      )
      finishRequest(rawGeneration)

    case .starting(let rawGeneration, let launch, let handle, let fallback):
      guard owns(rawGeneration),
        var request = requests[rawGeneration]
      else {
        return
      }
      let external = ExternalPreviewState(
        item: request.item,
        generation: PreviewGeneration(rawValue: rawGeneration),
        adapterName: launch.adapterName,
        status: .starting,
        handle: handle,
        fallback: fallback
      )
      request.external = external
      requests[rawGeneration] = request
      request.continuation.yield(.external(external))

    case .ready(let rawGeneration, let handleID):
      updateExternal(rawGeneration, handleID: handleID) {
        $0.status = .ready
      }

    case .slow(let rawGeneration, let handleID):
      updateExternal(rawGeneration, handleID: handleID) {
        $0.status = .slow
      }

    case .exited(let rawGeneration, let handleID, let reason):
      switch reason {
      case .normal(code: 0), .sessionClosed:
        updateExternal(rawGeneration, handleID: handleID) {
          $0.status = .exited(reason)
        }
      case .normal(let code):
        publishExternalFailure(
          rawGeneration,
          handleID: handleID,
          failure: .externalExit(code)
        )
      case .signal(let signal):
        publishExternalFailure(
          rawGeneration,
          handleID: handleID,
          failure: .externalSignal(signal)
        )
      }
      finishRequest(rawGeneration)

    case .failed(let rawGeneration, let failure, let fallback):
      guard owns(rawGeneration),
        let request = requests[rawGeneration]
      else {
        return
      }
      let mappedFailure: PreviewFailure =
        switch failure {
        case .startup(let message):
          .unreadable("Preview failed to start: \(message)")
        }
      request.continuation.yield(
        .failed(
          item: request.item,
          generation: PreviewGeneration(rawValue: rawGeneration),
          adapter: request.external?.adapterName,
          failure: mappedFailure,
          fallback: fallback
        )
      )
      finishRequest(rawGeneration)
    }
  }

  private func updateExternal(
    _ rawGeneration: UInt64,
    handleID: UUID,
    update: (inout ExternalPreviewState) -> Void
  ) {
    guard owns(rawGeneration),
      var request = requests[rawGeneration],
      var external = request.external,
      external.handle.id == handleID
    else {
      return
    }
    update(&external)
    request.external = external
    requests[rawGeneration] = request
    request.continuation.yield(.external(external))
  }

  private func publishResolutionFailure(
    _ failure: PreviewResolutionFailure,
    rawGeneration: UInt64,
    fallback: BuiltInPreview?
  ) {
    guard owns(rawGeneration),
      let request = requests[rawGeneration]
    else {
      return
    }
    let adapter: String?
    let previewFailure: PreviewFailure
    switch failure {
    case .missingExecutable(let adapterName, let executable):
      adapter = adapterName
      previewFailure = .missingExecutable(executable)
    case .noMatchingAdapter:
      adapter = nil
      previewFailure = .unreadable(
        "No external preview adapter matches this item."
      )
    }
    request.continuation.yield(
      .failed(
        item: request.item,
        generation: PreviewGeneration(rawValue: rawGeneration),
        adapter: adapter,
        failure: previewFailure,
        fallback: fallback
      )
    )
    finishRequest(rawGeneration)
  }

  private func publishExternalFailure(
    _ rawGeneration: UInt64,
    handleID: UUID,
    failure: PreviewFailure
  ) {
    guard owns(rawGeneration),
      let request = requests[rawGeneration],
      let external = request.external,
      external.handle.id == handleID
    else {
      return
    }
    request.continuation.yield(
      .failed(
        item: request.item,
        generation: PreviewGeneration(rawValue: rawGeneration),
        adapter: external.adapterName,
        failure: failure,
        fallback: external.fallback
      )
    )
  }

  private func finishRequests(olderThan rawGeneration: UInt64) {
    let older = requests.keys.filter { $0 < rawGeneration }
    for generation in older {
      finishRequest(generation)
    }
  }

  private func finishAllRequests() {
    let generations = Array(requests.keys)
    for generation in generations {
      finishRequest(generation)
    }
  }

  private func finishRequest(_ rawGeneration: UInt64) {
    requests.removeValue(forKey: rawGeneration)?.continuation.finish()
  }

  private func owns(_ rawGeneration: UInt64) -> Bool {
    !isShuttingDown
      && latestGeneration == rawGeneration
      && requests[rawGeneration] != nil
  }

  private func finishedStream() -> AsyncStream<PreviewModelEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  private func removeRequest(_ rawGeneration: UInt64) {
    requests.removeValue(forKey: rawGeneration)
  }
}
