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
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.12.1"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-terminal-view.git", exact: "0.12.1")
  ],
  targets: [
    .target(
      name: "Sextant",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITerminalView", package: "swift-tui-terminal-view"),
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
        .product(name: "SwiftTUITerminalView", package: "swift-tui-terminal-view"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
