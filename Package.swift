// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "process-nio",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
    .watchOS(.v6),
    .tvOS(.v13),
  ],
  products: [
    .executable(name: "testclient", targets: ["testclient"]),
    .library(
      name: "ProcessNIO",
      targets: ["ProcessNIO"]
    )
  ],
  dependencies: [
    .package(name: "swift-nio", url: "https://github.com/apple/swift-nio.git", from: "2.33.0"),
  ],
  targets: [
    .executableTarget(
      name: "testclient",
      dependencies: [
        .product(name: "NIO", package: "swift-nio"),
        "ProcessNIO",
      ]),
    .target(
      name: "ProcessNIO",
      dependencies: [
        .product(name: "NIO", package: "swift-nio"),
      ]),
    .testTarget(
      name: "process-nioTests",
      dependencies: ["ProcessNIO"]),
  ]
)
