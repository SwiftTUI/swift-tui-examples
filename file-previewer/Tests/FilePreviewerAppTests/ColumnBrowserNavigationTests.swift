@testable import FilePreviewerApp
import Foundation
import SwiftTUI
import Testing

@MainActor
struct ColumnBrowserNavigationTests {
  @Test("moving selection onto a folder keeps focus in the current column")
  func movingSelectionOntoFolderKeepsFocusInCurrentColumn() async throws {
    let root = try temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let firstFolder = root.appendingPathComponent("folder-a", isDirectory: true)
    let secondFolder = root.appendingPathComponent("folder-b", isDirectory: true)
    try FileManager.default.createDirectory(
      at: firstFolder,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: secondFolder,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: firstFolder.appendingPathComponent("folder-a-child", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: secondFolder.appendingPathComponent("folder-b-child", isDirectory: true),
      withIntermediateDirectories: true
    )

    let host = RecordingPresentationSurface(size: CellSize(width: 80, height: 16))
    let inputReader = SequenceInputReader([
      .key(.arrowDown),
      .key(.arrowDown),
      .key(.character("d"), modifiers: .ctrl),
    ])
    let rootIdentity = Identity(components: ["file-previewer.navigation.tests"])
    let runLoop = SwiftTUI.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: ProposedSize(width: host.surfaceSize.width, height: host.surfaceSize.height),
      viewBuilder: { _, _ in
        ColumnBrowser(path: [root])
      }
    )

    _ = try await runLoop.run()

    let rendered = try #require(host.renderedFrames.last).lines.joined(separator: "\n")
    #expect(rendered.contains("> folder-b/"))
    #expect(!rendered.contains("> folder-a-child/"))
  }
}

private final class SequenceInputReader: TerminalInputReading {
  private let events: [InputEvent]

  init(_ events: [InputEvent]) {
    self.events = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class RecordingPresentationSurface: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var renderedFrames: [RasterSurface] = []

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    renderedFrames.append(surface)
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

private func temporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("file-previewer-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
