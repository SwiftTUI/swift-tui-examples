import Foundation
import SwiftTUI
import Synchronization
import Testing

@testable import Mrkdwn

private enum StubFailure: Error {
  case unavailable
}

private actor MermaidRequestRecorder {
  private(set) var requests: [MermaidRenderRequest] = []

  func record(_ request: MermaidRenderRequest) {
    requests.append(request)
  }
}

private actor ImageRequestRecorder {
  private(set) var sources: [String] = []

  func record(_ source: String) {
    sources.append(source)
  }
}

private actor ResourceLifecycleProbe {
  private(set) var activeMermaid = 0
  private(set) var activeImages = 0
  private(set) var maximumMermaid = 0
  private(set) var maximumImages = 0
  private(set) var cancelledMermaid = 0
  private(set) var cancelledImages = 0

  func activeCounts() -> (mermaid: Int, images: Int) {
    (activeMermaid, activeImages)
  }

  func unavailableMermaid(
    delay: Duration = .milliseconds(2)
  ) async -> MermaidPresentation {
    activeMermaid += 1
    maximumMermaid = max(maximumMermaid, activeMermaid)
    defer { activeMermaid -= 1 }
    do {
      try await Task.sleep(for: delay)
      return .unavailable(diagnostic: "fixture unavailable")
    } catch {
      cancelledMermaid += 1
      return .unavailable(diagnostic: "fixture cancelled")
    }
  }

  func failingImage(
    delay: Duration = .milliseconds(2)
  ) async throws -> LoadedImage {
    activeImages += 1
    maximumImages = max(maximumImages, activeImages)
    defer { activeImages -= 1 }
    do {
      try await Task.sleep(for: delay)
    } catch {
      cancelledImages += 1
      throw error
    }
    throw StubFailure.unavailable
  }
}

private actor NavigationScript {
  var failsNextReadOfFirst = true

  func read(_ url: URL) throws -> DocumentSnapshot {
    if url.lastPathComponent == "one.md", failsNextReadOfFirst {
      failsNextReadOfFirst = false
      throw StubFailure.unavailable
    }
    return DocumentSnapshot(
      source: "# \(url.deletingPathExtension().lastPathComponent.capitalized)",
      url: url,
      displayName: url.lastPathComponent
    )
  }
}

private actor ReloadScript {
  var snapshot: DocumentSnapshot

  init(snapshot: DocumentSnapshot) {
    self.snapshot = snapshot
  }

  func read() -> DocumentSnapshot {
    snapshot
  }
}

private actor NavigationReloadRaceScript {
  let currentURL: URL
  let navigationURL: URL
  private var navigationPending = false
  private var currentReadCount = 0

  init(currentURL: URL, navigationURL: URL) {
    self.currentURL = currentURL
    self.navigationURL = navigationURL
  }

  func read(_ url: URL) async -> DocumentSnapshot {
    if url == navigationURL {
      navigationPending = true
      try? await Task.sleep(for: .seconds(30))
      navigationPending = false
      return DocumentSnapshot(
        source: "# Stale navigation",
        url: navigationURL,
        displayName: navigationURL.lastPathComponent
      )
    }

    currentReadCount += 1
    return DocumentSnapshot(
      source: currentReadCount == 1 ? "# One manually reloaded" : "# One watched",
      url: currentURL,
      displayName: currentURL.lastPathComponent
    )
  }

  func navigationIsPending() -> Bool {
    navigationPending
  }
}

private final class WatchHarness: Sendable {
  private let continuations = Mutex([URL: AsyncStream<Void>.Continuation]())

  func stream(for url: URL) -> AsyncStream<Void> {
    AsyncStream { continuation in
      continuations.withLock {
        $0[url] = continuation
      }
    }
  }

  func yield(_ url: URL) {
    _ = continuations.withLock {
      $0[url]?.yield()
    }
  }
}

private actor ThemeReloadScript {
  private var attempt = 0
  let recoveredTheme: ViewerTheme

  init(recoveredTheme: ViewerTheme) {
    self.recoveredTheme = recoveredTheme
  }

  func load() throws -> LoadedTheme {
    attempt += 1
    if attempt == 1 { throw StubFailure.unavailable }
    return LoadedTheme(theme: recoveredTheme, sourceURL: nil)
  }
}

private actor SupersededLoadProbe {
  struct Metrics: Sendable {
    var documentCalls: Int
    var activeDocuments: Int
    var maximumDocuments: Int
    var cancelledDocuments: Int
    var themeCalls: Int
    var activeThemes: Int
    var maximumThemes: Int
    var cancelledThemes: Int
  }

  let documentURL: URL
  let latestTheme: ViewerTheme
  private var documentCalls = 0
  private var activeDocuments = 0
  private var maximumDocuments = 0
  private var cancelledDocuments = 0
  private var themeCalls = 0
  private var activeThemes = 0
  private var maximumThemes = 0
  private var cancelledThemes = 0

  init(documentURL: URL, latestTheme: ViewerTheme) {
    self.documentURL = documentURL
    self.latestTheme = latestTheme
  }

  func readDocument() async throws -> DocumentSnapshot {
    documentCalls += 1
    activeDocuments += 1
    maximumDocuments = max(maximumDocuments, activeDocuments)
    defer { activeDocuments -= 1 }
    if documentCalls == 1 {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        cancelledDocuments += 1
        throw error
      }
    }
    return DocumentSnapshot(
      source: "# Latest document",
      url: documentURL,
      displayName: documentURL.lastPathComponent
    )
  }

  func loadTheme() async throws -> LoadedTheme {
    themeCalls += 1
    activeThemes += 1
    maximumThemes = max(maximumThemes, activeThemes)
    defer { activeThemes -= 1 }
    if themeCalls == 1 {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        cancelledThemes += 1
        throw error
      }
    }
    return LoadedTheme(theme: latestTheme, sourceURL: nil)
  }

  func metrics() -> Metrics {
    Metrics(
      documentCalls: documentCalls,
      activeDocuments: activeDocuments,
      maximumDocuments: maximumDocuments,
      cancelledDocuments: cancelledDocuments,
      themeCalls: themeCalls,
      activeThemes: activeThemes,
      maximumThemes: maximumThemes,
      cancelledThemes: cancelledThemes
    )
  }
}

private actor SupersededSearchProbe {
  private(set) var startedQueries: [String] = []
  private(set) var cancellationCount = 0

  func search(_ index: SearchIndex, for query: String) async -> SearchResultSet {
    startedQueries.append(query)
    if query == "alpha" {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        cancellationCount += 1
      }
      return SearchResultSet(
        matches: [
          SearchMatch(
            blockID: BlockID("stale-alpha"),
            range: query.startIndex..<query.endIndex
          )
        ],
        isTruncated: false
      )
    }
    return index.results(for: query)
  }
}

@MainActor
@Suite("viewer model and shell")
struct ViewerModelAndRenderTests {
  @Test("search and heading actions mutate semantic state")
  func searchAndHeadings() async {
    let model = makeModel(
      """
      # One

      alpha beta alpha

      ## Two
      """
    )
    await model.start()

    #expect(model.state.document?.outline.count == 2)
    model.send(.beginSearch)
    model.send(.updateSearch("alpha"))
    #expect(model.state.searchVisible)
    #expect(model.state.isSearching)
    await waitUntil { !model.state.isSearching }
    #expect(model.state.searchMatches.count == 2)
    #expect(model.pendingScrollTarget != nil)
    model.send(.nextHeading)
    #expect(model.pendingScrollTarget == model.state.document?.outline.first?.id)
    model.send(.clearScrollTarget)
    model.send(.nextHeading)
    #expect(model.pendingScrollTarget == model.state.document?.outline.last?.id)
    model.send(.endSearch)
    #expect(!model.state.searchVisible)

    await model.shutdown()
  }

  @Test("dense search bounds retained results and scanned text")
  func denseSearchBounds() {
    let id = BlockID("dense")
    let dense = SearchIndex(entries: [(id, String(repeating: "a", count: 4_096))])
    let retained = dense.results(
      for: "a",
      maximumRetainedMatches: 32,
      maximumScannedCharacters: 4_096
    )

    #expect(retained.matches.count == 32)
    #expect(retained.isTruncated)
    #expect(retained.matches.allSatisfy { $0.blockID == id })

    let productionClamped = dense.results(
      for: "a",
      maximumRetainedMatches: .max,
      maximumScannedCharacters: .max
    )
    #expect(productionClamped.matches.count == SearchIndex.maximumRetainedMatches)
    #expect(productionClamped.isTruncated)

    let budgeted = SearchIndex(
      entries: [(id, String(repeating: "x", count: 128) + "needle")]
    ).results(
      for: "needle",
      maximumRetainedMatches: 32,
      maximumScannedCharacters: 64
    )
    #expect(budgeted.matches.isEmpty)
    #expect(budgeted.isTruncated)
  }

  @Test("superseded search cannot commit a stale query result")
  func supersededSearchDoesNotCommit() async {
    let probe = SupersededSearchProbe()
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "# Search\n\nalpha beta",
        url: nil,
        displayName: "search.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      ),
      search: { index, query in
        await probe.search(index, for: query)
      }
    )
    await model.start()

    model.send(.updateSearch("alpha"))
    await waitUntilAsync { await probe.startedQueries.contains("alpha") }
    model.send(.updateSearch("beta"))
    await waitUntil { !model.state.isSearching }

    #expect(model.state.searchQuery == "beta")
    #expect(model.state.searchMatches.count == 1)
    #expect(model.state.searchMatches.first?.blockID != BlockID("stale-alpha"))
    #expect(await probe.cancellationCount == 1)
    await model.shutdown()
    #expect(model.ownedEffectCount == 0)
  }

  @Test("cross-document fragment scrolls after the fragment-free document commits")
  func crossDocumentFragmentNavigation() async {
    let reads = Mutex<[URL]>([])
    let initialURL = URL(fileURLWithPath: "/docs/one.md")
    let expectedURL = URL(fileURLWithPath: "/docs/next doc.md")
    let model = ViewerModel(
      snapshot: DocumentSnapshot(source: "# One", url: initialURL, displayName: "one.md"),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { url in
          reads.withLock { $0.append(url) }
          return DocumentSnapshot(
            source: "# Intro\n\nDestination",
            url: url,
            displayName: url.lastPathComponent
          )
        },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    model.send(.openDestination("next%20doc.md#intro"))
    await waitUntil { model.state.snapshot.url == expectedURL }

    #expect(reads.withLock { $0 } == [expectedURL])
    #expect(model.pendingScrollTarget == model.state.document?.outline.first?.id)

    model.send(.openDestination("missing.md#absent"))
    await waitUntil { model.state.snapshot.url?.lastPathComponent == "missing.md" }
    #expect(model.state.diagnostic?.message == "No heading named #absent")
    await model.shutdown()
  }

  @Test(
    "responsive shell keeps content and quit help visible",
    arguments: [
      ViewerSize(width: 60, height: 16),
      ViewerSize(width: 80, height: 24),
      ViewerSize(width: 120, height: 40),
      ViewerSize(width: 180, height: 60),
    ]
  )
  func responsiveRender(size: ViewerSize) async {
    let model = makeModel("# Read me\n\nVisible paragraph.")
    await model.start()
    model.updateViewport(size)

    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: size.width, height: size.height)
    let artifacts = DefaultRenderer().render(
      MrkdwnRootView(model: model),
      context: .init(
        identity: Identity(components: [.named("MrkdwnRoot")]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: size.width, height: size.height)
    )
    let text = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("mrkdwn"))
    #expect(text.contains("Read me"))
    #expect(text.contains("q quit"))

    await model.shutdown()
  }

  @Test("outline and links expose pointer hit regions and accessibility metadata")
  func pointerAndAccessibilitySurface() async throws {
    let model = makeModel(
      """
      # Accessible heading

      [Focusable link](https://example.com)
      """
    )
    await model.start()
    let size = ViewerSize(width: 120, height: 40)
    model.updateViewport(size)
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: size.width, height: size.height)
    let artifacts = DefaultRenderer().render(
      MrkdwnRootView(model: model),
      context: .init(
        identity: Identity(components: [.named("MrkdwnAccessibility")]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: size.width, height: size.height)
    )
    #expect(!artifacts.semanticSnapshot.focusRegions.isEmpty)
    let regions = artifacts.semanticSnapshot.interactionRegions
    #expect(!regions.isEmpty)
    for region in regions {
      let center = PointerLocation.cellFallback(
        CellPoint(
          x: region.rect.origin.x + max(0, region.rect.size.width - 1) / 2,
          y: region.rect.origin.y + max(0, region.rect.size.height - 1) / 2
        )
      )
      #expect(region.contains(center))
    }
    #expect(
      artifacts.semanticSnapshot.accessibilityNodes.contains {
        $0.label?.contains("Accessible heading") == true
      }
    )
    await model.shutdown()
  }

  @Test("rapid viewport changes coalesce to one Mermaid reflow")
  func viewportDebounce() async {
    let recorder = MermaidRequestRecorder()
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "```mermaid\nflowchart LR\nA --> B\n```",
        url: nil,
        displayName: "diagram.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          await recorder.record(request)
          return .unavailable(diagnostic: "stub")
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { duration in try? await Task.sleep(for: duration) }
      )
    )
    await model.start()
    guard
      let id = firstResourceID(
        in: model,
        matching: {
          if case .mermaid = $0 { return true }
          return false
        })
    else {
      Issue.record("Expected a Mermaid block")
      await model.shutdown()
      return
    }
    model.resourceBecameVisible(id)
    await waitUntilAsync { await recorder.requests.count == 1 }
    model.updateViewport(ViewerSize(width: 70, height: 20))
    model.updateViewport(ViewerSize(width: 90, height: 20))
    model.updateViewport(ViewerSize(width: 100, height: 20))
    await waitUntilAsync { await recorder.requests.count == 2 }

    let requests = await recorder.requests
    #expect(requests.count == 2)
    #expect(requests.last?.width == 94)
    await model.shutdown()
  }

  @Test("nested diagrams and images enter the async resource pipelines")
  func nestedResources() async {
    let mermaid = MermaidRequestRecorder()
    let images = ImageRequestRecorder()
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: """
          > ```mermaid
          > flowchart LR
          > A --> B
          > ```

          - ![nested](image.png)
          """,
        url: URL(fileURLWithPath: "/docs/one.md"),
        displayName: "one.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          await mermaid.record(request)
          return .unavailable(diagnostic: "stub")
        },
        loadImage: { source, _ in
          await images.record(source)
          throw StubFailure.unavailable
        },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    for descriptor in MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ) {
      switch descriptor.block {
      case .mermaid(let id, _, _), .image(let id, _, _):
        model.resourceBecameVisible(id)
      default:
        break
      }
    }
    for _ in 0..<20 {
      if await mermaid.requests.count == 1, await images.sources.count == 1 {
        break
      }
      await Task.yield()
    }
    #expect(await mermaid.requests.count == 1)
    #expect(
      await mermaid.requests.first?.width
        == MarkdownBlockLayout.quoteContentWidth(model.state.viewport.documentWidth)
    )
    #expect(await images.sources == ["image.png"])
    await model.shutdown()
  }

  @Test("reload restores a later heading after loose-list source lines move")
  func reloadRestoresHeadingAnchor() async {
    let url = URL(fileURLWithPath: "/docs/reload.md")
    let next = DocumentSnapshot(
      source: """
        # Intro

        inserted

        - first paragraph

          second paragraph

        ## Keep

        retained
        """,
      url: url,
      displayName: "reload.md"
    )
    let script = ReloadScript(snapshot: next)
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: """
          # Intro

          - first paragraph

            second paragraph

          ## Keep

          retained
          """,
        url: url,
        displayName: "reload.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in await script.read() },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          .unavailable(diagnostic: "stub")
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    let keep = model.state.document?.outline.first(where: { $0.anchor == "keep" })
    if let keep {
      model.send(.scrollToHeading(keep.id))
      model.send(.clearScrollTarget)
      model.updateDocumentScrollOffset(model.documentGeometryTop(for: keep.id) ?? 0)
    }

    model.send(.reload)
    await waitUntil { model.state.snapshot.source == next.source && !model.state.isReloading }

    let reloadedKeep = model.state.document?.outline.first(where: { $0.anchor == "keep" })
    #expect(reloadedKeep != nil)
    #expect(model.pendingScrollTarget == reloadedKeep?.id)
    #expect(reloadedKeep?.id != keep?.id)
    await model.shutdown()
  }

  @Test("rapid reloads cancel, drain, and coalesce document and theme work")
  func reloadEffectCoalescing() async throws {
    let url = URL(fileURLWithPath: "/docs/coalesced.md")
    var latestTheme = ViewerTheme.default
    latestTheme.accent = try ThemeColor("#123456")
    let probe = SupersededLoadProbe(
      documentURL: url,
      latestTheme: latestTheme
    )
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "# Original",
        url: url,
        displayName: url.lastPathComponent
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in try await probe.readDocument() },
        loadTheme: { try await probe.loadTheme() },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()

    model.send(.reload)
    await waitUntilAsync {
      let metrics = await probe.metrics()
      return metrics.activeDocuments == 1 && metrics.activeThemes == 1
    }
    for _ in 0..<32 {
      model.send(.reload)
    }
    await waitUntil {
      model.state.snapshot.source == "# Latest document"
        && model.state.theme.accent.hex == "#123456"
        && model.ownedEffectCount == 0
    }

    let metrics = await probe.metrics()
    #expect(metrics.documentCalls == 2)
    #expect(metrics.maximumDocuments == 1)
    #expect(metrics.cancelledDocuments == 1)
    #expect(metrics.themeCalls == 2)
    #expect(metrics.maximumThemes == 1)
    #expect(metrics.cancelledThemes == 1)
    await model.shutdown()
  }

  @Test("reload restores the visible rendered block and intra-block row")
  func reloadRestoresRenderedGeometry() async throws {
    let url = URL(fileURLWithPath: "/docs/geometry.md")
    let retained =
      "retained paragraph wraps across several terminal rows and remains the visible block"
    let next = DocumentSnapshot(
      source: """
        # Intro

        newly inserted paragraph

        another inserted paragraph

        \(retained)
        """,
      url: url,
      displayName: "geometry.md"
    )
    let script = ReloadScript(snapshot: next)
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "# Intro\n\n\(retained)",
        url: url,
        displayName: "geometry.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in await script.read() },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    model.updateViewport(ViewerSize(width: 24, height: 16))
    let oldGeometry = MarkdownBlockLayout.renderedGeometry(
      try #require(model.state.document?.blocks),
      inputs: .init(
        mermaid: model.mermaid,
        images: model.images,
        revealedMermaidSources: model.state.revealedMermaidSources,
        documentURL: model.state.snapshot.url
      ),
      offeredWidth: model.state.viewport.documentWidth
    )
    let oldParagraph = try #require(
      oldGeometry.first { entry in
        model.state.document?.blocks.first(where: { $0.id == entry.blockID })?.searchableText
          == retained
      }
    )
    model.updateDocumentScrollOffset(oldParagraph.top + 1)

    model.send(.reload)
    await waitUntil { model.state.snapshot.source == next.source && !model.state.isReloading }
    let newDocument = try #require(model.state.document)
    let retainedID = try #require(
      newDocument.blocks.first(where: { $0.searchableText == retained })?.id
    )
    let newGeometry = MarkdownBlockLayout.renderedGeometry(
      newDocument.blocks,
      inputs: .init(
        mermaid: model.mermaid,
        images: model.images,
        revealedMermaidSources: model.state.revealedMermaidSources,
        documentURL: model.state.snapshot.url
      ),
      offeredWidth: model.state.viewport.documentWidth
    )
    let newParagraph = try #require(newGeometry.first { $0.blockID == retainedID })
    #expect(model.pendingScrollTarget == nil)
    #expect(model.documentScrollOffset == newParagraph.top + 1)
    await model.shutdown()
  }

  @Test("failed history navigation preserves the retry target")
  func historyFailureIsTransactional() async {
    let first = URL(fileURLWithPath: "/docs/one.md")
    let script = NavigationScript()
    let model = ViewerModel(
      snapshot: DocumentSnapshot(source: "# One", url: first, displayName: "one.md"),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { try await script.read($0) },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          .unavailable(diagnostic: "stub")
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    model.send(.openDestination("two.md"))
    await waitUntil { model.state.snapshot.displayName == "two.md" }
    #expect(model.state.canGoBack)

    model.send(.goBack)
    await waitUntil { model.state.diagnostic?.severity == .error }
    #expect(model.state.snapshot.displayName == "two.md")
    #expect(model.state.canGoBack)

    model.send(.goBack)
    await waitUntil { model.state.snapshot.displayName == "one.md" }
    #expect(model.state.canGoForward)
    await model.shutdown()
  }

  @Test("scroll position updates reuse one geometry snapshot per layout revision")
  func scrollGeometryCache() async {
    let source = (0..<10_000)
      .map { index in
        index.isMultiple(of: 100)
          ? "## Heading \(index)"
          : "paragraph \(index) with enough content to exercise terminal layout"
      }
      .joined(separator: "\n\n")
    let model = makeModel(source)
    await model.start()
    #expect(model.renderedGeometryComputationCount == 0)

    model.updateDocumentScrollOffset(1)
    #expect(model.renderedGeometryComputationCount == 1)
    for offset in 2..<100 {
      model.updateDocumentScrollOffset(offset)
    }
    #expect(model.renderedGeometryComputationCount == 1)

    model.updateViewport(ViewerSize(width: 100, height: 24))
    model.updateDocumentScrollOffset(101)
    #expect(model.renderedGeometryComputationCount == 2)
    await model.shutdown()
  }

  @Test("document navigation resets Mermaid disclosure and focus revision")
  func documentLocalPresentationReset() async {
    let first = URL(fileURLWithPath: "/docs/one.md")
    let second = URL(fileURLWithPath: "/docs/two.md")
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "```mermaid\nflowchart LR\nA --> B\n```",
        url: first,
        displayName: "one.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { url in
          DocumentSnapshot(source: "# Two", url: url, displayName: "two.md")
        },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    let mermaidID = model.state.document?.blocks.first?.id
    if let mermaidID { model.send(.toggleMermaidSource(mermaidID)) }
    #expect(!model.state.revealedMermaidSources.isEmpty)
    let firstRevision = model.state.contentRevision

    model.send(.openDestination(second.path))
    await waitUntil { model.state.snapshot.url == second }
    #expect(model.state.revealedMermaidSources.isEmpty)
    #expect(model.state.contentRevision > firstRevision)
    await model.shutdown()
  }

  @Test("an oversized presentation becomes a stable bounded fallback")
  func oversizedPresentationFallback() async {
    let recorder = MermaidRequestRecorder()
    let oversized = RenderedMermaid(
      width: 300,
      height: 300,
      cells: Array(
        repeating: Array(
          repeating: MermaidPaintCell(character: "A", role: .text),
          count: 300
        ),
        count: 300
      )
    )
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "```mermaid\nflowchart LR\nA --> B\n```",
        url: nil,
        displayName: "oversized.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: {
          await recorder.record($0)
          return .ready(oversized)
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    guard
      let id = firstResourceID(
        in: model,
        matching: {
          if case .mermaid = $0 { return true }
          return false
        })
    else {
      Issue.record("Expected a Mermaid block")
      await model.shutdown()
      return
    }
    model.resourceBecameVisible(id)
    await waitUntil(attempts: 5_000) {
      if case .unavailable? = model.mermaid[id] { return true }
      return false
    }
    model.resourceBecameHidden(id)
    model.resourceBecameVisible(id)
    await Task.yield()
    #expect(await recorder.requests.count == 1)
    #expect(model.retainedPresentationOccupancy.mermaidEntries == 0)
    await model.shutdown()
  }

  @Test("next Mermaid reveal follows flattened authored order and stops when complete")
  func revealNextMermaidSource() async {
    let model = makeModel(
      """
      ```mermaid
      flowchart LR
      FIRST --> A
      ```

      > ```mermaid
      > flowchart LR
      > SECOND --> B
      > ```
      """
    )
    await model.start()
    let ids = MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ).compactMap { descriptor -> BlockID? in
      if case .mermaid(let id, _, _) = descriptor.block { return id }
      return nil
    }
    #expect(ids.count == 2)

    model.send(.revealNextMermaidSource)
    #expect(model.state.revealedMermaidSources == Set(ids.prefix(1)))
    model.send(.revealNextMermaidSource)
    #expect(model.state.revealedMermaidSources == Set(ids))
    model.send(.revealNextMermaidSource)
    #expect(model.state.revealedMermaidSources == Set(ids))
    await model.shutdown()
  }

  @Test("100 Mermaid and image results stay inside aggregate state budgets")
  func aggregatePresentationBudgets() async {
    let mermaidRequests = MermaidRequestRecorder()
    let imageRequests = ImageRequestRecorder()
    let mermaidSources = (0..<100).map {
      "```mermaid\nflowchart LR\nA\($0) --> B\($0)\n```"
    }
    let imageSources = (0..<100).map {
      "![image \($0)](image-\($0).png \"title \($0)\")"
    }
    let rendered = RenderedMermaid(
      width: 64,
      height: 64,
      cells: Array(
        repeating: Array(
          repeating: MermaidPaintCell(character: "A", role: .text),
          count: 64
        ),
        count: 64
      )
    )
    let imageData = Data(repeating: 0xA5, count: 1_024 * 1_024)
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: (mermaidSources + imageSources).joined(separator: "\n\n"),
        url: URL(fileURLWithPath: "/docs/budgets.md"),
        displayName: "budgets.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          await mermaidRequests.record(request)
          return .ready(rendered)
        },
        loadImage: { source, _ in
          await imageRequests.record(source)
          return LoadedImage(
            data: imageData,
            url: URL(fileURLWithPath: "/docs/\(source)"),
            image: InspectedImage(
              format: .png,
              dimensions: ImageDimensions(width: 32, height: 32)
            )
          )
        },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )

    await model.start()
    let descriptors = MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    )
    let mermaidIDs = descriptors.compactMap { descriptor -> BlockID? in
      if case .mermaid(let id, _, _) = descriptor.block { return id }
      return nil
    }
    let imageIDs = descriptors.compactMap { descriptor -> BlockID? in
      if case .image(let id, _, _) = descriptor.block { return id }
      return nil
    }
    for id in mermaidIDs + imageIDs {
      model.resourceBecameVisible(id)
    }
    await waitUntil(attempts: 5_000) {
      model.ownedEffectCount == 0
        && model.retainedPresentationOccupancy.mermaidEntries > 0
        && model.retainedPresentationOccupancy.imageEntries > 0
    }
    #expect(await mermaidRequests.requests.count == 100)
    #expect(await imageRequests.sources.count == 28)
    for id in mermaidIDs {
      model.resourceBecameHidden(id)
    }
    for id in imageIDs {
      model.resourceBecameVisible(id)
    }
    await waitUntil(attempts: 5_000) {
      model.ownedEffectCount == 0
        && model.retainedPresentationOccupancy.imageEntries > 0
    }
    let occupancy = model.retainedPresentationOccupancy
    #expect(occupancy.mermaidEntries <= ViewerModel.maximumRetainedMermaidPresentations)
    #expect(occupancy.mermaidBytes <= ViewerModel.maximumRetainedMermaidBytes)
    #expect(occupancy.imageEntries <= ViewerModel.maximumRetainedImagePresentations)
    #expect(occupancy.imageBytes <= ViewerModel.maximumRetainedImageBytes)
    #expect(
      model.mermaid.values.filter {
        if case .ready = $0 { return true }
        return false
      }.count == occupancy.mermaidEntries
    )
    #expect(
      model.images.values.filter {
        if case .ready = $0 { return true }
        return false
      }.count == occupancy.imageEntries
    )

    #expect(await mermaidRequests.requests.count == 100)
    #expect(await imageRequests.sources.count == 100)
    // A resource released from the bounded cache either loses its state entry
    // outright or, while it is still visible, degrades to the nonblank
    // released placeholder asserted by the visible-overflow suites. Both are
    // evictions; only a retained `.ready` presentation is not.
    let releasedMermaid = mermaidIDs.first {
      switch model.mermaid[$0] {
      case nil, .unavailable?: true
      default: false
      }
    }
    if let evictedMermaid = releasedMermaid {
      model.resourceBecameHidden(evictedMermaid)
      model.resourceBecameVisible(evictedMermaid)
      await waitUntil(attempts: 5_000) {
        if case .ready? = model.mermaid[evictedMermaid] { return true }
        return false
      }
      #expect(await mermaidRequests.requests.count == 101)
    } else {
      Issue.record("Expected at least one Mermaid presentation eviction")
    }
    let releasedImage = imageIDs.first {
      switch model.images[$0] {
      case nil, .terminalFallback?: true
      default: false
      }
    }
    if let evictedImage = releasedImage {
      model.resourceBecameHidden(evictedImage)
      model.resourceBecameVisible(evictedImage)
      await waitUntil(attempts: 5_000) {
        if case .ready? = model.images[evictedImage] { return true }
        return false
      }
      #expect(await imageRequests.sources.count == 101)
    } else {
      Issue.record("Expected at least one image presentation eviction")
    }
    await model.shutdown()
  }

  @Test("visible Mermaid overflow retains bounded nonblank presentation states")
  func visibleMermaidPresentationOverflow() async {
    let recorder = MermaidRequestRecorder()
    let count = ViewerModel.maximumRetainedMermaidPresentations + 1
    let sources = (0..<count).map {
      "```mermaid\nflowchart LR\nA\($0) --> B\($0)\n```"
    }
    let rendered = RenderedMermaid(
      width: 1,
      height: 1,
      cells: [[MermaidPaintCell(character: "A", role: .text)]]
    )
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: sources.joined(separator: "\n\n"),
        url: URL(fileURLWithPath: "/docs/visible-mermaid-overflow.md"),
        displayName: "visible-mermaid-overflow.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          await recorder.record(request)
          return .ready(rendered)
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )

    await model.start()
    let ids = MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ).compactMap { descriptor -> BlockID? in
      if case .mermaid(let id, _, _) = descriptor.block { return id }
      return nil
    }
    #expect(ids.count == count)
    for id in ids {
      model.resourceBecameVisible(id)
    }
    await waitUntil(attempts: 5_000) {
      model.ownedEffectCount == 0
    }

    #expect(await recorder.requests.count == count)
    #expect(
      model.retainedPresentationOccupancy.mermaidEntries
        <= ViewerModel.maximumRetainedMermaidPresentations
    )
    #expect(model.mermaid.count <= ViewerModel.maximumRetainedResourceStates)
    #expect(
      ids.allSatisfy { id in
        switch model.mermaid[id] {
        case .ready?, .unavailable?:
          true
        case .pending?, .reflowing?, nil:
          false
        }
      }
    )
    #expect(
      ids.contains { id in
        if case .unavailable? = model.mermaid[id] { return true }
        return false
      }
    )
    let settledRequestCount = await recorder.requests.count
    for _ in 0..<20 {
      await Task.yield()
    }
    #expect(await recorder.requests.count == settledRequestCount)
    await model.shutdown()
  }

  @Test("visible image overflow retains bounded nonblank presentation states")
  func visibleImagePresentationOverflow() async {
    let recorder = ImageRequestRecorder()
    let count = ViewerModel.maximumRetainedImagePresentations + 1
    let sources = (0..<count).map {
      "![image \($0)](visible-image-\($0).png)"
    }
    let imageData = Data([0xA5])
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: sources.joined(separator: "\n\n"),
        url: URL(fileURLWithPath: "/docs/visible-image-overflow.md"),
        displayName: "visible-image-overflow.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { source, _ in
          await recorder.record(source)
          return LoadedImage(
            data: imageData,
            url: URL(fileURLWithPath: "/docs/\(source)"),
            image: InspectedImage(
              format: .png,
              dimensions: ImageDimensions(width: 1, height: 1)
            )
          )
        },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )

    await model.start()
    let ids = MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ).compactMap { descriptor -> BlockID? in
      if case .image(let id, _, _) = descriptor.block { return id }
      return nil
    }
    #expect(ids.count == count)
    for id in ids {
      model.resourceBecameVisible(id)
    }
    await waitUntil(attempts: 5_000) {
      model.ownedEffectCount == 0
    }

    #expect(await recorder.sources.count == count)
    #expect(
      model.retainedPresentationOccupancy.imageEntries
        <= ViewerModel.maximumRetainedImagePresentations
    )
    #expect(model.images.count <= ViewerModel.maximumRetainedResourceStates)
    #expect(
      ids.allSatisfy { id in
        switch model.images[id] {
        case .ready?, .terminalFallback?:
          true
        case .loading?, .blocked?, .failed?, nil:
          false
        }
      }
    )
    #expect(
      ids.contains { id in
        if case .terminalFallback? = model.images[id] { return true }
        return false
      }
    )
    let settledRequestCount = await recorder.sources.count
    for _ in 0..<20 {
      await Task.yield()
    }
    #expect(await recorder.sources.count == settledRequestCount)
    await model.shutdown()
  }

  @Test("resource admission, active work, and non-ready states stay bounded")
  func boundedResourceLifecycle() async {
    let probe = ResourceLifecycleProbe()
    let mermaidSources = (0..<300).map {
      "```mermaid\nflowchart LR\nA\($0) --> B\($0)\n```"
    }
    let imageSources = (0..<300).map {
      "![image \($0)](failure-\($0).png)"
    }
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: (mermaidSources + imageSources).joined(separator: "\n\n"),
        url: URL(fileURLWithPath: "/docs/bounded-lifecycle.md"),
        displayName: "bounded-lifecycle.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in await probe.unavailableMermaid() },
        loadImage: { _, _ in try await probe.failingImage() },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    let resourceIDs = MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ).compactMap { descriptor -> BlockID? in
      switch descriptor.block {
      case .mermaid(let id, _, _), .image(let id, _, _):
        id
      default:
        nil
      }
    }

    for batchStart in stride(
      from: 0,
      to: resourceIDs.count,
      by: ViewerModel.maximumVisibleResourceIDs
    ) {
      let batchEnd = min(
        resourceIDs.count,
        batchStart + ViewerModel.maximumVisibleResourceIDs
      )
      let batch = resourceIDs[batchStart..<batchEnd]
      for id in batch {
        model.resourceBecameVisible(id)
      }
      let admitted = model.resourceLifecycleOccupancy
      #expect(admitted.visible <= ViewerModel.maximumVisibleResourceIDs)
      #expect(admitted.activeMermaid <= ViewerModel.maximumConcurrentMermaidRequests)
      #expect(admitted.activeImages <= ViewerModel.maximumConcurrentImageRequests)
      await waitUntil { model.ownedEffectCount == 0 }
      let settled = model.resourceLifecycleOccupancy
      #expect(settled.mermaidStates <= ViewerModel.maximumRetainedResourceStates)
      #expect(settled.imageStates <= ViewerModel.maximumRetainedResourceStates)
      for id in batch {
        model.resourceBecameHidden(id)
      }
    }

    #expect(await probe.maximumMermaid <= ViewerModel.maximumConcurrentMermaidRequests)
    #expect(await probe.maximumImages <= ViewerModel.maximumConcurrentImageRequests)
    #expect(model.resourceLifecycleOccupancy.visible == 0)
    #expect(
      model.resourceLifecycleOccupancy.mermaidStates
        <= ViewerModel.maximumRetainedResourceStates
    )
    #expect(
      model.resourceLifecycleOccupancy.imageStates
        <= ViewerModel.maximumRetainedResourceStates
    )
    await model.shutdown()
  }

  @Test("hidden resource work is cancelled and drained immediately")
  func hiddenResourceCancellation() async {
    let probe = ResourceLifecycleProbe()
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: """
          ```mermaid
          flowchart LR
          A --> B
          ```

          ![late](late.png)
          """,
        url: URL(fileURLWithPath: "/docs/hidden.md"),
        displayName: "hidden.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in
          await probe.unavailableMermaid(delay: .seconds(30))
        },
        loadImage: { _, _ in
          try await probe.failingImage(delay: .seconds(30))
        },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    let resourceIDs = MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ).compactMap { descriptor -> BlockID? in
      switch descriptor.block {
      case .mermaid(let id, _, _), .image(let id, _, _):
        id
      default:
        nil
      }
    }
    for id in resourceIDs {
      model.resourceBecameVisible(id)
    }
    await waitUntilAsync {
      let active = await probe.activeCounts()
      return active.mermaid == 1 && active.images == 1
    }
    for id in resourceIDs {
      model.resourceBecameHidden(id)
    }
    await waitUntil {
      model.ownedEffectCount == 0
        && model.resourceLifecycleOccupancy.activeMermaid == 0
        && model.resourceLifecycleOccupancy.activeImages == 0
    }

    #expect(await probe.cancelledMermaid == 1)
    #expect(await probe.cancelledImages == 1)
    #expect(model.resourceLifecycleOccupancy.visible == 0)
    #expect(model.resourceLifecycleOccupancy.mermaidStates == 0)
    #expect(model.resourceLifecycleOccupancy.imageStates == 0)
    await model.shutdown()
  }

  @Test("shutdown invalidates late results and drains every owned effect")
  func shutdownGenerationAndDrain() async {
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: """
          ```mermaid
          flowchart LR
          A --> B
          ```

          ![late](late.png)
          """,
        url: URL(fileURLWithPath: "/docs/late.md"),
        displayName: "late.md"
      ),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { _ in
          try? await Task.sleep(for: .seconds(30))
          return .ready(
            RenderedMermaid(
              width: 1,
              height: 1,
              cells: [[MermaidPaintCell(character: "L", role: .text)]]
            )
          )
        },
        loadImage: { _, _ in
          try? await Task.sleep(for: .seconds(30))
          return LoadedImage(
            data: Data([1]),
            url: URL(fileURLWithPath: "/docs/late.png"),
            image: InspectedImage(
              format: .png,
              dimensions: ImageDimensions(width: 1, height: 1)
            )
          )
        },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    for descriptor in MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ) {
      model.resourceBecameVisible(descriptor.block.id)
    }
    await Task.yield()
    await model.shutdown()

    #expect(model.ownedEffectCount == 0)
    #expect(model.retainedPresentationOccupancy.mermaidEntries == 0)
    #expect(model.retainedPresentationOccupancy.imageEntries == 0)
    #expect(!model.mermaid.values.contains { if case .ready = $0 { true } else { false } })
    #expect(!model.images.values.contains { if case .ready = $0 { true } else { false } })

    model.send(.reload)
    model.updateViewport(ViewerSize(width: 120, height: 40))
    await Task.yield()
    #expect(model.ownedEffectCount == 0)
  }

  @Test("navigation suspends the old watcher until the new document commits")
  func navigationWatcherRace() async {
    let first = URL(fileURLWithPath: "/docs/one.md")
    let second = URL(fileURLWithPath: "/docs/two.md")
    let watcher = WatchHarness()
    let model = ViewerModel(
      snapshot: DocumentSnapshot(source: "# One", url: first, displayName: "one.md"),
      theme: .default,
      watchesDocument: true,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { url in
          try? await Task.sleep(for: .milliseconds(25))
          return DocumentSnapshot(
            source: "# \(url == second ? "Two" : "One reloaded")",
            url: url,
            displayName: url.lastPathComponent
          )
        },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { watcher.stream(for: $0) },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    model.send(.openDestination("two.md"))
    watcher.yield(first)
    await waitUntil { model.state.snapshot.url == second }

    #expect(model.state.snapshot.displayName == "two.md")
    #expect(model.state.document?.outline.first?.anchor == "two")
    await model.shutdown()
  }

  @Test("reload superseding delayed navigation reinstalls the committed document watcher")
  func reloadSupersedesNavigationWatcherRace() async {
    let first = URL(fileURLWithPath: "/docs/one.md")
    let second = URL(fileURLWithPath: "/docs/two.md")
    let watcher = WatchHarness()
    let script = NavigationReloadRaceScript(currentURL: first, navigationURL: second)
    let model = ViewerModel(
      snapshot: DocumentSnapshot(source: "# One", url: first, displayName: "one.md"),
      theme: .default,
      watchesDocument: true,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { await script.read($0) },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { watcher.stream(for: $0) },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()

    model.send(.openDestination("two.md"))
    await waitUntilAsync { await script.navigationIsPending() }
    model.send(.reload)
    await waitUntil { model.state.snapshot.source == "# One manually reloaded" }

    watcher.yield(first)
    await waitUntil { model.state.snapshot.source == "# One watched" }
    await Task.yield()

    #expect(model.state.snapshot.url == first)
    #expect(model.state.document?.outline.first?.anchor == "one-watched")
    await model.shutdown()
  }

  @Test("bad then good theme watcher events preserve and recover the theme")
  func badThenGoodThemeReload() async throws {
    let documentURL = URL(fileURLWithPath: "/docs/theme.md")
    let themeURL = URL(fileURLWithPath: "/config/mrkdwn/theme.toml")
    let watcher = WatchHarness()
    var recovered = ViewerTheme.default
    recovered.accent = try ThemeColor("#010203")
    let script = ThemeReloadScript(recoveredTheme: recovered)
    let model = ViewerModel(
      snapshot: DocumentSnapshot(source: "# Theme", url: documentURL, displayName: "theme.md"),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: themeURL,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { try await script.load() },
        watchFile: { watcher.stream(for: $0) },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()

    watcher.yield(themeURL)
    await waitUntil { model.state.diagnostic?.severity == .error }
    #expect(model.state.theme == .default)

    watcher.yield(themeURL)
    await waitUntil { model.state.theme.accent.hex == "#010203" }
    #expect(model.state.diagnostic == nil)
    await model.shutdown()
  }

  @Test("invalid watched theme does not block a valid document reload")
  func invalidThemeDoesNotBlockDocumentReload() async {
    let documentURL = URL(fileURLWithPath: "/docs/reload-with-bad-theme.md")
    let themeURL = URL(fileURLWithPath: "/config/mrkdwn/theme.toml")
    let watcher = WatchHarness()
    let next = DocumentSnapshot(
      source: "# Updated document",
      url: documentURL,
      displayName: documentURL.lastPathComponent
    )
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "# Original document",
        url: documentURL,
        displayName: documentURL.lastPathComponent
      ),
      theme: .default,
      watchesDocument: true,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: themeURL,
        readDocument: { _ in next },
        loadTheme: { throw StubFailure.unavailable },
        watchFile: { watcher.stream(for: $0) },
        renderMermaid: { _ in .unavailable(diagnostic: "stub") },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()

    watcher.yield(themeURL)
    await waitUntil { model.state.diagnostic?.severity == .error }
    watcher.yield(documentURL)
    await waitUntil {
      model.state.snapshot.source == next.source && !model.state.isReloading
    }

    #expect(model.state.document?.outline.first?.anchor == "updated-document")
    #expect(model.state.theme == .default)
    #expect(model.state.diagnostic?.severity == .error)
    await model.shutdown()
  }

  @Test("launch Mermaid policy survives every model request key")
  func mermaidLaunchConfiguration() async {
    let recorder = MermaidRequestRecorder()
    let configuration = ViewerMermaidConfiguration(
      glyphMode: .ascii,
      ambiguousWidth: .wide
    )
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: "```mermaid\nflowchart LR\nA --> B\n```",
        url: nil,
        displayName: "policy.md"
      ),
      theme: .default,
      watchesDocument: false,
      mermaidConfiguration: configuration,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: {
          await recorder.record($0)
          return .unavailable(diagnostic: "stub")
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
    await model.start()
    if let id = firstResourceID(
      in: model,
      matching: {
        if case .mermaid = $0 { return true }
        return false
      })
    {
      model.resourceBecameVisible(id)
    }
    await waitUntilAsync { await recorder.requests.count == 1 }
    #expect(await recorder.requests.first?.configuration == configuration)
    await model.shutdown()
  }

  @Test("scroll-frequency writes bypass whole-state observers")
  func scrollWritesBypassStateObservers() async throws {
    let model = makeModel("# One\n\nalpha\n\nbeta\n\ngamma")
    await model.start()
    model.updateViewport(ViewerSize(width: 80, height: 24))

    // A chrome-shaped observer: reads only `state`, the way the header,
    // status bar, and overlays do. A per-notch offset write must not fire it —
    // that cone is exactly what Stage 1's split removes.
    let stateFired = Mutex(false)
    withObservationTracking {
      _ = model.state
    } onChange: {
      stateFired.withLock { $0 = true }
    }
    let offsetFired = Mutex(false)
    withObservationTracking {
      _ = model.documentScrollOffset
    } onChange: {
      offsetFired.withLock { $0 = true }
    }

    model.updateDocumentScrollOffset(2)
    #expect(offsetFired.withLock { $0 })
    #expect(!stateFired.withLock { $0 })

    // Navigation targets are also split out: a heading jump fires neither the
    // chrome observer nor the offset observer.
    let targetFired = Mutex(false)
    withObservationTracking {
      _ = model.pendingScrollTarget
    } onChange: {
      targetFired.withLock { $0 = true }
    }
    let heading = try #require(model.state.document?.outline.first?.id)
    model.send(.scrollToHeading(heading))
    #expect(targetFired.withLock { $0 })
    #expect(!stateFired.withLock { $0 })

    // And the reverse direction: a genuine `state` write does fire the
    // chrome observer (the tracking above was consumed, so re-register).
    withObservationTracking {
      _ = model.state
    } onChange: {
      stateFired.withLock { $0 = true }
    }
    model.send(.toggleOutline)
    #expect(stateFired.withLock { $0 })
    await model.shutdown()
  }

  private func makeModel(_ source: String) -> ViewerModel {
    ViewerModel(
      snapshot: DocumentSnapshot(source: source, url: nil, displayName: "fixture.md"),
      theme: .default,
      watchesDocument: false,
      compiler: MarkdownCompiler(),
      linkResolver: LinkResolver(),
      dependencies: ViewerDependencies(
        themeURL: nil,
        readDocument: { _ in throw StubFailure.unavailable },
        loadTheme: { LoadedTheme(theme: .default, sourceURL: nil) },
        watchFile: { _ in AsyncStream { $0.finish() } },
        renderMermaid: { request in
          .unavailable(diagnostic: "stub")
        },
        loadImage: { _, _ in throw StubFailure.unavailable },
        openExternal: { _ in true },
        sleep: { _ in }
      )
    )
  }

  private func firstResourceID(
    in model: ViewerModel,
    matching predicate: (MarkdownBlock) -> Bool
  ) -> BlockID? {
    MarkdownBlockLayout.flattened(
      model.state.document?.blocks ?? [],
      offeredWidth: model.state.viewport.documentWidth
    ).first(where: { predicate($0.block) })?.block.id
  }

  private func waitUntil(
    attempts: Int = 500,
    _ predicate: @MainActor () -> Bool
  ) async {
    for _ in 0..<attempts {
      if predicate() { return }
      try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Viewer model did not reach the expected state")
  }

  private func waitUntilAsync(
    _ predicate: () async -> Bool
  ) async {
    for _ in 0..<500 {
      if await predicate() { return }
      try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Viewer model did not reach the expected async state")
  }
}
