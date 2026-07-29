import Foundation

public struct DocumentSnapshot: Equatable, Sendable {
  public var source: String
  public var url: URL?
  public var displayName: String

  public init(source: String, url: URL?, displayName: String) {
    self.source = source
    self.url = url
    self.displayName = displayName
  }
}

public enum DocumentSourceError: Error, Sendable, LocalizedError {
  case missing(URL)
  case notRegularFile(URL)
  case unreadable(URL, String)
  case tooLarge(displayName: String, byteCount: Int)
  case invalidUTF8(String)

  public var errorDescription: String? {
    switch self {
    case .missing(let url):
      "Markdown file does not exist: \(url.path)"
    case .notRegularFile(let url):
      "Markdown source is not a regular file: \(url.path)"
    case .unreadable(let url, let reason):
      "Cannot read \(url.path): \(reason)"
    case .tooLarge(let name, let count):
      "\(name) is \(count) bytes; mrkdwn accepts at most 16 MiB"
    case .invalidUTF8(let name):
      "\(name) is not valid UTF-8"
    }
  }
}

public struct DocumentSource: Sendable {
  public static let maximumBytes = 16 * 1_024 * 1_024

  public init() {}

  public func read(fileURL: URL) throws -> DocumentSnapshot {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw DocumentSourceError.missing(fileURL)
    }
    let data: Data
    do {
      data = try BoundedRegularFileReader.read(
        fileURL,
        maximumBytes: Self.maximumBytes
      )
    } catch BoundedRegularFileReadError.notRegularFile {
      throw DocumentSourceError.notRegularFile(fileURL)
    } catch BoundedRegularFileReadError.tooLarge(let count) {
      throw DocumentSourceError.tooLarge(displayName: fileURL.path, byteCount: count)
    } catch {
      throw DocumentSourceError.unreadable(fileURL, error.localizedDescription)
    }
    guard let source = String(data: data, encoding: .utf8) else {
      throw DocumentSourceError.invalidUTF8(fileURL.path)
    }
    return DocumentSnapshot(
      source: source,
      url: fileURL.standardizedFileURL,
      displayName: fileURL.lastPathComponent
    )
  }

  public func readStandardInput(_ handle: FileHandle = .standardInput) throws -> DocumentSnapshot {
    let data = try boundedData(from: handle, displayName: "standard input")
    guard let source = String(data: data, encoding: .utf8) else {
      throw DocumentSourceError.invalidUTF8("standard input")
    }
    return DocumentSnapshot(source: source, url: nil, displayName: "stdin")
  }

  private func boundedData(from handle: FileHandle, displayName: String) throws -> Data {
    var data = Data()
    while true {
      let chunk: Data
      do {
        chunk = try handle.read(upToCount: 64 * 1_024) ?? Data()
      } catch {
        throw DocumentSourceError.unreadable(
          URL(fileURLWithPath: displayName),
          error.localizedDescription
        )
      }
      guard !chunk.isEmpty else { break }
      if data.count > Self.maximumBytes - chunk.count {
        throw DocumentSourceError.tooLarge(
          displayName: displayName,
          byteCount: data.count + chunk.count
        )
      }
      data.append(chunk)
    }
    return data
  }
}
