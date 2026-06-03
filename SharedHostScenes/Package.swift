// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "shared-host-scenes",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "SharedHostScenes",
      targets: ["SharedHostScenes"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.13")
  ],
  targets: [
    .target(
      name: "SharedHostScenes",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
