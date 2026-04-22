// swift-tools-version:5.10
import PackageDescription

let package = Package(
  name: "tca-graph",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "tca-graph", targets: ["TCAGraphCLI"]),
    .library(name: "TCAGraphParser", targets: ["TCAGraphParser"]),
    .library(name: "TCAGraphModel", targets: ["TCAGraphModel"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
  ],
  targets: [
    .target(name: "TCAGraphModel"),
    .target(
      name: "TCAGraphParser",
      dependencies: [
        "TCAGraphModel",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .executableTarget(
      name: "TCAGraphCLI",
      dependencies: ["TCAGraphParser", "TCAGraphModel"]
    ),
    .testTarget(
      name: "TCAGraphParserTests",
      dependencies: ["TCAGraphParser", "TCAGraphModel"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
