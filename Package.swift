// swift-tools-version:5.5

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-package-registry-compatibility-test-suite",
    platforms: [.macOS("12.0")],
    products: [],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.32.1")),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.48.3")),
        // TODO: pin to release with async/await support
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", .branch("main")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-metrics.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/apple/swift-statsd-client.git", .upToNextMajor(from: "1.0.0-alpha")),
        .package(url: "https://github.com/apple/swift-package-manager.git", .branch("main")),
        .package(url: "https://github.com/vapor/multipart-kit.git", .upToNextMajor(from: "4.2.1")),
        .package(url: "https://github.com/vapor/postgres-kit.git", .upToNextMajor(from: "2.3.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", .upToNextMajor(from: "1.3.0")),
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "0.0.3")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "0.4.3")),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "1.1.6")),
    ],
    targets: [
        .target(name: "DatabaseMigrations", dependencies: [
            .product(name: "Logging", package: "swift-log"),
        ]),

        .target(name: "PostgresMigrations", dependencies: [
            "DatabaseMigrations",
            .product(name: "_NIOConcurrency", package: "swift-nio"), // async/await bridge
            .product(name: "PostgresKit", package: "postgres-kit"),
        ]),

        .target(name: "PackageRegistryModels", dependencies: []),

        .executableTarget(name: "PackageRegistry",
                          dependencies: [
                              "PostgresMigrations",
                              "PackageRegistryModels",
                              .product(name: "NIO", package: "swift-nio"),
                              .product(name: "_NIOConcurrency", package: "swift-nio"), // async/await bridge
                              .product(name: "Vapor", package: "vapor"),
                              .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                              .product(name: "LifecycleNIOCompat", package: "swift-service-lifecycle"),
                              .product(name: "Logging", package: "swift-log"),
                              .product(name: "Metrics", package: "swift-metrics"),
                              .product(name: "StatsdClient", package: "swift-statsd-client"),
                              .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
                              .product(name: "PostgresKit", package: "postgres-kit"),
                              .product(name: "MultipartKit", package: "multipart-kit"),
                              .product(name: "Crypto", package: "swift-crypto"),
                          ],
                          exclude: ["README.md"]),

        .target(name: "PackageRegistryClient", dependencies: [
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            .product(name: "_NIOConcurrency", package: "swift-nio"), // async/await bridge
            .product(name: "Atomics", package: "swift-atomics"),
            .product(name: "Logging", package: "swift-log"),
        ]),

        .executableTarget(name: "PackageRegistryTool", dependencies: [
            "PackageRegistryClient",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),

        .testTarget(name: "PostgresMigrationsTests", dependencies: [
            "PostgresMigrations",
        ]),

        .testTarget(name: "PackageRegistryTests", dependencies: [
            "PackageRegistryModels",
            "PackageRegistryClient",
            .product(name: "Crypto", package: "swift-crypto"),
        ]),
    ]
)
