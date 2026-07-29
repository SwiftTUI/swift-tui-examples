// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety()
]

let package = Package(
  name: "mrkdwn",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "Mrkdwn", targets: ["Mrkdwn"]),
    .executable(name: "mrkdwn", targets: ["MrkdwnCommand"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/SwiftTUI/swift-tui.git",
      .upToNextMinor(from: "0.4.2")
    ),
    .package(
      url: "https://github.com/swiftlang/swift-markdown.git",
      .upToNextMinor(from: "0.8.0")
    ),
    .package(
      url: "https://github.com/SwiftTUI/swift-mermaid.git",
      .upToNextMinor(from: "0.1.0")
    ),
  ],
  targets: [
    .target(
      name: "Mrkdwn",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "SwiftMermaid", package: "swift-mermaid"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "MrkdwnCommand",
      dependencies: [
        "Mrkdwn",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "MrkdwnTests",
      dependencies: [
        "Mrkdwn",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
        .product(name: "SwiftMermaid", package: "swift-mermaid"),
      ],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
