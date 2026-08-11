import Foundation
import SwiftTUI
import TerminalWorkspace

public struct TerminalWorkspaceExampleView: View {
  @State private var workspace: TerminalWorkspaceState
  @State private var workspaceChangedSinceLaunch = false

  public init() {
    _workspace = State(
      wrappedValue: TerminalWorkspaceExampleModel.initialWorkspace()
    )
  }

  public var body: some View {
    TerminalWorkspaceView(workspace: $workspace)
      .task {
        @MainActor in
        guard let persisted = await TerminalWorkspacePersistence.load() else {
          return
        }
        // An empty workspace persists when the user exits every shell;
        // restoring it would relaunch into a blank surface, so keep the
        // seeded tabs instead.
        guard !persisted.tabs.isEmpty else {
          return
        }
        guard !workspaceChangedSinceLaunch else {
          return
        }
        workspace = persisted
      }
      .onChange(of: workspace) {
        let snapshot = workspace
        workspaceChangedSinceLaunch = true
        TerminalWorkspacePersistence.save(snapshot)
      }
  }
}

public enum TerminalWorkspaceExampleModel {
  public static func initialWorkspace(
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> TerminalWorkspaceState {
    TerminalWorkspaceState(
      tabs: [
        TerminalWorkspaceTab(
          id: "dev",
          title: "dev",
          root: .terminal(
            .shell(
              id: "dev-shell",
              title: "shell",
              workingDirectory: workingDirectory
            )
          )
        ),
        TerminalWorkspaceTab(
          id: "ops",
          title: "ops",
          root: .terminal(
            .shell(
              id: "ops-shell",
              title: "ops shell",
              workingDirectory: workingDirectory
            )
          )
        ),
      ],
      activeTabID: "dev",
      focusedPaneID: "dev-shell"
    )
  }
}

enum TerminalWorkspacePersistence {
  static func load() async -> TerminalWorkspaceState? {
    let fileURL = fileURL
    return await Task.detached(priority: .userInitiated) {
      guard let data = try? Data(contentsOf: fileURL) else {
        return nil
      }
      return try? JSONDecoder().decode(TerminalWorkspaceState.self, from: data)
    }.value
  }

  static func save(_ workspace: TerminalWorkspaceState) {
    let fileURL = fileURL
    Task.detached(priority: .utility) {
      guard let data = try? JSONEncoder().encode(workspace) else {
        return
      }
      try? data.write(to: fileURL, options: [.atomic])
    }
  }

  private static var fileURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".swift-tui-terminal-workspace.json")
  }
}
