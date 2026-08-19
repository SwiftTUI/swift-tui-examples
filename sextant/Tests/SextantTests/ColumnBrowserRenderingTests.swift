import Foundation
import SwiftTUI
import SwiftTUITerminal
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

    let headerRow = artifacts.rasterSurface.cells[0]

    // The title is a padded glyph chip filled with the accent, so the accent
    // arrives as a background rather than a foreground.
    #expect(headerRow.contains { $0.character == "∢" })
    #expect(
      headerRow.prefix(3).allSatisfy {
        $0.style?.backgroundColor == accent
      }
    )
    #expect(headerRow.contains { $0.style?.foregroundColor == muted })
  }

  @Test("the browser fills the surface it is given")
  func browserFillsSurfaceHeight() {
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

    let artifacts = DefaultRenderer().render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 100, height: 40)
    )
    let lines = artifacts.rasterSurface.lines

    // The status bar is the last band in the stack, so it lands on the final
    // row only when the columns have taken every row between the header and
    // it. A `Spacer` makes its stack flexible on both axes, so the header and
    // status bar must stay explicitly fixed-height or all three bands split
    // the surface between them and the browser stops less than a third down.
    #expect(lines.count == 40)
    #expect(lines[39].contains("BROWSER"))
    #expect(lines[38].contains("│"))
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

  /// An open overlay squeezes the browser/preview region to a couple of rows,
  /// and the column content is taller than the rows it is handed. Without a
  /// clip the surplus lines paint straight over the status bar: the shipped
  /// 0.3.8 build rendered `/tmp/…/demo-v0.1` immediately followed by the tail
  /// of the preview's `File · 5100 bytes · modified …` on the status row.
  ///
  /// The status bar is the last row, so its right-hand mode word is the probe:
  /// nothing from the column region may share that row.
  @Test("an open overlay never lets column content paint over the status bar")
  func overlaySqueezeDoesNotOverflowStatusBar() {
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

    // Deliberately short: the help panel alone is taller than this, which is
    // exactly the squeeze that produced the overflow.
    let artifacts = DefaultRenderer().render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 100, height: 12)
    )
    let lines = artifacts.rasterSurface.lines
    let statusRow = try? #require(lines.last)

    // The status row carries the path on the left and the mode on the right.
    // Any column content that escaped its region lands between them.
    #expect(statusRow?.contains("/fixture") == true)
    #expect(statusRow?.contains("Preview") == false)
    #expect(statusRow?.contains("(loading)") == false)
  }

  /// An external preview embeds a `TerminalView`, which accepts the parent's
  /// full proposal. A `VStack` splits leftover height evenly between its
  /// flexible children, so a trailing `Spacer` in the preview pane became a
  /// second claimant and halved the pane: an embedded `bat` painted 12 of the
  /// 25 rows it had and the `Spacer` swallowed the other 13, whatever the
  /// terminal's height. A built-in preview does not catch this — `Text` takes
  /// its full ideal height and is clamped, leaving a `Spacer` nothing.
  @Test("an external preview fills the pane down to the status bar")
  func externalPreviewFillsPaneHeight() async throws {
    let root = URL(fileURLWithPath: "/fixture")
    let rootID = DirectoryID(identity: .path(root.path))
    let itemURL = root.appendingPathComponent("long.txt")
    let identity = FileSystemIdentity.path(itemURL.path)
    let item = BrowserItem(
      id: BrowserItemID(identity: identity),
      directoryID: rootID,
      name: "long.txt",
      url: itemURL,
      kind: .file,
      listingMetadata: ItemMetadata(identity: identity, isReadable: true)
    )
    let secondURL = root.appendingPathComponent("other.txt")
    let secondIdentity = FileSystemIdentity.path(secondURL.path)
    let second = BrowserItem(
      id: BrowserItemID(identity: secondIdentity),
      directoryID: rootID,
      name: "other.txt",
      url: secondURL,
      kind: .file,
      listingMetadata: ItemMetadata(identity: secondIdentity, isReadable: true)
    )
    let session = FullyInkedTerminalSession()
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { request in
          .success(DirectorySnapshot(request: request, items: [item, second]))
        },
        previewEvents: { item, _, generation in
          AsyncStream { continuation in
            continuation.yield(
              .external(
                ExternalPreviewState(
                  item: item,
                  generation: generation,
                  adapterName: "stub",
                  status: .ready,
                  handle: PreviewSessionHandle(
                    terminal: session,
                    start: {},
                    terminate: { _ in },
                    lifecycle: { .running }
                  ),
                  fallback: nil
                )
              )
            )
            continuation.finish()
          }
        }
      )
    )

    model.send(.start)
    let clock = ContinuousClock()
    let loadDeadline = clock.now + .seconds(5)
    while clock.now < loadDeadline {
      if model.state.activeDirectory?.selectedItemID != nil { break }
      await Task.yield()
    }
    // A preview is requested on selection change, so nudge the selection off
    // the initial item and back.
    model.send(.moveSelection(.offset(1)))
    model.send(.moveSelection(.offset(-1)))
    let deadline = clock.now + .seconds(5)
    while clock.now < deadline {
      if case .external = model.state.preview { break }
      await Task.yield()
    }
    guard case .external = model.state.preview else {
      Issue.record("the external preview never reached the model")
      return
    }
    model.send(.focusPreview)

    let height = 24
    let lines = DefaultRenderer().render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 100, height: height)
    ).rasterSurface.lines
    #expect(lines.count == height)

    // The embedded grid paints `@`, and no chrome in this fixture does, so the
    // inked rows are exactly the rows the pane handed the terminal. The last
    // row is the status bar; everything above it, from where the grid starts,
    // must be the terminal's.
    let inked = lines.indices.filter { lines[$0].contains("@") }
    let lastContentRow = height - 2
    #expect(inked.last == lastContentRow)
    #expect(inked == Array((inked.first ?? 0)...lastContentRow))
  }
}

/// A session whose grid is taller and wider than any pane under test, so the
/// rows it paints are exactly the rows layout gave it.
private final class FullyInkedTerminalSession: TerminalSession {
  private let grid: ForeignGrid

  init() {
    let size = CellSize(width: 200, height: 200)
    grid = ForeignGrid(
      size: size,
      cells: Array(
        repeating: Array(repeating: RasterCell(character: "@"), count: size.width),
        count: size.height
      )
    )
  }

  var cachedSnapshot: ForeignGrid { grid }
  func start() async throws {}
  func snapshot() async -> ForeignGrid { grid }
  func currentTitle() async -> String? { nil }
  func currentWorkingDirectory() async -> String? { nil }
  func currentLifecycle() async -> TerminalLifecycle { .running }
  func send(key _: TerminalEmulatorKey) async {}
  func send(paste _: String) async {}
  func send(mouse _: TerminalEmulatorMouse) async {}
  func resize(_: CellSize) async throws {}
  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { $0.finish() }
  }
}
