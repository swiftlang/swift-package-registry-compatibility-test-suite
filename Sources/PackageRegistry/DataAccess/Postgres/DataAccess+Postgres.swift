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

import NIO
import PostgresKit
import PostgresMigrations

struct PostgresDataAccess: DataAccess {
    typealias Configuration = PostgresDataAccessConfiguration

    private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>

    init(eventLoopGroup: EventLoopGroup, configuration config: PostgresDataAccessConfiguration) {
        let tls = config.tls ? TLSConfiguration.clientDefault : nil
        let configuration = PostgresConfiguration(hostname: config.host,
                                                  port: config.port,
                                                  username: config.username,
                                                  password: config.password,
                                                  database: config.database,
                                                  tlsConfiguration: tls)
        self.connectionPool = EventLoopGroupConnectionPool(source: PostgresConnectionSource(configuration: configuration), on: eventLoopGroup)
    }

    func migrate() -> EventLoopFuture<Void> {
        DatabaseMigrations.Postgres(self.connectionPool).apply(on: self.connectionPool.eventLoopGroup).map { _ in () }
    }

    func shutdown() {
        self.connectionPool.shutdown()
    }
}

protocol PostgresDataAccessConfiguration {
    var host: String { get }
    var port: Int { get }
    var tls: Bool { get }
    var database: String { get }
    var username: String { get }
    var password: String { get }
}
