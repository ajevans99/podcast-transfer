// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "podcast-transfer",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .watchOS(.v10),
  ],
  products: [
    .library(name: "PodcastTransferCore", targets: ["PodcastTransferCore"]),
    .library(name: "PodcastTransferFeature", targets: ["PodcastTransferFeature"]),
    .library(name: "PodcastTransferUI", targets: ["PodcastTransferUI"]),
    .executable(name: "PodcastTransferApp", targets: ["PodcastTransferApp"]),
    .executable(name: "Playground", targets: ["Playground"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.7"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.4"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.4.3"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
  ],
  targets: [
    .target(
      name: "PodcastTransferCore",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]
    ),
    .target(
      name: "PodcastTransferFeature",
      dependencies: [
        "PodcastTransferCore",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
      ]
    ),
    .target(
      name: "PodcastTransferUI",
      dependencies: [
        "PodcastTransferFeature",
        "PodcastTransferCore",
      ]
    ),
    .executableTarget(
      name: "PodcastTransferApp",
      dependencies: [
        "PodcastTransferUI",
        "PodcastTransferFeature",
        "PodcastTransferCore",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
      ]
    ),
    .executableTarget(
      name: "Playground",
      dependencies: ["PodcastTransferFeature", "PodcastTransferCore"]
    ),
    .testTarget(
      name: "PodcastTransferCoreTests",
      dependencies: [
        "PodcastTransferCore",
        "PodcastTransferFeature",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "PodcastTransferSnapshotTests",
      dependencies: [
        "PodcastTransferUI",
        "PodcastTransferFeature",
        "PodcastTransferCore",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      resources: [
        .process("__Snapshots__")
      ]
    ),
  ]
)
