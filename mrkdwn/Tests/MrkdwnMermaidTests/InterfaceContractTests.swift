import MrkdwnMermaid
import Testing

@Suite
struct InterfaceContractTests {
  @Test
  func measurementAndStructuredRenderShareOneLayout() {
    let source = "flowchart LR\nsource[Source] --> render[Render]"
    let renderer = MermaidRenderer()
    let metrics = renderer.layoutMetrics(for: source)

    #expect(metrics.fidelity == .complete)
    let minimumWidth = metrics.output?.minimumWidth ?? 1
    for width in [minimumWidth, 24, 48, 120] {
      let measured = renderer.measure(source, forWidth: width)
      let rendered = renderer.renderSurface(source, forWidth: width)
      #expect(measured.output == rendered.output?.size)
    }
  }

  @Test
  func crlfAndLfSourcesProduceTheSameSurface() {
    let renderer = MermaidRenderer()
    let lf = renderer.renderSurface("flowchart LR\nA --> B\nB --> C", forWidth: 40)
    let crlf = renderer.renderSurface(
      "flowchart LR\r\nA --> B\r\nB --> C",
      forWidth: 40
    )

    #expect(lf == crlf)
  }
}
