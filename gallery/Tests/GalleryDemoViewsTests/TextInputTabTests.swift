import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct TextInputTabTests {
  @Test("TextInputTab resolves and rasterises core input surfaces")
  func rendersTextInputShowcase() {
    let terminalSize = CellSize(width: 80, height: 60)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      TextInputTab(),
      context: .init(
        identity: Identity(components: [.named("TextInputTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Text Input"))
    #expect(surface.contains("Single-line fields"))
    #expect(surface.contains("Secure entry"))
    #expect(surface.contains("Multiline editor"))
  }

  @Test("Gallery --tab key selects the text input tab")
  func galleryTabKeySelectsTextInput() throws {
    #expect(GalleryView.GalleryTab(key: "text-input") == .textInput)
  }
}
