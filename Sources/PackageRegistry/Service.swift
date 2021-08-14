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

import Lifecycle
import LifecycleNIOCompat
import Logging
import Metrics
import NIO
import StatsdClient

public enum PackageRegistry {
    public static func main() {
        let configuration = Configuration()
        LoggingSystem.bootstrap { label in
            var logger = StreamLogHandler.standardOutput(label: label)
            logger.logLevel = configuration.app.logLevel
            return logger
        }
        let logger = Logger(label: "\(PackageRegistry.self)")
        logger.info("\(configuration)")

        let lifecycle = ServiceLifecycle()

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        lifecycle.registerShutdown(label: "eventLoopGroup", .sync(eventLoopGroup.syncShutdownGracefully))

        let dataAccess = PostgresDataAccess(eventLoopGroup: eventLoopGroup, configuration: configuration.postgres)
        lifecycle.register(label: "dataAccess",
                           start: .eventLoopFuture(dataAccess.migrate),
                           shutdown: .sync(dataAccess.shutdown))

        let api = API(configuration: configuration)
        lifecycle.register(label: "api",
                           start: .sync(api.start),
                           shutdown: .sync(api.shutdown),
                           shutdownIfNotStarted: true)

        if let metricsPort = configuration.app.metricsPort {
            logger.info("Bootstrapping statsd client on port \(metricsPort)")
            if let statsdClient = try? StatsdClient(eventLoopGroupProvider: .shared(eventLoopGroup), host: "localhost", port: metricsPort) {
                MetricsSystem.bootstrap(statsdClient)
                lifecycle.registerShutdown(label: "statsd-client", .async(statsdClient.shutdown))
            }
        }

        lifecycle.start { error in
            if let error = error {
                logger.error("Failed starting \(self) ☠️: \(error)")
            } else {
                logger.info("\(self) started successfully 🚀")
            }
        }
        lifecycle.wait()
    }
}
