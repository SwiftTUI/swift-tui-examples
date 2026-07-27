public import Foundation
public import SwiftTUI

public struct SextantRootView: View {
  private let model: BrowserModel
  private let configuration: SextantConfiguration

  public init(
    root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) {
    self.init(
      root: root,
      initialSelectionURL: nil,
      policy: DirectoryPolicy(),
      previewMode: .automatic,
      watchesFileSystem: true,
      configuration: SextantConfiguration(),
      stateURL: nil
    )
  }

  public init(launch: ResolvedLaunchInput) {
    self.init(
      root: launch.rootDirectoryURL,
      initialSelectionURL: launch.selectedFileURL,
      policy: DirectoryPolicy(
        showsHiddenFiles: launch.showsHiddenFiles,
        sort: Self.directorySort(
          launch.sort,
          direction: launch.sortDirection
        ),
        directoriesFirst: launch.configuration.sort.directoriesFirst
      ),
      previewMode: Self.previewMode(launch.previewMode),
      watchesFileSystem: launch.watchesFileSystem,
      configuration: launch.configuration,
      stateURL: launch.stateURL
    )
  }

  private init(
    root: URL,
    initialSelectionURL: URL?,
    policy: DirectoryPolicy,
    previewMode: PreviewPipelineMode,
    watchesFileSystem: Bool,
    configuration: SextantConfiguration,
    stateURL: URL?
  ) {
    let root = root.standardizedFileURL
    let fileSystem = LocalFileSystemClient()
    let rootIdentity: FileSystemIdentity =
      switch fileSystem.identity(at: root, followingSymbolicLinks: true) {
      case .success(let identity):
        identity
      case .failure:
        .pathFallback(for: root)
      }
    let directoryStore = DirectoryStore(client: fileSystem)
    let searchCoordinator = FilenameSearchCoordinator(fileSystem: fileSystem)
    let adapters =
      configuration.previewAdapters.map(Self.previewAdapter)
      + PreviewAdapterDescription.defaults
    let previewPipeline = PreviewPipeline(
      fileSystem: fileSystem,
      resolver: PreviewResolver(adapters: adapters),
      executableCache: .live(
        path: ProcessInfo.processInfo.environment["PATH"] ?? ""
      ),
      mode: previewMode
    )
    let watcher: (any DirectoryWatching)? =
      watchesFileSystem ? LiveDirectoryWatcher() : nil
    let stateClient = stateURL.map(PersistentStateClient.jsonFile)
    let persistedState = (try? stateClient?.load()) ?? SextantPersistentState()
    let stateRepository = stateClient.map {
      SextantStateRepository(client: $0)
    }
    let handoffClient = HandoffClient.live()
    let editorEnvironment = ProcessInfo.processInfo.environment
    let configuredEditor = configuration.editor
    self.configuration = configuration
    model = BrowserModel(
      root: root,
      rootID: DirectoryID(identity: rootIdentity),
      policy: policy,
      initialSelectionURL: initialSelectionURL,
      hasSeenHelp: persistedState.hasSeenHelp,
      bookmarks: persistedState.bookmarks,
      recents: persistedState.recents,
      dependencies: BrowserModelDependencies(
        loadDirectory: { request in
          await directoryStore.load(request)
        },
        previewEvents: { item, directorySnapshot, generation in
          await previewPipeline.events(
            for: item,
            generation: generation,
            directorySnapshot: directorySnapshot
          )
        },
        cancelPreview: {
          await previewPipeline.cancelCurrent()
        },
        watchEvents: { directories in
          guard let watcher else {
            return AsyncStream { $0.finish() }
          }
          return await watcher.events(for: directories)
        },
        invalidateDirectory: { directoryID in
          await directoryStore.invalidate(directoryID)
        },
        pinDirectories: { requests in
          await directoryStore.setPinnedRequests(requests)
        },
        markHelpSeen: {
          try? await stateRepository?.markHelpSeen()
        },
        recordRecent: { url in
          try? await stateRepository?.recordRecent(url)
        },
        toggleBookmark: { url in
          try? await stateRepository?.toggleBookmark(url)
        },
        performHandoff: { request in
          await handoffClient.performWithRuntimeHandoff(request)
        },
        resolveEditor: {
          EditorCommandResolver().resolve(
            environment: editorEnvironment,
            configuredFallback: configuredEditor
          )
        },
        searchEvents: { root, query, policy in
          await searchCoordinator.search(
            root: root,
            query: query,
            policy: policy
          )
        },
        inspectLaunchPath: { url in
          LocalLaunchPathInspector().kind(of: url)
        },
        resolveFileSystemIdentity: { url, followingSymbolicLinks in
          fileSystem.identity(
            at: url,
            followingSymbolicLinks: followingSymbolicLinks
          )
        },
        shutdown: {
          await previewPipeline.shutdown()
          await searchCoordinator.cancel()
          await watcher?.shutdown()
          await directoryStore.cancelAll()
        }
      )
    )
  }

  init(model: BrowserModel) {
    self.model = model
    configuration = SextantConfiguration()
  }

  public var body: some View {
    ColumnBrowser(model: model, configuration: configuration)
  }

  public func shutdown() async {
    await model.shutdown()
  }

  private static func directorySort(
    _ sort: LaunchSort,
    direction: SortConfiguration.Direction
  ) -> DirectorySort {
    let direction: SortDirection =
      direction == .ascending ? .ascending : .descending
    switch sort {
    case .name:
      return DirectorySort(key: .name, direction: direction)
    case .modified:
      return DirectorySort(key: .modificationDate, direction: direction)
    case .size:
      return DirectorySort(key: .size, direction: direction)
    }
  }

  private static func previewMode(_ mode: LaunchPreviewMode) -> PreviewPipelineMode {
    switch mode {
    case .auto:
      .automatic
    case .builtIn:
      .builtIn
    case .external:
      .external
    case .off:
      .off
    }
  }

  static func previewAdapter(
    _ configuration: ExternalPreviewConfiguration
  ) -> PreviewAdapterDescription {
    PreviewAdapterDescription(
      id: PreviewAdapterID(configuration.id),
      displayName: configuration.displayName,
      contentKinds: Set(
        configuration.contentKinds.map { kind in
          switch kind {
          case .text:
            .text
          case .binary:
            .binary
          case .anyFile:
            .anyFile
          }
        }
      ),
      fileExtensions: Set(configuration.fileExtensions),
      executable: configuration.executable,
      isInteractive: configuration.isInteractive,
      priority: configuration.priority,
      maximumByteCount: configuration.maximumByteCount,
      arguments: { url in
        configuration.arguments.map {
          $0 == "{path}" ? url.path : $0
        }
      }
    )
  }
}
