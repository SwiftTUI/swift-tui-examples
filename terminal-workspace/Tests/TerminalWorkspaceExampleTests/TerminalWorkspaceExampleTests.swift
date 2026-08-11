import TerminalWorkspace
import TerminalWorkspaceExample
import Testing

struct TerminalWorkspaceExampleTests {
  @Test("initial workspace has one shell pane per tab")
  func initialWorkspaceShape() {
    let workspace = TerminalWorkspaceExampleModel.initialWorkspace(workingDirectory: "/tmp")

    #expect(workspace.tabs.map(\.id) == ["dev", "ops"])
    #expect(workspace.activeTabID == "dev")
    #expect(workspace.focusedPaneID == "dev-shell")
    #expect(workspace.allPaneIDs == ["dev-shell", "ops-shell"])
  }
}
