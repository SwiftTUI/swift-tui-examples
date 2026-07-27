import Foundation
import GIFEditorCore

/// Document load/save/encode for the editor. Stateless: every entry
/// takes the document (or a target URL) and returns a value, so the
/// coordinator keeps ownership of `document` and the dirty flag while
/// this type owns only the encoding and filesystem details.
enum GIFDocumentIO {
  /// Outcome of a save attempt, surfaced so the coordinator can update
  /// `document.path`, the clean generation, and the status line without
  /// this type reaching back into the view model.
  enum SaveOutcome {
    case needsOverwriteConfirmation
    case saved
    case failed(any Error)
  }

  /// The URL a save defaults to: the document's existing path, or
  /// `untitled.gif` in the current working directory.
  static func defaultSaveURL(for document: GIFDocument) -> URL {
    document.path
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("untitled.gif")
  }

  /// Resolves user-entered save path text into a URL, expanding `~` and
  /// rooting relative paths at the current working directory. Returns
  /// `nil` for blank input.
  static func saveURL(from pathText: String) -> URL? {
    let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let expanded = (trimmed as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
      return URL(fileURLWithPath: expanded)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(expanded)
  }

  /// Encodes `document` and writes it to `target`. Refuses to clobber an
  /// existing file unless `overwriteExisting` is set, matching the
  /// editor's save-confirmation contract.
  static func save(
    document: GIFDocument,
    to target: URL,
    overwriteExisting: Bool
  ) -> SaveOutcome {
    if FileManager.default.fileExists(atPath: target.path) && !overwriteExisting {
      return .needsOverwriteConfirmation
    }

    do {
      let bytes = try GIFEncoder.encode(document: document)
      try Data(bytes).write(to: target, options: .atomic)
      return .saved
    } catch {
      return .failed(error)
    }
  }

  static func saveOffMain(
    document: GIFDocument,
    to target: URL,
    overwriteExisting: Bool
  ) async -> SaveOutcome {
    await Task.detached(priority: .userInitiated) {
      save(document: document, to: target, overwriteExisting: overwriteExisting)
    }.value
  }
}

// MARK: - Project files

extension GIFDocumentIO {
  /// True when `url` names a project file rather than an export.
  ///
  /// Extension-based, and only ever used to decide where a *save*
  /// goes. Deciding what an existing file *is* goes through
  /// ``fileKind(of:)`` instead — a name is a claim, and bytes are
  /// evidence.
  static func isProjectFile(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == ProjectFile.fileExtension
  }

  /// The URL `Save` writes back to without prompting, or `nil` when the
  /// coordinator should fall through to `Save As`.
  ///
  /// A document imported from a GIF has a `path`, and writing a layered
  /// document back over it would flatten every layer — so the plain
  /// `Save` verb refuses it and the user gets a location prompt whose
  /// default is the `.halfcell` sibling. Saving must never be the
  /// thing that destroys the work.
  static func projectSaveTarget(for document: GIFDocument) -> URL? {
    guard let path = document.path, isProjectFile(path) else { return nil }
    return path
  }

  /// What a `Save As` field is pre-filled with: the document's own path
  /// re-extensioned to `.halfcell` when it has one, otherwise
  /// `untitled.halfcell` in the working directory — the same shape as
  /// ``defaultSaveURL(for:)``, which now serves GIF *export*.
  static func defaultProjectSaveURL(for document: GIFDocument) -> URL {
    guard let path = document.path else {
      return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("untitled.\(ProjectFile.fileExtension)")
    }
    if isProjectFile(path) { return path }
    return path.deletingPathExtension().appendingPathExtension(ProjectFile.fileExtension)
  }

  /// Encodes `document` as a project file and writes it to `target`.
  ///
  /// Same contract as the GIF save it sits beside: the existing-file
  /// check comes first so the coordinator can raise its confirmation
  /// sheet, and the write is atomic so an interrupted save cannot leave
  /// a half-file where a project used to be.
  static func saveProject(
    document: GIFDocument,
    to target: URL,
    overwriteExisting: Bool
  ) -> SaveOutcome {
    if FileManager.default.fileExists(atPath: target.path) && !overwriteExisting {
      return .needsOverwriteConfirmation
    }

    do {
      let data = try ProjectFile.data(for: document)
      try data.write(to: target, options: .atomic)
      return .saved
    } catch {
      return .failed(error)
    }
  }

  /// Encoding a full-size document is base64 over every pixel plane in
  /// every layer of every frame — measurable work, and not the main
  /// actor's, exactly as for the GIF path.
  static func saveProjectOffMain(
    document: GIFDocument,
    to target: URL,
    overwriteExisting: Bool
  ) async -> SaveOutcome {
    await Task.detached(priority: .userInitiated) {
      saveProject(document: document, to: target, overwriteExisting: overwriteExisting)
    }.value
  }
}

// MARK: - Opening

extension GIFDocumentIO {
  /// What the first few bytes of a file say it is.
  enum FileKind: Hashable, Sendable {
    case gif
    case project
  }

  enum OpenError: Error, CustomStringConvertible {
    /// The bytes could not be read at all.
    case unreadable(URL)

    /// The bytes are neither a GIF nor a project envelope. Reported
    /// before any decoder sees them, so the user is told "this is not a
    /// file I can open" instead of being handed a JSON parse error
    /// about a byte offset in a GIF.
    case unrecognizedFormat(URL)

    var description: String {
      switch self {
      case .unreadable(let url):
        return "could not read \(url.lastPathComponent)"
      case .unrecognizedFormat(let url):
        return
          "\(url.lastPathComponent) is neither a GIF nor a .\(ProjectFile.fileExtension) project"
      }
    }
  }

  /// Sniffs `data` for a format this editor opens, or returns `nil`.
  ///
  /// Routing on content rather than on the extension is a binding
  /// decision of the file-lifecycle work: a project saved without an
  /// extension, or a GIF someone renamed `.halfcell` to get it into a
  /// file list, still reaches the right reader. The project probe is
  /// the JSON object opener — the envelope is `{"formatVersion":…}` and
  /// nothing else this app writes starts with `{` — with leading
  /// whitespace skipped so a hand-edited file that gained a newline
  /// still opens.
  static func fileKind(of data: Data) -> FileKind? {
    if ProjectFile.hasGIFSignature(data) { return .gif }

    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
    // Bounded so a huge file of spaces cannot turn a sniff into a scan.
    for byte in data.prefix(64) where !whitespace.contains(byte) {
      return byte == UInt8(ascii: "{") ? .project : nil
    }
    return nil
  }

  /// Opens whatever is at `url`, routing on its bytes.
  ///
  /// GIFs come back through the importer (quantized, one layer per
  /// frame); projects come back through the hardened project decoder
  /// with `path` restored, since the format strips it on the way out
  /// and the caller is the one who knows which file it just read.
  static func open(
    contentsOf url: URL,
    dithering: Quantizer.Dithering = .none
  ) throws -> GIFDocument {
    guard let data = try? Data(contentsOf: url) else {
      throw OpenError.unreadable(url)
    }

    switch fileKind(of: data) {
    case .gif:
      return try GIFLoader.load(data: data, sourcePath: url, dithering: dithering)
    case .project:
      var document = try ProjectFile.document(from: data)
      document.path = url
      return document
    case nil:
      throw OpenError.unrecognizedFormat(url)
    }
  }

  /// Decoding is the mirror of encoding: base64 and quantization over
  /// every pixel of every frame, so it stays off the main actor too.
  static func openOffMain(
    contentsOf url: URL,
    dithering: Quantizer.Dithering = .none
  ) async throws -> GIFDocument {
    try await Task.detached(priority: .userInitiated) {
      try open(contentsOf: url, dithering: dithering)
    }.value
  }

  /// Where the app keeps state that outlives any one document: the
  /// recents list and the autosave recovery file.
  ///
  /// This lives on the UI side of the seam on purpose. `GIFEditorCore`
  /// takes every path as a parameter so a SwiftUI or web port can reuse
  /// it verbatim; deciding that a terminal build on this machine keeps
  /// its state in `~/.config/halfcell/` is precisely the environment
  /// assumption Core is being kept free of. `homeDirectory` is a
  /// parameter so a test never writes into the developer's real config
  /// directory.
  ///
  /// Compose the file names Core declares onto it:
  /// `RecentDocuments.defaultFileName`, `AutosaveStore.defaultFileName`.
  static func stateDirectory(homeDirectory: String = NSHomeDirectory()) -> URL {
    URL(fileURLWithPath: homeDirectory)
      .appendingPathComponent(".config")
      .appendingPathComponent("halfcell")
  }

  /// The recents state file inside `directory`. Composed here rather
  /// than at each call site so the writer, the reader and the menu that
  /// renders the list cannot drift onto different files.
  static func recentsURL(inStateDirectory directory: URL) -> URL {
    directory.appendingPathComponent(RecentDocuments.defaultFileName)
  }

  /// The autosave recovery file inside `directory`.
  static func autosaveURL(inStateDirectory directory: URL) -> URL {
    directory.appendingPathComponent(AutosaveStore.defaultFileName)
  }
}

// MARK: - Path completion

extension GIFDocumentIO {
  /// What completing partially-typed path text produced.
  ///
  /// A file picker is the eventual nicety; this is the affordance that
  /// makes a bare `TextField` usable in the meantime, and it is a pure
  /// function of the text plus the filesystem, so it is testable without
  /// rendering anything.
  struct PathCompletion: Equatable, Sendable {
    /// What the field should hold afterwards. Equal to the input when
    /// nothing matched — completing is never allowed to *lose* what the
    /// author typed.
    var text: String

    /// The names in the directory that matched the typed fragment, in
    /// sorted order, for the hint line under the field.
    var matches: [String]

    /// True when exactly one name matched, so the field now holds a
    /// complete path (with a trailing `/` if it named a directory).
    var isUnique: Bool { matches.count == 1 }

    /// True when the author has typed something no file answers to —
    /// worth saying out loud, because the alternative is a Complete
    /// button that appears to do nothing.
    var isEmpty: Bool { matches.isEmpty }
  }

  /// Completes `text` against the filesystem, extending it as far as the
  /// matching names agree.
  ///
  /// The directory portion the author typed is preserved *verbatim* in
  /// the result — `~/art/` stays `~/art/` — and expanded only for the
  /// lookup, so completing never rewrites a path into a form the author
  /// did not type. Dotfiles stay out of the candidate set until the
  /// fragment itself starts with a dot, which is the convention every
  /// shell already taught everybody.
  static func completePath(_ text: String) -> PathCompletion {
    let separator = text.lastIndex(of: "/")
    let directoryText = separator.map { String(text[...$0]) } ?? ""
    let fragment = separator.map { String(text[text.index(after: $0)...]) } ?? text

    let lookupPath =
      directoryText.isEmpty
      ? FileManager.default.currentDirectoryPath
      : (directoryText as NSString).expandingTildeInPath
    guard
      let names = try? FileManager.default.contentsOfDirectory(atPath: lookupPath)
    else {
      return PathCompletion(text: text, matches: [])
    }

    let matches =
      names
      .filter { $0.hasPrefix(fragment) }
      .filter { fragment.hasPrefix(".") || !$0.hasPrefix(".") }
      .sorted()
    guard let shared = longestCommonPrefix(of: matches) else {
      return PathCompletion(text: text, matches: [])
    }

    var completed = directoryText + shared
    if matches.count == 1 {
      var isDirectory: ObjCBool = false
      let full = (lookupPath as NSString).appendingPathComponent(matches[0])
      if FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        // The trailing separator is what makes a second completion
        // descend rather than re-complete the directory's own name.
        completed += "/"
      }
    }
    return PathCompletion(text: completed, matches: matches)
  }

  /// Longest prefix shared by every element, or `nil` for an empty list.
  private static func longestCommonPrefix(of names: [String]) -> String? {
    guard var prefix = names.first else { return nil }
    for name in names.dropFirst() {
      while !name.hasPrefix(prefix) {
        prefix.removeLast()
        if prefix.isEmpty { return "" }
      }
    }
    return prefix
  }
}
