// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "TerminalApp",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "WebExampleScenes",
      targets: ["WebExampleScenes"]
    ),
    .executable(
      name: "WebExampleApp",
      targets: ["WebExampleApp"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.25"),
    .package(path: "../../gallery"),
    .package(name: "shared-host-scenes", path: "../../SharedHostScenes"),
  ],
  targets: [
    .target(
      name: "WebExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "SharedHostScenes", package: "shared-host-scenes"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ],
      path: "Sources/WebExampleScenes"
    ),
    .executableTarget(
      name: "WebExampleApp",
      dependencies: [
        "WebExampleScenes",
        .product(name: "SwiftTUIWASI", package: "swift-tui"),
      ],
      path: "Sources/TerminalApp"
    ),
    .testTarget(
      name: "WebExampleScenesTests",
      dependencies: ["WebExampleScenes"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
