import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct CommandPaletteTests {
  @Test("command palette publishes focusable filter semantics")
  func commandPalettePublishesFocusableFilterSemantics() {
    let rootIdentity = Identity(components: ["CommandPaletteRoot"])
    var environment = EnvironmentValues()
    environment.terminalSize = .init(width: 80, height: 24)

    let artifacts = DefaultRenderer().render(
      CommandPaletteList(
        commands: [],
        dismiss: {}
      ),
      context: .init(
        identity: rootIdentity,
        environmentValues: environment
      ),
      proposal: .init(width: 44, height: 12)
    )

    #expect(!artifacts.semanticSnapshot.focusRegions.isEmpty)
    #expect(
      artifacts.semanticSnapshot.focusRegions.contains {
        $0.rect.size.width > 0 && $0.rect.size.height > 0
      }
    )
  }

  @Test("command palette list does not render an internal title")
  func commandPaletteListDoesNotRenderInternalTitle() {
    var environment = EnvironmentValues()
    environment.terminalSize = .init(width: 80, height: 24)

    let artifacts = DefaultRenderer().render(
      CommandPaletteList(
        commands: [],
        dismiss: {}
      ),
      context: .init(
        identity: Identity(components: ["CommandPaletteTitleProbe"]),
        environmentValues: environment
      ),
      proposal: .init(width: 44, height: 12)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(!surface.contains("Command palette"))
  }
}
