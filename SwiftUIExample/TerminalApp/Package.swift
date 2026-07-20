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
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.1.10"),
    .package(path: "../../gallery"),
    .package(name: "shared-host-scenes", path: "../../SharedHostScenes"),
  ],
  targets: [
    .target(
      name: "ExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "SharedHostScenes", package: "shared-host-scenes"),
        // SwiftUIHost embeds a SwiftTUIRuntime app. Depend on the runtime, NOT
        // the SwiftTUI umbrella — the umbrella bundles SwiftTUIWebHostCLI →
        // SwiftTUIWebHost, whose Process() use is macOS-only and breaks the
        // iOS build. An embedded host must never pull the web host.
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ],
      path: "Sources/ExampleScenes"
    )
  ],
  swiftLanguageModes: [.v6]
)
