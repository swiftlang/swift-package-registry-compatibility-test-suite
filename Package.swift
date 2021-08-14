// swift-tools-version:5.2
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPackageRegistryCompatibilityTestSuite open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftPackageRegistryCompatibilityTestSuite project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPackageRegistryCompatibilityTestSuite project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-package-registry-compatibility-test-suite",
    platforms: [.macOS("11.0")],
    products: [
        .executable(name: "PackageRegistryLauncher", targets: ["PackageRegistryLauncher"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.30.0")),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.48.3")),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", .upToNextMinor(from: "1.0.0-alpha")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-metrics.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/apple/swift-statsd-client.git", .upToNextMajor(from: "1.0.0-alpha")),
        .package(url: "https://github.com/swift-server/async-http-client.git", .upToNextMajor(from: "1.3.0")),
    ],
    targets: [
        .target(name: "PackageRegistry", dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "Vapor", package: "vapor"),
            .product(name: "Lifecycle", package: "swift-service-lifecycle"),
            .product(name: "LifecycleNIOCompat", package: "swift-service-lifecycle"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "Metrics", package: "swift-metrics"),
            .product(name: "StatsdClient", package: "swift-statsd-client"),
        ]),

        .target(name: "PackageRegistryLauncher", dependencies: [
            "PackageRegistry",
        ]),

        .testTarget(name: "PackageRegistryTests", dependencies: [
            "PackageRegistry",
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
        ]),
    ]
)
