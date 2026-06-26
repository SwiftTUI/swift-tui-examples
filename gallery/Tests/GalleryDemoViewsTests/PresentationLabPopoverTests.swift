import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct PresentationLabPopoverTests {
  @Test("PresentationLabTab includes the consolidated popover showcase")
  func rendersConsolidatedPopoverShowcase() {
    let terminalSize = CellSize(width: 80, height: 30)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      PresentationLabTab(),
      context: .init(
        identity: Identity(components: [.named("PresentationLabPopoverSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Presentation Lab"))
    #expect(surface.contains("Boolean binding"))
    #expect(surface.contains("Show Details"))
    #expect(surface.contains("Optional item binding"))
    #expect(surface.contains("TipKit-inspired tip"))
  }

  @Test("Gallery --tab popovers aliases to Presentation Lab")
  func galleryTabKeyAliasesPopoversToPresentationLab() {
    #expect(GalleryView.GalleryTab(key: "popovers") == .presentationLab)
  }
}
