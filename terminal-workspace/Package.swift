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
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.8.6")
  ],
  targets: [
    // The tabbed/split-pane workspace layer, owned by this example and built
    // on the framework's public SwiftTUITerminal embedding surface.
    .target(
      name: "TerminalWorkspace",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftTUITerminal", package: "swift-tui"),
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
