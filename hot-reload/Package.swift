// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "hot-reload",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.13.3")
  ],
  targets: [
    .executableTarget(name: "HotReloadDemo", dependencies: [
      .product(name: "SwiftTUI", package: "swift-tui")
    ])
  ],
  swiftLanguageModes: [.v6]
)
