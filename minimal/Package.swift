// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "minimal",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.24")
  ],
  targets: [
    .executableTarget(
      name: "minimal",
      dependencies: [.product(name: "SwiftTUICLI", package: "swift-tui")]
    )
  ],
  swiftLanguageModes: [.v6]
)
