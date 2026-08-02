public import Foundation

public struct RowID: Hashable, Comparable, Sendable, CustomStringConvertible {
  public enum Storage: Hashable, Sendable {
    case source(Int)
    case inserted(UInt64)
  }

  public var storage: Storage

  public init(sourceIndex: Int) { storage = .source(sourceIndex) }
  public init(insertedID: UInt64) { storage = .inserted(insertedID) }

  public static func < (lhs: RowID, rhs: RowID) -> Bool {
    switch (lhs.storage, rhs.storage) {
    case (.source(let left), .source(let right)): left < right
    case (.source, .inserted): true
    case (.inserted, .source): false
    case (.inserted(let left), .inserted(let right)): left < right
    }
  }

  public var sourceIndex: Int? {
    guard case .source(let value) = storage else { return nil }
    return value
  }

  public var description: String {
    switch storage {
    case .source(let index): "row:\(index)"
    case .inserted(let id): "inserted-row:\(id)"
    }
  }
}

public struct ColumnID: Hashable, Comparable, Sendable, CustomStringConvertible {
  public var rawValue: Int

  public init(_ rawValue: Int) { self.rawValue = rawValue }
  public static func < (lhs: ColumnID, rhs: ColumnID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
  public var description: String { "column:\(rawValue)" }
}

public struct CSVCellAddress: Hashable, Sendable {
  public var row: RowID
  public var column: ColumnID

  public init(row: RowID, column: ColumnID) {
    self.row = row
    self.column = column
  }
}

public enum CSVLineEnding: String, CaseIterable, Hashable, Sendable {
  case crlf
  case lf
  case cr

  public var bytes: [UInt8] {
    switch self {
    case .crlf: [13, 10]
    case .lf: [10]
    case .cr: [13]
    }
  }

  public var displayName: String {
    switch self {
    case .crlf: "CRLF"
    case .lf: "LF"
    case .cr: "CR"
    }
  }
}

public struct CSVDelimiter: Equatable, Hashable, Sendable, CustomStringConvertible {
  public var byte: UInt8

  public init(byte: UInt8) throws {
    guard byte >= 0x20, byte <= 0x7E, byte != 0x22, byte != 0x0A, byte != 0x0D else {
      throw CSVFormatError(
        message: "delimiter must be one printable single-byte ASCII character other than quote",
        line: 1,
        column: 1,
        byteOffset: 0
      )
    }
    self.byte = byte
  }

  public init(character: Character) throws {
    let bytes = Array(String(character).utf8)
    guard bytes.count == 1 else {
      throw CSVFormatError(
        message: "delimiter must be one printable single-byte ASCII character",
        line: 1,
        column: 1,
        byteOffset: 0
      )
    }
    try self.init(byte: bytes[0])
  }

  public static let comma = try! CSVDelimiter(byte: 0x2C)
  public static let tab = CSVDelimiter(uncheckedByte: 0x09)
  public static let semicolon = try! CSVDelimiter(byte: 0x3B)
  public static let pipe = try! CSVDelimiter(byte: 0x7C)

  private init(uncheckedByte: UInt8) { byte = uncheckedByte }

  public var character: Character { Character(String(UnicodeScalar(byte))) }

  public var description: String {
    switch byte {
    case 0x2C: "comma"
    case 0x09: "tab"
    case 0x3B: "semicolon"
    case 0x7C: "pipe"
    default: String(character)
    }
  }

  public static func parse(_ value: String) throws -> CSVDelimiter {
    switch value.lowercased() {
    case "comma": return .comma
    case "tab": return .tab
    case "semicolon": return .semicolon
    case "pipe": return .pipe
    default:
      guard value.count == 1, let character = value.first else {
        throw CSVFormatError(
          message: "delimiter must be comma, tab, semicolon, pipe, or one ASCII character",
          line: 1,
          column: 1,
          byteOffset: 0
        )
      }
      return try CSVDelimiter(character: character)
    }
  }
}

public struct CSVDialect: Equatable, Sendable {
  public var delimiter: CSVDelimiter
  public var hasHeaders: Bool
  public var hasUTF8BOM: Bool
  public var dominantLineEnding: CSVLineEnding
  public var observedLineEndings: Set<CSVLineEnding>
  public var hasFinalNewline: Bool

  public init(
    delimiter: CSVDelimiter,
    hasHeaders: Bool = true,
    hasUTF8BOM: Bool = false,
    dominantLineEnding: CSVLineEnding = .lf,
    observedLineEndings: Set<CSVLineEnding> = [],
    hasFinalNewline: Bool = false
  ) {
    self.delimiter = delimiter
    self.hasHeaders = hasHeaders
    self.hasUTF8BOM = hasUTF8BOM
    self.dominantLineEnding = dominantLineEnding
    self.observedLineEndings = observedLineEndings
    self.hasFinalNewline = hasFinalNewline
  }
}

public struct CSVFormatError: Error, Equatable, Sendable, LocalizedError {
  public var message: String
  public var line: Int
  public var column: Int
  public var byteOffset: Int

  public init(message: String, line: Int, column: Int, byteOffset: Int) {
    self.message = message
    self.line = line
    self.column = column
    self.byteOffset = byteOffset
  }

  public var errorDescription: String? {
    "CSV parse error at line \(line), column \(column), byte \(byteOffset): \(message)"
  }
}

public enum CSVSourceOrigin: Equatable, Sendable {
  case regularFile(URL)
  case standardInput
}

public struct CSVSourceIdentity: Equatable, Sendable {
  public var device: UInt64
  public var inode: UInt64
  public var size: UInt64
  public var modificationSeconds: Int64
  public var modificationNanoseconds: Int64
  public var changeSeconds: Int64
  public var changeNanoseconds: Int64
  public var mode: UInt32
  public var linkCount: UInt64

  public init(
    device: UInt64,
    inode: UInt64,
    size: UInt64,
    modificationSeconds: Int64,
    modificationNanoseconds: Int64,
    changeSeconds: Int64,
    changeNanoseconds: Int64,
    mode: UInt32,
    linkCount: UInt64
  ) {
    self.device = device
    self.inode = inode
    self.size = size
    self.modificationSeconds = modificationSeconds
    self.modificationNanoseconds = modificationNanoseconds
    self.changeSeconds = changeSeconds
    self.changeNanoseconds = changeNanoseconds
    self.mode = mode
    self.linkCount = linkCount
  }
}

public struct CSVWriteBackAuthority: Equatable, Sendable {
  public var destination: URL
  public var identity: CSVSourceIdentity

  public init(destination: URL, identity: CSVSourceIdentity) {
    self.destination = destination
    self.identity = identity
  }
}

public struct CSVSourceSnapshot: Equatable, Sendable {
  public var origin: CSVSourceOrigin
  public var displayName: String
  public var bytes: Data
  public var identity: CSVSourceIdentity?
  public var writeBackAuthority: CSVWriteBackAuthority?
  public var loadGeneration: UInt64

  public init(
    origin: CSVSourceOrigin,
    displayName: String,
    bytes: Data,
    identity: CSVSourceIdentity? = nil,
    writeBackAuthority: CSVWriteBackAuthority? = nil,
    loadGeneration: UInt64 = 0
  ) {
    self.origin = origin
    self.displayName = displayName
    self.bytes = bytes
    self.identity = identity
    self.writeBackAuthority = writeBackAuthority
    self.loadGeneration = loadGeneration
  }
}
