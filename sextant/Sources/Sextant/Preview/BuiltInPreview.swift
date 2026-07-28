public import Foundation

public enum PreviewContentClassification: Equatable, Sendable {
  case text(PreviewTextEncoding)
  case binary
}

public enum PreviewTextEncoding: String, Equatable, Sendable {
  case utf8 = "UTF-8"
  case utf16LittleEndian = "UTF-16 LE"
  case utf16BigEndian = "UTF-16 BE"
}

public struct PreviewMetadata: Equatable, Sendable {
  public var displayName: String
  public var path: String
  public var kind: String
  public var size: UInt64?
  public var modificationDate: Date?

  public init(
    displayName: String,
    path: String,
    kind: String,
    size: UInt64? = nil,
    modificationDate: Date? = nil
  ) {
    self.displayName = displayName
    self.path = path
    self.kind = kind
    self.size = size
    self.modificationDate = modificationDate
  }
}

public struct TextPreview: Equatable, Sendable {
  public var text: String
  public var encoding: PreviewTextEncoding
  public var isTruncated: Bool

  public init(
    text: String,
    encoding: PreviewTextEncoding,
    isTruncated: Bool
  ) {
    self.text = text
    self.encoding = encoding
    self.isTruncated = isTruncated
  }
}

public struct HexPreview: Equatable, Sendable {
  public var formatted: String
  public var renderedByteCount: Int
  public var isTruncated: Bool

  public init(
    formatted: String,
    renderedByteCount: Int,
    isTruncated: Bool
  ) {
    self.formatted = formatted
    self.renderedByteCount = renderedByteCount
    self.isTruncated = isTruncated
  }
}

public struct DirectorySummary: Equatable, Sendable {
  /// How many entry names a summary carries. The preview panel is a peek at a
  /// directory you have not entered, not a second column, so this is
  /// deliberately short.
  public static let listedEntryLimit = 12

  public var itemCount: Int
  public var directoryCount: Int
  public var fileCount: Int
  public var specialCount: Int
  public var totalKnownBytes: UInt64
  public var isTruncated: Bool
  /// The leading entry names, directory-like ones suffixed with `/`.
  public var entryNames: [String]
  /// Entries beyond ``entryNames``, surfaced as an "and N more" line.
  public var hiddenEntryCount: Int

  public init(
    itemCount: Int,
    directoryCount: Int,
    fileCount: Int,
    specialCount: Int,
    totalKnownBytes: UInt64,
    isTruncated: Bool = false,
    entryNames: [String] = [],
    hiddenEntryCount: Int = 0
  ) {
    self.itemCount = itemCount
    self.directoryCount = directoryCount
    self.fileCount = fileCount
    self.specialCount = specialCount
    self.totalKnownBytes = totalKnownBytes
    self.isTruncated = isTruncated
    self.entryNames = entryNames
    self.hiddenEntryCount = hiddenEntryCount
  }
}

public enum PreviewUnavailableReason: Equatable, Sendable {
  case specialFile
  case previewDisabled
  case unsupported(String)
}

public enum PreviewFailure: Equatable, Sendable {
  case permissionDenied
  case missing
  case missingExecutable(String)
  case externalExit(Int32)
  case externalSignal(Int32)
  case unreadable(String)
}

public enum BuiltInPreviewBody: Equatable, Sendable {
  case text(TextPreview)
  case hexadecimal(HexPreview)
  case directorySummary(DirectorySummary)
  case metadataOnly
  case unavailable(PreviewUnavailableReason)
  case failed(PreviewFailure)
}

public struct BuiltInPreview: Equatable, Sendable {
  public var adapterName: String
  public var metadata: PreviewMetadata
  public var body: BuiltInPreviewBody

  public init(
    adapterName: String = "Built-in",
    metadata: PreviewMetadata,
    body: BuiltInPreviewBody
  ) {
    self.adapterName = adapterName
    self.metadata = metadata
    self.body = body
  }
}
