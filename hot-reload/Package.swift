// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "hot-reload",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.14.0")
  ],
  targets: [
    .executableTarget(name: "HotReloadDemo", dependencies: [
      .product(name: "SwiftTUI", package: "swift-tui")
    ])
  ],
  swiftLanguageModes: [.v6]
)
