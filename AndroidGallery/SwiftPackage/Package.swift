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
      revision: "08ba535e59dca67d163e9d128ac0c41f2899e36b"
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
