import Testing

@testable import MrkdwnMermaid

@Suite
struct UnicodeSurfaceTests {
  @Test
  func wideGraphemesHaveSameRowContinuationCells() {
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA[界 👩‍💻 🇺🇳 1️⃣] --> B[e\u{301}]",
      forWidth: 48
    )
    let rows = report.output?.rows ?? []
    var sawWideLeader = false
    var sawContinuation = false

    for row in rows {
      for (column, cell) in row.enumerated() {
        switch cell {
        case .grapheme(_, _, let spanWidth) where spanWidth > 1:
          sawWideLeader = true
        case .continuation(let leadColumn, let role):
          sawContinuation = true
          #expect(leadColumn < column)
          #expect(row[leadColumn].role == role)
        default:
          break
        }
      }
    }
    #expect(sawWideLeader)
    #expect(sawContinuation)
  }

  @Test
  func ambiguousWidthPolicyChangesLeaderSpan() {
    let narrow = MermaidRenderer(
      configuration: .init(ambiguousWidth: .narrow)
    ).renderSurface("flowchart LR\nA[·]", forWidth: 20)
    let wide = MermaidRenderer(
      configuration: .init(ambiguousWidth: .wide)
    ).renderSurface("flowchart LR\nA[·]", forWidth: 20)

    #expect(span(of: "·", in: narrow.output) == 1)
    #expect(span(of: "·", in: wide.output) == 2)
  }

  @Test
  func generatedWidthTableCoversNonObviousScalarWidths() {
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA[\u{17D8}]",
      forWidth: 20
    )

    #expect(span(of: "\u{17D8}", in: report.output) == 3)
  }

  @Test
  func canonicalSpellingsMeasureAlikeWithoutNormalization() {
    let renderer = MermaidRenderer()
    let nfc = renderer.renderSurface("flowchart LR\nA[\u{00E9}]", forWidth: 20)
    let nfd = renderer.renderSurface("flowchart LR\nA[e\u{0301}]", forWidth: 20)

    #expect(nfc.output?.size == nfd.output?.size)
    #expect(nfc.output?.serialized().contains("\u{00E9}") == true)
    #expect(nfd.output?.serialized().contains("e\u{0301}") == true)
  }

  @Test
  func rtlIsLogicalOrderPartialAndBidiControlsAreRejected() {
    let logical = MermaidRenderer().renderSurface(
      "flowchart LR\nA[שלום ABC] --> B[مرحبا]",
      forWidth: 48
    )
    let spoofing = MermaidRenderer().renderSurface(
      "flowchart LR\nA[before\u{202E}after]",
      forWidth: 48
    )

    #expect(logical.fidelity == .partial)
    #expect(logical.output?.serialized().contains("שלום ABC") == true)
    #expect(logical.diagnostics.contains { $0.code == .rtlVisualOrderUnsupported })
    #expect(spoofing.fidelity == .unavailable)
    #expect(spoofing.diagnostics.first?.code == .bidiControlUnsupported)
  }

  @Test
  func controlsCannotReachTheSurfaceAndTabsAreEscaped() {
    let escape = MermaidRenderer().renderSurface(
      "flowchart LR\nA[bad\u{1B}sequence]",
      forWidth: 40
    )
    let tab = MermaidRenderer().renderSurface(
      "flowchart LR\nA[one\ttwo]",
      forWidth: 40
    )

    #expect(escape.fidelity == .unavailable)
    #expect(escape.diagnostics.first?.code == .controlCharacterUnsupported)
    #expect(tab.fidelity == .partial)
    #expect(tab.output?.serialized().contains("\t") == false)
    #expect(tab.diagnostics.contains { $0.code == .controlCharacterEscaped })
  }

  @Test(arguments: [UInt32(0x2028), UInt32(0x2029)])
  func unicodeLineSeparatorsAreRejectedBeforeLayout(_ scalarValue: UInt32) throws {
    let separator = try #require(Unicode.Scalar(scalarValue))
    let source = "flowchart LR\nA[before\(separator)after]"
    let renderer = MermaidRenderer()
    let metrics = renderer.layoutMetrics(for: source)
    let measured = renderer.measure(source, forWidth: 40)
    let rendered = renderer.renderSurface(source, forWidth: 40)

    #expect(MermaidUnicodeWidth.containsRejectedControl(String(separator)))
    #expect(metrics.fidelity == .unavailable)
    #expect(metrics.output == nil)
    #expect(metrics.diagnostics.map(\.code) == [.controlCharacterUnsupported])
    #expect(measured.fidelity == .unavailable)
    #expect(measured.output == nil)
    #expect(measured.diagnostics.map(\.code) == [.controlCharacterUnsupported])
    #expect(rendered.fidelity == .unavailable)
    #expect(rendered.output == nil)
    #expect(rendered.diagnostics.map(\.code) == [.controlCharacterUnsupported])

    let safe = try #require(
      renderer.renderSurface("flowchart LR\nA[before after]", forWidth: 40).output
    )
    let serializedLines = safe.serializedLines(as: .ascii)
    #expect(serializedLines.count == safe.size.height)
    for line in serializedLines {
      #expect(line.unicodeScalars.allSatisfy { $0.isASCII })
      #expect(line.utf8.count <= safe.size.width)
      #expect(!line.unicodeScalars.contains(separator))
    }
  }

  @Test(arguments: [UInt32(0x200B), 0x2060, 0x206A, 0x206F, 0xFEFF])
  func standaloneZeroWidthFormattingCharactersAreRejected(_ scalarValue: UInt32) throws {
    let formattingCharacter = try #require(Unicode.Scalar(scalarValue))
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA[ad\(formattingCharacter)min]",
      forWidth: 32
    )

    #expect(
      MermaidUnicodeWidth.containsStandaloneZeroWidthCharacter(
        String(formattingCharacter)
      )
    )
    #expect(report.fidelity == .unavailable)
    #expect(report.output == nil)
    #expect(report.diagnostics.map(\.code) == [.controlCharacterUnsupported])
  }

  @Test
  func serializerTrimsOnlyEmptyCanvasFiller() {
    let surface = MermaidSurface(
      validating: [
        [
          .grapheme("A", role: .text, spanWidth: 1),
          .grapheme(" ", role: .text, spanWidth: 1),
          .empty(role: .background),
        ]
      ]
    )

    #expect(surface.serialized() == "A ")
  }

  @Test
  func surfaceValidationRequiresCompleteBoundedContinuationRuns() {
    let valid: [[MermaidCell]] = [
      [
        .grapheme("界", role: .text, spanWidth: 2),
        .continuation(leadColumn: 0, role: .text),
        .empty(role: .background),
      ]
    ]
    #expect(MermaidSurface.rowsAreValid(valid))

    let invalid: [[[MermaidCell]]] = [
      [
        [.grapheme("A", role: .text, spanWidth: 0)]
      ],
      [
        [
          .grapheme("界", role: .text, spanWidth: 2),
          .empty(role: .background),
        ]
      ],
      [
        [
          .grapheme("界", role: .text, spanWidth: 3),
          .continuation(leadColumn: 0, role: .text),
        ]
      ],
      [
        [
          .grapheme("界", role: .text, spanWidth: 2),
          .continuation(leadColumn: 0, role: .edge),
        ]
      ],
      [
        [
          .grapheme("A", role: .text, spanWidth: 1),
          .continuation(leadColumn: 0, role: .text),
        ]
      ],
      [
        [.continuation(leadColumn: 0, role: .text)]
      ],
      [
        [.grapheme("AB", role: .text, spanWidth: 1)]
      ],
      [
        [.empty(role: .background)],
        [.empty(role: .background), .empty(role: .background)],
      ],
    ]
    for rows in invalid {
      #expect(!MermaidSurface.rowsAreValid(rows))
    }
  }

  private func span(of grapheme: String, in surface: MermaidSurface?) -> Int? {
    for cell in surface?.rows.flatMap({ $0 }) ?? [] {
      if case .grapheme(let value, _, let spanWidth) = cell, value == grapheme {
        return spanWidth
      }
    }
    return nil
  }
}
