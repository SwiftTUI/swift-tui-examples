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
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.12"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1"),
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
        .product(name: "SwiftTUICharts", package: "swift-tui"),
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
    .executableTarget(
      name: "LayoutSnippetGenerator",
      dependencies: [
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      path: "Plugins/LayoutSnippetGenerator"
    ),
  ]
)
