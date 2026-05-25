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
  @FocusState private var isFocused: Bool

  private let registry: PreviewerRegistry

  public init(
    path: [URL],
    registry: PreviewerRegistry = .defaults,
    entryCache: DirectoryEntryCache = DirectoryEntryCache()
  ) {
    let normalizedPath =
      path.isEmpty
      ? [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
      : path
    _path = State(initialValue: normalizedPath)
    _previewSessions = State(
      initialValue: PreviewSessionSlot<TerminalProcessSession> { session in
        Task {
          await session.terminate()
        }
      }
    )
    _entryCache = State(initialValue: entryCache)
    self.registry = registry
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      MillerLayout {
        ForEach(path.indices, id: \.self) { index in
          let directory = path[index]
          FileColumn(
            directory: directory,
            entries: entries(in: directory),
            selection: selection[directory],
            isActive: index == activeColumn
          )
        }

        previewPane
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .focusable(true)
    .focused($isFocused)
    .defaultFocus($isFocused, true)
    .onKeyPress(perform: handleKeyPress)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Text("File Previewer")
        .foregroundStyle(.tint)
      Text(activeDirectory.path)
        .foregroundStyle(.separator)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text(previewedURL?.lastPathComponent ?? "no preview")
        .foregroundStyle(.muted)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  @ViewBuilder
  private var previewPane: some View {
    if let previewSession = previewSessions.current {
      TerminalView(session: previewSession)
        .border(.separator)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("Preview")
          .foregroundStyle(.muted)
        Divider()
        Text("(select a file)")
          .foregroundStyle(.separator)
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .border(.separator)
    }
  }

  private var activeDirectory: URL {
    path[min(activeColumn, max(0, path.count - 1))]
  }

  private func entries(in directory: URL) -> [FileEntry] {
    entryCache.entries(in: directory)
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
    default:
      return .ignored
    }
  }

  private func moveSelection(by delta: Int) {
    let directory = activeDirectory
    let fileEntries = entries(in: directory)
    guard !fileEntries.isEmpty else {
      selection[directory] = nil
      clearPreview()
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
    clearPreview()
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
      clearPreview()
      clearDescendants(after: directory)
      return
    }

    let isDirectory =
      (try? selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    if isDirectory {
      let prefix = pathPrefix(through: directory)
      path = prefix + [selected]
      activeColumn =
        activatesDirectory
        ? max(0, path.count - 1)
        : max(0, prefix.count - 1)
      entryCache.retainOnly(Set(path))
      clearPreview()
    } else {
      clearDescendants(after: directory)
      showPreview(for: selected)
    }
  }

  private func clearPreview() {
    previewSessions.clear()
    previewedURL = nil
  }

  private func showPreview(for selected: URL) {
    let command = registry.command(for: selected)
    previewSessions.replace(
      with: TerminalProcessSession(
        command: command.executable,
        arguments: command.arguments(selected),
        initialSize: CellSize(width: 80, height: 40)
      )
    )
    previewedURL = selected
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
}
