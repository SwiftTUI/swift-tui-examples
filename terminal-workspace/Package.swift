// swift-tools-version: 6.3

import PackageDescription

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
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.11")
  ],
  targets: [
    .target(
      name: "TerminalWorkspaceExample",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITerminalWorkspace", package: "swift-tui"),
      ]
    ),
    .executableTarget(
      name: "TerminalWorkspaceExampleRunner",
      dependencies: [
        "TerminalWorkspaceExample",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "TerminalWorkspaceExampleTests",
      dependencies: [
        "TerminalWorkspaceExample",
        .product(name: "SwiftTUITerminalWorkspace", package: "swift-tui"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
