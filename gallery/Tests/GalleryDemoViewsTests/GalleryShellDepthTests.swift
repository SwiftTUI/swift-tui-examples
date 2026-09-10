import SwiftTUI
import Testing

@testable import GalleryDemoViews

// The shell's root modifier chain is ~25 layers deep (one per palette
// command), and the resolver copies the wrapped value once per layer, so the
// gallery lives near the resolve stack's limit. Adding the nineteenth tab
// overflowed the 8 MB main-thread stack while rendering the Presentation Lab
// tab until the tab tuple moved below `GalleryShellContent`. Rendering every
// tab through the shell pins that margin: a future tab, modifier, or heavier
// tab value that crosses the limit fails here with a signal instead of in a
// user's terminal.
@MainActor
@Suite
struct GalleryShellDepthTests {
  @Test(
    "the shell renders every tab at the app's real depth",
    arguments: GalleryView.GalleryTab.allCases
  )
  func shellRendersEveryTab(tab: GalleryView.GalleryTab) {
    let size = CellSize(width: 120, height: 60)
    var env = EnvironmentValues()
    env.terminalSize = size
    let artifacts = DefaultRenderer().render(
      GalleryView(initialTab: tab),
      context: .init(
        identity: Identity(components: [.named("GalleryShellDepth")]),
        environmentValues: env
      ),
      proposal: .init(width: size.width, height: size.height)
    )
    // The strip overflows at this width, so a tab's title is not always
    // visible; the toolbar item is, and the point of the test is that the
    // render completed at all.
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("⌃K Palette"), "the shell did not render for \(tab)")
  }
}
