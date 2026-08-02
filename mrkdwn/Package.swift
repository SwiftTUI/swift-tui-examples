// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety(),
  .defaultIsolation(.none),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
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
      .upToNextMinor(from: "0.4.7")
    ),
    .package(
      url: "https://github.com/swiftlang/swift-markdown.git",
      .upToNextMinor(from: "0.8.0")
    ),
  ],
  targets: [
    // Vendored, example-internal Mermaid renderer. Not a published product:
    // mrkdwn owns this source outright rather than depending on a separate
    // package. See Sources/MrkdwnMermaid/NOTICE for its Apache-2.0 provenance.
    .target(
      name: "MrkdwnMermaid",
      exclude: ["LICENSE", "NOTICE", "README.md", "SYNTAX.md"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "Mrkdwn",
      dependencies: [
        "MrkdwnMermaid",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "MrkdwnCommand",
      dependencies: [
        "Mrkdwn",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
        .product(name: "SwiftTUIProfiling", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "MrkdwnMermaidTests",
      dependencies: ["MrkdwnMermaid"],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "MrkdwnTests",
      dependencies: [
        "Mrkdwn",
        "MrkdwnMermaid",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
      ],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
