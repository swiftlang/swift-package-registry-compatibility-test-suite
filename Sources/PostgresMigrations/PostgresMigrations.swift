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

@_exported import DatabaseMigrations
import NIOCore // async/await bridge
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
        ///    - migrations: collection of `DatabaseMigrations.Entry`.
        ///    - to: maximum version of migrations to run.
        public func apply(migrations: [DatabaseMigrations.Entry], to version: UInt32 = UInt32.max) async throws -> Int {
            try await DatabaseMigrations.apply(handler: self.handler, migrations: migrations, to: version)
        }
    }

    private struct PostgresHandler: DatabaseMigrations.Handler {
        private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>

        init(_ connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
            self.connectionPool = connectionPool
        }

        func needsBootstrapping() async throws -> Bool {
            try await self.connectionPool.withConnection { connection in
                connection.simpleQuery("select to_regclass('\(SchemaVersion.tableName)');")
            }.map { rows in
                rows.first.flatMap { $0.column("to_regclass")?.value } == nil
            }.get()
        }

        func bootstrap() async throws {
            try await self.connectionPool.withConnection { connection in
                connection.simpleQuery("create table \(SchemaVersion.tableName) (version bigint);")
            }.map { _ in () }.get()
        }

        func versions() async throws -> [UInt32] {
            try await self.connectionPool.withConnection { connection in
                connection.select()
                    .column("version")
                    .from(SchemaVersion.tableName)
                    .all(decoding: SchemaVersion.self)
                    // cast is safe since data is entered as UInt32
                    .map { $0.map { UInt32($0.version) } }
            }.get()
        }

        func apply(version: UInt32, statement: String) async throws {
            try await self.connectionPool.withConnection { connection -> EventLoopFuture<Void> in
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
            }.get()
        }

        private struct SchemaVersion: Codable {
            static let tableName = "schema_migrations"

            var version: Int64
        }
    }
}
