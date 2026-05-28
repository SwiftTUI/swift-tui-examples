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

  @Option(help: "Open the gallery on a specific tab.")
  var tab: GalleryView.GalleryTab?

  var body: some Scene {
    WindowGroup {
      GalleryView(initialTab: tab)
    }
  }
}

extension GalleryView.GalleryTab: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(key: argument)
  }

  public static var allValueStrings: [String] {
    allCases.map(\.key)
  }
}
