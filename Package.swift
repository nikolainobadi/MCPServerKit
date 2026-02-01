// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPServerKit",
    products: [
        .library(
            name: "MCPServerKit",
            targets: ["MCPServerKit"]),
    ],
    targets: [
        .target(
            name: "MCPServerKit"),
        .testTarget(
            name: "MCPServerKitTests",
            dependencies: ["MCPServerKit"]
        ),
    ]
)
