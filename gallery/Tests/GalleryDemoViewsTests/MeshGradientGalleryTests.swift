@_spi(Runners) @_spi(Testing) import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct MeshGradientGalleryTests {
  @Test("mesh cards render static, point, and color variants with distinct output")
  func meshCardsRenderDistinctOutput() {
    let staticSurface = Self.render(BordersAndShapesMeshGradientSection.staticMesh)
    let movedSurface = Self.render(
      BordersAndShapesMeshGradientSection.pointAnimatedMesh(phase: 1)
    )
    let recoloredSurface = Self.render(
      BordersAndShapesMeshGradientSection.colorAnimatedMesh(alternate: true)
    )

    #expect(staticSurface.cells != movedSurface.cells)
    #expect(staticSurface.cells != recoloredSurface.cells)
  }

  @Test("mesh crafter emits a complete paste-ready Swift definition")
  func crafterEmitsCompleteDefinition() {
    let definition = MeshGradientCrafter.definition(
      points: BordersAndShapesMeshGradientSection.identityPoints,
      controlColors: MeshGradientPalette.aurora.colors,
      smoothsColors: true,
      colorSpace: .perceptual
    )

    #expect(definition.hasPrefix("MeshGradient("))
    #expect(definition.contains("width: 3"))
    #expect(definition.contains("height: 3"))
    #expect(definition.components(separatedBy: "    .init(").count - 1 == 9)
    #expect(definition.contains("background: .black"))
    #expect(definition.contains("smoothsColors: true"))
    #expect(definition.contains("colorSpace: .perceptual"))
  }

  @Test("Copy Definition writes the current mesh through the active host clipboard")
  func copyDefinitionWritesHostClipboard() async throws {
    let terminalSize = CellSize(width: 100, height: 30)
    let rootIdentity = Identity(components: [.named("MeshGradientCrafterClipboard")])
    let host = MeshCrafterClipboardHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance

    let initial = DefaultRenderer().render(
      MeshGradientCrafter(),
      context: .init(
        identity: rootIdentity,
        environmentValues: environment
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    ).rasterSurface
    let copyCenter = try #require(Self.center(of: "Copy Definition", in: initial))

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: MeshCrafterScriptedInput(
        events: [
          .mouse(.init(kind: .down(.primary), location: copyCenter)),
          .mouse(.init(kind: .up(.primary), location: copyCenter)),
        ]
      ),
      signalReader: MeshCrafterEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in MeshGradientCrafter() }
    )
    _ = try await runLoop.run()

    #expect(host.clipboardWrites.count == 1)
    #expect(host.clipboardWrites[0].hasPrefix("MeshGradient("))
    #expect(
      host.lastSurface?.lines.joined(separator: "\n").contains("Copied MeshGradient") == true
    )
  }

  private static func render(_ mesh: MeshGradient) -> RasterSurface {
    let size = CellSize(width: 18, height: 6)
    var environment = EnvironmentValues()
    environment.terminalSize = size
    return DefaultRenderer().render(
      Rectangle().fill(mesh).frame(width: size.width, height: size.height),
      context: .init(
        identity: Identity(components: [.named("MeshGradientGalleryEndpoint")]),
        environmentValues: environment
      ),
      proposal: .init(width: size.width, height: size.height)
    ).rasterSurface
  }

  private static func center(of text: String, in surface: RasterSurface) -> Point? {
    for (row, line) in surface.lines.enumerated() {
      guard let range = line.range(of: text) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + text.count / 2, y: row))
    }
    return nil
  }
}

private final class MeshCrafterClipboardHost:
  PresentationSurface,
  ClipboardWritingPresentationSurface
{
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastSurface: RasterSurface?
  private(set) var clipboardWrites: [String] = []

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
    lastSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.cells.count,
      strategy: .fullRepaint
    )
  }

  @discardableResult
  func writeClipboard(_ text: String) throws -> Bool {
    clipboardWrites.append(text)
    return true
  }
}

private final class MeshCrafterScriptedInput: TerminalInputReading {
  let events: [InputEvent]

  init(events: [InputEvent]) {
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

private final class MeshCrafterEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
