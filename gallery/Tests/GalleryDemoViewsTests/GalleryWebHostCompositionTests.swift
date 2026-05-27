import Foundation
import Testing

struct GalleryWebHostCompositionTests {
  @Test("gallery executable uses batteries-included SwiftTUI without direct WebHostCLI ownership")
  func galleryExecutableUsesBatteriesIncludedSwiftTUIWithoutDirectWebHostCLIOwnership() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let source = try String(
      contentsOf: packageRoot.appendingPathComponent("Sources/GalleryDemo/GalleryDemoApp.swift"),
      encoding: .utf8
    )
    let manifest = try String(
      contentsOf: packageRoot.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )

    #expect(source.contains("import SwiftTUI\n"))
    #expect(source.contains("struct GalleryDemoApp: App"))
    #expect(source.contains("var swiftTUIOptions: SwiftTUIOptions"))
    #expect(source.contains("CommandConfiguration("))
    #expect(!source.contains("import SwiftTUIWebHostCLI"))
    #expect(!source.contains("WebHostCLIRunner.run("))
    #expect(!source.contains("struct GalleryDemoOptions"))
    #expect(!source.contains("import SwiftTUICLI"))

    #expect(manifest.contains(".product(name: \"SwiftTUI\", package: \"swift-tui\")"))
    #expect(!manifest.contains("SwiftTUIWebHostCLI"))
    #expect(!manifest.contains("SwiftTUIArguments"))
    #expect(!manifest.contains("SwiftTUICLI"))
  }

  @Test("shared gallery and WebExample scenes stay runtime-only for WASI builds")
  func sharedSceneTargetsStayRuntimeOnlyForWASIBuilds() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let examplesRoot = packageRoot.deletingLastPathComponent()
    let webExampleRoot = examplesRoot.appendingPathComponent("WebExample/TerminalApp")

    let galleryManifest = try String(
      contentsOf: packageRoot.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let webExampleManifest = try String(
      contentsOf: webExampleRoot.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let webExampleApp = try String(
      contentsOf: webExampleRoot.appendingPathComponent(
        "Sources/WebExampleScenes/WebExampleApp.swift"
      ),
      encoding: .utf8
    )

    #expect(galleryManifest.contains(".product(name: \"SwiftTUIRuntime\", package: \"swift-tui\")"))
    #expect(
      webExampleManifest.contains(".product(name: \"SwiftTUIRuntime\", package: \"swift-tui\")"))
    #expect(webExampleApp.contains("import SwiftTUIRuntime"))
    #expect(!webExampleApp.contains("import SwiftTUI\n"))

    for source in try swiftSources(
      under: packageRoot.appendingPathComponent("Sources/GalleryDemoViews")
    ) {
      let contents = try String(contentsOf: source, encoding: .utf8)
      #expect(!contents.contains("import SwiftTUI\n"), "\(source.path) imports SwiftTUI")
    }
  }

  private func swiftSources(under directory: URL) throws -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var sources: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      if values.isRegularFile == true {
        sources.append(url)
      }
    }
    return sources
  }
}
