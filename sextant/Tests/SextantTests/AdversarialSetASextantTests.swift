import Foundation
import Testing

@testable import Sextant

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Campaign two E1 pass 2: sextant input contracts (e1s127–e1s162).
///
/// Filesystem cases build real temporary trees and remove them on every
/// exit path; search cases drain each stream to its `.finished` event, the
/// producer-owned completion signal. e1s129 needs a user that permission
/// bits apply to, so it is its own test, disabled for root.
@Suite("Campaign E1 pass 2 sextant contracts", .serialized)
struct AdversarialSetASextantTests {
  @Test(arguments: Array(127...162).filter { $0 != 129 })
  func sextant(id: Int) async throws {
    switch id {
    case 127, 128, 130, 132...137: try await e1Listing(id)
    case 131, 138, 158, 159: try await e1Search(id)
    case 139...147: e1Classification(id)
    case 148...150: try await e1DisplayNames(id)
    case 151...155: try e1Lexer(id)
    case 156, 157: try await e1ExecutableSearch(id)
    case 160, 161: e1PreviewTemplates(id)
    default: try await e1Bookmarks()
    }
  }

  @Test(
    "e1s129 a symlink into a non-searchable directory",
    .enabled(if: geteuid() != 0, "permission bits do not apply to root")
  )
  func symlinkIntoNonSearchableDirectory() async throws {
    try await e1WithDirectory { root in
      let locked = root.appendingPathComponent("locked", isDirectory: true)
      try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
      try Data("s".utf8).write(to: locked.appendingPathComponent("secret"))
      try FileManager.default.createSymbolicLink(
        atPath: root.appendingPathComponent("peek").path, withDestinationPath: "locked/secret")
      try Data("f".utf8).write(to: root.appendingPathComponent("file.txt"))
      try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
      defer {
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: locked.path)
      }
      let result = await LocalFileSystemClient().readDirectory(e1Request(root))
      // STUI-1342: the denied target lists as a broken link.
      #expect(e1Names(result) == ["file.txt", "locked", "peek"])
      #expect(e1Item(result, "peek")?.kind == .brokenSymbolicLink)
    }
  }
}

// MARK: - listing and prefixes (e1s127–e1s137)

private func e1Listing(_ id: Int) async throws {
  try await e1WithDirectory { root in
    let manager = FileManager.default
    func link(_ name: String, _ target: String) throws {
      try manager.createSymbolicLink(
        atPath: root.appendingPathComponent(name).path, withDestinationPath: target)
    }
    try Data("f".utf8).write(to: root.appendingPathComponent("file.txt"))
    let client = LocalFileSystemClient()
    switch id {
    case 127, 128, 130:
      if id == 127 { try link("loop", "loop") }
      if id == 128 {
        try link("a", "b")
        try link("b", "a")
      }
      if id == 130 { try link("odd", "file.txt/child") }
      let result = await client.readDirectory(e1Request(root))
      let expected: [String] =
        id == 127
        ? ["file.txt", "loop"] : id == 128 ? ["a", "b", "file.txt"] : ["file.txt", "odd"]
      // STUI-1342: a loop or non-directory target lists as a broken link.
      #expect(e1Names(result) == expected)
      if case .success(let snapshot) = result {
        #expect(
          snapshot.items.filter { $0.name != "file.txt" }.allSatisfy {
            $0.kind == .brokenSymbolicLink && $0.targetDirectoryID == nil
          })
      }
    case 132:
      try link("gone", "absent")
      let result = await client.readDirectory(e1Request(root))
      #expect(e1Item(result, "gone")?.kind == .brokenSymbolicLink)
    case 133:
      let names = ["tab\tname", "back\\slash", "-dash", "...", "trail ", "*?[", ":colon", "%20"]
      for name in names {
        try Data(name.utf8).write(to: root.appendingPathComponent(name))
      }
      let result = await client.readDirectory(
        e1Request(root, policy: DirectoryPolicy(showsHiddenFiles: true)))
      #expect(Set(e1Names(result)) == Set(names + ["file.txt"]))
    case 134, 136:
      let fifo = root.appendingPathComponent("pipe")
      let made = fifo.path.withCString { unsafe mkfifo($0, mode_t(0o600)) }
      try #require(made == 0)
      if id == 134 {
        try link("pipe-link", "pipe")
        let result = await client.readDirectory(e1Request(root))
        #expect(e1Item(result, "pipe")?.kind == .special(.fifo))
        #expect(e1Item(result, "pipe-link")?.kind == .symbolicLinkToSpecial(.fifo))
      } else {
        // No writer holds the FIFO open; a blocking open would never return.
        let result = await client.readPrefix(at: fifo, maximumBytes: 16)
        guard case .failure(.unsupported) = result else {
          Issue.record("expected unsupported, got \(result)")
          return
        }
      }
    case 135:
      try manager.linkItem(
        atPath: root.appendingPathComponent("file.txt").path,
        toPath: root.appendingPathComponent("two").path)
      let result = await client.readDirectory(e1Request(root))
      let one = try #require(e1Item(result, "file.txt"))
      let two = try #require(e1Item(result, "two"))
      #expect(one.listingMetadata.identity == two.listingMetadata.identity)
      #expect(one.id != two.id)
    default:
      let result = await client.readPrefix(at: root, maximumBytes: 16)
      guard case .failure(.unsupported) = result else {
        Issue.record("expected unsupported, got \(result)")
        return
      }
    }
  }
}

// MARK: - recursive search (e1s131, e1s138, e1s158, e1s159)

private func e1Search(_ id: Int) async throws {
  if id == 158 || id == 159 {
    let fileSystem = InMemoryFileSystemClient()
    let root = URL(fileURLWithPath: "/e1", isDirectory: true)
    let names = id == 158 ? ["needle-1", "needle-2", "other"] : ["e\u{301}clair.txt"]
    await fileSystem.setDirectory(
      names.map { InMemoryFileSystemEntry(name: $0, kind: .file, identity: .path("/e1/\($0)")) },
      at: root)
    let search = FilenameSearchCoordinator(
      fileSystem: fileSystem, budget: .init(batchSize: 10, maximumResults: 2))
    let (results, truncated) = await e1Drain(
      search, root: root, query: id == 158 ? "needle" : "écl")
    if id == 158 {
      #expect(results.sorted() == ["needle-1", "needle-2"])
      e1Known(
        "NEW-24: a search with exactly the result limit of matches reports the results as truncated; reaching maximumResults sets wasTruncated without checking for further matches; contract: FilenameSearchCoordinator.swift:212-214 (truncation means work remained), ColumnBrowser.swift:459-461"
      ) {
        #expect(truncated == false)
      }
    } else {
      #expect(results == ["e\u{301}clair.txt"])
    }
    return
  }
  try await e1WithDirectory { root in
    let manager = FileManager.default
    let directory = root.appendingPathComponent(id == 131 ? "sub" : "d", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    try Data("n".utf8).write(to: directory.appendingPathComponent("needle-b"))
    try Data("n".utf8).write(to: root.appendingPathComponent("needle-a"))
    try manager.createSymbolicLink(
      atPath: directory.appendingPathComponent(id == 131 ? "loop" : "up").path,
      withDestinationPath: id == 131 ? "loop" : "..")
    let search = FilenameSearchCoordinator(fileSystem: LocalFileSystemClient())
    let (results, _) = await e1Drain(search, root: root, query: "needle")
    // STUI-1342 (e1s131): search continues past the loop link's directory.
    #expect(results.sorted() == ["needle-a", "needle-b"])
  }
}

private func e1Drain(
  _ search: FilenameSearchCoordinator, root: URL, query: String
) async -> ([String], Bool?) {
  var names: [String] = []
  var truncated: Bool?
  for await event in await search.search(root: root, query: query, policy: DirectoryPolicy()) {
    switch event {
    case .batch(_, let batch): names += batch.map(\.name)
    case .finished(_, _, let wasTruncated): truncated = wasTruncated
    }
  }
  return (names, truncated)
}

// MARK: - preview classification (e1s139–e1s147)

private func e1Classification(_ id: Int) {
  let formatter = BuiltInPreviewFormatter()
  let a = UInt8(ascii: "a")
  var bytes: [UInt8]
  switch id {
  case 139: bytes = [UInt8](repeating: a, count: 8_191) + [0xC3, 0xA9, UInt8(ascii: "b")]
  case 140: bytes = [UInt8](repeating: a, count: 8_190) + Array("😀".utf8)
  case 141:
    bytes =
      [0xFF, 0xFE] + Array(repeating: [a, 0], count: 4_094).flatMap { $0 }
      + [0x3D, 0xD8, 0x00, 0xDE, a, 0]
  case 142: bytes = [UInt8](repeating: a, count: 9_000) + [0xC3, 0x28]
  case 143: bytes = [UInt8](repeating: a, count: 9_000) + [0x00, UInt8(ascii: "b")]
  case 144:
    bytes =
      [UInt8](repeating: a, count: BuiltInPreviewFormatter.maximumReadBytes - 1)
      + [0xC3, 0xA9, UInt8(ascii: "b")]
  case 145: bytes = [0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00]
  case 146: bytes = [0xEF, 0xBB, 0xBF]
  default: bytes = [0x00, 0x68, 0x00, 0x69]
  }
  let data = Data(bytes)
  switch id {
  case 139, 140, 141:
    // Precondition: the bytes are well-formed in their encoding.
    let encoding: PreviewTextEncoding = id == 141 ? .utf16LittleEndian : .utf8
    let payload = id == 141 ? Data(data.dropFirst(2)) : data
    #expect(String(data: payload, encoding: id == 141 ? .utf16LittleEndian : .utf8) != nil)
    #expect(data.count > BuiltInPreviewFormatter.classificationByteLimit)
    // STUI-1343: the scalar the 8 KiB sample boundary splits is trimmed.
    #expect(formatter.classify(data) == .text(encoding))
  case 142, 143:
    let body = formatter.format(
      prefix: FilePrefix(data: data, totalByteCount: UInt64(data.count), isTruncated: false))
    // STUI-1343: text versus binary is decided on the whole capped read.
    guard case .hexadecimal = body else {
      Issue.record("expected a hexadecimal preview, got \(e1Describe(body))")
      return
    }
  case 144:
    let read = Data(data.prefix(BuiltInPreviewFormatter.requestedReadBytes))
    let body = formatter.format(
      prefix: FilePrefix(data: read, totalByteCount: UInt64(data.count), isTruncated: true))
    guard case .text(let preview) = body else {
      Issue.record("expected a text preview, got \(e1Describe(body))")
      return
    }
    #expect(preview.isTruncated)
    // STUI-1343: the cap's partial scalar is trimmed, not repaired.
    #expect(!preview.text.unicodeScalars.contains("\u{FFFD}"))
    #expect(
      preview.text == String(repeating: "a", count: BuiltInPreviewFormatter.maximumReadBytes - 1))
  case 145:
    // STUI-1343: the UTF-32LE mark is checked before the UTF-16LE one.
    #expect(formatter.classify(data) == .binary)
  case 146:
    #expect(formatter.classify(data) == .text(.utf8))
    #expect(
      formatter.format(prefix: FilePrefix(data: data, totalByteCount: 3, isTruncated: false))
        == .text(TextPreview(text: "", encoding: .utf8, isTruncated: false)))
  default:
    #expect(formatter.classify(data) == .binary)
  }
}

private func e1Describe(_ body: BuiltInPreviewBody) -> String {
  switch body {
  case .text(let preview): "text(\(preview.text.unicodeScalars.suffix(3).map(\.value)))"
  case .hexadecimal: "hexadecimal"
  default: "\(body)"
  }
}

// MARK: - display names (e1s148–e1s150)

private func e1DisplayNames(_ id: Int) async throws {
  let fileSystem = InMemoryFileSystemClient()
  let directory = URL(fileURLWithPath: "/e1", isDirectory: true)
  let name = id == 148 ? "👨‍👩‍👧.txt" : id == 149 ? "🏴󠁧󠁢󠁳󠁣󠁴󠁿.txt" : "a\u{1B}b"
  let url = directory.appendingPathComponent(name)
  let metadata = ItemMetadata(identity: .path(url.path), byteCount: 1, isReadable: true)
  await fileSystem.setFile(Data("x".utf8), metadata: metadata, at: url)
  let file = BrowserItem(
    id: BrowserItemID(identity: .path(url.path)),
    directoryID: DirectoryID(identity: .path(directory.path)),
    name: name, url: url, kind: .file, listingMetadata: metadata)
  let previewer = BuiltInPreviewer(fileSystem: fileSystem)
  if id == 149 {
    let parent = BrowserItem(
      id: BrowserItemID(identity: .path(directory.path)),
      directoryID: DirectoryID(identity: .path("/")),
      name: "e1", url: directory, kind: .directory,
      listingMetadata: ItemMetadata(identity: .path(directory.path)))
    let snapshot = DirectorySnapshot(request: e1Request(directory), items: [file])
    let preview = await previewer.preview(item: parent, directorySnapshot: snapshot)
    guard case .directorySummary(let summary) = preview.body else {
      Issue.record("expected a directory summary")
      return
    }
    // STUI-1344: a tag-sequence flag keeps its tag characters.
    #expect(summary.entryNames == [name])
    return
  }
  let preview = await previewer.preview(item: file)
  if id == 148 {
    // STUI-1344: a ZWJ sequence keeps its joiners.
    #expect(preview.metadata.displayName.unicodeScalars.elementsEqual(name.unicodeScalars))
  } else {
    #expect(preview.metadata.displayName == "a\u{FFFD}b")
  }
}

// MARK: - editor command lexing (e1s151–e1s155)

private func e1Lexer(_ id: Int) throws {
  let lexer = POSIXWordLexer()
  switch id {
  case 151:
    let words = try lexer.parse("edit \"C:\\temp\"")
    // STUI-1344: inside double quotes `\t` is not an escape (XCU 2.2.3).
    #expect(words == ["edit", "C:\\temp"])
  case 152:
    let words = try lexer.parse("code \\\n--wait")
    // STUI-1344: backslash-newline is a removed continuation (XCU 2.2.1).
    #expect(words == ["code", "--wait"])
  case 153, 154:
    let source = id == 153 ? "/Apps/My\u{A0}Editor --wait" : "エディタ\u{3000}起動"
    let words = try lexer.parse(source)
    // STUI-1344: only space, tab and newline delimit (XCU 2.3, XBD 7.3.1).
    #expect(
      words == (id == 153 ? ["/Apps/My\u{A0}Editor", "--wait"] : ["エディタ\u{3000}起動"]))
  default:
    #expect(try lexer.parse("'it'\\''s' \"a\\\"b\" \"\"") == ["it's", "a\"b", ""])
  }
}

// MARK: - preview executable search (e1s156, e1s157)

private func e1ExecutableSearch(_ id: Int) async throws {
  try await e1WithDirectory { root in
    let manager = FileManager.default
    let first = root.appendingPathComponent("dirA", isDirectory: true)
    let second = root.appendingPathComponent("dirB", isDirectory: true)
    try manager.createDirectory(at: first, withIntermediateDirectories: false)
    try manager.createDirectory(at: second, withIntermediateDirectories: false)
    if id == 156 {
      try manager.createDirectory(
        at: first.appendingPathComponent("tool", isDirectory: true),
        withIntermediateDirectories: false)
    }
    let tool = second.appendingPathComponent("tool")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    let path = id == 156 ? "\(first.path):\(second.path)" : "\(first.path):\(second.path)/"
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("e1"), displayName: "E1", executable: "tool", isInteractive: false,
      priority: 0, arguments: { [$0.path] })
    let found = await PreviewExecutableCache.live(path: path).availability(for: [adapter])["tool"]
    let resolved = found.map(URL.init(fileURLWithPath:))
    #expect(resolved?.lastPathComponent == "tool")
    if id == 156 {
      e1Known(
        "NEW-23: a directory named like a preview tool earlier in PATH is chosen as its executable; PreviewExecutableCache.live accepts FileManager.isExecutableFile, which is true for searchable directories; contract: POSIX XCU 2.9.1.4 (first executable file), HandoffClient.swift:299-312"
      ) {
        #expect(resolved?.deletingLastPathComponent().lastPathComponent == "dirB")
      }
    } else {
      #expect(resolved?.deletingLastPathComponent().lastPathComponent == "dirB")
    }
  }
}

// MARK: - preview templates (e1s160, e1s161)

private func e1PreviewTemplates(_ id: Int) {
  let adapter =
    id == 160
    ? ExternalPreviewConfiguration(
      id: "py", displayName: "Py", executable: "python3",
      arguments: ["-c", "import sys; print(open(sys.argv[1]).read())", "{path}"])
    : ExternalPreviewConfiguration(
      id: "nice", displayName: "Nice", executable: "nice",
      arguments: ["sh", "-c", "cat \"$1\"", "sh", "{path}"])
  e1Known(
    "NEW-25: preview templates that run inline interpreter source are accepted; executesInterpreterSource recognises only eight shell basenames, directly or after env; contract: README.md:93-96, SextantConfiguration.swift:335-336"
  ) {
    #expect(throws: ConfigurationFailure.previewAdapterContainsShellSource(adapter.id)) {
      _ = try SextantConfiguration(previewAdapters: [adapter]).validated()
    }
  }
}

// MARK: - bookmarks (e1s162)

private func e1Bookmarks() async throws {
  try await e1WithDirectory { root in
    let composed = root.appendingPathComponent("\u{E9}")
    let decomposed = root.appendingPathComponent("e\u{301}")
    try Data("1".utf8).write(to: composed)
    try Data("2".utf8).write(to: decomposed)
    // Oracle from the filesystem: are these one file or two?
    let distinct = try FileManager.default.contentsOfDirectory(atPath: root.path).count
    try #require(distinct == 1 || distinct == 2)
    let repository = SextantStateRepository(
      client: .jsonFile(at: root.appendingPathComponent("state.json")))
    #expect(try await repository.toggleBookmark(composed))
    let second = try await repository.toggleBookmark(decomposed)
    if distinct == 1 {
      #expect(second == false)
    } else {
      e1Known(
        "NEW-26: bookmarking one of two distinct NFC/NFD-named files reports the other as already bookmarked; bookmark identity is Swift String equality, which is canonical equivalence; contract: POSIX filenames are byte strings (two inodes here)"
      ) {
        #expect(second)
      }
    }
  }
}

// MARK: - fixtures

private func e1Known(_ comment: Comment, _ body: () throws -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_E1_UNMARKED"] == "1" {
    do { try body() } catch { Issue.record(error, comment) }
  } else {
    withKnownIssue(comment) { try body() }
  }
}

private func e1Request(_ url: URL, policy: DirectoryPolicy = DirectoryPolicy()) -> DirectoryRequest
{
  DirectoryRequest(
    id: DirectoryRequestID(rawValue: 1),
    directoryID: DirectoryID(identity: .pathFallback(for: url)),
    url: url,
    policy: policy)
}

private func e1Names(_ result: Result<DirectorySnapshot, FileSystemFailure>) -> [String] {
  guard case .success(let snapshot) = result else {
    Issue.record("listing failed: \(result)")
    return []
  }
  return snapshot.items.map(\.name).sorted()
}

private func e1Item(
  _ result: Result<DirectorySnapshot, FileSystemFailure>, _ name: String
) -> BrowserItem? {
  guard case .success(let snapshot) = result else { return nil }
  return snapshot.items.first { $0.name == name }
}

private func e1WithDirectory(_ body: (URL) async throws -> Void) async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("e1-sextant-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: root) }
  try await body(root)
}
