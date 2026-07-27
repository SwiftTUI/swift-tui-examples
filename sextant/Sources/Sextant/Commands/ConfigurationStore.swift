public import Foundation

public struct SextantPaths: Equatable, Sendable {
  public var configurationFile: URL
  public var stateFile: URL

  public init(configurationFile: URL, stateFile: URL) {
    self.configurationFile = configurationFile
    self.stateFile = stateFile
  }

  public static func resolve(
    environment: [String: String],
    homeDirectory: URL
  ) -> SextantPaths {
    let configRoot =
      environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
      ?? homeDirectory.appendingPathComponent(".config", isDirectory: true)
    let stateRoot =
      environment["XDG_STATE_HOME"].map(URL.init(fileURLWithPath:))
      ?? homeDirectory.appendingPathComponent(".local/state", isDirectory: true)
    return SextantPaths(
      configurationFile:
        configRoot
        .appendingPathComponent("sextant", isDirectory: true)
        .appendingPathComponent("config.json"),
      stateFile:
        stateRoot
        .appendingPathComponent("sextant", isDirectory: true)
        .appendingPathComponent("state.json")
    )
  }
}

public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
  public var url: URL

  public init(url: URL) {
    self.url = url
  }

  public func load(default defaultValue: @autoclosure () -> Value) throws -> Value {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return defaultValue()
    }
    return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
  }

  public func save(_ value: Value) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }
}
