// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "terminal-runner",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "terminal-runner",
      targets: ["TerminalRunnerExample"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.6")
  ],
  targets: [
    .executableTarget(
      name: "TerminalRunnerExample",
      dependencies: [.product(name: "SwiftTUICLI", package: "swift-tui")]
    ),
    .testTarget(
      name: "TerminalRunnerExampleTests",
      dependencies: []
    ),
  ],
  swiftLanguageModes: [.v6]
)
