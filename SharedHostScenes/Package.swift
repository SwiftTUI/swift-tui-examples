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
    .package(name: "swift-tui", path: "../../swift-tui")
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
