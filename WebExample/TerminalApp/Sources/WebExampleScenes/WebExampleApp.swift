import GalleryDemoViews
import SharedHostScenes
import SwiftTUIRuntime

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Game of Life") {
      LifeTab()
    }
    WindowGroup("Animations", id: WindowIdentifier("animations")) {
      AnimationsTab()
    }
    WindowGroup("Images", id: WindowIdentifier("images")) {
      ImagesTab()
    }
    WindowGroup("Calculator", id: WindowIdentifier("calculator")) {
      CalculatorTab()
    }
  }

  /// Stable, ordered roster of scene titles for tests and the host picker.
  public nonisolated var sceneTitles: [String] {
    ["Game of Life", "Animations", "Images", "Calculator"]
  }
}
