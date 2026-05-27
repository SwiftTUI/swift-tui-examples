import GalleryDemoViews
import SwiftTUI

@main
struct GalleryDemoApp: App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "gallery-demo",
    abstract: "Explore SwiftTUI controls and runtime behavior."
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}
