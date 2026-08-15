// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "git-viz",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "git-viz", targets: ["GitViz"])
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.8.10"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-charts.git", exact: "0.8.10"),
  ],
  targets: [
    .executableTarget(
      name: "GitViz",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
        .product(name: "SwiftTUICharts", package: "swift-tui-charts"),
      ]
    ),
    .testTarget(
      name: "GitVizTests",
      dependencies: ["GitViz"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
