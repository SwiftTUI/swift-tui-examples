// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "ExampleApp",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "ExampleScenes",
      targets: ["ExampleScenes"]
    )
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../../../swift-tui"),
    .package(path: "../../gallery"),
    .package(name: "shared-host-scenes", path: "../../SharedHostScenes"),
  ],
  targets: [
    .target(
      name: "ExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "SharedHostScenes", package: "shared-host-scenes"),
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      path: "Sources/ExampleScenes"
    )
  ],
  swiftLanguageModes: [.v6]
)
