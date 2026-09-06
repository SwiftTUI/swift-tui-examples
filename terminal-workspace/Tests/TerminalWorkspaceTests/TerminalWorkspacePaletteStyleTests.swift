import SwiftTUIRuntime
import Testing

@testable import TerminalWorkspace

@MainActor
struct TerminalWorkspacePaletteStyleTests {
  @Test("workspace palette keeps its header, filter, descriptions, and cancel affordance")
  func composition() {
    let snapshot = DefaultRenderer().render(
      Panel(id: "workspace") { Text("Base") }
        .paletteCommand(name: "Split pane right", description: "Alt+V", action: {})
        .paletteCommand(name: "Close focused pane", isEnabled: false, action: {})
        .paletteSheet("Workspace commands", isPresented: .constant(true))
        .paletteStyle(TerminalWorkspacePaletteStyle()),
      context: .init(identity: Identity(components: ["WorkspacePalette"])),
      proposal: .init(width: 72, height: 24))
    let text = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("Workspace commands"))
    #expect(text.contains("Enter to run"))
    #expect(text.contains("Filter commands"))
    #expect(text.contains("Split pane right"))
    #expect(text.contains("Alt+V"))
    #expect(text.contains("Close focused pane"))
    #expect(text.contains("Cancel"))
    #expect(!text.contains("×"))
  }

  @Test("workspace palette retains its empty result message")
  func emptyCommands() {
    let snapshot = DefaultRenderer().render(
      Panel(id: "workspace") { Text("Base") }
        .paletteSheet("Workspace commands", isPresented: .constant(true))
        .paletteStyle(TerminalWorkspacePaletteStyle()),
      context: .init(identity: Identity(components: ["WorkspacePalette"])),
      proposal: .init(width: 72, height: 24))
    #expect(snapshot.rasterSurface.lines.joined().contains("No matches"))
  }
}
