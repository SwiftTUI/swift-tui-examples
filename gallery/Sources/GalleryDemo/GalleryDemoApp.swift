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

  @Option(help: "Open the Animations tab on a specific page (implies --tab animations).")
  var animationsPage: AnimationsPage?

  var body: some Scene {
    WindowGroup {
      GalleryView(
        initialTab: tab ?? (animationsPage == nil ? nil : .animations),
        initialAnimationsPage: animationsPage
      )
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

// String-backed and CaseIterable, so ArgumentParser derives the parser and
// the help listing from the raw values.
extension AnimationsPage: ExpressibleByArgument {}
