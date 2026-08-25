// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety(),
  .defaultIsolation(.none),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "csvui",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "CSVUI", targets: ["CSVUI"]),
    .executable(name: "csvui", targets: ["CSVUICommand"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/SwiftTUI/swift-tui.git",
      .upToNextMinor(from: "0.9.8")
    )
  ],
  targets: [
    .target(
      name: "CSVUI",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "CSVUICommand",
      dependencies: [
        "CSVUI",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
        .product(name: "SwiftTUIProfiling", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "CSVUITests",
      dependencies: [
        "CSVUI",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
      ],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
