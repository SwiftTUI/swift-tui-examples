public import Foundation

public struct PreviewAdapterID: Hashable, Sendable {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum PreviewAdapterContentKind: Hashable, Sendable {
  case text
  case binary
  case anyFile
}

public struct PreviewAdapterDescription: Sendable {
  public var id: PreviewAdapterID
  public var displayName: String
  public var contentKinds: Set<PreviewAdapterContentKind>
  public var fileExtensions: Set<String>
  public var executable: String
  public var isInteractive: Bool
  public var priority: Int
  public var maximumByteCount: UInt64?
  public var arguments: @Sendable (URL) -> [String]

  public init(
    id: PreviewAdapterID,
    displayName: String,
    contentKinds: Set<PreviewAdapterContentKind> = [.anyFile],
    fileExtensions: Set<String> = [],
    executable: String,
    isInteractive: Bool,
    priority: Int,
    maximumByteCount: UInt64? = nil,
    arguments: @escaping @Sendable (URL) -> [String]
  ) {
    self.id = id
    self.displayName = displayName
    self.contentKinds = contentKinds
    self.fileExtensions = Set(fileExtensions.map { $0.lowercased() })
    self.executable = executable
    self.isInteractive = isInteractive
    self.priority = priority
    self.maximumByteCount = maximumByteCount
    self.arguments = arguments
  }
}

public struct PreviewLaunch: Equatable, Sendable {
  public var adapterID: PreviewAdapterID
  public var adapterName: String
  public var executable: String
  public var arguments: [String]
  public var isInteractive: Bool

  public init(
    adapterID: PreviewAdapterID,
    adapterName: String,
    executable: String,
    arguments: [String],
    isInteractive: Bool
  ) {
    self.adapterID = adapterID
    self.adapterName = adapterName
    self.executable = executable
    self.arguments = arguments
    self.isInteractive = isInteractive
  }
}

public enum PreviewResolutionFailure: Equatable, Sendable {
  case missingExecutable(adapterName: String, executable: String)
  case noMatchingAdapter
}

public enum PreviewResolution: Equatable, Sendable {
  case external(PreviewLaunch)
  case builtIn
  case unavailable(PreviewResolutionFailure)
}

extension PreviewAdapterDescription {
  public static let defaults: [PreviewAdapterDescription] = [
    PreviewAdapterDescription(
      id: PreviewAdapterID("glow"),
      displayName: "Glow",
      contentKinds: [.text],
      fileExtensions: ["md", "markdown"],
      executable: "glow",
      isInteractive: false,
      priority: 80,
      arguments: { ["-s", "dark", "--", $0.path] }
    ),
    PreviewAdapterDescription(
      id: PreviewAdapterID("jq"),
      displayName: "jq",
      contentKinds: [.text],
      fileExtensions: ["json"],
      executable: "jq",
      isInteractive: false,
      priority: 80,
      arguments: { ["-C", ".", "--", $0.path] }
    ),
    PreviewAdapterDescription(
      id: PreviewAdapterID("chafa"),
      displayName: "Chafa",
      contentKinds: [.binary],
      fileExtensions: ["gif", "jpeg", "jpg", "png"],
      executable: "chafa",
      isInteractive: false,
      priority: 70,
      arguments: { ["--symbols=block", "--", $0.path] }
    ),
    PreviewAdapterDescription(
      id: PreviewAdapterID("unzip"),
      displayName: "unzip",
      contentKinds: [.binary],
      fileExtensions: ["zip"],
      executable: "unzip",
      isInteractive: false,
      priority: 70,
      arguments: { ["-l", "--", $0.path] }
    ),
    PreviewAdapterDescription(
      id: PreviewAdapterID("tar"),
      displayName: "tar",
      contentKinds: [.binary],
      fileExtensions: ["tar"],
      executable: "tar",
      isInteractive: false,
      priority: 70,
      arguments: { ["-tvf", $0.path] }
    ),
    PreviewAdapterDescription(
      id: PreviewAdapterID("bat"),
      displayName: "bat",
      contentKinds: [.text],
      executable: "bat",
      isInteractive: true,
      priority: 20,
      arguments: { ["--color=always", "--", $0.path] }
    ),
  ]
}
