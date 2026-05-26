import GalleryDemoViews
import SharedHostScenes
import SwiftTUI

public struct ExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Component Gallery") {
      GalleryView()
    }
    WindowGroup("Details", id: WindowIdentifier("details")) {
      HostDetailsView(
        title: "Details",
        lines: [],
        showsTerminalSizeInBody: true
      )
    }
  }
}
