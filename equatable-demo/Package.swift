// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "equatable-demo",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", .upToNextMajor(from: "0.21.0"))
  ],
  targets: [
    .executableTarget(
      name: "EquatableDemo",
      dependencies: [.product(name: "SwiftTUICLI", package: "swift-tui")]
    )
  ],
  swiftLanguageModes: [.v6]
)
