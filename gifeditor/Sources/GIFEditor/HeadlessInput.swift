import Foundation
import GIFEditorCore

/// Reading, identifying and decoding the files the headless subcommands
/// accept.
///
/// Every subcommand starts here, so the three ways an input can be wrong —
/// missing, unrecognized, damaged — are classified in exactly one place and
/// every subcommand exits with the same code for the same cause.
///
/// The sniff duplicates the one the editor uses. `GIFDocumentIO.fileKind(of:)`
/// is internal to `GIFEditorUI`, and the alternative to two small copies is
/// promoting an editor-coordinator type into public API so a CLI can call four
/// lines of it. Both copies test the same two markers, and both are pinned by
/// tests against the same checked-in fixtures.
public enum HeadlessInput {

  /// What the first bytes of a file say it is.
  public enum FileKind: String, Hashable, Sendable, Codable {
    case gif
    case project

    /// How the kind is named in error text — "a GIF", "a halfcell project".
    public var article: String {
      switch self {
      case .gif:
        return "a GIF"
      case .project:
        return "a .\(ProjectFile.fileExtension) project"
      }
    }
  }

  /// A file that has been read, identified and decoded.
  public struct Loaded: Sendable {
    public let url: URL
    public let kind: FileKind
    /// The file's size on disk, kept because every subcommand reports it
    /// and re-stating the file after the fact would be a second answer to
    /// a question already answered.
    public let byteCount: Int
    public let document: GIFDocument
  }

  /// Sniffs `data` for a format this build reads, or returns `nil`.
  ///
  /// The project probe is the JSON object opener — the envelope is
  /// `{"formatVersion":…}` and nothing else this app writes starts with
  /// `{` — with leading whitespace skipped so a hand-edited file that
  /// gained a newline still opens, and bounded so a huge file of spaces
  /// cannot turn a sniff into a scan.
  public static func fileKind(of data: Data) -> FileKind? {
    if ProjectFile.hasGIFSignature(data) { return .gif }

    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
    for byte in data.prefix(64) where !whitespace.contains(byte) {
      return byte == UInt8(ascii: "{") ? .project : nil
    }
    return nil
  }

  /// Reads the bytes at `url`, distinguishing "not there" from "there and
  /// unreadable" so the two land on their own exit codes.
  public static func read(contentsOf url: URL) throws(HeadlessError) -> Data {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw .fileNotFound(url)
    }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw .unreadable(url, detail: String(describing: error))
    }
  }

  /// Decodes already-read bytes, routing on the sniff.
  ///
  /// Split from ``read(contentsOf:)`` so a test can hand in bytes it
  /// synthesized without owning a file, and so nothing downstream has to
  /// read the file a second time.
  public static func decode(
    data: Data,
    url: URL,
    dithering: Quantizer.Dithering = .none
  ) throws(HeadlessError) -> Loaded {
    switch fileKind(of: data) {
    case .gif:
      let document: GIFDocument
      do {
        document = try GIFLoader.load(data: data, sourcePath: url, dithering: dithering)
      } catch {
        throw .damaged(url, detail: String(describing: error))
      }
      // The document's loop count *is* the file's: `GIFLoader` reads the
      // application extension the decoder now surfaces, and defaults an
      // absent one to "plays once" rather than to "forever".
      return Loaded(url: url, kind: .gif, byteCount: data.count, document: document)
    case .project:
      var document: GIFDocument
      do {
        document = try ProjectFile.document(from: data)
      } catch {
        throw .damaged(url, detail: String(describing: error))
      }
      document.path = url
      return Loaded(url: url, kind: .project, byteCount: data.count, document: document)
    case nil:
      throw .unrecognizedFormat(url)
    }
  }

  /// Reads and decodes in one step — what a subcommand calls.
  public static func load(
    contentsOf url: URL,
    dithering: Quantizer.Dithering = .none
  ) throws(HeadlessError) -> Loaded {
    let data = try read(contentsOf: url)
    return try decode(data: data, url: url, dithering: dithering)
  }

  /// The loop count a GIF with no `NETSCAPE2.0` block has: the format
  /// defines the animation as playing through once.
  ///
  /// Zero, in this and in ``GIFDocument/loopCount``, means forever.
  ///
  /// One spelling of the constant, in `GIFEditorCore` beside the loader
  /// that applies it. This is the CLI's name for it.
  public static let playsOnce = GIFLoader.playsOnce

  /// The loop count declared by a GIF's `NETSCAPE2.0` application
  /// extension, or `nil` when the file carries none.
  ///
  /// This was a second, byte-for-byte copy of the loader's raw-byte scan,
  /// written when the vendored decoder discarded the extension and
  /// `Vendor/` was read-only. The decoder now surfaces the count, the
  /// loader reads it from there, and this is the CLI's name for the same
  /// question — see ``GIFLoader/declaredLoopCount(in:)``.
  public static func gifLoopCount(in data: Data) -> Int? {
    GIFLoader.declaredLoopCount(in: data)
  }
}
