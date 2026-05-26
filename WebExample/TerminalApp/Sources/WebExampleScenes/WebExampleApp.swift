import GalleryDemoViews
import SharedHostScenes
import SwiftTUIRuntime

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Game of Life") {
      LifeTab()
    }
    WindowGroup("Demo Details", id: WindowIdentifier("details")) {
      Panel(id: "details-panel") {
        HostDetailsView(
          title: "Conway's Game of Life Web Demo",
          lines: [
            "This is a standard SwiftTUI app with two Scenes: \"Game of Life\", \"Demo Details\".",
            "The app runs in terminal, SwiftUI, and Web hosts.",
            "For this demo the app is compiled to wasm32-wasi to run in your browser via the Web host.",
            "The host handles scene selection and displays output in this page's HTML <canvas>.",
          ],
          showsTerminalSizeInToolbar: true
        )
      }.toolbar(style: .defaultBottom)
    }

  }
}
