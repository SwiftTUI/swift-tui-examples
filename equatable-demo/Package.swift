// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "equatable-demo",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.2.0")
  ],
  targets: [
    .executableTarget(
      name: "EquatableDemo",
      dependencies: [.product(name: "SwiftTUICLI", package: "swift-tui")]
    )
  ],
  swiftLanguageModes: [.v6]
)
