// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPServerKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MCPServerKit",
            targets: ["MCPServerKit"]
        ),
        .library(
            name: "MCPServerKitAuth",
            targets: ["MCPServerKitAuth"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", "5.0.0"..<"5.3.0"),
    ],
    targets: [
        .target(
            name: "MCPServerKit",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ]
        ),
        .target(
            name: "MCPServerKitAuth",
            dependencies: [
                "MCPServerKit",
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ]
        ),
        .testTarget(
            name: "MCPServerKitTests",
            dependencies: [
                "MCPServerKit",
            ]
        ),
    ]
)
