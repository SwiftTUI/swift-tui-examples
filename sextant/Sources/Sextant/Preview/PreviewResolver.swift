public import Foundation

public struct PreviewResolver: Sendable {
  public var adapters: [PreviewAdapterDescription]

  public init(
    adapters: [PreviewAdapterDescription] = PreviewAdapterDescription.defaults
  ) {
    self.adapters = adapters
  }

  public func resolve(
    url: URL,
    classification: PreviewContentClassification,
    byteCount: UInt64?,
    availableExecutables: [String: String],
    requiresExternal: Bool = false
  ) -> PreviewResolution {
    let contentKind: PreviewAdapterContentKind =
      switch classification {
      case .text:
        .text
      case .binary:
        .binary
      }
    let fileExtension = url.pathExtension.lowercased()
    let eligible =
      adapters
      .filter { adapter in
        if let limit = adapter.maximumByteCount {
          guard let byteCount, byteCount <= limit else {
            return false
          }
        }
        let matchesContent =
          adapter.contentKinds.contains(.anyFile)
          || adapter.contentKinds.contains(contentKind)
        guard matchesContent else {
          return false
        }
        return adapter.fileExtensions.isEmpty
          || adapter.fileExtensions.contains(fileExtension)
      }
      .sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
          return lhs.priority > rhs.priority
        }
        return lhs.id.rawValue < rhs.id.rawValue
      }
    let matches = eligible.filter {
      availableExecutables[$0.executable] != nil
    }

    guard
      let selected = matches.first,
      let executable = availableExecutables[selected.executable]
    else {
      guard let selected = eligible.first else {
        return requiresExternal
          ? .unavailable(.noMatchingAdapter)
          : .builtIn
      }
      guard requiresExternal else {
        return .builtIn
      }
      return .unavailable(
        .missingExecutable(
          adapterName: selected.displayName,
          executable: selected.executable
        )
      )
    }
    return .external(
      PreviewLaunch(
        adapterID: selected.id,
        adapterName: selected.displayName,
        executable: executable,
        arguments: selected.arguments(url),
        isInteractive: selected.isInteractive
      )
    )
  }
}

public actor PreviewExecutableCache {
  public typealias Probe =
    @Sendable (_ executable: String, _ path: String) async -> String?

  private let path: String
  private let probe: Probe
  private var resolved: [String: String?] = [:]

  public init(path: String, probe: @escaping Probe) {
    self.path = path
    self.probe = probe
  }

  public func availability(
    for adapters: [PreviewAdapterDescription]
  ) async -> [String: String] {
    var available: [String: String] = [:]
    for executable in Set(adapters.map(\.executable)).sorted() {
      let result: String?
      if let cached = resolved[executable] {
        result = cached
      } else if resolved.keys.contains(executable) {
        result = nil
      } else {
        result = await probe(executable, path)
        resolved[executable] = result
      }
      if let result {
        available[executable] = result
      }
    }
    return available
  }
}

extension PreviewExecutableCache {
  public static func live(path: String) -> PreviewExecutableCache {
    PreviewExecutableCache(path: path) { executable, path in
      for directory in path.split(separator: ":", omittingEmptySubsequences: false) {
        let base = directory.isEmpty ? "." : String(directory)
        let candidate = URL(fileURLWithPath: base).appendingPathComponent(executable).path
        if FileManager.default.isExecutableFile(atPath: candidate) {
          return URL(fileURLWithPath: candidate).standardizedFileURL.path
        }
      }
      return nil
    }
  }
}
