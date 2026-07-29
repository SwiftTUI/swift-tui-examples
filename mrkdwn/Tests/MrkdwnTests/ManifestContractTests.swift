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

    let expected: [String: (location: String, version: String)] = [
      "swift-markdown": (
        "https://github.com/swiftlang/swift-markdown.git",
        "0.8.0"
      ),
      "swift-mermaid": (
        "https://github.com/SwiftTUI/swift-mermaid.git",
        "0.1.0"
      ),
      "swift-tui": (
        "https://github.com/SwiftTUI/swift-tui.git",
        "0.4.2"
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
        #expect(state["version"] as? String == contract.version)
      }
    }
  }
}
