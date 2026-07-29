// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety()
]

let package = Package(
  name: "sextant",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "sextant",
      targets: ["SextantCommand"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.4.2")
  ],
  targets: [
    .target(
      name: "Sextant",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITerminal", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "SextantCommand",
      dependencies: [
        "Sextant",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "SextantTests",
      dependencies: [
        "Sextant",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITerminal", package: "swift-tui"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
