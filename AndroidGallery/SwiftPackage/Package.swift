// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gallery-android-host",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "GalleryAndroidHost",
      type: .dynamic,
      targets: ["GalleryAndroidHost"]
    )
  ],
  dependencies: [
    .package(path: "../../gallery"),
    .package(
      url: "https://github.com/SwiftTUI/swift-tui.git",
      exact: "0.2.0"
    ),
  ],
  targets: [
    .target(
      name: "GalleryAndroidHost",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "SwiftTUIAndroidHost", package: "swift-tui"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .strictMemorySafety(),
        .defaultIsolation(.none),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      ]
    )
  ]
)
