// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "gitviz",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "gitviz", targets: ["GitViz"])
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.1.12"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-charts.git", exact: "0.1.12"),
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
