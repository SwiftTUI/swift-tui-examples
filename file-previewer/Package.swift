// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety()
]

let package = Package(
  name: "file-previewer",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "FilePreviewerApp",
      targets: ["FilePreviewerAppRunner"]
    )
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../../swift-tui")
  ],
  targets: [
    .target(
      name: "FilePreviewerApp",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITerminal", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "FilePreviewerAppRunner",
      dependencies: [
        "FilePreviewerApp",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "FilePreviewerAppTests",
      dependencies: [
        "FilePreviewerApp",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
