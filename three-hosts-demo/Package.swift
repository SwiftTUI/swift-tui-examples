// swift-tools-version: 6.3

import PackageDescription

var platforms: [SupportedPlatform]? = nil
var targets: [Target] = [
  .executableTarget(
    name: "three-hosts-demo",
    dependencies: ["ThreeHostsDemoCore"]
  ),
  .target(
    name: "ThreeHostsDemoCore",
    dependencies: [
      .product(name: "SwiftTUI", package: "swift-tui")
    ]
  ),
]
var products: [Product] = [
  .executable(
    name: "three-hosts-demo",
    targets: ["three-hosts-demo"]
  )
]
#if os(macOS)
  platforms = [.macOS(.v15)]
  targets += [
    .executableTarget(
      name: "ThreeHostsSwiftUI",
      dependencies: [
        "ThreeHostsDemoCore",
        .product(name: "SwiftUIHost", package: "swift-tui"),
      ]
    )
  ]
  products += [
    .executable(name: "ThreeHostsSwiftUI", targets: ["ThreeHostsSwiftUI"])
  ]
#endif

let package = Package(
  name: "three-hosts-demo",
  platforms: platforms,
  products: products,
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.5")
  ],
  targets: targets,
  swiftLanguageModes: [.v6]
)
