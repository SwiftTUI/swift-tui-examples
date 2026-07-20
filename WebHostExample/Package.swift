// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "WebHostExample",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "WebHostExample",
      targets: ["WebHostExample"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.1.10")
  ],
  targets: [
    .executableTarget(
      name: "WebHostExample",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ]
    ),
    .testTarget(
      name: "WebHostExampleTests",
      dependencies: []
    ),
  ],
  swiftLanguageModes: [.v6]
)
