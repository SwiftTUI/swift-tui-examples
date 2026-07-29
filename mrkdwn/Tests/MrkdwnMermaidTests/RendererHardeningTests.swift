import Foundation
import Testing

@testable import MrkdwnMermaid

@Suite
struct RendererHardeningTests {
  @Test(
    arguments: [
      "NaN --> 10",
      "-NaN --> 10",
      "0 --> inf",
      "-inf --> 10",
      "-1e999 --> 10",
      "0 --> 1e999",
      "10 --> 0",
      "1 --> 1",
    ]
  )
  func invalidXYAxesAreRecoverableAndNeverTrap(axis: String) {
    let source =
      """
      xychart-beta
        x-axis [A, B]
        y-axis \(axis)
        line [1, 2]
      """
    let renderer = MermaidRenderer()
    let report = renderer.renderSurface(source, forWidth: 20)

    #expect(report.fidelity == .partial)
    #expect(report.output != nil)
    #expect(report.output?.size.width ?? 21 <= 20)
    #expect(report.diagnostics.contains { $0.code == .contentElided })
  }

  @Test
  func extremeFiniteXYAxisUsesStableNormalization() {
    let source =
      """
      xychart-beta
        x-axis [low, high]
        y-axis -1e308 --> 1e308
        line [-1e308, 1e308]
      """
    let renderer = MermaidRenderer()
    let metrics = renderer.layoutMetrics(for: source)
    #expect(metrics.fidelity == .complete)
    guard let metrics = metrics.output else { return }

    for width in metrics.minimumWidth...metrics.idealSize.width {
      let report = renderer.renderSurface(source, forWidth: width)
      #expect(report.fidelity == .complete)
      #expect(report.output?.size.width ?? width + 1 <= width)
      #expect(report.output?.serialized().contains("-1e+308") == true)
      #expect(report.output?.serialized().contains("1e+308") == true)
    }
  }

  @Test
  func denseXYAggregatesGeometryButRetainsEveryAuthoredValue() throws {
    let source = try fixture("xy/dense.mmd")
    let renderer = MermaidRenderer()
    let metrics = try #require(renderer.layoutMetrics(for: source).output)

    for width in metrics.minimumWidth...metrics.idealSize.width {
      let measured = renderer.measure(source, forWidth: width)
      let rendered = renderer.renderSurface(source, forWidth: width)
      let surface = try #require(rendered.output)
      #expect(measured.output == surface.size)
      #expect(surface.size.width <= width)
      let text = surface.serialized()
      let unwrapped = text.replacingOccurrences(of: "\n", with: "")
      for index in 0..<40 {
        #expect(unwrapped.contains(formatIndex(index)))
      }
      #expect(unwrapped.contains("-18"))
      #expect(unwrapped.contains("40"))
    }
  }

  @Test
  func connectorTokenizerIgnoresQuotedAndBracketedSyntax() throws {
    let source = try fixture("flowchart/scoped-connectors.mmd")
    let report = MermaidRenderer().renderSurface(source, forWidth: 64)
    let text = try #require(report.output?.serialized())

    #expect(report.fidelity == .complete)
    #expect(text.contains("x --> y; [nested]"))
    #expect(text.contains("\"quoted\": ok"))
    #expect(text.contains("right: -->; done"))
    #expect(!report.diagnostics.contains { $0.code == .contentElided })
  }

  @Test(
    arguments: [
      "A[label --> inside]",
      "A(label --> inside)",
      "A{label --> inside}",
      "A[[label --> inside]]",
      "A((label --> inside))",
      "A[(label --> inside)]",
      "A([label --> inside])",
      "A{{label --> inside}}",
      "A>label --> inside]",
    ]
  )
  func connectorTokenizerTracksEveryDeclaredNodeShape(leftNode: String) throws {
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\n\(leftNode) --> B[Done]",
      forWidth: 56
    )
    let text = try #require(report.output?.serialized())

    #expect(report.fidelity == .complete)
    #expect(text.contains("label --> inside"))
    #expect(text.contains("[A]"))
    #expect(text.contains("[-->] B"))
  }

  @Test
  func declaredConnectorGrammarPreservesEndpointSemantics() throws {
    let flowchartCases:
      [(
        connector: String, start: MermaidEdgeEndpoint, end: MermaidEdgeEndpoint,
        line: MermaidEdgeLine
      )] =
        [
          ("---", .none, .none, .solid),
          ("-->", .none, .arrow, .solid),
          ("<-->", .arrow, .arrow, .solid),
          ("--o", .none, .circle, .solid),
          ("o--o", .circle, .circle, .solid),
          ("--x", .none, .cross, .solid),
          ("x--x", .cross, .cross, .solid),
          ("-.->", .none, .arrow, .dotted),
          ("==>", .none, .arrow, .thick),
        ]

    for testCase in flowchartCases {
      let report = parser().parse("flowchart LR\nA \(testCase.connector) B")
      let diagram = try #require(report.output)
      let edge = try #require(diagram.edges.first)

      #expect(report.fidelity == .complete)
      #expect(edge.connector == testCase.connector)
      #expect(edge.startEndpoint == testCase.start)
      #expect(edge.endEndpoint == testCase.end)
      #expect(edge.line == testCase.line)
      #expect(edge.from == "A")
      #expect(edge.to == "B")
    }

    let renderedFlowchart =
      "flowchart LR\n"
      + flowchartCases.enumerated().map { index, testCase in
        "A \(testCase.connector) B\(index)"
      }.joined(separator: "\n")
    let renderedFlowchartReport = MermaidRenderer().renderSurface(
      renderedFlowchart,
      forWidth: 64
    )
    let renderedFlowchartText = try #require(renderedFlowchartReport.output?.serialized())
    #expect(renderedFlowchartReport.fidelity == .complete)
    for (index, testCase) in flowchartCases.enumerated() {
      #expect(renderedFlowchartText.contains("[\(testCase.connector)] B\(index)"))
    }
    #expect(
      renderedFlowchartReport.output?.rows.flatMap { $0 }.contains { $0.role == .edge } == true
    )

    let compact = parser().parse("flowchart LR\nA---oB")
    let compactEdge = try #require(compact.output?.edges.first)
    #expect(compact.fidelity == .complete)
    #expect(compactEdge.connector == "---o")
    #expect(compactEdge.to == "B")
    #expect(compactEdge.endEndpoint == .circle)

    for (statement, expectedSource, expectedConnector, expectedTarget) in [
      ("go-->B", "go", "-->", "B"),
      ("box-->B", "box", "-->", "B"),
      ("foo---bar", "foo", "---", "bar"),
    ] {
      let report = parser().parse("flowchart LR\n\(statement)")
      let edge = try #require(report.output?.edges.first)

      #expect(report.fidelity == .complete)
      #expect(edge.from == expectedSource)
      #expect(edge.connector == expectedConnector)
      #expect(edge.to == expectedTarget)
    }

    let leftMarkers: [(String, MermaidEdgeEndpoint)] = [
      ("|o", .zeroOrOne), ("||", .exactlyOne), ("}o", .zeroOrMore), ("}|", .oneOrMore),
    ]
    let rightMarkers: [(String, MermaidEdgeEndpoint)] = [
      ("o|", .zeroOrOne), ("||", .exactlyOne), ("o{", .zeroOrMore), ("|{", .oneOrMore),
    ]
    for (left, startEndpoint) in leftMarkers {
      for line in ["--", ".."] {
        for (right, endEndpoint) in rightMarkers {
          let connector = left + line + right
          let report = parser().parse("erDiagram\nA \(connector) B : relates")
          let edge = try #require(report.output?.edges.first)

          #expect(report.fidelity == .complete)
          #expect(edge.connector == connector)
          #expect(edge.startEndpoint == startEndpoint)
          #expect(edge.endEndpoint == endEndpoint)
          #expect(edge.line == (line == ".." ? .dotted : .solid))
        }
      }
    }

    let parallel = MermaidRenderer().renderSurface(
      "flowchart LR\nA --> B: first\nA --> B: second",
      forWidth: 48
    )
    let parallelText = try #require(parallel.output?.serialized())
    #expect(parallel.fidelity == .complete)
    #expect(parallelText.components(separatedBy: "[-->] B").count - 1 == 2)
    #expect(parallelText.contains("first"))
    #expect(parallelText.contains("second"))
  }

  @Test
  func everyDeclaredFlowchartNodeShapeHasDistinctGeometry() throws {
    let shapeCases: [(source: String, shape: MermaidNodeShape)] = [
      ("A[Shape]", .rectangle),
      ("A(Shape)", .rounded),
      ("A([Shape])", .stadium),
      ("A[[Shape]]", .subroutine),
      ("A[(Shape)]", .cylinder),
      ("A((Shape))", .circle),
      ("A{Shape}", .diamond),
      ("A{{Shape}}", .hexagon),
      ("A>Shape]", .asymmetric),
    ]
    var unicodeSurfaces: Set<String> = []
    var asciiSurfaces: Set<String> = []
    var serializedUnicodeAsASCII: Set<String> = []

    for testCase in shapeCases {
      let source = "flowchart LR\n\(testCase.source)"
      let parsed = parser().parse(source)
      let node = try #require(parsed.output?.node(forID: "A"))
      let unicodeSurface = try #require(
        MermaidRenderer().renderSurface(source, forWidth: 32).output
      )
      let unicode = unicodeSurface.serialized()
      let ascii = try #require(
        MermaidRenderer(configuration: .init(glyphMode: .ascii))
          .renderSurface(source, forWidth: 32).output?.serialized(as: .ascii)
      )

      #expect(parsed.fidelity == .complete)
      #expect(node.shape == testCase.shape)
      unicodeSurfaces.insert(unicode)
      asciiSurfaces.insert(ascii)
      serializedUnicodeAsASCII.insert(unicodeSurface.serialized(as: .ascii))
    }

    for text in serializedUnicodeAsASCII {
      let nonASCII = text.unicodeScalars.filter { !$0.isASCII }
      #expect(nonASCII.isEmpty, "Unexpected non-ASCII structural scalars: \(nonASCII)")
    }
    #expect(unicodeSurfaces.count == shapeCases.count)
    #expect(asciiSurfaces.count == shapeCases.count)
    #expect(serializedUnicodeAsASCII.count == shapeCases.count)

    let retained = parser().parse(
      "flowchart LR\nA((Circle)) --> B[Box]\nA --> C[Other]"
    )
    #expect(retained.output?.node(forID: "A")?.shape == .circle)
  }

  @Test
  func unterminatedQuotedTokensNeverFabricateCompleteOutput() throws {
    let onlyMalformed = MermaidRenderer().renderSurface(
      "flowchart LR\nA[\"unterminated]",
      forWidth: 40
    )
    #expect(onlyMalformed.fidelity == .unavailable)
    #expect(onlyMalformed.output == nil)
    #expect(onlyMalformed.diagnostics.first?.code == .malformedDiagram)

    let recoverable = MermaidRenderer().renderSurface(
      "flowchart LR\nA --> B\nC[\"unterminated]",
      forWidth: 48
    )
    let recoverableText = try #require(recoverable.output?.serialized())
    #expect(recoverable.fidelity == .partial)
    #expect(recoverable.diagnostics.map(\.code) == [.contentElided])
    #expect(recoverableText.contains("[-->] B"))
    #expect(!recoverableText.contains("unterminated"))
    #expect(!recoverableText.contains("[C]"))

    let strictFinal = MermaidRenderer().renderSurface(
      "classDiagram\nclass A\nclass B[\"unterminated]",
      forWidth: 48
    )
    #expect(strictFinal.fidelity == .partial)
    #expect(strictFinal.diagnostics.map(\.code) == [.contentElided])

    let strictMiddle = MermaidRenderer().renderSurface(
      "classDiagram\nclass A[\"unterminated]\nclass B",
      forWidth: 48
    )
    #expect(strictMiddle.fidelity == .unavailable)
    #expect(strictMiddle.diagnostics.first?.code == .malformedDiagram)
  }

  @Test
  func unmatchedNodeDelimitersNeverFabricateCompleteOutput() throws {
    for malformed in [
      "A[foo]]",
      "A(foo))",
      "A{foo}}",
      "A[[foo]]]",
      "Afoo]",
      "A[foo[bar]",
      "A[foo)]",
    ] {
      let unavailable = MermaidRenderer().renderSurface(
        "flowchart LR\n\(malformed)",
        forWidth: 40
      )
      #expect(unavailable.fidelity == .unavailable)
      #expect(unavailable.output == nil)
      #expect(unavailable.diagnostics.first?.code == .malformedDiagram)

      let partial = MermaidRenderer().renderSurface(
        "flowchart LR\nGood --> Done\n\(malformed)",
        forWidth: 48
      )
      let text = try #require(partial.output?.serialized())
      #expect(partial.fidelity == .partial)
      #expect(partial.diagnostics.map(\.code) == [.contentElided])
      #expect(text.contains("[-->] Done"))
      #expect(!text.contains("foo"))
    }

    let balanced = MermaidRenderer().renderSurface(
      "flowchart LR\nA[\"quoted [nested] (label)\"]",
      forWidth: 48
    )
    #expect(balanced.fidelity == .complete)
    #expect(balanced.output?.serialized().contains("quoted [nested] (label)") == true)
  }

  @Test
  func xyTitlesMustBeQuoted() {
    let unquoted = MermaidRenderer().renderSurface(
      "xychart-beta\ntitle Requests\nline [1, 2]",
      forWidth: 48
    )
    let quoted = MermaidRenderer().renderSurface(
      "xychart-beta\ntitle \"Requests\"\nline [1, 2]",
      forWidth: 48
    )

    #expect(unquoted.fidelity == .unavailable)
    #expect(unquoted.output == nil)
    #expect(unquoted.diagnostics.first?.code == .malformedDiagram)
    #expect(quoted.fidelity == .complete)
    #expect(quoted.output?.serialized().contains("Requests") == true)
  }

  @Test
  func asciiSerializationOnlyMapsRendererStructuralGlyphs() throws {
    let source = "flowchart LR\nA[\"authored → ● ·\"] --> B[done]"
    for configuration in [
      MermaidConfiguration(),
      MermaidConfiguration(glyphMode: .ascii),
    ] {
      let report = MermaidRenderer(configuration: configuration)
        .renderSurface(source, forWidth: 52)
      let text = try #require(report.output?.serialized(as: .ascii))

      #expect(report.fidelity == .complete)
      #expect(text.contains("authored → ● ·"))
      #expect(!text.contains("┌"))
      #expect(!text.contains("▶"))
    }
  }

  @Test
  func exactHeadersDirectionsAndStrictStateBracesNeverFabricateSuccess() {
    for source in [
      "flowchart SIDEWAYS\nA --> B",
      "flowchart LR extra\nA --> B",
      "stateDiagram-v2 extra\nA --> B",
      "classDiagram-v2\nclass A",
      "flowchart LR\nA --> B\ndirection SIDEWAYS",
      "stateDiagram-v2\nA --> B\ndirection SIDEWAYS",
      "classDiagram\nclass A\ndirection SIDEWAYS",
      "stateDiagram-v2\nstate Parent {\nA --> B",
      "stateDiagram-v2\nA --> B\n}",
    ] {
      let report = MermaidRenderer().renderSurface(source, forWidth: 52)
      #expect(report.fidelity == .unavailable)
      #expect(report.output == nil)
      #expect(
        report.diagnostics.first?.code == .malformedDiagram
          || report.diagnostics.first?.code == .unsupportedDiagram
      )
    }
  }

  @Test
  func recognizedOmissionsArePartialAndNeverBecomeFabricatedNodes() throws {
    let sequence = MermaidRenderer().renderSurface(
      "sequenceDiagram\nparticipant A\nparticipant B\nA->>B: request\nactivate B",
      forWidth: 56
    )
    let classDiagram = MermaidRenderer().renderSurface(
      "classDiagram\nclass A\nclass B\nA --> B\nstyle A fill:red",
      forWidth: 56
    )
    let subgraph = MermaidRenderer().renderSurface(
      "flowchart TD\nsubgraph Multi Word Label\nA --> B\nend",
      forWidth: 56
    )
    let classText = try #require(classDiagram.output?.serialized())
    let subgraphText = try #require(subgraph.output?.serialized())

    #expect(sequence.fidelity == .partial)
    #expect(sequence.diagnostics.map(\.code) == [.unsupportedConstruct])
    #expect(classDiagram.fidelity == .partial)
    #expect(classDiagram.diagnostics.map(\.code) == [.unsupportedConstruct])
    #expect(!classText.contains("style A fill"))
    #expect(subgraph.fidelity == .complete)
    #expect(subgraphText.contains("subgraph Multi Word Label"))
  }

  @Test
  func xyShapeMismatchIsDiagnosedWithoutInventingBuckets() throws {
    let partial = MermaidRenderer().renderSurface(
      "xychart-beta\nx-axis [A, B, C]\nline [1, 2, 3]\nbar [4, 5]",
      forWidth: 52
    )
    let unavailable = MermaidRenderer().renderSurface(
      "xychart-beta\nx-axis [A, B, C]\nline [1, 2]",
      forWidth: 52
    )
    let text = try #require(partial.output?.serialized())

    #expect(partial.fidelity == .partial)
    #expect(partial.diagnostics.map(\.code) == [.contentElided])
    #expect(text.contains("line 1: 1, 2, 3"))
    #expect(!text.contains("bar 2"))
    #expect(unavailable.fidelity == .unavailable)
    #expect(unavailable.diagnostics.first?.code == .malformedDiagram)
  }

  @Test
  func graphFamilyCardsArePlacedOnceInSharedTopology() throws {
    let sources = [
      "flowchart TD\nA[Alpha] --> B[Beta]\nA --> C[Gamma]\nB --> C\nC --> A",
      "stateDiagram-v2\nAlpha --> Beta\nAlpha --> Gamma\nBeta --> Gamma\nGamma --> Alpha",
      "classDiagram\nclass Alpha\nclass Beta\nclass Gamma\nAlpha --> Beta\nAlpha --> Gamma\nGamma --> Alpha",
      "erDiagram\nAlpha ||--o{ Beta : owns\nAlpha ||--o{ Gamma : owns\nGamma ||--o{ Alpha : owns",
    ]
    for source in sources {
      let report = MermaidRenderer().renderSurface(source, forWidth: 64)
      let lines = try #require(report.output?.serializedLines())

      #expect(report.fidelity == .complete)
      for label in ["Alpha", "Beta", "Gamma"] {
        #expect(
          lines.filter { $0.contains("│ \(label)") }.count == 1,
          "Expected exactly one card for \(label)"
        )
      }
    }
  }

  @Test
  func strictFamiliesOnlySalvageOneUnreadableFinalStatement() throws {
    for family in ["state", "sequence", "class", "er"] {
      let middle = MermaidRenderer().renderSurface(
        try fixture("\(family)/malformed-middle.mmd"),
        forWidth: 60
      )
      let final = MermaidRenderer().renderSurface(
        try fixture("\(family)/salvage-final.mmd"),
        forWidth: 60
      )

      #expect(middle.fidelity == .unavailable)
      #expect(middle.output == nil)
      #expect(middle.diagnostics.first?.code == .malformedDiagram)
      #expect(final.fidelity == .partial)
      #expect(final.output != nil)
      #expect(final.diagnostics.contains { $0.code == .contentElided })
    }
  }

  @Test
  func flowchartSafelyOmitsUnknownStatementsAtAnyPosition() {
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA --> B\nunknown authored construct\nB --> C",
      forWidth: 48
    )

    #expect(report.fidelity == .partial)
    #expect(report.output != nil)
    #expect(report.diagnostics.contains { $0.code == .contentElided })
  }

  @Test
  func privateStatementNodeAndEdgeBudgetsFailBeforeGrowth() {
    let tooManyStatements =
      "flowchart LR\n" + String(repeating: "A\n", count: 4_096)
    let tooManyNodes =
      "flowchart LR\n" + (0...512).map { "N\($0)" }.joined(separator: "\n")
    let tooManyEdges =
      "flowchart LR\n" + Array(repeating: "A --> B", count: 1_025).joined(separator: "\n")

    for source in [tooManyStatements, tooManyNodes, tooManyEdges] {
      let report = MermaidRenderer().renderSurface(source, forWidth: 40)
      #expect(report.fidelity == .unavailable)
      #expect(report.output == nil)
      #expect(report.diagnostics.first?.code == .resourceLimit)
    }
  }

  @Test
  func hostileSingleLineAndDistributedSourcesHitEarlyWorkLimits() {
    let header = "flowchart LR\n"
    let oneMiBSingleNode =
      header
      + String(
        repeating: "a",
        count: 1_048_576 - header.utf8.count
      )
    let distributedConnectorFree =
      header
      + Array(
        repeating: String(repeating: "a", count: 254),
        count: 4_095
      ).joined(separator: "\n")
    let sources = [
      (
        source: oneMiBSingleNode,
        renderer: MermaidRenderer(
          configuration: .init(
            safetyLimits: .init(maximumInputBytes: 1_048_576)
          )
        ),
        expectsResourceLimit: true
      ),
      (
        source: distributedConnectorFree,
        renderer: MermaidRenderer(
          configuration: .init(
            safetyLimits: .init(maximumInputBytes: 1_048_576)
          )
        ),
        expectsResourceLimit: false
      ),
      (
        source: header + String(repeating: "a", count: 65_537),
        renderer: MermaidRenderer(),
        expectsResourceLimit: true
      ),
      (
        source: header + String(repeating: "-", count: 16_385),
        renderer: MermaidRenderer(),
        expectsResourceLimit: true
      ),
    ]

    for testCase in sources {
      for width in [16, Int.max] {
        let report = testCase.renderer.renderSurface(testCase.source, forWidth: width)
        if testCase.expectsResourceLimit {
          #expect(report.fidelity == .unavailable)
          #expect(report.output == nil)
          #expect(report.diagnostics.map(\.code) == [.resourceLimit])
        } else {
          #expect(report.fidelity == .complete)
          #expect(report.output != nil)
          #expect(report.diagnostics.isEmpty)
        }
      }
    }
  }

  @Test
  func entityDecoderPreservesLongRepeatedAuthoredLabels() throws {
    let count = 2_048
    let source = "flowchart LR\nA[\"" + String(repeating: "&amp;", count: count) + "\"]"
    let report = MermaidRenderer().renderSurface(source, forWidth: 64)
    let text = try #require(report.output?.serialized())

    #expect(report.fidelity == .complete)
    #expect(text.filter { $0 == "&" }.count == count)
  }

  @Test
  func cellBudgetFailsBeforeRectangularSurfaceAllocation() {
    let renderer = MermaidRenderer(
      configuration: .init(
        safetyLimits: .init(maximumOutputCells: 64)
      )
    )
    let report = renderer.renderSurface(
      "flowchart LR\nA[A long retained label] --> B[Another retained label]",
      forWidth: 40
    )

    #expect(report.fidelity == .unavailable)
    #expect(report.output == nil)
    #expect(report.diagnostics.first?.code == .resourceLimit)
  }

  @Test
  func familyLayoutsUseRoutedSemanticGeometry() throws {
    for family in ["flowchart", "state", "sequence", "class", "er"] {
      let source = try fixture("\(family)/minimal.mmd")
      let report = MermaidRenderer().renderSurface(source, forWidth: 72)
      let surface = try #require(report.output)
      let cells = surface.rows.flatMap { $0 }

      #expect(report.fidelity == .complete)
      #expect(cells.contains { $0.role == .edge })
      #expect(cells.contains { $0.role == .border })
      #expect(cells.contains { $0.role == .text })
      #expect(!surface.serialized().contains("Relations"))
    }
  }

  @Test
  func cyclicParallelAndUnicodeFixturesRemainCompleteAndBounded() throws {
    for path in [
      "flowchart/cyclic.mmd",
      "flowchart/scoped-connectors.mmd",
    ] {
      let source = try fixture(path)
      let renderer = MermaidRenderer()
      let metrics = try #require(renderer.layoutMetrics(for: source).output)
      for width in metrics.minimumWidth...metrics.idealSize.width {
        let report = renderer.renderSurface(source, forWidth: width)
        #expect(report.fidelity == .complete)
        #expect(report.output?.size.width ?? width + 1 <= width)
      }
    }

    let unicode = MermaidRenderer().renderSurface(
      try fixture("flowchart/unicode-wide.mmd"),
      forWidth: 48
    )
    #expect(unicode.fidelity == .partial)
    #expect(unicode.output?.serialized().contains("解析 👩🏽‍💻 é") == true)
    #expect(unicode.diagnostics.contains { $0.code == .rtlVisualOrderUnsupported })
  }

  @Test
  func exactBidiClassDetectionAvoidsWholeScriptFalsePositives() {
    let neutralAndNumbers = MermaidRenderer().renderSurface(
      "flowchart LR\nA[١٢، Aً] --> B[Aְ]",
      forWidth: 40
    )
    let strong = MermaidRenderer().renderSurface(
      "flowchart LR\nA[א]",
      forWidth: 24
    )

    #expect(neutralAndNumbers.fidelity == .complete)
    #expect(!neutralAndNumbers.diagnostics.contains { $0.code == .rtlVisualOrderUnsupported })
    #expect(strong.fidelity == .partial)
    #expect(strong.diagnostics.contains { $0.code == .rtlVisualOrderUnsupported })
  }

  @Test(
    arguments: [
      0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
      0x2066, 0x2067, 0x2068, 0x2069,
    ]
  )
  func everyBidiControlRangeIsRejected(value: Int) {
    guard let scalar = Unicode.Scalar(value) else {
      Issue.record("invalid test scalar")
      return
    }
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA[before\(String(scalar))after]",
      forWidth: 40
    )

    #expect(report.fidelity == .unavailable)
    #expect(report.output == nil)
    #expect(report.diagnostics.first?.code == .bidiControlUnsupported)
  }

  @Test
  func adversarialInputsNeverTrapOrExceedOfferedWidth() {
    let corpus = [
      "",
      "flowchart LR\n[",
      "flowchart LR\nA[\"unterminated]",
      "sequenceDiagram\nend",
      "classDiagram\n}",
      "erDiagram\n}",
      "xychart-beta\ny-axis -1e999 --> 1e999\nline [NaN]",
      "flowchart LR\nA[(((([[[{{{\\\";%%-->]]]] --> B",
      String(repeating: "x", count: 4_096),
    ]
    for source in corpus {
      let renderer = MermaidRenderer()
      let metrics = renderer.layoutMetrics(for: source)
      if let metrics = metrics.output {
        for width in metrics.minimumWidth...min(metrics.idealSize.width, metrics.minimumWidth + 8) {
          let report = renderer.renderSurface(source, forWidth: width)
          #expect(report.output?.size.width ?? 0 <= width)
        }
      } else {
        #expect(metrics.fidelity == .unavailable)
      }
    }
  }

  private func fixture(_ path: String) throws -> String {
    let components = path.split(separator: "/")
    let filename = String(try #require(components.last))
    let subdirectory = "Fixtures/" + components.dropLast().joined(separator: "/")
    let name = String(filename.prefix { $0 != "." })
    let extensionName = filename.split(separator: ".").last.map(String.init)
    let url = try #require(
      Bundle.module.url(
        forResource: name,
        withExtension: extensionName,
        subdirectory: subdirectory
      )
    )
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func parser() -> MermaidDiagramParser {
    MermaidDiagramParser(
      limits: .init(
        maximumDiagnostics: 32,
        maximumDiagnosticBytes: 512
      )
    )
  }

  private func formatIndex(_ value: Int) -> String {
    value < 10 ? "v0\(value)" : "v\(value)"
  }
}
