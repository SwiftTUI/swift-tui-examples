// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "layouts-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "layouts-demo",
      targets: ["LayoutsApp"]
    ),
    .library(
      name: "Layouts",
      targets: ["Layouts"]
    ),
    .plugin(
      name: "LayoutSourceSnippetPlugin",
      targets: ["LayoutSourceSnippetPlugin"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.10.0"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-charts.git", exact: "0.10.0"),
  ],
  targets: [
    .executableTarget(
      name: "LayoutsApp",
      dependencies: [
        "Layouts",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .target(
      name: "Layouts",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftTUICharts", package: "swift-tui-charts"),
      ],
      plugins: [
        .plugin(name: "LayoutSourceSnippetPlugin")
      ]
    ),
    .testTarget(
      name: "LayoutsTests",
      dependencies: [
        "Layouts",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .plugin(
      name: "LayoutSourceSnippetPlugin",
      capability: .buildTool(),
      dependencies: [
        "LayoutSnippetGenerator"
      ],
      path: "Plugins/LayoutSourceSnippetPlugin"
    ),
    // Plain-Swift source scanner, deliberately dependency-free: swift-syntax
    // cost every build of this package (and LayoutsSwiftUI) ~7 minutes of
    // release compile. See the header of Plugins/LayoutSnippetGenerator/main.swift.
    .executableTarget(
      name: "LayoutSnippetGenerator",
      path: "Plugins/LayoutSnippetGenerator"
    ),
  ]
)
