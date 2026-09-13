@_spi(Testing) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

@MainActor
struct CustomDisclosureStyleTests {
  private struct Root: View {
    @State private var expanded = false
    @State private var presses = 0
    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        DisclosureGroup("Details", isExpanded: $expanded) {
          Button("Content action") { presses += 1 }
        }.disclosureGroupStyle(ArrowDisclosureGroupStyle())
        Text("expanded=\(expanded) presses=\(presses)")
      }
    }
  }

  @Test("custom disclosure routes the label and keeps expanded content interactive")
  func pointerActivation() async throws {
    typealias Step = AnimationRegressionAwaitedInputStep
    let size = CellSize(width: 40, height: 8)
    let identity = Identity(components: [.named("CustomDisclosure")])
    let trigger = try AnimationRegressionHarness.centerOfText(
      "Details", in: Root(), terminalSize: size, rootIdentity: identity)
    let host = AnimationRegressionRecordingHost(size: size)
    func shows(_ text: String) -> Bool {
      host.surfaces.last?.lines.joined(separator: "\n").contains(text) == true
    }
    let input = AnimationRegressionAwaitedInputReader(
      frameSignal: host.frameSignal,
      steps: [.awaitCondition { shows("expanded=false presses=0") }]
        + Step.click(trigger)
        + [.awaitCondition { shows("expanded=true presses=0") }]
        + Step.click(Point(x: 5, y: 1))
        + [.awaitCondition { shows("expanded=true presses=1") }]
        + Step.click(trigger)
        + [.awaitCondition { shows("expanded=false presses=1") }, .exit])
    _ = try await AnimationRegressionHarness.run(
      host: host, terminalSize: size, rootIdentity: identity,
      inputReader: input, viewBuilder: { Root() })
    try await input.requireNoWaitFailure()
    #expect(shows("expanded=false presses=1"))
  }
}
