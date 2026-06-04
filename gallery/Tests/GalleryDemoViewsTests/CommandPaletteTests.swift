import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct CommandPaletteTests {
  @Test("command palette resolves through a declared child identity")
  func commandPaletteResolvesThroughDeclaredChildBoundary() {
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

    #expect(artifacts.resolvedTree.identity == rootIdentity.child("Group[0]"))
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
