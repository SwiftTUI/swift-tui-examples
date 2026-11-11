import Foundation
import Testing

@Suite("public dependency contract")
struct ManifestContractTests {
  @Test("committed resolution contains released remote pins")
  func resolvedDependencies() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    guard !isDisposableCoordinationOverlay(packageRoot) else { return }
    let semanticGate = packageRoot.appendingPathComponent(
      "Scripts/check_manifest_contract.py"
    )
    #expect(
      FileManager.default.fileExists(atPath: semanticGate.path),
      "The focused gate must validate `swift package dump-package` outside `swift test`."
    )
    try validateResolvedDependencies(at: packageRoot)
  }

  private func isDisposableCoordinationOverlay(_ packageRoot: URL) -> Bool {
    if ProcessInfo.processInfo.environment["SWIFTTUI_CHECKOUT"] != nil {
      return true
    }
    return packageRoot.deletingLastPathComponent().lastPathComponent
      .hasPrefix("mrkdwn-overlay.")
  }

  private func validateResolvedDependencies(at packageRoot: URL) throws {
    let lockURL = packageRoot.appendingPathComponent("Package.resolved")
    let data = try Data(contentsOf: lockURL)
    let root = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(root["version"] as? Int == 3)
    let pins = try #require(root["pins"] as? [[String: Any]])

    // Versions are derived from the authored SwiftPM range lower
    // bounds in Package.swift rather than spelled out again here: a second
    // copy of the version drifts the moment a release bumps only one of them,
    // and the org bump tool deliberately never rewrites files under `Tests/`.
    // The locations stay authored — a silently moved dependency URL must fail.
    let manifestLowerBounds = try authoredLowerBounds(at: packageRoot)
    let expected: [String: (location: String, version: String)] = [
      "swift-markdown": (
        "https://github.com/swiftlang/swift-markdown.git",
        try #require(
          manifestLowerBounds["https://github.com/swiftlang/swift-markdown.git"]
        )
      ),
      "swift-tui": (
        "https://github.com/SwiftTUI/swift-tui.git",
        try #require(
          manifestLowerBounds["https://github.com/SwiftTUI/swift-tui.git"]
        )
      ),
    ]
    let identities = Set(pins.compactMap { $0["identity"] as? String })
    #expect(Set(expected.keys).isSubset(of: identities))
    for pin in pins {
      let identity = try #require(pin["identity"] as? String)
      #expect(pin["kind"] as? String == "remoteSourceControl")
      let state = try #require(pin["state"] as? [String: Any])
      #expect(state["version"] as? String != nil)
      #expect(state["branch"] == nil)
      #expect(state["revision"] as? String != nil)
      if let contract = expected[identity] {
        #expect(pin["location"] as? String == contract.location)
        let selectedVersion = try #require(state["version"] as? String)
        if identity == "swift-tui" {
          #expect(isMajorCompatible(selectedVersion, from: contract.version))
        } else {
          #expect(selectedVersion == contract.version)
        }
      }
    }
  }

  @Test("SwiftTUI lock updates stay within the declared major range")
  func compatibleLockVersions() {
    for version in ["0.21.0", "0.21.3", "0.22.1", "0.99.0"] {
      #expect(isMajorCompatible(version, from: "0.21.0"))
    }
    for version in ["0.20.9", "1.0.0", "0.22.0-dev", "main", "0..21.0", "00.21.0"] {
      #expect(!isMajorCompatible(version, from: "0.21.0"))
    }
  }

  private func isMajorCompatible(_ selected: String, from lower: String) -> Bool {
    guard selected.wholeMatch(of: /(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)/) != nil
    else {
      return false
    }
    let version = selected.split(separator: ".").compactMap { Int($0) }
    let floor = lower.split(separator: ".").compactMap { Int($0) }
    guard version.count == 3, floor.count == 3 else { return false }
    return version[0] == floor[0] && !version.lexicographicallyPrecedes(floor)
  }

  /// The authored SwiftPM range lower bounds in `Package.swift`,
  /// keyed by dependency URL.
  private func authoredLowerBounds(at packageRoot: URL) throws -> [String: String] {
    let manifestURL = packageRoot.appendingPathComponent("Package.swift")
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
    let declaration =
      /\.package\(\s*url:\s*"([^"]+)"\s*,\s*\.upToNext(?:Minor|Major)\(from:\s*"([^"]+)"\)\s*\)/
    return Dictionary(
      manifest.matches(of: declaration).map { (String($0.1), String($0.2)) },
      uniquingKeysWith: { first, _ in first }
    )
  }
}
