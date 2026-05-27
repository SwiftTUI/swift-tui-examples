// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "three-hosts-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "three-hosts-demo",
      targets: ["three-hosts-demo"]
    ),
    .library(
      name: "ThreeHostsDemoCore",
      targets: ["ThreeHostsDemoCore"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.3")
  ],
  targets: [
    .target(
      name: "ThreeHostsDemoCore",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ]
    ),
    .executableTarget(
      name: "three-hosts-demo",
      dependencies: ["ThreeHostsDemoCore"]
    ),
    .testTarget(
      name: "ThreeHostsDemoCoreTests",
      dependencies: ["ThreeHostsDemoCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
