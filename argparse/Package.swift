// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "argparse-demo",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "argparse-demo", targets: ["ArgParseDemo"])
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.24")
  ],
  targets: [
    .executableTarget(
      name: "ArgParseDemo",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ]
    )
  ]
)
