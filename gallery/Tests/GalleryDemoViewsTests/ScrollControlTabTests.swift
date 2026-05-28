import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct ScrollControlTabTests {
  @Test("ScrollControlTab resolves and rasterises proxy examples")
  func rendersScrollControlShowcase() {
    let terminalSize = CellSize(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      ScrollControlTab(),
      context: .init(
        identity: Identity(components: [.named("ScrollControlTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Scroll Control"))
    #expect(surface.contains("ScrollViewReader drives identity"))
    #expect(surface.contains("Top"))
    #expect(surface.contains("Errors"))
  }

  @Test("Gallery --tab key selects the scroll control tab")
  func galleryTabKeySelectsScrollControl() {
    #expect(GalleryView.GalleryTab(key: "scroll-control") == .scrollControl)
  }
}
