@testable import FilePreviewerApp
import Foundation
import SwiftTUI
import Testing

@MainActor
struct ColumnBrowserCacheTests {
  @Test("browser does not reread the same directory across repeated renders")
  func browserDoesNotRereadDirectoryAcrossRepeatedRenders() {
    let root = URL(fileURLWithPath: "/tmp/root")
    var loadCount = 0
    let cache = DirectoryEntryCache(capacity: 8) { directory in
      loadCount += 1
      return [
        FileEntry(
          url: directory.appendingPathComponent("one.swift"),
          isDirectory: false
        ),
        FileEntry(
          url: directory.appendingPathComponent("two.swift"),
          isDirectory: false
        ),
      ]
    }
    let browser = ColumnBrowser(
      path: [root],
      registry: .defaults,
      entryCache: cache
    )
    let renderer = DefaultRenderer()

    _ = renderer.render(
      browser,
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 80, height: 20)
    )
    _ = renderer.render(
      browser,
      context: .init(identity: Identity(components: ["Root"])),
      proposal: .init(width: 80, height: 20)
    )

    #expect(loadCount == 1)
  }
}
