// swift-tools-version: 6.3

import PackageDescription

// SwiftUI port of `layouts`. The intent is to render the same
// 56 layout-shape examples in real SwiftUI so the BEHAVIOUR_FINDINGS
// observations can be compared side-by-side with the embedded SwiftTUI
// implementation. This package deliberately drops the test target
// from the original — the original tests rasterise via SwiftTUI's
// `DefaultRenderer` / `RasterSurface`, which has no SwiftUI public
// equivalent.
let package = Package(
  name: "layouts-swiftui-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "layouts-swiftui-demo",
      targets: ["SwiftUILayoutsApp"]
    ),
    .library(
      name: "SwiftUILayouts",
      targets: ["SwiftUILayouts"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/JohnSundell/Splash.git", exact: "0.16.0"),
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.27"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-swiftui.git", exact: "0.0.27"),
    .package(name: "layouts-demo", path: "../layouts"),
  ],
  targets: [
    .executableTarget(
      name: "SwiftUILayoutsApp",
      dependencies: [
        "SwiftUILayouts",
        .product(name: "Splash", package: "Splash"),
        .product(name: "Layouts", package: "layouts-demo"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftUIHost", package: "swift-tui-swiftui"),
      ],
      path: "Sources/LayoutsApp"
    ),
    .target(
      name: "SwiftUILayouts",
      dependencies: [],
      path: "Sources/Layouts",
      plugins: [
        .plugin(name: "LayoutSourceSnippetPlugin", package: "layouts-demo")
      ]
    ),
    .testTarget(
      name: "LayoutsSwiftUITests",
      dependencies: [
        "SwiftUILayouts",
        .product(name: "Layouts", package: "layouts-demo"),
      ],
      path: "Tests/LayoutsSwiftUITests"
    ),
  ]
)
