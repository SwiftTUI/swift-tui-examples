import Foundation
import GIFEditorCore

/// What `export` can turn a document into.
///
/// The three are one flag each rather than `--format <name>` because they
/// take different kinds of destination — a base path, a directory, a file —
/// and a single `--format` option would hide that behind a value the help
/// text could only describe in prose.
public enum ExportFormat: String, Hashable, Sendable, Codable, CaseIterable {
  /// One PNG grid plus the sidecar JSON that says where each frame sits.
  case spritesheet
  /// One PNG per frame, zero-padded so a lexicographic listing is frame
  /// order.
  case frames
  /// A single animated PNG.
  case apng
}

/// A file `export` wrote.
public struct ExportedFile: Hashable, Sendable, Codable {
  public let path: String
  public let byteCount: Int
}

/// What `export` produced.
public struct ExportReport: Hashable, Sendable, Codable {
  public let format: ExportFormat
  public let source: String
  public let files: [ExportedFile]
  public let totalByteCount: Int

  public init(format: ExportFormat, source: String, files: [ExportedFile]) {
    self.format = format
    self.source = source
    self.files = files
    self.totalByteCount = files.reduce(0) { $0 + $1.byteCount }
  }
}

/// The `export` subcommand's logic: where the output goes, and putting it
/// there.
///
/// Every format decision already lives in `GIFEditorCore` — the near-square
/// column rule, the zero-padded frame names, the APNG chunk order. This
/// type owns only the two things a *command line* adds: resolving a
/// destination from an optional `-o`, and reporting what landed.
public enum HeadlessExport {

  /// Where output goes when `-o` is absent: beside the input, named after
  /// it.
  ///
  /// Pure — it never touches the filesystem — so the naming rule is
  /// testable without a temporary directory, and so a caller can print the
  /// path it *would* use.
  ///
  /// - `spritesheet` → `<dir>/<stem>-sheet`, a *base path*; the writer
  ///   appends `.png` and `.json`.
  /// - `frames` → `<dir>/<stem>-frames`, a *directory*.
  /// - `apng` → `<dir>/<stem>.png`, a *file*. Suffix-free because an
  ///   animated PNG is a PNG, and a consumer that does not know about
  ///   `acTL` still opens it as the first frame.
  ///
  /// The `-sheet` and `-frames` suffixes exist so exporting twice in two
  /// formats cannot have the second clobber the first, and so no default
  /// ever writes over the input.
  public static func defaultDestination(for format: ExportFormat, input: URL) -> URL {
    let directory = input.deletingLastPathComponent()
    let stem = baseName(for: input)
    switch format {
    case .spritesheet:
      return directory.appendingPathComponent("\(stem)-sheet")
    case .frames:
      return directory.appendingPathComponent("\(stem)-frames")
    case .apng:
      return directory.appendingPathComponent("\(stem).png")
    }
  }

  /// The file names inside an export: the input's name without its
  /// extension.
  public static func baseName(for input: URL) -> String {
    let stem = input.deletingPathExtension().lastPathComponent
    return stem.isEmpty ? "untitled" : stem
  }

  /// Resolves `-o` against the format's expectations, falling back to
  /// ``defaultDestination(for:input:)``.
  ///
  /// The one filesystem question asked here is whether an explicit `-o`
  /// names a directory that already exists. `export --apng -o build/`
  /// obviously means "put it in `build/`", and taking the argument
  /// literally would write a file *named* `build` — or fail — which is a
  /// papercut every CLI eventually grows this check to avoid. A trailing
  /// separator counts too, so the intent works before the directory does.
  public static func resolveDestination(
    for format: ExportFormat,
    input: URL,
    output: String?
  ) -> URL {
    guard let output, !output.trimmingCharacters(in: .whitespaces).isEmpty else {
      return defaultDestination(for: format, input: input)
    }

    let expanded = (output as NSString).expandingTildeInPath
    let url =
      expanded.hasPrefix("/")
      ? URL(fileURLWithPath: expanded)
      : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(expanded)

    // `frames` already wants a directory, so there is nothing to reinterpret.
    guard format != .frames else { return url }

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    let namesDirectory = (exists && isDirectory.boolValue) || expanded.hasSuffix("/")
    guard namesDirectory else { return url }

    let stem = baseName(for: input)
    switch format {
    case .spritesheet:
      return url.appendingPathComponent("\(stem)-sheet")
    case .apng:
      return url.appendingPathComponent("\(stem).png")
    case .frames:
      return url
    }
  }

  /// Encodes and writes, returning what landed on disk.
  ///
  /// `columns` surfaces ``SpritesheetExport``'s override of the near-square
  /// column rule; it is ignored by the other two formats, which have no
  /// grid.
  public static func write(
    document: GIFDocument,
    format: ExportFormat,
    destination: URL,
    baseName: String,
    columns: Int? = nil,
    source: URL
  ) throws(HeadlessError) -> ExportReport {
    let written: [URL]
    switch format {
    case .spritesheet:
      let sheet = SpritesheetExport.encode(document: document, columns: columns)
      do {
        let urls = try SpritesheetExport.write(
          sheet,
          toDirectory: destination.deletingLastPathComponent(),
          baseName: destination.lastPathComponent
        )
        written = [urls.png, urls.metadata]
      } catch {
        throw .operationFailed(
          detail: "could not write the spritesheet — \(String(describing: error))"
        )
      }

    case .frames:
      do {
        written = try FrameSequenceExport.write(
          document: document,
          toDirectory: destination,
          baseName: baseName
        )
      } catch {
        throw .operationFailed(
          detail: "could not write the frame sequence — \(String(describing: error))"
        )
      }

    case .apng:
      try HeadlessWrite.write(bytes: APNGEncoder.encode(document: document), to: destination)
      written = [destination]
    }

    var files: [ExportedFile] = []
    files.reserveCapacity(written.count)
    for url in written {
      files.append(ExportedFile(path: url.path, byteCount: try HeadlessWrite.byteCount(of: url)))
    }
    return ExportReport(format: format, source: source.path, files: files)
  }

  /// Reads, decodes, encodes and writes — what the subcommand calls.
  public static func run(
    input: URL,
    format: ExportFormat,
    output: String? = nil,
    columns: Int? = nil,
    dithering: Quantizer.Dithering = .none
  ) throws(HeadlessError) -> ExportReport {
    let loaded = try HeadlessInput.load(contentsOf: input, dithering: dithering)
    return try write(
      document: loaded.document,
      format: format,
      destination: resolveDestination(for: format, input: input, output: output),
      baseName: baseName(for: input),
      columns: columns,
      source: input
    )
  }

  /// The human-readable rendering.
  public static func text(for report: ExportReport) -> String {
    var lines = [
      "\(URL(fileURLWithPath: report.source).lastPathComponent) -> \(report.format.rawValue)"
    ]
    let width = report.files.map(\.byteCount).map { String($0).count }.max() ?? 0
    for file in report.files {
      lines.append(
        "  " + HeadlessText.rightAligned(String(file.byteCount), width: width)
          + " bytes  " + file.path
      )
    }
    return lines.joined(separator: "\n")
  }
}
