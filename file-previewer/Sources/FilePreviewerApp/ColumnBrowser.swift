public import Foundation
public import SwiftTUI
import SwiftTUITerminal

public struct ColumnBrowser: View {
  @State private var path: [URL]
  @State private var selection: [URL: URL] = [:]
  @State private var activeColumn: Int = 0
  @State private var previewSessions: PreviewSessionSlot<TerminalProcessSession>
  @State private var previewedURL: URL?
  @State private var entryCache: DirectoryEntryCache
  @State private var directoryLoadRevision = 0
  @State private var semanticFocus: BrowserFocus?
  @FocusState private var runtimeFocus: BrowserFocus?

  private let registry: PreviewerRegistry
  private let onPreviewSessionCreated: (@MainActor @Sendable (TerminalProcessSession) -> Void)?

  public init(
    path: [URL],
    registry: PreviewerRegistry = .defaults,
    entryCache: DirectoryEntryCache = DirectoryEntryCache(),
    previewSessions: PreviewSessionSlot<TerminalProcessSession> = .terminalProcesses()
  ) {
    self.init(
      path: path,
      registry: registry,
      entryCache: entryCache,
      previewSessions: previewSessions,
      onPreviewSessionCreated: nil
    )
  }

  init(
    path: [URL],
    registry: PreviewerRegistry,
    entryCache: DirectoryEntryCache,
    previewSessions: PreviewSessionSlot<TerminalProcessSession> = .terminalProcesses(),
    onPreviewSessionCreated:
      (@MainActor @Sendable (TerminalProcessSession) -> Void)?
  ) {
    let normalizedPath =
      path.isEmpty
      ? [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
      : path
    _path = State(initialValue: normalizedPath)
    _previewSessions = State(initialValue: previewSessions)
    _entryCache = State(initialValue: entryCache)
    _semanticFocus = State(
      initialValue: .browser(DirectoryID(normalizedPath[0]))
    )
    self.registry = registry
    self.onPreviewSessionCreated = onPreviewSessionCreated
  }

  public var body: some View {
    _ = directoryLoadRevision
    return VStack(alignment: .leading, spacing: 0) {
      MillerLayout {
        ForEach(path.indices, id: \.self) { index in
          let directory = path[index]
          FileColumn(
            directory: directory,
            entries: entries(in: directory),
            selection: selection[directory],
            isActive: index == activeColumn,
            isLoading: !entryCache.hasEntries(in: directory)
          )
          .border(.muted, set: BorderSet.single, sides: Edge.Set.trailing)
          .focusable(index == activeColumn)
          .focused($runtimeFocus, equals: .browser(DirectoryID(directory)))
        }
        previewPane
      }
      paths
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .defaultFocus($runtimeFocus, .browser(DirectoryID(activeDirectory)))
    .onChange(of: runtimeFocus) { _, next in
      semanticFocus = next
    }
    .onKeyPress(perform: handleKeyPress)
    .onDisappear {
      Task {
        await clearPreview()
      }
    }
    .task(id: DirectoryLoadKey(directories: path)) { @MainActor in
      await loadVisibleDirectories()
    }
  }

  private var paths: some View {
    HStack(spacing: 1) {
      Text(activeDirectory.path)
        .foregroundStyle(.separator)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text(focusLabel)
        .foregroundStyle(.muted)
    }
    .background(.black.opacity(0.1))
  }

  private var focusLabel: String {
    switch semanticFocus {
    case .preview:
      "PREVIEW"
    default:
      "BROWSER"
    }
  }

  @ViewBuilder
  private var previewPane: some View {
    VStack(alignment: .leading) {
      Text(previewedURL?.lastPathComponent ?? "")
        .foregroundStyle(.muted)
      Divider()
      if let previewSession = previewSessions.current {
        TerminalView(
          session: previewSession,
          keyRouting: routePreviewKey
        )
        .hostFocused($runtimeFocus, equals: .preview)
        .focusable(semanticFocus == .preview)
        .onAppear {
          setFocus(
            semanticFocus == .preview
              ? .preview
              : .browser(DirectoryID(activeDirectory))
          )
        }
      }
      Spacer()
    }
  }

  private var activeDirectory: URL {
    path[min(activeColumn, max(0, path.count - 1))]
  }

  private func entries(in directory: URL) -> [FileEntry] {
    entryCache.cachedEntries(in: directory) ?? []
  }

  private func handleKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    switch keyPress {
    case KeyPress(.arrowUp):
      moveSelection(by: -1)
      return .handled
    case KeyPress(.arrowDown):
      moveSelection(by: 1)
      return .handled
    case KeyPress(.arrowLeft):
      moveToParentColumn()
      return .handled
    case KeyPress(.arrowRight), KeyPress(.return):
      advanceOrPreview(directory: activeDirectory, selected: selection[activeDirectory])
      return .handled
    case KeyPress(.tab):
      guard previewSessions.current != nil else {
        return .ignored
      }
      setFocus(.preview)
      return .handled
    case KeyPress(.character("d"), modifiers: .ctrl):
      Task {
        await clearPreview()
      }
      return .ignored
    default:
      return .ignored
    }
  }

  private func routePreviewKey(_ keyPress: KeyPress) -> TerminalViewKeyDisposition {
    guard keyPress == KeyPress(.escape) else {
      return .forwardToChild
    }
    setFocus(.browser(DirectoryID(activeDirectory)))
    return .handledByHost
  }

  private func setFocus(_ next: BrowserFocus?) {
    semanticFocus = next
    runtimeFocus = next
  }

  private func moveSelection(by delta: Int) {
    let directory = activeDirectory
    let fileEntries = entries(in: directory)
    guard !fileEntries.isEmpty else {
      selection[directory] = nil
      Task {
        await clearPreview()
      }
      clearDescendants(after: directory)
      return
    }

    let selectedURL = selection[directory]
    let currentIndex =
      selectedURL.flatMap { selected in
        fileEntries.firstIndex { $0.url == selected }
      } ?? (delta >= 0 ? -1 : fileEntries.count)
    let nextIndex = min(max(currentIndex + delta, 0), fileEntries.count - 1)
    let selected = fileEntries[nextIndex]
    selection[directory] = selected.url
    revealOrPreview(directory: directory, selected: selected.url)
  }

  private func moveToParentColumn() {
    guard activeColumn > 0 else {
      return
    }
    activeColumn -= 1
    clearDescendants(after: activeDirectory)
    Task {
      await clearPreview()
    }
    setFocus(.browser(DirectoryID(activeDirectory)))
  }

  private func advanceOrPreview(
    directory: URL,
    selected: URL?
  ) {
    handleSelection(directory: directory, selected: selected, activatesDirectory: true)
  }

  private func revealOrPreview(
    directory: URL,
    selected: URL?
  ) {
    handleSelection(directory: directory, selected: selected, activatesDirectory: false)
  }

  private func handleSelection(
    directory: URL,
    selected: URL?,
    activatesDirectory: Bool
  ) {
    guard let selected else {
      Task {
        await clearPreview()
      }
      clearDescendants(after: directory)
      return
    }

    let isDirectory =
      entryCache.cachedEntries(in: directory)?.first { $0.url == selected }?.isDirectory
      ?? ((try? selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
    if isDirectory {
      let prefix = pathPrefix(through: directory)
      path = prefix + [selected]
      activeColumn =
        activatesDirectory
        ? max(0, path.count - 1)
        : max(0, prefix.count - 1)
      entryCache.retainOnly(Set(path))
      Task {
        await clearPreview()
      }
      setFocus(.browser(DirectoryID(activeDirectory)))
    } else {
      clearDescendants(after: directory)
      showPreview(for: selected, shouldFocus: activatesDirectory)
    }
  }

  private func clearPreview() async {
    await previewSessions.clear()
    previewedURL = nil
  }

  private func showPreview(for selected: URL, shouldFocus: Bool) {
    if previewedURL == selected, previewSessions.current != nil {
      if shouldFocus {
        setFocus(.preview)
      }
      return
    }
    let command = registry.command(for: selected)
    let session = TerminalProcessSession(
      command: command.executable,
      arguments: command.arguments(selected),
      initialSize: CellSize(width: 80, height: 40)
    )
    Task {
      guard await previewSessions.replace(with: session) else {
        return
      }
      onPreviewSessionCreated?(session)
      previewedURL = selected
      setFocus(
        shouldFocus
          ? .preview
          : .browser(DirectoryID(activeDirectory))
      )
    }
  }

  private func pathPrefix(through directory: URL) -> [URL] {
    guard let index = path.firstIndex(of: directory) else {
      return [directory]
    }
    return Array(path.prefix(index + 1))
  }

  private func clearDescendants(after directory: URL) {
    path = pathPrefix(through: directory)
    activeColumn = min(activeColumn, max(0, path.count - 1))
    entryCache.retainOnly(Set(path))
  }

  private func loadVisibleDirectories() async {
    if runtimeFocus == nil {
      runtimeFocus = semanticFocus
    }
    let directories = path
    var didChange = false
    for directory in directories {
      guard !entryCache.hasEntries(in: directory) else {
        continue
      }
      let entries = await FileEntry.entriesOffMain(in: directory)
      guard !Task.isCancelled else {
        return
      }
      entryCache.store(entries, for: directory)
      didChange = true
    }
    entryCache.retainOnly(Set(path))
    if didChange {
      directoryLoadRevision &+= 1
    }
  }

}

private struct DirectoryLoadKey: Equatable, Sendable {
  var directories: [URL]
}

private func terminatePreviewSession(_ session: TerminalProcessSession) async {
  await session.terminate()
  if await waitForPreviewExit(session, timeout: .milliseconds(750)) {
    return
  }
  await session.terminate(signal: 9)
  await waitForPreviewExit(session)
}

extension PreviewSessionSlot where Session == TerminalProcessSession {
  public static func terminalProcesses() -> PreviewSessionSlot<TerminalProcessSession> {
    PreviewSessionSlot<TerminalProcessSession> { session in
      await terminatePreviewSession(session)
    }
  }
}

private func waitForPreviewExit(
  _ session: TerminalProcessSession,
  timeout: Duration
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while clock.now < deadline {
    if case .exited = await session.currentLifecycle() {
      return true
    }
    await Task.yield()
  }
  return false
}

private func waitForPreviewExit(_ session: TerminalProcessSession) async {
  while true {
    if case .exited = await session.currentLifecycle() {
      return
    }
    await Task.yield()
  }
}
