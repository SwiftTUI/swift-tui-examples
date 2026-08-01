public import SwiftTUI

/// Holds the latest `ScrollViewProxy` published by the document pane's
/// `ScrollViewReader`, so the root key handler can issue scroll commands
/// without living *inside* the reader scope. The reader now wraps only
/// `MarkdownDocumentView`: its proxy bridge invalidates the whole reader
/// content on every programmatic scroll, and wrapping the root ZStack made
/// each `j`/`k` keypress repaint the entire app (scroll-latency Stage 1).
/// Routing key commands through observed state instead would add a frame of
/// latency per keypress — the box keeps the direct dispatch path.
@MainActor
private final class ScrollProxyBox {
  var proxy: ScrollViewProxy?

  func adopt(_ proxy: ScrollViewProxy) {
    self.proxy = proxy
  }
}

public struct MrkdwnRootView: View {
  private let model: ViewerModel
  @FocusState private var focusedMermaidID: BlockID?
  @State private var proxyBox = ScrollProxyBox()

  public init(model: ViewerModel) {
    self.model = model
  }

  public var body: some View {
    GeometryReader { geometry in
      let viewport = ViewerSize(
        width: geometry.size.width,
        height: geometry.size.height
      )
      ZStack {
        viewer
        if model.state.outlineVisible, viewport.width < 120 {
          overlayCard(title: "Table of contents") {
            OutlineView(model: model)
          }
        }
        if model.state.searchVisible {
          searchOverlay
        }
        if model.state.helpVisible {
          helpOverlay
        }
      }
      .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .topLeading
      )
      .foregroundStyle(model.state.theme.foreground.swiftTUIColor)
      .background(model.state.theme.background.swiftTUIColor)
      .openLinkAction(
        OpenLinkAction { destination in
          model.send(.openDestination(destination.rawValue))
          return true
        }
      )
      .focusable(true)
      .onKeyPress(.any) { keyPress in
        handle(keyPress)
      }
      .task(id: viewport) { @MainActor in
        model.updateViewport(viewport)
      }
    }
    .task { @MainActor in
      await model.start()
    }
    .task(id: model.state.contentRevision) { @MainActor in
      focusedMermaidID = nil
    }
    .panel(id: "mrkdwn")
    .keyCommand(
      "Reveal next Mermaid source",
      key: .character("m"),
      modifiers: .alt,
      isEnabled: !model.state.searchVisible
    ) {
      model.send(.revealNextMermaidSource)
    }
  }

  public func shutdown() async {
    await model.shutdown()
  }

  @ViewBuilder
  private var viewer: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.state.viewport.width < 80 {
        compactHeader
      } else {
        regularHeader
      }
      Divider()
      HStack(alignment: .top, spacing: 2) {
        if model.state.viewport.width >= 120, model.state.outlineVisible {
          OutlineView(model: model)
            .frame(width: 28, alignment: .topLeading)
          Divider()
        }
        Spacer(minLength: 0)
        ScrollViewReader { proxy in
          let _ = proxyBox.adopt(proxy)
          MarkdownDocumentView(
            model: model,
            focusedMermaidID: $focusedMermaidID
          )
          .frame(
            maxWidth: .finite(model.state.viewport.documentFrameWidth),
            alignment: .topLeading
          )
          // A fixed pane height, not `maxHeight: .infinity`: the enclosing
          // VStack's ideal pass measures a flexible pane at an unspecified
          // height, and the scroll layout declares no measure viewport for an
          // unknown axis — the document then realizes and measures every
          // block on every frame instead of the visible window. The model
          // already knows the pane height (the viewport minus the 4 chrome
          // rows), so a fixed frame keeps every proposal the scroll view
          // sees finite and the document windowed.
          .frame(height: model.state.viewport.documentHeight)
          .task(id: model.pendingScrollTarget) { @MainActor in
            guard let target = model.pendingScrollTarget else { return }
            _ = proxy.scrollTo(target, anchor: .top)
            model.send(.clearScrollTarget)
          }
        }
        Spacer(minLength: 0)
      }
      Divider()
      StatusView(state: model.state)
    }
  }

  private var regularHeader: some View {
    HStack(spacing: 2) {
      Text("mrkdwn").bold()
        .foregroundStyle(model.state.theme.accent.swiftTUIColor)
      Text(model.state.snapshot.displayName)
      Spacer(minLength: 1)
      Text("/ search · t outline · ? help")
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }

  private var compactHeader: some View {
    HStack(spacing: 1) {
      Text("mrkdwn").bold()
        .foregroundStyle(model.state.theme.accent.swiftTUIColor)
      Text(model.state.snapshot.displayName)
        .lineLimit(1)
      Spacer(minLength: 0)
      Text("?")
        .foregroundStyle(model.state.theme.muted.swiftTUIColor)
    }
  }

  private var searchOverlay: some View {
    overlayCard(title: "Search") {
      VStack(alignment: .leading, spacing: 1) {
        Text("/\(model.state.searchQuery)▏")
          .foregroundStyle(model.state.theme.searchMatch.swiftTUIColor)
        Text(searchSummary)
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
        Text("Type to search · Enter/Escape close · n/N move")
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
      }
    }
  }

  private var searchSummary: String {
    if model.state.isSearching { return "Searching…" }
    guard !model.state.searchMatches.isEmpty else {
      return model.state.searchResultsTruncated
        ? "No retained matches · search capped"
        : "No matches"
    }
    let selected = (model.state.selectedSearchMatch ?? 0) + 1
    let suffix = model.state.searchResultsTruncated ? "+ matches · capped" : " matches"
    return "\(selected) of \(model.state.searchMatches.count)\(suffix)"
  }

  private var helpOverlay: some View {
    overlayCard(title: "Keyboard reference") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(CommandCatalog.entries.enumerated()), id: \.offset) { _, entry in
          HStack(spacing: 2) {
            Text(entry.keys)
              .foregroundStyle(model.state.theme.accent.swiftTUIColor)
              .frame(width: 22, alignment: .leading)
            Text(entry.title)
          }
        }
        Text("Press ? or Escape to close")
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
      }
    }
  }

  private func overlayCard<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 1) {
        Text(title).bold()
        Spacer(minLength: 0)
        Text("Esc")
          .foregroundStyle(model.state.theme.muted.swiftTUIColor)
      }
      Divider()
      content()
    }
    .padding(1)
    .frame(
      maxWidth: .finite(min(72, max(20, model.state.viewport.width - 4))),
      maxHeight: .finite(max(8, model.state.viewport.height - 4)),
      alignment: .topLeading
    )
    .background(model.state.theme.background.swiftTUIColor)
    .border(model.state.theme.tableBorder.swiftTUIColor)
  }

  private func handle(_ keyPress: KeyPress) -> KeyPressResult {
    if CommandCatalog.runtimeExitKeys.contains(keyPress),
      !model.state.searchVisible
    {
      return .ignored
    }
    if model.state.helpVisible {
      if keyPress.key == .escape || keyPress == KeyPress(.character("?")) {
        model.send(.toggleHelp)
      }
      return .handled
    }
    if model.state.searchVisible {
      return handleSearch(keyPress)
    }
    if CommandCatalog.runtimeExitKeys.contains(keyPress) {
      return .ignored
    }

    let page = model.state.viewport.documentHeight
    switch keyPress {
    case KeyPress(.character("j")), KeyPress(.arrowDown):
      _ = proxyBox.proxy?.scrollBy(y: 1)
    case KeyPress(.character("k")), KeyPress(.arrowUp):
      _ = proxyBox.proxy?.scrollBy(y: -1)
    case KeyPress(.pageDown), KeyPress(.space):
      _ = proxyBox.proxy?.scrollBy(y: page)
    case KeyPress(.pageUp), KeyPress(.space, modifiers: .shift):
      _ = proxyBox.proxy?.scrollBy(y: -page)
    case KeyPress(.character("g")), KeyPress(.home):
      _ = proxyBox.proxy?.scrollTo(edge: .top)
    case KeyPress(.character("G")), KeyPress(.character("g"), modifiers: .shift),
      KeyPress(.end):
      _ = proxyBox.proxy?.scrollTo(edge: .bottom)
    case KeyPress(.character("]")):
      model.send(.nextHeading)
    case KeyPress(.character("[")):
      model.send(.previousHeading)
    case KeyPress(.character("t")):
      model.send(.toggleOutline)
    case KeyPress(.character("/")):
      model.send(.beginSearch)
    case KeyPress(.character("n")):
      model.send(.nextMatch)
    case KeyPress(.character("N")), KeyPress(.character("n"), modifiers: .shift):
      model.send(.previousMatch)
    case KeyPress(.character("b")):
      model.send(.goBack)
    case KeyPress(.character("f")):
      model.send(.goForward)
    case KeyPress(.character("r")):
      model.send(.reload)
    case KeyPress(.character("m")):
      if let id = focusedMermaidID ?? firstMermaidBlockID {
        model.send(.toggleMermaidSource(id))
      }
    case KeyPress(.character("M")), KeyPress(.character("m"), modifiers: .shift):
      model.send(.revealNextMermaidSource)
    case KeyPress(.character("?")):
      model.send(.toggleHelp)
    case KeyPress(.escape):
      if model.state.outlineVisible, model.state.viewport.width < 120 {
        model.send(.toggleOutline)
      } else if model.state.diagnostic != nil {
        model.send(.dismissError)
      } else {
        return .ignored
      }
    default:
      return .ignored
    }
    return .handled
  }

  private func handleSearch(_ keyPress: KeyPress) -> KeyPressResult {
    if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
      return .ignored
    }
    guard keyPress.modifiers.isEmpty || keyPress.modifiers == .shift else {
      return .handled
    }
    switch keyPress.key {
    case .escape, .return:
      model.send(.endSearch)
    case .backspace:
      model.send(.updateSearch(String(model.state.searchQuery.dropLast())))
    case .space:
      model.send(.updateSearch(model.state.searchQuery + " "))
    case .character(let character):
      let authored =
        keyPress.modifiers == .shift
        ? String(character).uppercased()
        : String(character)
      model.send(.updateSearch(model.state.searchQuery + authored))
    default:
      return .handled
    }
    return .handled
  }

  private var firstMermaidBlockID: BlockID? {
    mermaidBlockIDs.first
  }

  private var mermaidBlockIDs: [BlockID] {
    guard let document = model.state.document else { return [] }
    return MarkdownBlockLayout.flattened(
      document.blocks,
      offeredWidth: model.state.viewport.documentWidth
    ).compactMap {
      if case .mermaid(let id, _, _) = $0.block { return id }
      return nil
    }
  }
}

private struct MarkdownDocumentView: View {
  let model: ViewerModel
  var focusedMermaidID: FocusState<BlockID?>.Binding

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: true,
      position: Binding(
        get: {
          ScrollPosition(y: model.documentScrollOffset)
        },
        set: {
          model.updateDocumentScrollOffset($0.y)
        }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 1) {
        if let document = model.state.document {
          ForEach(document.blocks, id: \.id) {
            MarkdownBlockView(
              block: $0,
              state: model.state,
              offeredWidth: model.state.viewport.documentWidth,
              focusedMermaidID: focusedMermaidID,
              toggleMermaidSource: {
                model.send(.toggleMermaidSource($0))
              },
              documentGeometryTop: {
                model.documentGeometryTop(for: $0)
              },
              resourceVisibilityChanged: { id, isVisible in
                if isVisible {
                  model.resourceBecameVisible(id)
                } else {
                  model.resourceBecameHidden(id)
                }
              },
              // Read at leaf-body time, not here: the closures execute inside
              // the block views' bodies, so the observation dependency on the
              // split model properties lands on the leaf that needs it, not
              // on this ForEach.
              documentScrollOffset: { model.documentScrollOffset },
              mermaidPresentation: { model.mermaid[$0] },
              imagePresentation: { model.images[$0] },
              tableMetrics: { model.tableMetrics(for: $1, identity: $0) }
            )
          }
        } else {
          Text("Loading \(model.state.snapshot.displayName)…")
            .foregroundStyle(model.state.theme.muted.swiftTUIColor)
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
    }
  }
}

private struct OutlineView: View {
  let model: ViewerModel

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Contents").bold()
          .foregroundStyle(model.state.theme.accent.swiftTUIColor)
        if let outline = model.state.document?.outline, !outline.isEmpty {
          ForEach(outline, id: \.id) { entry in
            Button(action: {
              model.send(.scrollToHeading(entry.id))
              if model.state.viewport.width < 120 {
                model.send(.toggleOutline)
              }
            }) {
              Text(String(repeating: "  ", count: max(0, entry.level - 1)) + entry.title)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
          }
        } else {
          Text("No headings")
            .foregroundStyle(model.state.theme.muted.swiftTUIColor)
        }
      }
      .padding(1)
    }
  }
}

private struct StatusView: View {
  var state: ViewerState

  var body: some View {
    HStack(spacing: 1) {
      Text(state.isReloading ? "reloading" : "ready")
        .foregroundStyle(
          state.isReloading
            ? state.theme.accent.swiftTUIColor
            : state.theme.muted.swiftTUIColor
        )
      if state.canGoBack { Text("←") }
      if state.canGoForward { Text("→") }
      if let diagnostic = state.diagnostic {
        Text("· \(diagnostic.message)")
          .foregroundStyle(color(for: diagnostic.severity))
          .lineLimit(1)
      } else if !state.searchQuery.isEmpty {
        Text(searchStatus)
          .foregroundStyle(state.theme.muted.swiftTUIColor)
      }
      Spacer(minLength: 0)
      Text("q quit · ? help")
        .foregroundStyle(state.theme.muted.swiftTUIColor)
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .accessibilityRole(.status)
  }

  private var searchStatus: String {
    if state.isSearching { return "· searching" }
    let suffix = state.searchResultsTruncated ? "+" : ""
    return "· \(state.searchMatches.count)\(suffix) search matches"
  }

  private func color(for severity: ViewerDiagnostic.Severity) -> Color {
    switch severity {
    case .information: state.theme.muted.swiftTUIColor
    case .warning: state.theme.searchMatch.swiftTUIColor
    case .error: state.theme.error.swiftTUIColor
    }
  }
}
