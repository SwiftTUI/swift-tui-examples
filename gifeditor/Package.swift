// swift-tools-version: 6.3

import PackageDescription

// Example app split across four targets:
//
//   * GIFEditorCore — pure value-type model plus bridge to the vendored
//     swift-gif encoder/decoder. Has no SwiftTUI dependency,
//     so a future SwiftUI / UIKit / web port can reuse it verbatim.
//   * GIFEditorUI — SwiftTUI-shaped view tree and view model. The
//     terminal-only authoring surface lives here; a sibling
//     GIFEditorUI_SwiftUI target would slot in alongside.
//   * GIFEditor — composition root. Today it just exposes the root
//     view; tomorrow it can wire alternative UIs to the same core.
//   * gifeditor — the executable. Hosts the App via SwiftTUIWebHostCLI.
let package = Package(
  name: "gifeditor",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "gifeditor",
      targets: ["GIFEditorApp"]
    ),
    .library(
      name: "GIFEditor",
      targets: ["GIFEditor"]
    ),
    .library(
      name: "GIFEditorUI",
      targets: ["GIFEditorUI"]
    ),
    .library(
      name: "GIFEditorCore",
      targets: ["GIFEditorCore"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.1.0")
  ],
  targets: [
    // Absorbed local copy of swift-gif. Wholesale-duplicated from swift-tui's
    // Vendor/swift-gif at the absorption point so gifeditor stops reaching
    // across the org root into swift-tui's internals. Renamed from `GIF` to
    // `EditorGIF` because swift-tui's vendor-absorption commit promoted its
    // own `GIF` into a first-class target inside swift-tui — SwiftPM requires
    // target names to be unique across the package graph, so both can't be
    // called `GIF`.
    .target(
      name: "EditorGIF",
      path: "Vendor/swift-gif/Sources/GIF"
    ),
    .testTarget(
      name: "EditorGIFTests",
      dependencies: ["EditorGIF"],
      path: "Vendor/swift-gif/Sources/GIFTests"
    ),
    .target(
      name: "GIFEditorCore",
      dependencies: [
        "EditorGIF"
      ]
    ),
    .target(
      name: "GIFEditorUI",
      dependencies: [
        "GIFEditorCore",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .target(
      name: "GIFEditor",
      dependencies: [
        "GIFEditorUI",
        "GIFEditorCore",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .executableTarget(
      name: "GIFEditorApp",
      dependencies: [
        "GIFEditor",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIWebHostCLI", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "GIFEditorCoreTests",
      dependencies: [
        "GIFEditorCore",
        "EditorGIF",
      ]
    ),
    .testTarget(
      name: "GIFEditorUITests",
      dependencies: [
        "GIFEditorUI",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
      ]
    ),
  ]
)
