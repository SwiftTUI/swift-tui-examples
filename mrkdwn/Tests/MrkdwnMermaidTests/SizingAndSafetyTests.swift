import MrkdwnMermaid
import Testing

@Suite
struct SizingAndSafetyTests {
  private let source =
    """
    flowchart LR
      A[A very long Unicode label 👩‍💻] -->|validated| B[Render]
      B --> C[Done]
    """

  @Test
  func finiteWidthsRespectMinimumAndDoNotStretchPastIdeal() {
    let renderer = MermaidRenderer()
    let metrics = renderer.layoutMetrics(for: source).output
    #expect(metrics != nil)
    guard let metrics else { return }

    let below = renderer.renderSurface(source, forWidth: metrics.minimumWidth - 4)
    #expect(below.output?.size.width ?? 0 >= metrics.minimumWidth)
    #expect(below.diagnostics.contains { $0.code == .widthClamped })

    for width in metrics.minimumWidth...metrics.idealSize.width {
      let measured = renderer.measure(source, forWidth: width)
      let rendered = renderer.renderSurface(source, forWidth: width)
      #expect(measured.output == rendered.output?.size)
      #expect(rendered.output?.size.width ?? 0 <= width)
    }

    let oversized = renderer.renderSurface(source, forWidth: metrics.idealSize.width + 80)
    #expect(oversized.output?.size == metrics.idealSize)
  }

  @Test
  func repeatedRenderingIsDeterministic() {
    let renderer = MermaidRenderer()
    let first = renderer.renderSurface(source, forWidth: 43)
    let second = renderer.renderSurface(source, forWidth: 43)
    #expect(first == second)
  }

  @Test
  func inputOutputAndDiagnosticLimitsFailSafely() {
    let inputLimited = MermaidRenderer(
      configuration: .init(
        safetyLimits: .init(maximumInputBytes: 8)
      )
    ).renderSurface(source, forWidth: 40)
    let outputLimited = MermaidRenderer(
      configuration: .init(
        safetyLimits: .init(maximumOutputCells: 10)
      )
    ).renderSurface("flowchart LR\nA --> B", forWidth: 40)
    let diagnosticsLimited = MermaidRenderer(
      configuration: .init(
        safetyLimits: .init(maximumDiagnostics: 2)
      )
    ).renderSurface(
      "flowchart LR\nA --> B\nstyle A fill:red\nstyle B fill:blue\nclick A x",
      forWidth: 40
    )

    #expect(inputLimited.fidelity == .unavailable)
    #expect(inputLimited.diagnostics.first?.code == .resourceLimit)
    #expect(outputLimited.fidelity == .unavailable)
    #expect(outputLimited.diagnostics.first?.code == .resourceLimit)
    #expect(diagnosticsLimited.diagnostics.count == 2)
    #expect(diagnosticsLimited.diagnostics.last?.code == .diagnosticsTruncated)
  }

  @Test
  func publiclyMutatedSafetyLimitsRemainSafeAtEveryUseSite() {
    var inputLimits = MermaidSafetyLimits()
    inputLimits.maximumInputBytes = Int.min
    let inputReport = MermaidRenderer(
      configuration: .init(safetyLimits: inputLimits)
    ).renderSurface("ab", forWidth: 1)
    #expect(inputReport.fidelity == .unavailable)
    #expect(inputReport.diagnostics.first?.code == .resourceLimit)
    #expect(inputReport.diagnostics.first?.message.contains("limit is 1 byte") == true)

    var outputLimits = MermaidSafetyLimits()
    outputLimits.maximumOutputCells = Int.min
    let outputReport = MermaidRenderer(
      configuration: .init(safetyLimits: outputLimits)
    ).renderSurface("flowchart LR\nA --> B", forWidth: 40)
    #expect(outputReport.fidelity == .unavailable)
    #expect(outputReport.diagnostics.first?.code == .resourceLimit)

    var diagnosticLimits = MermaidSafetyLimits()
    diagnosticLimits.maximumDiagnostics = Int.min
    diagnosticLimits.maximumDiagnosticMessageBytes = Int.min
    let diagnosticReport = MermaidRenderer(
      configuration: .init(safetyLimits: diagnosticLimits)
    ).renderSurface("", forWidth: 1)
    #expect(diagnosticReport.fidelity == .unavailable)
    #expect(diagnosticReport.diagnostics.count == 1)
    #expect(diagnosticReport.diagnostics[0].message.utf8.count <= 32)
  }

  @Test
  func asciiModeAvoidsUnicodeStructuralGlyphs() {
    let report = MermaidRenderer(
      configuration: .init(glyphMode: .ascii)
    ).renderSurface("flowchart LR\nA[Start] --> B[Done]", forWidth: 40)
    let text = report.output?.serialized(as: .ascii) ?? ""

    #expect(!text.contains("┌"))
    #expect(!text.contains("▶"))
    #expect(text.contains("+"))
    #expect(text.contains(">"))
  }
}
