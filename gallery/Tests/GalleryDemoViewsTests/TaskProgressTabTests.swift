import Foundation
import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct TaskProgressTabTests {
  // A minimal state that exercises every visual branch:
  // completed (strikethrough + dim ✓), in-progress (bold ■),
  // pending (□), token direction, the yellow status tail, and the
  // hidden-item summary.
  private static func sampleState() -> TaskProgressState {
    TaskProgressState(
      title: "Write design doc",
      elapsedSeconds: 225,
      tokensThousands: 15.4,
      tokenDirection: .down,
      statusTail: .thinking(remaining: "almost done thinking…"),
      items: [
        TaskProgressItem(title: "Spec self-review and user review", state: .completed),
        TaskProgressItem(title: "Write design doc", state: .inProgress),
        TaskProgressItem(title: "Transition to implementation", state: .pending),
      ],
      hiddenPendingCount: 1,
      hiddenCompletedCount: 4
    )
  }

  private func renderPanel(
    _ state: TaskProgressState,
    width: Int = 90,
    height: Int = 20
  ) -> String {
    let terminalSize = CellSize(width: width, height: height)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      TaskProgressPanel(state: state),
      context: .init(
        identity: Identity(components: [.named("TaskProgressPanelTest")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    return artifacts.rasterSurface.lines.joined(separator: "\n")
  }

  @Test("Panel renders the header title, metadata, and status tail")
  func headerRendersExpectedText() {
    let surface = renderPanel(Self.sampleState())

    #expect(surface.contains("Write design doc"))
    #expect(surface.contains("3m 45s"))
    #expect(surface.contains("15.4k"))
    #expect(surface.contains("tokens"))
    #expect(surface.contains("↓"))
    #expect(surface.contains("almost done thinking"))
  }

  @Test("Panel renders all three item states with their markers")
  func itemMarkersAndTreeConnector() {
    let surface = renderPanel(Self.sampleState())

    // Tree connector hooks the first item under the spinner.
    #expect(surface.contains("└"))
    // Completed state uses a green check.
    #expect(surface.contains("✓"))
    // In-progress state uses a filled square.
    #expect(surface.contains("■"))
    // Pending state uses an outline square.
    #expect(surface.contains("□"))
    // All three item titles appear.
    #expect(surface.contains("Spec self-review and user review"))
    #expect(surface.contains("Transition to implementation"))
  }

  @Test("Panel summary line shows both pending and completed counts")
  func summaryLineRenders() {
    let surface = renderPanel(Self.sampleState())

    #expect(surface.contains("…"))
    #expect(surface.contains("+1 pending"))
    #expect(surface.contains("4 completed"))
  }

  @Test("Panel omits the summary line when nothing is hidden")
  func summaryHiddenWhenCountsZero() {
    var state = Self.sampleState()
    state.hiddenPendingCount = 0
    state.hiddenCompletedCount = 0
    let surface = renderPanel(state)

    #expect(surface.contains("Write design doc"))
    #expect(!surface.contains("+1 pending"))
    #expect(!surface.contains("completed"))
  }

  @Test("Token formatter handles whole + fractional thousands")
  func tokenFormatting() {
    var state = Self.sampleState()
    state.tokensThousands = 12
    let whole = renderPanel(state)
    #expect(whole.contains("12k"))

    state.tokensThousands = 9.0
    let nineWhole = renderPanel(state)
    #expect(nineWhole.contains("9k"))

    state.tokensThousands = 16.2
    let tenths = renderPanel(state)
    #expect(tenths.contains("16.2k"))
  }

  @Test("Up-arrow token direction renders ↑")
  func upArrowTokenDirection() {
    var state = Self.sampleState()
    state.tokenDirection = .up
    let surface = renderPanel(state)

    #expect(surface.contains("↑"))
    #expect(!surface.contains("↓"))
  }

  @Test("Thought-for status tail renders the seconds count")
  func thoughtForTailRenders() {
    var state = Self.sampleState()
    state.statusTail = .thoughtFor(seconds: 2)
    let surface = renderPanel(state)

    #expect(surface.contains("thought for 2s"))
  }

  @Test("TaskProgressTab renders its panel surface within the gallery shell")
  func tabRendersInsideGalleryShell() {
    let terminalSize = CellSize(width: 100, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      TaskProgressTab(),
      context: .init(
        identity: Identity(components: [.named("TaskProgressTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Task progress pane"))
    #expect(surface.contains("Write design doc"))
  }

  @Test("Gallery initial-tab aliases select the task progress tab")
  func galleryInitialTabAliasesIncludeTaskProgress() {
    #expect(GalleryView.GalleryTab(environmentName: "progress") == .taskProgress)
    #expect(GalleryView.GalleryTab(environmentName: "task-progress") == .taskProgress)
    #expect(GalleryView.GalleryTab(environmentName: "working") == .taskProgress)
    #expect(GalleryView.GalleryTab(environmentName: "todolist") == .taskProgress)
    #expect(GalleryView.GalleryTab(environmentName: "todo-list") == .taskProgress)
  }
}
