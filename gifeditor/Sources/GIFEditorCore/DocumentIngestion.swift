import Foundation

/// The authoring format identified from externally supplied bytes.
public enum DocumentKind: String, Hashable, Sendable, Codable {
  case gif
  case project
}

/// Descriptive information about where bytes came from.
///
/// This is provenance, not persistence authority. In particular, a file URL
/// here does not make that file a Project backing that plain Save may replace.
public struct DocumentSourceMetadata: Hashable, Sendable {
  public var url: URL?
  public var displayName: String?

  public init(url: URL? = nil, displayName: String? = nil) {
    self.url = url
    self.displayName = displayName
  }

  public static func file(_ url: URL) -> DocumentSourceMetadata {
    DocumentSourceMetadata(url: url, displayName: url.lastPathComponent)
  }
}

/// Import choices that change how foreign bytes become editable state.
public struct GIFImportPolicy: Hashable, Sendable {
  public var dithering: Quantizer.Dithering

  public init(dithering: Quantizer.Dithering = .none) {
    self.dithering = dithering
  }
}

/// Provenance retained after successful ingestion.
public struct DocumentProvenance: Hashable, Sendable {
  public let source: DocumentSourceMetadata
  public let kind: DocumentKind

  public init(source: DocumentSourceMetadata, kind: DocumentKind) {
    self.source = source
    self.kind = kind
  }
}

/// A decoded authoring document together with the evidence used to route it.
public struct IngestedDocument: Hashable, Sendable {
  public let document: GIFDocument
  public let provenance: DocumentProvenance

  /// Convenience view of the single kind stored in provenance.
  public var kind: DocumentKind {
    provenance.kind
  }

  init(
    document: GIFDocument,
    provenance: DocumentProvenance
  ) {
    self.document = document
    self.provenance = provenance
  }
}

/// Neutral failures from recognizing or interpreting already-read bytes.
///
/// File transport and user-facing wording stay in adapters. `detail` is for
/// diagnostics and deliberately does not expose a decoder-specific error type
/// as part of this module's interface.
public enum DocumentIngestionError: Error, Hashable, Sendable, CustomStringConvertible {
  case unrecognizedFormat
  case malformed(kind: DocumentKind, detail: String)

  public var description: String {
    switch self {
    case .unrecognizedFormat:
      return "unrecognized document format"
    case .malformed(let kind, let detail):
      return "\(kind.rawValue) document is malformed: \(detail)"
    }
  }
}

/// Recognizes and interprets externally supplied bytes as editable state.
///
/// This is the single format-routing seam shared by interactive and headless
/// adapters. It is synchronous and performs no file access, presentation,
/// recents update, or persistence decision.
public enum DocumentIngestion {
  /// Identifies a supported format from a bounded prefix.
  public static func kind(of data: Data) -> DocumentKind? {
    if ProjectFile.hasGIFSignature(data) {
      return .gif
    }

    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
    for byte in data.prefix(64) where !whitespace.contains(byte) {
      return byte == UInt8(ascii: "{") ? .project : nil
    }
    return nil
  }

  public static func ingest(
    _ data: Data,
    source: DocumentSourceMetadata = DocumentSourceMetadata(),
    policy: GIFImportPolicy = GIFImportPolicy()
  ) throws(DocumentIngestionError) -> IngestedDocument {
    guard let kind = kind(of: data) else {
      throw .unrecognizedFormat
    }

    let document: GIFDocument
    do {
      switch kind {
      case .gif:
        document = try GIFLoader.load(
          data: data,
          dithering: policy.dithering
        )
      case .project:
        document = try ProjectFile.document(from: data)
      }
    } catch {
      throw .malformed(kind: kind, detail: String(describing: error))
    }

    return IngestedDocument(
      document: document,
      provenance: DocumentProvenance(source: source, kind: kind)
    )
  }
}
