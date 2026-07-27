import Foundation
import SwiftTUI
import Synchronization
import Testing

@testable import Sextant

@MainActor
struct ColumnBrowserRenderingTests {
  @Test("rendering the browser does not start filesystem work")
  func renderDoesNotStartFilesystemWork() {
    let root = URL(fileURLWithPath: "/fixture")
    let rootID = DirectoryID(identity: .path(root.path))
    let loadCount = Mutex(0)
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { _ in
          loadCount.withLock { $0 += 1 }
          return .failure(.cancelled)
        }
      )
    )
    let renderer = DefaultRenderer()

    _ = renderer.render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 80, height: 20)
    )
    _ = renderer.render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 80, height: 20)
    )

    #expect(loadCount.withLock { $0 } == 0)
  }

  @Test("the root renders loading chrome before a directory response")
  func rootRendersLoadingChrome() {
    let root = URL(fileURLWithPath: "/fixture")
    let rootID = DirectoryID(identity: .path(root.path))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { _ in .failure(.cancelled) }
      )
    )
    let renderer = DefaultRenderer()

    let artifacts = renderer.render(
      SextantRootView(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 80, height: 20)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("(loading)"))
    #expect(rendered.contains("Preview"))
    #expect(rendered.contains("/fixture"))
  }

  @Test("help renders configured key overrides from the dispatch catalog")
  func configuredHelpBindings() {
    let root = URL(fileURLWithPath: "/fixture")
    let rootID = DirectoryID(identity: .path(root.path))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { _ in .failure(.cancelled) }
      )
    )
    model.send(.showHelp)

    let artifacts = DefaultRenderer().render(
      ColumnBrowser(
        model: model,
        configuration: SextantConfiguration(
          keyOverrides: ["navigation.up": "Ctrl-U"]
        )
      ),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 100, height: 35)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("Ctrl-U"))
    #expect(rendered.contains("Move selection up"))
  }

  @Test("configured accent and muted colors reach rendered chrome")
  func configuredColors() throws {
    let root = URL(fileURLWithPath: "/fixture")
    let rootID = DirectoryID(identity: .path(root.path))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { _ in .failure(.cancelled) }
      )
    )
    let accent = try Color(hex: "#123456")
    let muted = try Color(hex: "#654321")

    let artifacts = DefaultRenderer().render(
      ColumnBrowser(
        model: model,
        configuration: SextantConfiguration(
          colors: ColorConfiguration(
            accent: "#123456",
            muted: "#654321"
          )
        )
      ),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 80, height: 20)
    )

    #expect(
      artifacts.rasterSurface.cells[0][0].style?.foregroundColor == accent
    )
    #expect(
      artifacts.rasterSurface.cells[0][10].style?.foregroundColor == muted
    )
  }

  @Test("empty search exposes bookmarks and recents as path-jump choices")
  func searchPathHistory() {
    let root = URL(fileURLWithPath: "/fixture")
    let rootID = DirectoryID(identity: .path(root.path))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      bookmarks: ["/fixture/bookmarked"],
      recents: ["/fixture/recent"],
      dependencies: BrowserModelDependencies(
        loadDirectory: { _ in .failure(.cancelled) }
      )
    )
    model.send(.showSearch)

    let artifacts = DefaultRenderer().render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 100, height: 35)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("BOOKMARKS"))
    #expect(rendered.contains("/fixture/bookmarked"))
    #expect(rendered.contains("RECENTS"))
    #expect(rendered.contains("/fixture/recent"))
  }
}
