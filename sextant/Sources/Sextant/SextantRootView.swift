public import Foundation
public import SwiftTUI
import SwiftTUITerminal

public struct SextantRootView: View {
  private let root: URL
  private let registry: PreviewerRegistry
  private let previewSessions: PreviewSessionSlot<TerminalProcessSession>

  public init(
    root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    registry: PreviewerRegistry = .defaults,
    previewSessions: PreviewSessionSlot<TerminalProcessSession> = .terminalProcesses()
  ) {
    self.root = root
    self.registry = registry
    self.previewSessions = previewSessions
  }

  public var body: some View {
    ColumnBrowser(
      path: [root],
      registry: registry,
      previewSessions: previewSessions
    )
  }

  public func shutdown() async {
    await previewSessions.shutdown()
  }
}
