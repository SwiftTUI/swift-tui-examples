import Foundation

public enum ViewerMermaidGlyphMode: String, Equatable, Hashable, Sendable {
  case unicode
  case ascii
}

public enum ViewerMermaidAmbiguousWidth: String, Equatable, Hashable, Sendable {
  case narrow
  case wide
}

public struct ViewerMermaidConfiguration: Equatable, Hashable, Sendable {
  public var glyphMode: ViewerMermaidGlyphMode
  public var ambiguousWidth: ViewerMermaidAmbiguousWidth

  public init(
    glyphMode: ViewerMermaidGlyphMode = .unicode,
    ambiguousWidth: ViewerMermaidAmbiguousWidth = .narrow
  ) {
    self.glyphMode = glyphMode
    self.ambiguousWidth = ambiguousWidth
  }
}

public struct MermaidRenderRequest: Equatable, Hashable, Sendable {
  public var blockID: BlockID
  public var source: String
  public var width: Int
  public var configuration: ViewerMermaidConfiguration

  public init(
    blockID: BlockID,
    source: String,
    width: Int,
    configuration: ViewerMermaidConfiguration = .init()
  ) {
    self.blockID = blockID
    self.source = source
    self.width = width
    self.configuration = configuration
  }
}

struct ViewerDependencies: Sendable {
  var themeURL: URL?
  var readDocument: @Sendable (URL) async throws -> DocumentSnapshot
  var loadTheme: @Sendable () async throws -> LoadedTheme
  var watchFile: @Sendable (URL) -> AsyncStream<Void>
  var renderMermaid: @Sendable (MermaidRenderRequest) async -> MermaidPresentation
  var loadImage: @Sendable (String, URL?) async throws -> LoadedImage
  var openExternal: @Sendable (URL) async -> Bool
  var sleep: @Sendable (Duration) async -> Void

  static func live(
    themeSelection: ThemeSelection,
    allowsRemoteImages: Bool,
    mermaidConfiguration: ViewerMermaidConfiguration = .init()
  ) -> ViewerDependencies {
    let documentSource = DocumentSource()
    let themeRepository = ThemeRepository()
    let watcher = FileWatcher()
    let resourceLoader = ResourceLoader(allowsRemoteImages: allowsRemoteImages)
    let imageCoordinator = ImageLoadCoordinator(loader: resourceLoader)
    let opener = PlatformLinkOpener()
    let themeURL: URL? =
      if case .file(let url, _) = themeSelection {
        Optional(url)
      } else {
        nil
      }
    return ViewerDependencies(
      themeURL: themeURL,
      readDocument: { url in
        try await withCancellableDetachedTask {
          try documentSource.read(fileURL: url)
        }
      },
      loadTheme: {
        try await withCancellableDetachedTask {
          try themeRepository.load(themeSelection)
        }
      },
      watchFile: { watcher.changes(to: $0) },
      renderMermaid: { request in
        precondition(
          request.configuration == mermaidConfiguration,
          "ViewerModel must preserve the launch Mermaid configuration"
        )
        return await MrkdwnMermaidAdapter.render(request)
      },
      loadImage: { source, documentURL in
        try await imageCoordinator.load(source: source, relativeTo: documentURL)
      },
      openExternal: { await opener.open($0) },
      sleep: { duration in
        try? await Task.sleep(for: duration)
      }
    )
  }
}

private func withCancellableDetachedTask<Value: Sendable>(
  _ operation: @escaping @Sendable () throws -> Value
) async throws -> Value {
  let task = Task.detached(operation: operation)
  return try await withTaskCancellationHandler {
    try await task.value
  } onCancel: {
    task.cancel()
  }
}
