import Foundation
import SwiftTUI
import SwiftTUITerminal

struct ColumnBrowser: View {
  @Bindable var model: BrowserModel
  @Environment(\.terminalSize) private var terminalSize
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
      // `responsiveSurfaces` only needs the width, and a `GeometryReader`
      // silently falls back to a 10x10 ideal whenever its height proposal is
      // not finite — which capped the whole browser at ten rows regardless of
      // terminal height. Reading the width from the environment removes that
      // seam; the explicit flexible frame is what marks this region unbounded
      // to the stack allocator, so it absorbs everything the header and status
      // bar leave behind.
      responsiveSurfaces(width: terminalSize.width)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Clip, because an open overlay squeezes this region to a couple of
        // rows and the column content is taller than what it is handed. Without
        // this the preview's metadata lines paint straight over the status bar
        // — visibly, `/tmp/…/demo-v0.1` followed by the tail of
        // `File · 5100 bytes · modified …` on the same row.
        .clipped()
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
      // U+2222 SPHERICAL ANGLE: an angle plus its measuring arc, which is what
      // a sextant reads. Padding widens the `Text` before the fill so the chip
      // is not glyph-tight.
      Text("∢")
        .foregroundStyle(onAccentStyle)
        .padding(.horizontal, 1)
        .background { Rectangle().fill(accentStyle) }
      Text("·")
        .foregroundStyle(.separator)
      Text(breadcrumb)
        .foregroundStyle(mutedStyle)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
    }
    // A `Spacer` makes its stack flexible on *both* axes, so without this the
    // header competes with the browser for leftover vertical space and the
    // three bands split the terminal between them instead of the columns
    // taking everything the fixed chrome leaves. Same for `statusBar`.
    .fixedSize(horizontal: false, vertical: true)
  }

  /// The entered part of the trail.
  ///
  /// The model keeps a prefetched node for the selected directory past the
  /// active column; that node is not somewhere the user has navigated to, so
  /// it must not appear in the path.
  private var breadcrumb: String {
    let enteredCount = (model.state.activeDirectoryIndex ?? 0) + 1
    return model.state.trail.prefix(enteredCount).map { node in
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
    // The same static width math `MillerLayout` will use when it places these
    // columns, so `FileColumn` can size its accent bars without a
    // `GeometryReader`. The trailing rule is an outset border, so it takes a
    // cell out of the column's own content box.
    let columnWidths = MillerLayout.columnWidths(
      totalWidth: width,
      columnCount: decision.visibleDirectoryIndices.count
        + (decision.showsPreview ? 1 : 0)
    )
    MillerLayout {
      ForEach(
        Array(decision.visibleDirectoryIndices.enumerated()),
        id: \.element
      ) { position, index in
        if model.state.trail.indices.contains(index) {
          let directory = model.state.trail[index]
          directoryColumn(
            directory,
            contentWidth: max(
              0,
              (columnWidths.indices.contains(position) ? columnWidths[position] : 0)
                - MillerLayout.separatorWidth
            )
          )
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
  private func directoryColumn(
    _ directory: BrowserTrailNode,
    contentWidth: Int
  ) -> some View {
    switch directory.directory {
    case .notRequested, .loading:
      FileColumn(
        directory: directory.url,
        entries: [],
        selection: nil,
        isActive: directory.id == model.state.activeDirectoryID,
        isLoading: true,
        accentStyle: accentStyle,
        mutedStyle: mutedStyle,
        contentWidth: contentWidth
      )
    case .loaded(let snapshot), .empty(let snapshot):
      fileColumn(directory, snapshot: snapshot, contentWidth: contentWidth)
    case .stale(let snapshot, let refresh):
      VStack(alignment: .leading, spacing: 0) {
        fileColumn(directory, snapshot: snapshot, contentWidth: contentWidth)
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
    snapshot: DirectorySnapshot,
    contentWidth: Int
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
      accentStyle: accentStyle,
      mutedStyle: mutedStyle,
      contentWidth: contentWidth,
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
      filterSlot
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
    .fixedSize(horizontal: false, vertical: true)
    .background(.black.opacity(0.1))
  }

  /// The leading half of the status bar: the active path, the filter field
  /// while it is open, or a `/query` reminder once it has been dismissed with
  /// a query still applied. The filter has no presence above the browser — this
  /// is the only place it appears.
  @ViewBuilder
  private var filterSlot: some View {
    if model.state.overlay == .filter {
      Text("/")
        .foregroundStyle(accentStyle)
      // `.plain` matters: the default rounded-border style is a padded,
      // bordered, three-row control and would tear the one-row bar apart.
      TextField("filter this directory…", text: $filterText)
        .textFieldStyle(.plain)
        .focused($runtimeFocus, equals: .filter)
        .onChange(of: filterText) { _, query in
          model.send(.setFilter(query))
        }
        .onKeyPress { keyPress in
          if keyPress == KeyPress(.escape) || keyPress == KeyPress(.return) {
            model.send(.dismissOverlay)
            return .handled
          }
          return .ignored
        }
    } else if !model.state.filter.query.isEmpty {
      Text("/\(model.state.filter.query)")
        .foregroundStyle(accentStyle)
        .lineLimit(1)
        .truncationMode(.middle)
    } else {
      Text(model.state.activeDirectory?.url.path ?? model.state.root.path)
        .foregroundStyle(.separator)
        .lineLimit(1)
        .truncationMode(.middle)
    }
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
      // The filter lives entirely in the status bar; nothing is drawn above
      // the browser for it.
      EmptyView()
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
      if !summary.entryNames.isEmpty {
        Divider()
        ForEach(summary.entryNames, id: \.self) { name in
          Text(name)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        if summary.hiddenEntryCount > 0 {
          Text("… and \(summary.hiddenEntryCount) more")
            .foregroundStyle(.separator)
        }
      }
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
    switch commandCatalog.dispatch(keyPress, context: commandContext) {
    case .perform(let action):
      send(action)
      return .handled
    case .unavailable(let reason):
      model.send(.reportStatus(.failure(reason)))
      return .handled
    case .runtimeOwned, nil:
      return .ignored
    }
  }

  private var commandContext: CommandContext {
    CommandContext(
      hasSelection: model.state.selectedItem != nil,
      hasPreview: model.state.preview.item != nil,
      previewFocused: model.state.focus == .preview,
      hasRootRelativeSelection: rootRelativeSelectionPath != nil,
      showsHiddenFiles: model.state.policy.showsHiddenFiles,
      isOverlayPresented: model.state.overlay != .none
    )
  }

  /// Sends a resolved action, seeding any text field the overlay it opens will
  /// bind to. The seed is the only part of a command's effect the view owns.
  private func send(_ action: BrowserAction) {
    switch action {
    case .showFilter:
      filterText = model.state.filter.query
    case .showPalette:
      paletteQuery = ""
    case .showSearch:
      searchQuery = ""
    default:
      break
    }
    model.send(action)
  }

  /// Invokes a command chosen by name rather than by key — the palette rows.
  /// Key eligibility does not apply here; the palette is itself an overlay.
  private func perform(_ command: CommandDefinition) {
    guard command.dispatchOwnership == .browser,
      let action = command.action.browserAction(in: commandContext)
    else {
      return
    }
    send(action)
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
    // The embedded child sees every key the catalog does not claim. Because
    // the context reports the preview as focused, dispatch already restricts
    // itself to the preview section.
    guard
      case .perform(let action)? =
        commandCatalog.dispatch(keyPress, context: commandContext)
    else {
      return .forwardToChild
    }
    send(action)
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

  /// Text drawn on top of ``accentStyle``.
  private var onAccentStyle: AnyShapeStyle {
    AnyShapeStyle(SemanticShapeStyle(.background))
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
