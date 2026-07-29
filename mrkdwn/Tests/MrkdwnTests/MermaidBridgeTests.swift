import SwiftTUI
import Testing

@testable import Mrkdwn

@Suite("MrkdwnMermaid bridge")
struct MermaidBridgeTests {
  @Test("adapter measures and renders one semantic surface")
  func semanticSurface() async {
    let request = MermaidRenderRequest(
      blockID: BlockID("diagram"),
      source: "flowchart LR\nA[Start 👩🏽‍💻] --> B[Finish]",
      width: 60
    )
    let presentation = await MrkdwnMermaidAdapter.render(request)
    guard case .ready(let rendered) = presentation else {
      Issue.record("Expected a rendered Mermaid surface")
      return
    }

    #expect(rendered.width > 0)
    #expect(rendered.height > 0)
    #expect(rendered.cells.count == rendered.height)
    #expect(rendered.cells.allSatisfy { $0.count == rendered.width })
    #expect(rendered.cells.flatMap { $0 }.contains { $0.role == .border })
  }

  @Test("ForeignGrid preserves wide leaders and continuation ownership")
  func continuationBridge() throws {
    let rendered = RenderedMermaid(
      width: 3,
      height: 1,
      cells: [
        [
          MermaidPaintCell(character: "界", spanWidth: 2, role: .text),
          MermaidPaintCell(spanWidth: 0, continuationLeadX: 0, role: .text),
          MermaidPaintCell(character: "!", spanWidth: 1, role: .title),
        ]
      ]
    )
    let grid = MermaidForeignPayload(rendered: rendered, theme: .default).grid
    #expect(grid.size == CellSize(width: 3, height: 1))
    #expect(grid.cells[0][0].character == "界")
    #expect(grid.cells[0][0].spanWidth == 2)
    #expect(grid.cells[0][1].spanWidth == 0)
    #expect(grid.cells[0][1].continuationLeadX == 0)
  }

  @Test("Mermaid work limiter never exceeds two concurrent jobs")
  func boundedConcurrency() async throws {
    let limiter = AsyncJobLimiter(limit: 2)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask {
          try await limiter.run {
            try await Task.sleep(for: .milliseconds(10))
          }
        }
      }
      try await group.waitForAll()
    }
    #expect(await limiter.peakActiveJobs == 2)
  }

  @Test("concurrent identical renders retain one cache entry")
  func duplicateRenderCacheAccounting() async {
    let coordinator = MermaidRenderCoordinator()
    let request = MermaidRenderRequest(
      blockID: BlockID("same-diagram"),
      source: "flowchart LR\nA --> B",
      width: 48
    )
    await withTaskGroup(of: MermaidPresentation.self) { group in
      for _ in 0..<8 {
        group.addTask { await coordinator.render(request) }
      }
      for await _ in group {}
    }
    let occupancy = await coordinator.occupancy
    #expect(occupancy.entries == 1)
    #expect(occupancy.bytes > 0)
    #expect(occupancy.bytes <= 4 * 1_024 * 1_024)
  }

  @Test("cache accounting includes retained request keys")
  func requestKeyCacheAccounting() {
    let source = String(repeating: "node", count: 256)
    let request = MermaidRenderRequest(
      blockID: BlockID("large-source-key"),
      source: source,
      width: 48
    )
    let emptyKeyRequest = MermaidRenderRequest(
      blockID: BlockID(""),
      source: "",
      width: 48
    )
    let presentation = MermaidPresentation.ready(
      RenderedMermaid(
        width: 1,
        height: 1,
        cells: [[MermaidPaintCell(character: "A", role: .text)]]
      )
    )
    let cost = MermaidRenderCoordinator.estimatedBytes(
      of: presentation,
      request: request
    )
    let emptyKeyCost = MermaidRenderCoordinator.estimatedBytes(
      of: presentation,
      request: emptyKeyRequest
    )
    #expect(
      cost - emptyKeyCost
        == source.utf8.count + request.blockID.rawValue.utf8.count
    )
  }

  @Test(
    "all six declared families bridge partial reports at narrow widths",
    arguments: [
      "flowchart LR\nA[Start] --> B[Done]",
      "stateDiagram-v2\n[*] --> Idle\nIdle --> Running: start",
      "sequenceDiagram\nparticipant A\nparticipant B\nA->>B: hello",
      "classDiagram\nclass Animal\nAnimal <|-- Duck",
      "erDiagram\nCUSTOMER ||--o{ ORDER : places",
      "xychart-beta\nx-axis [A, B]\ny-axis 0 --> 10\nbar [4, 8]",
    ]
  )
  func familyMatrix(source: String) async {
    let request = MermaidRenderRequest(
      blockID: BlockID("family-\(source.prefix(8))"),
      source: source,
      width: 1,
      configuration: .init(glyphMode: .unicode, ambiguousWidth: .narrow)
    )
    guard case .ready(let rendered) = await MermaidRenderCoordinator().render(request) else {
      Issue.record("Expected the family to bridge into a terminal surface")
      return
    }
    #expect(rendered.width > 0)
    #expect(rendered.height > 0)
    #expect(rendered.cells.count == rendered.height)
  }

  @Test("partial diagnostics and ASCII glyph policy survive the bridge")
  func partialAndASCII() async {
    let presentation = await MermaidRenderCoordinator().render(
      MermaidRenderRequest(
        blockID: BlockID("partial-ascii"),
        source: "flowchart LR\nA --> B\nstyle A fill:#fff",
        width: 40,
        configuration: .init(glyphMode: .ascii, ambiguousWidth: .wide)
      )
    )
    guard case .ready(let rendered) = presentation else {
      Issue.record("Expected a partial rendered surface")
      return
    }
    #expect(rendered.isPartial)
    #expect(!rendered.diagnostics.isEmpty)
    #expect(
      rendered.cells.flatMap { $0 }.allSatisfy {
        $0.character.unicodeScalars.allSatisfy { $0.isASCII }
      }
    )
  }

  @Test("renderer configuration participates in request and cache identity")
  func configurationIdentity() async {
    let coordinator = MermaidRenderCoordinator()
    let base = MermaidRenderRequest(
      blockID: BlockID("configuration"),
      source: "flowchart LR\nA[·] --> B",
      width: 40,
      configuration: .init(glyphMode: .unicode, ambiguousWidth: .narrow)
    )
    var wide = base
    wide.configuration.ambiguousWidth = .wide
    var ascii = base
    ascii.configuration.glyphMode = .ascii
    #expect(base != wide)
    #expect(base != ascii)
    _ = await coordinator.render(base)
    _ = await coordinator.render(wide)
    _ = await coordinator.render(ascii)
    #expect(await coordinator.occupancy.entries == 3)
  }
}
