import MrkdwnMermaid
import Testing

@Suite
struct FamilyConformanceTests {
  @Test(
    arguments: [
      "flowchart LR\nA[Start] --> B[Done]",
      "stateDiagram-v2\n[*] --> Idle\nIdle --> Running: start",
      "sequenceDiagram\nparticipant A\nparticipant B\nA->>B: hello",
      "classDiagram\nclass Animal\nAnimal <|-- Duck",
      "erDiagram\nCUSTOMER ||--o{ ORDER : places",
      "xychart-beta\nx-axis [A, B]\ny-axis 0 --> 10\nbar [4, 8]",
    ]
  )
  func declaredFamilyProducesStructuredArt(source: String) {
    let report = MermaidRenderer().renderSurface(source, forWidth: 72)

    #expect(report.fidelity == .complete)
    #expect(report.output?.size.width ?? 0 > 0)
    #expect(report.output?.size.height ?? 0 > 0)
    #expect(report.output?.rows.flatMap { $0 }.contains { $0.role == .text } == true)
    #expect(report.output?.rows.flatMap { $0 }.contains { $0.role == .border } == true)
  }

  @Test
  func recognizedButIgnoredConstructIsPartial() {
    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA --> B\nstyle A fill:#fff\nclick A \"https://example.com\"",
      forWidth: 40
    )

    #expect(report.fidelity == .partial)
    #expect(report.output != nil)
    #expect(report.diagnostics.contains { $0.code == .unsupportedConstruct })
  }

  @Test
  func unsupportedAndMalformedFamiliesRemainUnavailable() {
    let unsupported = MermaidRenderer().renderSurface("pie\n\"A\": 1", forWidth: 40)
    let malformed = MermaidRenderer().renderSurface("sequenceDiagram", forWidth: 40)

    #expect(unsupported.fidelity == .unavailable)
    #expect(unsupported.diagnostics.first?.code == .unsupportedDiagram)
    #expect(malformed.fidelity == .unavailable)
    #expect(malformed.diagnostics.first?.code == .malformedDiagram)
  }
}
