import Foundation
import GIFEditorCore

/// Reading, identifying and decoding the files the headless subcommands
/// accept.
///
/// Every subcommand starts here, so the three ways an input can be wrong —
/// missing, unrecognized, damaged — are classified in exactly one place and
/// every subcommand exits with the same code for the same cause.
///
/// Recognition and decoding delegate to `DocumentIngestion`, so interactive
/// and headless callers cannot drift onto different format rules. This adapter
/// owns only file transport, CLI error categories, and reporting metadata.
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
    let ingested: IngestedDocument
    do {
      ingested = try DocumentIngestion.ingest(
        data,
        source: .file(url),
        policy: GIFImportPolicy(dithering: dithering)
      )
    } catch {
      switch error {
      case .unrecognizedFormat:
        throw .unrecognizedFormat(url)
      case .malformed(_, let detail):
        throw .damaged(url, detail: detail)
      }
    }

    let kind: FileKind =
      switch ingested.kind {
      case .gif: .gif
      case .project: .project
    }
    return Loaded(url: url, kind: kind, byteCount: data.count, document: ingested.document)
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
