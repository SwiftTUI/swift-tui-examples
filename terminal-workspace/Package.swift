// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety()
]

let package = Package(
  name: "terminal-workspace",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "terminal-workspace",
      targets: ["TerminalWorkspaceExampleRunner"]
    ),
    .library(
      name: "TerminalWorkspaceExample",
      targets: ["TerminalWorkspaceExample"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.13.1"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-terminal-view.git", exact: "0.13.1")
  ],
  targets: [
    // The tabbed/split-pane workspace layer, owned by this example and built
    // on the SwiftTUITerminalView package's embedding surface.
    .target(
      name: "TerminalWorkspace",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftTUITerminalView", package: "swift-tui-terminal-view"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "TerminalWorkspaceExample",
      dependencies: [
        "TerminalWorkspace",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "TerminalWorkspaceExampleRunner",
      dependencies: [
        "TerminalWorkspaceExample",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "TerminalWorkspaceTests",
      dependencies: [
        "TerminalWorkspace"
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "TerminalWorkspaceExampleTests",
      dependencies: [
        "TerminalWorkspace",
        "TerminalWorkspaceExample",
      ],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
