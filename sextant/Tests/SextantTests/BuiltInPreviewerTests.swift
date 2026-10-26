import Foundation
import Testing

@testable import Sextant

@Suite("Built-in previewer")
struct BuiltInPreviewerTests {
  @Test("file preview requests exactly one bounded prefix")
  func boundedFileRead() async {
    let client = InMemoryFileSystemClient()
    let url = URL(fileURLWithPath: "/fixture/large.txt")
    let metadata = ItemMetadata(
      identity: .inode(device: 1, inode: 2),
      byteCount: UInt64(BuiltInPreviewFormatter.requestedReadBytes + 10),
      modificationDate: Date(timeIntervalSince1970: 123),
      isReadable: true
    )
    await client.setFile(
      Data(
        repeating: Character("a").asciiValue!,
        count: BuiltInPreviewFormatter.requestedReadBytes + 10
      ),
      metadata: metadata,
      at: url
    )

    let preview = await BuiltInPreviewer(fileSystem: client).preview(
      item: item(url: url, kind: .file, metadata: metadata)
    )

    #expect(
      await client.recordedPrefixReads()
        == [
          InMemoryFileSystemClient.PrefixRead(
            url: url,
            maximumBytes: BuiltInPreviewFormatter.requestedReadBytes
          )
        ]
    )
    #expect(preview.metadata.size == metadata.byteCount)
    guard case .text(let text) = preview.body else {
      Issue.record("expected text preview")
      return
    }
    #expect(text.text.utf8.count == BuiltInPreviewFormatter.maximumReadBytes)
    #expect(text.isTruncated)
  }

  @Test("special files are refused before a prefix read")
  func specialFile() async {
    let client = InMemoryFileSystemClient()
    let url = URL(fileURLWithPath: "/fixture/socket")
    let metadata = ItemMetadata(
      identity: .path(url.path),
      isReadable: true
    )
    await client.setMetadata(.success(metadata), at: url)

    let preview = await BuiltInPreviewer(fileSystem: client).preview(
      item: item(url: url, kind: .special(.socket), metadata: metadata)
    )

    #expect(preview.body == .unavailable(.specialFile))
    #expect(await client.recordedPrefixReads().isEmpty)
  }

  @Test("directory summary uses the supplied snapshot")
  func directorySummary() async {
    let client = InMemoryFileSystemClient()
    let directoryURL = URL(fileURLWithPath: "/fixture")
    let directoryID = DirectoryID(identity: .inode(device: 1, inode: 10))
    let directoryMetadata = ItemMetadata(
      identity: directoryID.identity,
      isReadable: true,
      isExecutable: true
    )
    await client.setMetadata(.success(directoryMetadata), at: directoryURL)
    let request = DirectoryRequest(
      id: DirectoryRequestID(rawValue: 1),
      directoryID: directoryID,
      url: directoryURL
    )
    let childFileMetadata = ItemMetadata(
      identity: .inode(device: 1, inode: 11),
      byteCount: 42,
      isReadable: true
    )
    let childDirectoryMetadata = ItemMetadata(
      identity: .inode(device: 1, inode: 12),
      isReadable: true,
      isExecutable: true
    )
    let snapshot = DirectorySnapshot(
      request: request,
      items: [
        item(
          url: directoryURL.appendingPathComponent("file"),
          kind: .file,
          metadata: childFileMetadata,
          directoryID: directoryID
        ),
        item(
          url: directoryURL.appendingPathComponent("child"),
          kind: .directory,
          metadata: childDirectoryMetadata,
          directoryID: directoryID
        ),
      ]
    )

    let preview = await BuiltInPreviewer(fileSystem: client).preview(
      item: item(
        url: directoryURL,
        kind: .directory,
        metadata: directoryMetadata,
        directoryID: directoryID
      ),
      directorySnapshot: snapshot
    )

    #expect(
      preview.body
        == .directorySummary(
          DirectorySummary(
            itemCount: 2,
            directoryCount: 1,
            fileCount: 1,
            specialCount: 0,
            totalKnownBytes: 42,
            entryNames: ["file", "child/"],
            hiddenEntryCount: 0
          )
        )
    )
    #expect(await client.recordedDirectoryRequests().isEmpty)
    #expect(await client.recordedPrefixReads().isEmpty)
  }

  /// Emoji sequences keep their joiners, variation selectors, modifiers and
  /// tag characters (UTS #51 2.3, ED-14a); terminal, bidi and other format
  /// controls are still replaced, including joiners and tags out of place.
  @Test(
    "display names keep emoji sequences and replace controls",
    arguments: [
      ("\u{2764}\u{FE0F}.txt", "\u{2764}\u{FE0F}.txt"),
      ("\u{1F44D}\u{1F3FD}", "\u{1F44D}\u{1F3FD}"),
      ("\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"),
      ("\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}", "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"),
      ("a\u{202E}txt.exe", "a\u{FFFD}txt.exe"),
      ("\u{2066}x\u{2069}\u{200E}\u{200F}\u{061C}", "\u{FFFD}x\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}"),
      ("a\u{200B}b\u{FEFF}c\u{00AD}d", "a\u{FFFD}b\u{FFFD}c\u{FFFD}d"),
      ("a\u{9B}31m\u{7F}", "a\u{FFFD}31m\u{FFFD}"),
      ("a\u{200D}b", "a\u{FFFD}b"),
      ("\u{1F600}\u{200D}", "\u{1F600}\u{FFFD}"),
      ("\u{200D}\u{1F600}", "\u{FFFD}\u{1F600}"),
      ("a\u{E0068}\u{E0069}\u{E007F}", "a\u{FFFD}\u{FFFD}\u{FFFD}"),
      ("\u{1F3F4}\u{E0068}\u{E0069}", "\u{1F3F4}\u{FFFD}\u{FFFD}"),
      ("\u{1F3F4}\u{E007F}", "\u{1F3F4}\u{FFFD}"),
    ])
  func displayNamesKeepEmojiAndReplaceControls(name: String, expected: String) async {
    let client = InMemoryFileSystemClient()
    let url = URL(fileURLWithPath: "/fixture").appendingPathComponent(name)
    let metadata = ItemMetadata(identity: .path(url.path), isReadable: true)
    let file = BrowserItem(
      id: BrowserItemID(identity: metadata.identity),
      directoryID: DirectoryID(identity: .path("/fixture")),
      name: name,
      url: url,
      kind: .special(.fifo),
      listingMetadata: metadata
    )

    let preview = await BuiltInPreviewer(fileSystem: client).preview(item: file)

    #expect(preview.metadata.displayName.unicodeScalars.elementsEqual(expected.unicodeScalars))
  }

  private func item(
    url: URL,
    kind: BrowserItemKind,
    metadata: ItemMetadata,
    directoryID: DirectoryID = DirectoryID(identity: .path("/fixture"))
  ) -> BrowserItem {
    BrowserItem(
      id: BrowserItemID(identity: metadata.identity),
      directoryID: directoryID,
      targetDirectoryID: kind.isDirectoryLike
        ? DirectoryID(identity: metadata.identity)
        : nil,
      name: url.lastPathComponent,
      url: url,
      kind: kind,
      listingMetadata: metadata
    )
  }
}
