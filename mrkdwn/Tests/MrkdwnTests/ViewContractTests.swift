import Foundation
@_spi(Runners) import SwiftTUI
import Synchronization
import Testing

@testable import Mrkdwn

@MainActor
@Suite("view contracts")
struct ViewContractTests {
  @Test("terminal table measurement counts cells rather than graphemes")
  func terminalCellMeasurement() {
    #expect(terminalDisplayWidth(of: "abc") == 3)
    #expect(terminalDisplayWidth(of: "界") == 2)
    #expect(terminalDisplayWidth(of: "👩🏽‍💻") == 2)
    #expect(terminalDisplayWidth(of: "e\u{301}") == 1)
  }

  @Test("ordered-list markers share one right-aligned hanging-indent column")
  func orderedListMarkerAlignment() {
    let list = MarkdownList(
      kind: .ordered(start: 9),
      items: [
        MarkdownListItem(blocks: []),
        MarkdownListItem(blocks: []),
      ]
    )

    #expect(
      MarkdownBlockLayout.alignedListMarker(
        list,
        item: list.items[0],
        index: 0,
        width: MarkdownBlockLayout.listMarkerWidth(list)
      )
        == " 9."
    )
    #expect(
      MarkdownBlockLayout.alignedListMarker(
        list,
        item: list.items[1],
        index: 1,
        width: MarkdownBlockLayout.listMarkerWidth(list)
      )
        == "10."
    )
    #expect(MarkdownBlockLayout.listContentWidth(list, offeredWidth: 12) == 8)
  }

  @Test("table metrics cache is identity-keyed with LRU eviction")
  func tableMetricsCacheReuse() {
    let table = MarkdownTable(
      header: [[InlineRun(text: "Name")], [InlineRun(text: "Value")]],
      rows: [
        [[InlineRun(text: "alpha")], [InlineRun(text: "one")]]
      ],
      alignments: [.leading, .trailing]
    )
    let cache = MarkdownTableLayoutCache(capacity: 2)

    let first = cache.metrics(for: table, identity: BlockID("t:1"), contentRevision: 1)
    let reused = cache.metrics(for: table, identity: BlockID("t:1"), contentRevision: 1)

    #expect(reused == first)
    #expect(cache.statistics.entryCount == 1)
    #expect(cache.statistics.computationCount == 1)
    #expect(cache.statistics.hitCount == 1)

    // A reload bumps the revision: same identity recomputes, never reuses.
    _ = cache.metrics(for: table, identity: BlockID("t:1"), contentRevision: 2)
    #expect(cache.statistics.computationCount == 2)

    // Third distinct key at capacity 2 evicts the least-recently used.
    _ = cache.metrics(for: table, identity: BlockID("t:2"), contentRevision: 2)
    #expect(cache.statistics.entryCount == 2)
    #expect(cache.statistics.computationCount == 3)
    #expect(cache.statistics.evictionCount == 1)
  }

  @Test("table metrics are width-independent so the key needs no viewport bucket")
  func tableMetricsWidthIndependence() {
    let table = MarkdownTable(
      header: [[InlineRun(text: String(repeating: "wide-header ", count: 12))]],
      rows: [[[InlineRun(text: String(repeating: "wide-content ", count: 20))]]],
      alignments: [.leading]
    )
    let metrics = MarkdownTableLayout.metrics(for: table)
    // Column widths derive from content clamped to [3, 32]; nothing about the
    // offered viewport reaches the computation. This is the invariant that
    // lets the cache key drop the width axis.
    #expect(metrics.columnWidths.allSatisfy { $0 >= 3 && $0 <= 32 })
  }

  @Test("model-owned caches keep colliding BlockIDs from crossing documents")
  @MainActor
  func tableMetricsCacheCrossModelIsolation() {
    // BlockIDs are source-position strings, so two different documents mint
    // identical IDs for a table at the same position. Instance-scoped caches
    // must never serve one document's metrics for the other's table.
    let narrow = MarkdownTable(
      header: [[InlineRun(text: "a")]],
      rows: [[[InlineRun(text: "b")]]],
      alignments: [.leading]
    )
    let wide = MarkdownTable(
      header: [[InlineRun(text: String(repeating: "wide ", count: 8))]],
      rows: [[[InlineRun(text: String(repeating: "cell ", count: 8))]]],
      alignments: [.leading]
    )
    let id = BlockID("table:3:1-5:10")
    let first = MarkdownTableLayoutCache(capacity: 4)
    let second = MarkdownTableLayoutCache(capacity: 4)
    let narrowMetrics = first.metrics(for: narrow, identity: id, contentRevision: 1)
    let wideMetrics = second.metrics(for: wide, identity: id, contentRevision: 1)
    #expect(narrowMetrics != wideMetrics)
    #expect(wideMetrics.columnWidths == [32])
  }

  @Test("concurrent table metrics requests compute one cache entry")
  func concurrentTableMetricsCacheReuse() async {
    let table = MarkdownTable(
      header: [[InlineRun(text: "Concurrent")]],
      rows: [
        [[InlineRun(text: String(repeating: "content ", count: 12))]]
      ],
      alignments: [.leading]
    )
    let cache = MarkdownTableLayoutCache(capacity: 2)

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<16 {
        group.addTask {
          _ = cache.metrics(for: table, identity: BlockID("t:1"), contentRevision: 1)
        }
      }
    }

    #expect(cache.statistics.entryCount == 1)
    #expect(cache.statistics.computationCount == 1)
    #expect(cache.statistics.hitCount == 15)
  }

  @Test("table viewport slicing preserves full height and selects intersecting rows")
  func tableViewportSlicing() {
    let table = MarkdownTable(
      header: [[InlineRun(text: "Header")]],
      rows: (0..<500).map {
        [[InlineRun(text: "r\($0)")]]
      },
      alignments: [.leading]
    )
    let metrics = MarkdownTableLayout.metrics(for: table)

    let slice = MarkdownTableLayout.visibleSlice(
      metrics,
      tableTop: 40,
      documentScrollOffset: 140,
      viewportHeight: 20,
      overscan: 0
    )

    #expect(slice.rows == 100..<120)
    #expect(slice.topSpacerHeight == 100)
    #expect(slice.bottomSpacerHeight == 382)
    #expect(
      slice.topSpacerHeight + slice.renderedHeight(in: metrics)
        + slice.bottomSpacerHeight == metrics.totalHeight
    )

    let beforeTable = MarkdownTableLayout.visibleSlice(
      metrics,
      tableTop: 100,
      documentScrollOffset: 0,
      viewportHeight: 20,
      overscan: 0
    )
    #expect(beforeTable.rows.isEmpty)
    #expect(beforeTable.topSpacerHeight == 0)
    #expect(beforeTable.bottomSpacerHeight == metrics.totalHeight)
  }

  @Test("wrapped table row heights match rendered geometry")
  func wrappedTableGeometry() throws {
    let table = MarkdownTable(
      header: [[InlineRun(text: "Header")]],
      rows: [
        [[InlineRun(text: String(repeating: "x", count: 65))]]
      ],
      alignments: [.leading]
    )
    let metrics = MarkdownTableLayout.metrics(for: table)

    #expect(metrics.columnWidths == [32])
    #expect(metrics.headerRowHeight == 1)
    #expect(metrics.bodyRowHeights == [3])
    #expect(metrics.totalHeight == 5)

    let geometry = MarkdownBlockLayout.renderedGeometry(
      [
        .table(
          id: BlockID("wrapped-table"),
          value: table,
          source: nil
        )
      ],
      inputs: .init(),
      offeredWidth: 80
    )

    #expect(try #require(geometry.first).height == metrics.totalHeight)

    let artifacts = DefaultRenderer().render(
      MarkdownTableView(
        table: table,
        theme: .default,
        searchQuery: nil,
        offeredWidth: 80,
        tableTop: 0,
        documentScrollOffset: 0,
        viewportHeight: 20,
        horizontalScrollPosition: nil
      ),
      context: .init(identity: Identity(components: [.named("WrappedTable")])),
      proposal: ProposedSize(width: 80, height: metrics.totalHeight)
    )
    #expect(artifacts.rasterSurface.lines.count == metrics.totalHeight)
    #expect(
      artifacts.rasterSurface.lines.filter { $0.contains("│") }.count
        == metrics.headerRowHeight + metrics.bodyRowHeights[0]
    )
  }

  @Test("loose-list geometry preserves zero spacing around nested and following tables")
  func looseListGeometry() throws {
    let document = MarkdownCompiler().compile(
      source: """
        - first paragraph

          second paragraph

          | Nested |
          | --- |
          | value |

        ## Later

        | Following |
        | --- |
        | value |
        """,
      sourceURL: nil
    )
    let descriptors = MarkdownBlockLayout.flattened(document.blocks, offeredWidth: 80)
    let geometry = MarkdownBlockLayout.renderedGeometry(
      document.blocks,
      inputs: .init(),
      offeredWidth: 80
    )
    let entriesByID = Dictionary(
      uniqueKeysWithValues: geometry.map { ($0.blockID, $0) }
    )
    let tables = descriptors.compactMap { descriptor -> MarkdownBlock? in
      if case .table = descriptor.block { return descriptor.block }
      return nil
    }
    let heading = try #require(
      descriptors.map(\.block).first {
        if case .heading = $0 { return true }
        return false
      }
    )
    let paragraphs = descriptors.compactMap { descriptor -> MarkdownBlock? in
      if case .paragraph = descriptor.block { return descriptor.block }
      return nil
    }

    #expect(tables.count == 2)
    #expect(paragraphs.count == 2)
    let firstParagraph = try #require(entriesByID[paragraphs[0].id])
    let secondParagraph = try #require(entriesByID[paragraphs[1].id])
    let nestedTable = try #require(entriesByID[tables[0].id])
    let laterHeading = try #require(entriesByID[heading.id])
    let followingTable = try #require(entriesByID[tables[1].id])

    #expect(secondParagraph.top == firstParagraph.top + firstParagraph.height)
    #expect(nestedTable.top == secondParagraph.top + secondParagraph.height)
    #expect(laterHeading.top == nestedTable.top + nestedTable.height + 1)
    #expect(followingTable.top == laterHeading.top + laterHeading.height + 1)
  }

  @Test(
    "table wheel routing preserves outer Y and reaches a wide final column",
    .timeLimit(.minutes(1))
  )
  func verticalWheelRoutesToDocument() async throws {
    let positions = TableScrollRoutingApp.positions
    positions.document.withLock { $0 = .zero }
    positions.table.withLock { $0 = .zero }
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 80, height: 24),
      appearance: .fallback
    ) { _ in }
    let session = try HostedSceneSession(
      for: TableScrollRoutingApp(),
      sceneID: TableScrollRoutingApp.sceneID,
      surface: surface
    )
    let task = Task {
      try await session.start()
    }

    do {
      let initial = await surface.waitForFrame { frame in
        frame.semantics.scrollRoutes.contains(where: isVerticalScrollRoute)
          && frame.semantics.scrollRoutes.contains(where: isHorizontalOnlyScrollRoute)
      }
      let documentRoute = try #require(
        initial.semantics.scrollRoutes.first(where: isVerticalScrollRoute)
      )
      let tableRoute = try #require(
        initial.semantics.scrollRoutes.first(where: isHorizontalOnlyScrollRoute)
      )
      let location = Point(
        CellPoint(
          x: max(documentRoute.viewportRect.origin.x, tableRoute.viewportRect.origin.x) + 1,
          y: max(documentRoute.viewportRect.origin.y, tableRoute.viewportRect.origin.y) + 1
        )
      )

      session.send(
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: 3),
            location: location
          )
        )
      )
      let verticallyScrolled = await surface.waitForFrame { frame in
        frame.semantics.scrollRoutes.contains {
          isVerticalScrollRoute($0) && $0.contentOffset.y == 3
        }
      }

      #expect(positions.document.withLock { $0.y } == 3)
      #expect(positions.table.withLock { $0.y } == 0)
      #expect(
        verticallyScrolled.semantics.scrollRoutes.contains {
          isHorizontalOnlyScrollRoute($0) && $0.contentOffset.y == 0
        }
      )

      session.send(
        .mouse(
          .init(
            kind: .scrolled(deltaX: 3, deltaY: 0),
            location: location
          )
        )
      )
      _ = await surface.waitForFrame { frame in
        frame.semantics.scrollRoutes.contains {
          isHorizontalOnlyScrollRoute($0) && $0.contentOffset.x == 3
        }
      }

      #expect(positions.document.withLock { $0.y } == 3)
      #expect(positions.table.withLock { $0.x } == 3)

      session.send(
        .mouse(
          .init(
            kind: .scrolled(deltaX: 10_000, deltaY: 0),
            location: location
          )
        )
      )
      let farRight = await surface.waitForFrame { frame in
        frame.semantics.scrollRoutes.contains {
          isHorizontalOnlyScrollRoute($0) && $0.contentOffset.x > 3
        }
      }

      #expect(positions.document.withLock { $0.y } == 3)
      #expect(positions.table.withLock { $0.x } > 3)
      #expect(
        farRight.raster.lines.joined(separator: "\n")
          .contains("FINAL-COLUMN-MARKER")
      )
      session.send(.key(.init(.character("d"), modifiers: .ctrl)))
      _ = try await task.value
    } catch {
      session.stop()
      _ = try? await task.value
      throw error
    }
  }

  @Test("inline code paints the configured foreground and background")
  func inlineCodeTheme() {
    let theme = ViewerTheme.default
    let artifacts = DefaultRenderer().render(
      InlineTextView(
        runs: [InlineRun(text: "code", traits: .code)],
        theme: theme
      ),
      context: .init(identity: Identity(components: [.named("InlineCode")]))
    )
    let cells = artifacts.rasterSurface.cells[0]
    #expect(
      cells.prefix(4).allSatisfy {
        $0.style?.foregroundColor == theme.codeForeground.swiftTUIColor
      })
    #expect(
      cells.prefix(4).allSatisfy {
        $0.style?.backgroundColor == theme.codeBackground.swiftTUIColor
      })
  }

  @Test("dense visible-block highlighting preserves text within one bounded segment budget")
  func denseVisibleBlockHighlighting() {
    let source = String(
      repeating: "a",
      count: SearchIndex.maximumScannedCharacters
    )
    let segments = InlineTextView.highlightedSegments(
      runs: [InlineRun(text: source)],
      searchQuery: "a"
    )

    #expect(
      segments.count
        <= (SearchIndex.maximumRetainedMatches * 2) + 1
    )
    #expect(segments.lazy.filter(\.highlighted).count == SearchIndex.maximumRetainedMatches)
    #expect(segments.lazy.map(\.text).joined() == source)
  }

  @Test("highlight cache returns exactly the direct segmentation")
  func highlightCacheMatchesDirectSegmentation() {
    // The cache delegates to the pure function; this oracle pins that lookups
    // return the *right* entry across the shapes that stress the key: traits,
    // links, multiple matches inside one run, and case/diacritic folding.
    let shapes: [[InlineRun]] = [
      [InlineRun(text: "plain engine text")],
      [
        InlineRun(text: "bold engine", traits: .strong),
        InlineRun(text: " and linked engine", destination: "https://example.invalid"),
      ],
      [InlineRun(text: "engine ENGINE éngine engine")],
      [InlineRun(text: ""), InlineRun(text: "engine")],
    ]
    let cache = InlineHighlightCache(capacity: 16)
    for runs in shapes {
      for query in ["engine", "ENGINE", "éngine"] {
        let direct = InlineTextView.highlightedSegments(runs: runs, searchQuery: query)
        // Miss then hit: both must equal the direct computation.
        #expect(cache.segments(runs: runs, searchQuery: query) == direct)
        #expect(cache.segments(runs: runs, searchQuery: query) == direct)
      }
    }
  }

  @Test("repeated highlight lookups compute once per (runs, query)")
  func highlightCacheComputesOncePerKey() {
    let cache = InlineHighlightCache(capacity: 16)
    let runs = [InlineRun(text: "the engine feeds the raster")]

    for _ in 0..<8 {
      _ = cache.segments(runs: runs, searchQuery: "engine")
    }
    #expect(cache.statistics.computationCount == 1)
    #expect(cache.statistics.hitCount == 7)

    // A different query is a different key; the empty query bypasses the
    // cache entirely (identity segmentation is cheaper than a lookup).
    _ = cache.segments(runs: runs, searchQuery: "raster")
    #expect(cache.statistics.computationCount == 2)
    _ = cache.segments(runs: runs, searchQuery: nil)
    _ = cache.segments(runs: runs, searchQuery: "")
    #expect(cache.statistics.computationCount == 2)
    #expect(cache.statistics.entryCount == 2)
  }

  @Test("content proposals subtract document padding and semantic nesting")
  func contentWidthAccounting() {
    let viewport = ViewerSize(width: 100, height: 24)
    #expect(viewport.documentFrameWidth == 96)
    #expect(viewport.documentWidth == 94)
    #expect(viewport.documentHeight == 20)

    let nested = MarkdownCompiler().compile(
      source: """
        > - ```mermaid
        >   flowchart LR
        >   A --> B
        >   ```
        """,
      sourceURL: nil
    )
    let descriptor = MarkdownBlockLayout.flattened(
      nested.blocks,
      offeredWidth: viewport.documentWidth
    ).first {
      if case .mermaid = $0.block { return true }
      return false
    }
    #expect(descriptor != nil)
    #expect(descriptor?.offeredWidth ?? viewport.documentWidth < viewport.documentWidth)
  }

  @Test("unavailable Mermaid reveals its source once with matching geometry")
  func unavailableMermaidSourceGeometry() throws {
    let id = BlockID("unavailable-mermaid")
    let source = "flowchart LR\nUNIQUE-SOURCE --> END"
    var inputs = MarkdownBlockLayout.GeometryInputs()
    inputs.mermaid[id] = .unavailable(diagnostic: "renderer unavailable")
    inputs.revealedMermaidSources.insert(id)
    let block = MarkdownBlock.mermaid(
      id: id,
      value: MermaidBlock(source: source),
      source: nil
    )
    let geometry = try #require(
      MarkdownBlockLayout.renderedGeometry(
        [block],
        inputs: inputs,
        offeredWidth: 80
      ).first
    )
    let artifacts = DefaultRenderer().render(
      MermaidBlockView(
        blockID: id,
        source: source,
        presentation: inputs.mermaid[id],
        theme: .default,
        offeredWidth: 80,
        revealsSource: true
      ),
      context: .init(identity: Identity(components: [.named("UnavailableMermaid")])),
      proposal: ProposedSize(width: 80, height: nil)
    )
    let lines = artifacts.rasterSurface.lines
    let text = lines.joined(separator: "\n")

    #expect(text.components(separatedBy: "UNIQUE-SOURCE").count - 1 == 1)
    #expect(lines.count == geometry.height)
  }

  @Test("wrapped Mermaid diagnostics match narrow-width geometry")
  func wrappedMermaidDiagnosticGeometry() throws {
    let id = BlockID("wrapped-mermaid-diagnostic")
    let source = "flowchart LR\nA --> B"
    let diagnostic = String(repeating: "renderer unavailable ", count: 5)
    let width = 24
    var inputs = MarkdownBlockLayout.GeometryInputs()
    inputs.mermaid[id] = .unavailable(diagnostic: diagnostic)
    let block = MarkdownBlock.mermaid(
      id: id,
      value: MermaidBlock(source: source),
      source: nil
    )
    let geometry = try #require(
      MarkdownBlockLayout.renderedGeometry(
        [block],
        inputs: inputs,
        offeredWidth: width
      ).first
    )
    let artifacts = DefaultRenderer().render(
      MermaidBlockView(
        blockID: id,
        source: source,
        presentation: inputs.mermaid[id],
        theme: .default,
        offeredWidth: width,
        revealsSource: false
      ),
      context: .init(identity: Identity(components: [.named("WrappedMermaidDiagnostic")])),
      proposal: ProposedSize(width: width, height: nil)
    )

    #expect(artifacts.rasterSurface.lines.count == geometry.height)
  }

  @Test("wrapped image fallback metadata matches narrow-width geometry")
  func wrappedImageFallbackGeometry() throws {
    let id = BlockID("wrapped-image-fallback")
    let width = 24
    let reference = ImageReference(
      source: "custom://host/a/very/long/image/destination.png",
      altText: "A detailed architecture diagram with many components",
      title: "System overview for the complete deployment"
    )
    let diagnostic = String(repeating: "image scheme unsupported ", count: 4)
    var inputs = MarkdownBlockLayout.GeometryInputs()
    inputs.images[id] = .failed(
      resolvedURL: URL(string: reference.source),
      diagnostic: diagnostic
    )
    let block = MarkdownBlock.image(id: id, value: reference, source: nil)
    let geometry = try #require(
      MarkdownBlockLayout.renderedGeometry(
        [block],
        inputs: inputs,
        offeredWidth: width
      ).first
    )
    let artifacts = DefaultRenderer().render(
      ImageBlockView(
        image: reference,
        documentURL: nil,
        presentation: inputs.images[id],
        theme: .default
      ),
      context: .init(identity: Identity(components: [.named("WrappedImageFallback")])),
      proposal: ProposedSize(width: width, height: nil)
    )

    #expect(artifacts.rasterSurface.lines.count == geometry.height)
  }

  @Test("wrapped HTML and custom blocks match narrow-width geometry")
  func wrappedLiteralFallbackGeometry() throws {
    let width = 16
    let htmlSource = String(repeating: "<long-element>content</long-element>", count: 3)
    let unsupportedKind = String(repeating: "custom-extension-", count: 3)
    let unsupportedSource = String(repeating: "custom payload ", count: 5)
    let html = MarkdownBlock.html(
      id: BlockID("wrapped-html"),
      sourceText: htmlSource,
      source: nil
    )
    let unsupported = MarkdownBlock.unsupported(
      id: BlockID("wrapped-custom"),
      kind: unsupportedKind,
      sourceText: unsupportedSource,
      source: nil
    )
    let geometry = MarkdownBlockLayout.renderedGeometry(
      [html, unsupported],
      inputs: .init(),
      offeredWidth: width
    )
    let htmlArtifacts = DefaultRenderer().render(
      Text(htmlSource)
        .padding(.init(horizontal: 1, vertical: 0)),
      context: .init(identity: Identity(components: [.named("WrappedHTML")])),
      proposal: ProposedSize(width: width, height: nil)
    )
    let unsupportedArtifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Unsupported Markdown: \(unsupportedKind)")
        Text(unsupportedSource)
      },
      context: .init(identity: Identity(components: [.named("WrappedCustom")])),
      proposal: ProposedSize(width: width, height: nil)
    )

    #expect(try #require(geometry.first).height == htmlArtifacts.rasterSurface.lines.count)
    #expect(try #require(geometry.last).height == unsupportedArtifacts.rasterSurface.lines.count)
  }

  @Test("ForeignSurface rewrites continuation ownership at a nonzero origin")
  func nonzeroForeignSurfaceOrigin() throws {
    let rendered = RenderedMermaid(
      width: 3,
      height: 1,
      cells: [
        [
          MermaidPaintCell(character: "界", spanWidth: 2, role: .text),
          MermaidPaintCell(spanWidth: 0, continuationLeadX: 0, role: .text),
          MermaidPaintCell(character: "!", role: .title),
        ]
      ]
    )
    let artifacts = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("prefix")
        ForeignSurface(payload: MermaidForeignPayload(rendered: rendered, theme: .default))
          .frame(width: 3, height: 1)
      }
      .padding(.init(horizontal: 2, vertical: 1)),
      context: .init(identity: Identity(components: [.named("NonzeroMermaid")])),
      proposal: ProposedSize(width: 20, height: 3)
    )
    let row = try #require(
      artifacts.rasterSurface.cells.first { $0.contains { $0.character == "界" } }
    )
    let leader = try #require(row.firstIndex { $0.character == "界" })
    #expect(leader > 0)
    #expect(row[leader].spanWidth == 2)
    #expect(row[leader + 1].spanWidth == 0)
    #expect(row[leader + 1].continuationLeadX == leader)
  }

  @Test("every image state keeps alt, title, and destination visibly accessible")
  func imageFallbackMetadata() {
    let reference = ImageReference(
      source: "custom://host/image.png",
      altText: "Architecture diagram",
      title: "System overview"
    )
    let artifacts = DefaultRenderer().render(
      ImageBlockView(
        image: reference,
        documentURL: URL(fileURLWithPath: "/docs/readme.md"),
        presentation: .failed(
          resolvedURL: URL(string: reference.source),
          diagnostic: "image scheme 'custom' is unsupported"
        ),
        theme: .default
      ),
      context: .init(identity: Identity(components: [.named("ImageFallback")]))
    )
    let text = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("Architecture diagram"))
    #expect(text.contains("System overview"))
    #expect(text.contains("custom://host/image.png"))
    #expect(text.contains("unsupported"))
    #expect(
      artifacts.semanticSnapshot.accessibilityNodes.contains {
        $0.label?.contains("Architecture diagram") == true
          && $0.label?.contains("System overview") == true
      }
    )
  }
}

private final class TableScrollRoutingPositions: Sendable {
  let document = Mutex(ScrollPosition.zero)
  let table = Mutex(ScrollPosition.zero)

  var documentBinding: Binding<ScrollPosition> {
    Binding(
      get: { self.document.withLock { $0 } },
      set: { next in self.document.withLock { $0 = next } }
    )
  }

  var tableBinding: Binding<ScrollPosition> {
    Binding(
      get: { self.table.withLock { $0 } },
      set: { next in self.table.withLock { $0 = next } }
    )
  }
}

private struct TableScrollRoutingApp: App {
  static let sceneID = WindowIdentifier("table-scroll-routing")
  static let positions = TableScrollRoutingPositions()

  var body: some Scene {
    WindowGroup("Table scroll routing", id: Self.sceneID) {
      ScrollView(
        .vertical,
        showsIndicators: true,
        position: Self.positions.documentBinding
      ) {
        MarkdownTableView(
          table: Self.table,
          theme: .default,
          searchQuery: nil,
          offeredWidth: 80,
          tableTop: 0,
          documentScrollOffset: Self.positions.document.withLock { $0.y },
          viewportHeight: 20,
          horizontalScrollPosition: Self.positions.tableBinding
        )
      }
      .frame(width: 80, height: 20, alignment: .topLeading)
    }
  }

  private static let table = MarkdownTable(
    header: (0..<20).map { column in
      [
        InlineRun(
          text: column == 19
            ? "FINAL-COLUMN-MARKER"
            : column.isMultiple(of: 2)
              ? "C\(column)"
              : String(repeating: "wide-\(column)-", count: 4)
        )
      ]
    },
    rows: (0..<100).map { row in
      (0..<20).map { column in
        [
          InlineRun(
            text: column == 19
              ? "FINAL-COLUMN-MARKER-\(row)"
              : "row-\(row)-column-\(column)"
          )
        ]
      }
    },
    alignments: Array(repeating: .leading, count: 20)
  )
}

private func isVerticalScrollRoute(_ route: ScrollRoute) -> Bool {
  route.contentBounds.size.height > route.viewportRect.size.height
}

private func isHorizontalOnlyScrollRoute(_ route: ScrollRoute) -> Bool {
  route.contentBounds.size.width > route.viewportRect.size.width
    && route.contentBounds.size.height <= route.viewportRect.size.height
}
