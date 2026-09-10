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

  @Option(help: "Open the Styles tab on a specific page (implies --tab styles).")
  var stylesPage: StylesPage?

  var body: some Scene {
    WindowGroup {
      GalleryView(
        initialTab: tab ?? impliedTab,
        initialAnimationsPage: animationsPage,
        initialStylesPage: stylesPage
      )
    }
  }

  /// The tab a page option implies when `--tab` is absent.
  private var impliedTab: GalleryView.GalleryTab? {
    if animationsPage != nil {
      return .animations
    }
    if stylesPage != nil {
      return .styles
    }
    return nil
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
extension StylesPage: ExpressibleByArgument {}
