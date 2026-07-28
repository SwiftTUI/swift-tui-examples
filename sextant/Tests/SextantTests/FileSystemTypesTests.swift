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

  @Test("posix identities survive the negative device numbers devfs hands out")
  func negativeDeviceNumbersAreRepresentable() {
    // Darwin's `dev_t` is a signed `Int32`, and devfs and autofs mount points
    // carry negative device numbers — `/dev` is one, which is why every
    // listing of `/` used to trap on the widening conversion.
    let devfs = FileSystemIdentity.posixInode(
      device: Int32(-755_755_819),
      inode: UInt64(333)
    )
    // The same number `stat(1)` and Python's `os.stat` report for `/dev`:
    // 2^64 - 755_755_819.
    #expect(
      devfs == .inode(device: 18_446_744_072_953_795_797, inode: 333)
    )
  }

  @Test("posix identity widening is total and injective within a stat field type")
  func identityWideningIsInjective() {
    // Distinctness is the only property `FileSystemIdentity` needs from these
    // fields — they are opaque tokens, never arithmetic operands. Each `stat`
    // field has one concrete type per platform, so injectivity is required
    // within a type, not across them.
    let darwinDevices: [Int32] = [
      -755_755_819, -1, Int32.min, 0, 1, 16_777_234, Int32.max,
    ]
    let darwinTokens = darwinDevices.map { FileSystemIdentity.identityToken($0) }
    #expect(Set(darwinTokens).count == darwinDevices.count)

    let linuxDevices: [UInt64] = [0, 1, 2049, UInt64(UInt32.max), UInt64.max]
    let linuxTokens = linuxDevices.map { FileSystemIdentity.identityToken($0) }
    #expect(Set(linuxTokens).count == linuxDevices.count)

    // Nonnegative values keep their arithmetic value, so identities recorded
    // before this widening existed still compare equal.
    #expect(FileSystemIdentity.identityToken(Int32(16_777_234)) == 16_777_234)
    #expect(FileSystemIdentity.identityToken(UInt64.max) == UInt64.max)
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
