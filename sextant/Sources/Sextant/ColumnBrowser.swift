import Foundation
import SwiftTUI
import SwiftTUITerminal

struct ColumnBrowser: View {
  @Bindable var model: BrowserModel
  @FocusState private var runtimeFocus: BrowserFocus?
  @State private var filterText = ""
  @State private var paletteQuery = ""
  @State private var searchQuery = ""
  @State private var isPreviewFocusHandoffActive = false

  private let commandCatalog: CommandCatalog
  private let configuration: SextantConfiguration

  init(
    model: BrowserModel,
    configuration: SextantConfiguration = SextantConfiguration()
  ) {
    self.model = model
    self.configuration = configuration
    commandCatalog =
      (try? CommandCatalog().applyingKeyOverrides(configuration.keyOverrides))
      ?? CommandCatalog()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      browserHeader
      if model.state.overlay != .none {
        overlayPanel
      }
      GeometryReader { proxy in
        responsiveSurfaces(width: proxy.size.width)
      }
      statusBar
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .defaultFocus($runtimeFocus, model.state.focus)
    .onAppear {
      model.send(.start)
      filterText = model.state.filter.query
      runtimeFocus = model.state.focus
    }
    .onChange(of: previewFocusTargetKind) { previous, next in
      beginPreviewFocusHandoffIfNeeded(from: previous, to: next)
    }
    .onChange(of: runtimeFocus) { _, next in
      if isPreviewFocusHandoffActive,
        model.state.focus == .preview,
        next != .preview
      {
        return
      }
      model.send(.runtimeFocusChanged(next))
    }
    .onChange(of: model.state.focus) { _, next in
      runtimeFocus = next
    }
    .onKeyPress(perform: handleKeyPress)
  }

  private var browserHeader: some View {
    HStack(spacing: 1) {
      Text("SEXTANT")
        .foregroundStyle(accentStyle)
      Text("·")
        .foregroundStyle(.separator)
      Text(breadcrumb)
        .foregroundStyle(mutedStyle)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
    }
  }

  private var breadcrumb: String {
    model.state.trail.map { node in
      let name = node.url.lastPathComponent
      return name.isEmpty ? node.url.path : name
    }.joined(separator: " / ")
  }

  @ViewBuilder
  private func responsiveSurfaces(width: Int) -> some View {
    let decision = BrowserLayoutPolicy().decision(
      width: width,
      trailCount: model.state.trail.count,
      activeIndex: model.state.activeDirectoryIndex ?? 0,
      hasPreview: model.state.preview.item != nil,
      previewFocused: model.state.focus == .preview
    )
    let visibleDirectoryIDs = decision.visibleDirectoryIndices.compactMap {
      model.state.trail.indices.contains($0)
        ? model.state.trail[$0].id
        : nil
    }
    MillerLayout {
      ForEach(decision.visibleDirectoryIndices, id: \.self) { index in
        if model.state.trail.indices.contains(index) {
          let directory = model.state.trail[index]
          directoryColumn(directory)
            .border(mutedStyle, set: BorderSet.single, sides: Edge.Set.trailing)
            .focusable(directory.id == model.state.activeDirectoryID)
            .focused($runtimeFocus, equals: .browser(directory.id))
        }
      }
      if decision.showsPreview {
        previewPane
      }
    }
    .onChange(of: visibleDirectoryIDs, initial: true) { _, directoryIDs in
      model.send(.setVisibleDirectoryWindow(directoryIDs))
    }
  }

  @ViewBuilder
  private func directoryColumn(_ directory: BrowserTrailNode) -> some View {
    switch directory.directory {
    case .notRequested, .loading:
      FileColumn(
        directory: directory.url,
        entries: [],
        selection: nil,
        isActive: directory.id == model.state.activeDirectoryID,
        isLoading: true
      )
    case .loaded(let snapshot), .empty(let snapshot):
      fileColumn(directory, snapshot: snapshot)
    case .stale(let snapshot, let refresh):
      VStack(alignment: .leading, spacing: 0) {
        fileColumn(directory, snapshot: snapshot)
        Text(refreshLabel(refresh))
          .foregroundStyle(mutedStyle)
          .lineLimit(1)
      }
    case .failed(let failure):
      VStack(alignment: .leading, spacing: 0) {
        directoryTitle(directory)
        Divider()
        Text(failure.description)
          .foregroundStyle(mutedStyle)
          .lineLimit(3)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func fileColumn(
    _ directory: BrowserTrailNode,
    snapshot: DirectorySnapshot
  ) -> some View {
    let entries = visibleItems(directory: directory, snapshot: snapshot)
    return FileColumn(
      directory: directory.url,
      entries: entries,
      selection: directory.selectedItemID,
      isActive: directory.id == model.state.activeDirectoryID,
      emptyLabel:
        directory.id == model.state.activeDirectoryID
        && !model.state.filter.query.isEmpty
        ? "(no matches)"
        : "(empty)",
      onSelect: { itemID in
        model.send(.selectItem(directoryID: directory.id, itemID: itemID))
      }
    )
  }

  private func visibleItems(
    directory: BrowserTrailNode,
    snapshot: DirectorySnapshot
  ) -> [BrowserItem] {
    guard directory.id == model.state.activeDirectoryID else {
      return snapshot.items
    }
    let query = model.state.filter.query
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !query.isEmpty else {
      return snapshot.items
    }
    return snapshot.items.filter { $0.name.lowercased().contains(query) }
  }

  private func directoryTitle(_ directory: BrowserTrailNode) -> some View {
    Text(
      directory.url.lastPathComponent.isEmpty
        ? directory.url.path
        : directory.url.lastPathComponent
    )
    .foregroundStyle(
      directory.id == model.state.activeDirectoryID
        ? accentStyle
        : mutedStyle
    )
    .lineLimit(1)
    .truncationMode(.middle)
  }

  private var statusBar: some View {
    HStack(spacing: 1) {
      Text(model.state.activeDirectory?.url.path ?? model.state.root.path)
        .foregroundStyle(.separator)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text(statusText)
        .foregroundStyle(mutedStyle)
        .lineLimit(1)
      if !model.state.hasSeenHelp {
        Text("? help  / filter  Tab preview")
          .foregroundStyle(.separator)
          .lineLimit(1)
      }
    }
    .background(.black.opacity(0.1))
  }

  private var statusText: String {
    switch model.state.status {
    case .none:
      switch model.state.focus {
      case .preview:
        "PREVIEW"
      default:
        "BROWSER"
      }
    case .message(let message), .failure(let message):
      message
    }
  }

  @ViewBuilder
  private var overlayPanel: some View {
    switch model.state.overlay {
    case .none:
      EmptyView()
    case .filter:
      VStack(alignment: .leading, spacing: 0) {
        Text("FILTER")
          .foregroundStyle(accentStyle)
        TextField("Type to filter this directory…", text: $filterText)
          .focused($runtimeFocus, equals: .filter)
          .onChange(of: filterText) { _, query in
            model.send(.setFilter(query))
          }
          .onKeyPress { keyPress in
            if keyPress == KeyPress(.escape) {
              model.send(.dismissOverlay)
              return .handled
            }
            if keyPress == KeyPress(.return) {
              model.send(.dismissOverlay)
              return .handled
            }
            return .ignored
          }
      }
      .padding(.horizontal, 1)
      .border(mutedStyle, set: .rounded)
    case .help:
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("HELP")
            .foregroundStyle(accentStyle)
          Spacer()
          Text("Escape closes")
            .foregroundStyle(.separator)
        }
        ForEach(commandCatalog.commands, id: \.id) { command in
          HStack(spacing: 1) {
            Text(command.defaultChord)
              .foregroundStyle(mutedStyle)
              .frame(width: 20, alignment: .leading)
            Text(command.title)
          }
        }
      }
      .padding(.horizontal, 1)
      .border(mutedStyle, set: .rounded)
      .focusable(true)
      .focused($runtimeFocus, equals: .help)
    case .palette:
      VStack(alignment: .leading, spacing: 0) {
        Text("COMMAND PALETTE")
          .foregroundStyle(accentStyle)
        TextField("Filter commands…", text: $paletteQuery)
          .focused($runtimeFocus, equals: .palette)
          .onKeyPress { keyPress in
            if keyPress == KeyPress(.escape) {
              model.send(.dismissOverlay)
              return .handled
            }
            if keyPress == KeyPress(.return) {
              if let command = paletteCommands.first {
                perform(command)
              }
              return .handled
            }
            return .ignored
          }
        ForEach(Array(paletteCommands.prefix(10)), id: \.id) { command in
          let availability = command.availability(commandContext)
          Button {
            perform(command)
          } label: {
            HStack(spacing: 1) {
              Text(command.title)
              Spacer()
              Text(
                availability.disabledReason
                  ?? command.defaultChord
              )
              .foregroundStyle(.separator)
            }
          }
          .buttonStyle(.plain)
          .disabled(!availability.isEnabled)
        }
      }
      .padding(.horizontal, 1)
      .border(mutedStyle, set: .rounded)
    case .search:
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("SEARCH")
            .foregroundStyle(accentStyle)
          Spacer()
          Text(
            model.state.search.isSearching
              ? "searching…"
              : "\(model.state.search.results.count) results"
          )
          .foregroundStyle(.separator)
        }
        TextField(
          "Filename query or /absolute/path…",
          text: $searchQuery
        )
        .focused($runtimeFocus, equals: .palette)
        .onChange(of: searchQuery) { _, query in
          model.send(.setSearchQuery(query))
        }
        .onKeyPress { keyPress in
          if keyPress == KeyPress(.escape) {
            model.send(.dismissOverlay)
            return .handled
          }
          if keyPress == KeyPress(.return) {
            if isPathQuery(searchQuery) {
              model.send(.jumpToPath(searchQuery))
            } else {
              model.send(.activateSearchResult(0))
            }
            return .handled
          }
          return .ignored
        }
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          pathHistorySection("BOOKMARKS", paths: model.state.bookmarks)
          pathHistorySection("RECENTS", paths: model.state.recents)
        }
        ForEach(
          Array(model.state.search.results.prefix(10).enumerated()),
          id: \.element.id
        ) { index, result in
          Button {
            model.send(.activateSearchResult(index))
          } label: {
            HStack(spacing: 1) {
              Text(result.kind.isDirectoryLike ? "▸" : " ")
                .foregroundStyle(mutedStyle)
              Text(result.url.path)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
          .buttonStyle(.plain)
        }
        if model.state.search.wasTruncated {
          Text("Result limit reached; refine the query.")
            .foregroundStyle(.separator)
        }
      }
      .padding(.horizontal, 1)
      .border(mutedStyle, set: .rounded)
    }
  }

  @ViewBuilder
  private func pathHistorySection(_ title: String, paths: [String]) -> some View {
    if !paths.isEmpty {
      Text(title)
        .foregroundStyle(mutedStyle)
      ForEach(paths, id: \.self) { path in
        Button {
          model.send(.jumpToPath(path))
        } label: {
          Text(path)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var paletteCommands: [CommandDefinition] {
    let query =
      paletteQuery
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !query.isEmpty else {
      return commandCatalog.commands
    }
    return commandCatalog.commands.filter {
      $0.title.lowercased().contains(query)
        || $0.id.rawValue.lowercased().contains(query)
    }
  }

  @ViewBuilder
  private var previewPane: some View {
    if previewUsesHostFocusTarget {
      previewPaneContent
        .focusable(true)
        .focused($runtimeFocus, equals: .preview)
        .onKeyPress(.escape) { _ in
          model.send(.focusBrowser)
          return .handled
        }
    } else {
      previewPaneContent
    }
  }

  private var previewPaneContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(model.state.preview.item?.name ?? "Preview")
        .foregroundStyle(
          model.state.focus == .preview
            ? accentStyle
            : mutedStyle
        )
        .lineLimit(1)
        .truncationMode(.middle)
      Divider()
      previewBody
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var previewBody: some View {
    switch model.state.preview {
    case .welcome:
      Text("Select an item to preview.")
        .foregroundStyle(.separator)
    case .loading:
      Text("Loading preview…")
        .foregroundStyle(.separator)
    case .builtIn(_, _, let preview):
      builtInPreview(preview)
    case .external(let preview):
      VStack(alignment: .leading, spacing: 0) {
        Text("\(preview.adapterName) · \(externalStatusLabel(preview.status))")
          .foregroundStyle(mutedStyle)
        TerminalView(
          session: preview.handle.terminal,
          keyRouting: routePreviewKey
        )
        .hostFocused($runtimeFocus, equals: .preview)
        .focusable(model.state.focus == .preview)
        .onAppear {
          runtimeFocus = model.state.focus
        }
      }
    case .unavailable(_, _, let reason):
      Text(unavailableLabel(reason))
        .foregroundStyle(mutedStyle)
    case .failed(_, _, let adapter, let failure, let fallback):
      VStack(alignment: .leading, spacing: 0) {
        if let adapter {
          Text(adapter)
            .foregroundStyle(mutedStyle)
        }
        Text(failureLabel(failure))
          .foregroundStyle(mutedStyle)
        if let fallback {
          Button {
            model.send(.activatePreviewFallback)
          } label: {
            Text("Use built-in preview")
          }
          .buttonStyle(.plain)
          Divider()
          builtInPreview(fallback)
        }
      }
    }
  }

  @ViewBuilder
  private func builtInPreview(_ preview: BuiltInPreview) -> some View {
    Text(preview.adapterName)
      .foregroundStyle(mutedStyle)
    Text(BuiltInPreviewPresentation.metadataLine(preview.metadata))
      .foregroundStyle(.separator)
      .lineLimit(1)
      .truncationMode(.middle)
    Text(preview.metadata.path)
      .foregroundStyle(.separator)
      .lineLimit(1)
      .truncationMode(.middle)
    if let indicator = BuiltInPreviewPresentation.indicator(preview.body) {
      Text(indicator)
        .foregroundStyle(mutedStyle)
    }
    switch preview.body {
    case .text(let text):
      Text(text.text)
    case .hexadecimal(let hex):
      Text(hex.formatted)
    case .directorySummary(let summary):
      Text(
        "\(summary.itemCount) items · \(summary.directoryCount) directories · "
          + "\(summary.fileCount) files"
      )
    case .metadataOnly:
      EmptyView()
    case .unavailable(let reason):
      Text(unavailableLabel(reason))
        .foregroundStyle(mutedStyle)
    case .failed(let failure):
      Text(failureLabel(failure))
        .foregroundStyle(mutedStyle)
    }
  }

  private func handleKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    if model.state.overlay != .none {
      if keyPress == KeyPress(.escape) {
        model.send(.dismissOverlay)
        return .handled
      }
      return .ignored
    }
    guard model.state.focus != .preview else {
      return .ignored
    }
    guard
      let (command, availability) = commandCatalog.command(
        for: keyPress,
        context: commandContext
      )
    else {
      return .ignored
    }
    guard availability.isEnabled else {
      model.send(
        .reportStatus(
          .failure(availability.disabledReason ?? "Command unavailable.")
        )
      )
      return .handled
    }
    if command.dispatchOwnership == .applicationRuntime {
      // The scene owns process exit so it can run the normal shutdown path.
      return .ignored
    }
    perform(command)
    return .handled
  }

  private var commandContext: CommandContext {
    CommandContext(
      hasSelection: model.state.selectedItem != nil,
      hasPreview: model.state.preview.item != nil,
      previewFocused: model.state.focus == .preview,
      hasRootRelativeSelection: rootRelativeSelectionPath != nil
    )
  }

  private func perform(_ command: CommandDefinition) {
    switch command.action {
    case .moveUp:
      model.send(.moveSelection(.offset(-1)))
    case .moveDown:
      model.send(.moveSelection(.offset(1)))
    case .moveParent:
      model.send(.moveToParent)
    case .enter:
      model.send(.enterSelected)
    case .first:
      model.send(.moveSelection(.first))
    case .last:
      model.send(.moveSelection(.last))
    case .pageUp:
      model.send(.moveSelection(.offset(-10)))
    case .pageDown:
      model.send(.moveSelection(.offset(10)))
    case .toggleSurface:
      if model.state.focus == .preview {
        model.send(.focusBrowser)
      } else {
        model.send(.focusPreview)
      }
    case .focusBrowser:
      model.send(.focusBrowser)
    case .filter:
      filterText = model.state.filter.query
      model.send(.showFilter)
    case .toggleHidden:
      model.send(.setHidden(!model.state.policy.showsHiddenFiles))
    case .refresh:
      model.send(.refresh)
    case .help:
      model.send(.showHelp)
    case .palette:
      paletteQuery = ""
      model.send(.showPalette)
    case .search:
      searchQuery = ""
      model.send(.showSearch)
    case .bookmark:
      model.send(.toggleBookmark)
    case .open, .edit, .reveal, .copyAbsolutePath, .copyRelativePath:
      performHandoff(command.action)
    case .quit:
      break
    }
  }

  private func performHandoff(_ action: SextantCommandAction) {
    let command: BrowserHandoffCommand? =
      switch action {
      case .open:
        .open
      case .edit:
        .edit
      case .reveal:
        .reveal
      case .copyAbsolutePath:
        .copyAbsolutePath
      case .copyRelativePath:
        .copyRelativePath
      default:
        nil
      }
    guard let command else {
      return
    }
    model.send(.performHandoff(command))
  }

  private var rootRelativeSelectionPath: String? {
    guard let selected = model.state.selectedItem?.url.standardizedFileURL.path else {
      return nil
    }
    let root = model.state.root.standardizedFileURL.path
    if selected == root {
      return "."
    }
    let prefix = root.hasSuffix("/") ? root : root + "/"
    guard selected.hasPrefix(prefix) else {
      return nil
    }
    return String(selected.dropFirst(prefix.count))
  }

  private func isPathQuery(_ query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.hasPrefix("/")
      || query.hasPrefix(".")
      || query.hasPrefix("~")
  }

  private func routePreviewKey(_ keyPress: KeyPress) -> TerminalViewKeyDisposition {
    guard keyPress == KeyPress(.escape) else {
      return .forwardToChild
    }
    model.send(.focusBrowser)
    return .handledByHost
  }

  private func refreshLabel(_ refresh: DirectoryRefreshState) -> String {
    switch refresh {
    case .loading:
      "(refreshing)"
    case .failed(let failure):
      "(stale: \(failure.description))"
    }
  }

  private func externalStatusLabel(_ status: ExternalPreviewStatus) -> String {
    switch status {
    case .starting:
      "starting"
    case .ready:
      "ready"
    case .slow:
      "waiting for output"
    case .exited(let reason):
      switch reason {
      case .normal(let code):
        "exited \(code)"
      case .signal(let signal):
        "signal \(signal)"
      case .sessionClosed:
        "closed"
      }
    }
  }

  private func unavailableLabel(_ reason: PreviewUnavailableReason) -> String {
    switch reason {
    case .specialFile:
      "Preview unavailable for special files."
    case .previewDisabled:
      "Preview is disabled."
    case .unsupported(let message):
      message
    }
  }

  private func failureLabel(_ failure: PreviewFailure) -> String {
    PreviewFailurePresentation.label(failure)
  }

  private var previewUsesHostFocusTarget: Bool {
    previewFocusTargetKind == .host
  }

  private var previewFocusTargetKind: PreviewFocusTargetKind {
    PreviewFocusPolicy.targetKind(model.state.preview)
  }

  private func beginPreviewFocusHandoffIfNeeded(
    from previous: PreviewFocusTargetKind,
    to next: PreviewFocusTargetKind
  ) {
    guard
      PreviewFocusHandoffPolicy.shouldPreserveSemanticFocus(
        from: previous,
        to: next,
        semanticFocus: model.state.focus
      )
    else {
      return
    }

    isPreviewFocusHandoffActive = true
    runtimeFocus = .preview
    Task { @MainActor in
      for _ in 0..<3 {
        await Task.yield()
        guard model.state.focus == .preview,
          previewFocusTargetKind == .terminal
        else {
          isPreviewFocusHandoffActive = false
          return
        }
        runtimeFocus = .preview
      }
      isPreviewFocusHandoffActive = false
    }
  }

  private var accentStyle: AnyShapeStyle {
    configuration.colors.accentColor.map(AnyShapeStyle.init)
      ?? AnyShapeStyle(SemanticShapeStyle(.tint))
  }

  private var mutedStyle: AnyShapeStyle {
    configuration.colors.mutedColor.map(AnyShapeStyle.init)
      ?? AnyShapeStyle(SemanticShapeStyle(.muted))
  }
}

struct PreviewFailurePresentation {
  static func label(_ failure: PreviewFailure) -> String {
    switch failure {
    case .permissionDenied:
      "Permission denied."
    case .missing:
      "The selected item no longer exists."
    case .missingExecutable(let executable):
      "External preview executable not found: \(executable)"
    case .externalExit(let status):
      "External preview exited with status \(status)."
    case .externalSignal(let signal):
      "External preview terminated by signal \(signal)."
    case .unreadable(let message):
      message
    }
  }
}

struct BuiltInPreviewPresentation {
  static func metadataLine(_ metadata: PreviewMetadata) -> String {
    var components = [metadata.kind]
    if let size = metadata.size {
      components.append("\(size) bytes")
    }
    if let modificationDate = metadata.modificationDate {
      components.append("modified \(modificationDate.formatted(.iso8601))")
    }
    return components.joined(separator: " · ")
  }

  static func indicator(_ body: BuiltInPreviewBody) -> String? {
    switch body {
    case .text(let preview):
      preview.encoding.rawValue
        + (preview.isTruncated ? " · truncated to 256 KiB" : "")
    case .hexadecimal(let preview):
      "\(preview.renderedByteCount) bytes shown"
        + (preview.isTruncated ? " · truncated" : "")
    case .directorySummary(let summary):
      "\(summary.totalKnownBytes) known bytes · \(summary.specialCount) special"
        + (summary.isTruncated ? " · truncated" : "")
    case .metadataOnly, .unavailable, .failed:
      nil
    }
  }
}

enum PreviewFocusTargetKind: Equatable {
  case none
  case host
  case terminal
}

struct PreviewFocusPolicy {
  static func targetKind(_ preview: PreviewState) -> PreviewFocusTargetKind {
    switch preview {
    case .loading, .builtIn, .unavailable, .failed:
      .host
    case .external:
      .terminal
    case .welcome:
      .none
    }
  }

  static func usesHostFocusTarget(_ preview: PreviewState) -> Bool {
    targetKind(preview) == .host
  }
}

struct PreviewFocusHandoffPolicy {
  static func shouldPreserveSemanticFocus(
    from previous: PreviewFocusTargetKind,
    to next: PreviewFocusTargetKind,
    semanticFocus: BrowserFocus
  ) -> Bool {
    semanticFocus == .preview
      && previous == .host
      && next == .terminal
  }
}
