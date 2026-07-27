import Foundation
import Testing

@testable import Sextant

struct FileSystemTypesTests {
  @Test("duplicate filesystem identities receive stable entry discriminators")
  func duplicateFilesystemIdentitiesAreSafe() throws {
    let directoryURL = URL(fileURLWithPath: "/fixtures/duplicates", isDirectory: true)
    let directoryID = DirectoryID(identity: .pathFallback(for: directoryURL))
    let sharedIdentity = FileSystemIdentity.inode(device: 7, inode: 42)
    let entries = [
      listing("first", identity: sharedIdentity, directoryURL: directoryURL),
      listing("second", identity: sharedIdentity, directoryURL: directoryURL),
      listing(
        "unique",
        identity: .inode(device: 7, inode: 43),
        directoryURL: directoryURL
      ),
    ]

    let items = makeBrowserItems(
      entries: entries,
      directoryID: directoryID,
      policy: DirectoryPolicy()
    )
    let first = try #require(items.first { $0.name == "first" })
    let second = try #require(items.first { $0.name == "second" })
    let unique = try #require(items.first { $0.name == "unique" })

    #expect(first.id != second.id)
    #expect(first.id.identity == second.id.identity)
    #expect(first.id.collisionDiscriminator == first.url.path)
    #expect(second.id.collisionDiscriminator == second.url.path)
    #expect(unique.id.collisionDiscriminator == nil)
  }

  @Test("directory-like and symbolic-link kinds remain semantically distinct")
  func itemKindsAreDistinct() {
    #expect(BrowserItemKind.directory.isDirectoryLike)
    #expect(BrowserItemKind.package.isDirectoryLike)
    #expect(BrowserItemKind.symbolicLinkToDirectory.isDirectoryLike)
    #expect(!BrowserItemKind.file.isDirectoryLike)
    #expect(!BrowserItemKind.symbolicLinkToFile.isDirectoryLike)
    #expect(!BrowserItemKind.brokenSymbolicLink.isDirectoryLike)
    #expect(BrowserItemKind.symbolicLinkToFile.isSymbolicLink)
    #expect(BrowserItemKind.symbolicLinkToSpecial(.fifo).isSymbolicLink)
    #expect(!BrowserItemKind.special(.fifo).isSymbolicLink)
  }

  @Test("hidden and sort policies produce separate deterministic listings")
  func policyFilteringAndSorting() {
    let directoryURL = URL(fileURLWithPath: "/fixtures/names", isDirectory: true)
    let directoryID = DirectoryID(identity: .pathFallback(for: directoryURL))
    let names = [
      ".hidden",
      "-leading-dash",
      "Zebra",
      "éclair",
      "line\nbreak",
      String(repeating: "界", count: 100),
    ]
    let entries = names.enumerated().map { index, name in
      listing(
        name,
        identity: .inode(device: 1, inode: UInt64(index + 1)),
        directoryURL: directoryURL,
        hidden: name == ".hidden"
      )
    }

    let ordinary = makeBrowserItems(
      entries: entries,
      directoryID: directoryID,
      policy: DirectoryPolicy()
    )
    let descending = makeBrowserItems(
      entries: entries,
      directoryID: directoryID,
      policy: DirectoryPolicy(
        showsHiddenFiles: true,
        sort: .nameDescending,
        directoriesFirst: true
      )
    )

    #expect(!ordinary.map(\.name).contains(".hidden"))
    #expect(descending.map(\.name).contains(".hidden"))
    #expect(Set(descending.map(\.name)) == Set(names))
    #expect(ordinary.map(\.name) != descending.map(\.name))
    #expect(descending.contains { $0.name == "line\nbreak" })
    #expect(descending.contains { $0.name == "-leading-dash" })
  }
}

private func listing(
  _ name: String,
  identity: FileSystemIdentity,
  directoryURL: URL,
  hidden: Bool = false
) -> DirectoryListingEntry {
  DirectoryListingEntry(
    name: name,
    url: directoryURL.appendingPathComponent(name),
    kind: .file,
    metadata: ItemMetadata(identity: identity, isReadable: true),
    isHidden: hidden
  )
}
