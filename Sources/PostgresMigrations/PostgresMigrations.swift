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

@_exported import DatabaseMigrations
import NIO
import PostgresKit

extension DatabaseMigrations {
    /// Postgres is an implementation of the DatabaseMigrations API for PostgreSQL.
    ///
    /// - Authors:
    ///  Tomer Doron (tomer@apple.com)
    public struct Postgres {
        internal let handler: DatabaseMigrations.Handler

        /// Initializes the `Postgres` migrations with the provided `ConnectionPool`.
        ///
        /// - parameters:
        ///    - connectionPool: `ConnectionPool<PostgresConnectionSource>` to run the migrations on.
        public init(_ connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
            self.handler = PostgresHandler(connectionPool)
        }

        /// Applies the  `migrations` on the `eventLoopGroup` .
        ///
        /// - parameters:
        ///    - on: `EventLoopGroup` to run the migrations on.
        ///    - migrations: collection of `DatabaseMigrations.Entry`.
        ///    - to: maximum version of migrations to run.
        public func apply(on eventLoopGroup: EventLoopGroup, migrations: [DatabaseMigrations.Entry], to version: UInt32 = UInt32.max) -> EventLoopFuture<Int> {
            DatabaseMigrations.apply(on: eventLoopGroup, handler: self.handler, migrations: migrations, to: version)
        }
    }

    private struct PostgresHandler: DatabaseMigrations.Handler {
        private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>

        init(_ connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
            self.connectionPool = connectionPool
        }

        func needsBootstrapping() -> EventLoopFuture<Bool> {
            self.connectionPool.withConnection { connection in
                connection.simpleQuery("select to_regclass('\(SchemaVersion.tableName)');")
            }.map { rows in
                rows.first.flatMap { $0.column("to_regclass")?.value } == nil
            }
        }

        func bootstrap() -> EventLoopFuture<Void> {
            self.connectionPool.withConnection { connection in
                connection.simpleQuery("create table \(SchemaVersion.tableName) (version bigint);")
            }.map { _ in () }
        }

        func versions() -> EventLoopFuture<[UInt32]> {
            self.connectionPool.withConnection { connection in
                connection.select()
                    .column("version")
                    .from(SchemaVersion.tableName)
                    .all(decoding: SchemaVersion.self)
                    // cast is safe since data is entered as UInt32
                    .map { $0.map { UInt32($0.version) } }
            }
        }

        func apply(version: UInt32, statement: String) -> EventLoopFuture<Void> {
            self.connectionPool.withConnection { connection in
                connection.simpleQuery(statement).flatMap { _ in
                    do {
                        return try connection
                            .insert(into: SchemaVersion.tableName)
                            // cast is safe as UInt32 fits into Int64
                            .model(SchemaVersion(version: Int64(version)))
                            .run()
                    } catch {
                        return connection.eventLoop.makeFailedFuture(error)
                    }
                }
            }
        }

        private struct SchemaVersion: Codable {
            static let tableName = "schema_migrations"

            var version: Int64
        }
    }
}
