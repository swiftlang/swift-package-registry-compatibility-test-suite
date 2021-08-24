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

import XCTest

import NIO
import PostgresKit
@testable import PostgresMigrations

final class Tests: XCTestCase {
    var eventLoopGroup: EventLoopGroup!
    var configuration: PostgresConfiguration!
    var connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>!

    override func setUp() {
        super.setUp()

        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.configuration = PostgresConfiguration(hostname: ProcessInfo.processInfo.environment["POSTGRES_HOST"] ?? "127.0.0.1",
                                                   port: ProcessInfo.processInfo.environment["POSTGRES_PORT"].flatMap(Int.init) ?? 5432,
                                                   username: ProcessInfo.processInfo.environment["POSTGRES_USER"] ?? "postgres",
                                                   password: ProcessInfo.processInfo.environment["POSTGRES_PASSWORD"] ?? "postgres",
                                                   database: ProcessInfo.processInfo.environment["POSTGRES_DATABASE"] ?? "postgres",
                                                   tlsConfiguration: nil)
        self.connectionPool = EventLoopGroupConnectionPool(source: PostgresConnectionSource(configuration: self.configuration),
                                                           on: self.eventLoopGroup)
        _ = try! self.connectionPool.withConnection { connection in
            connection.simpleQuery("drop table if exists schema_migrations")
        }.wait()
    }

    override func tearDown() {
        super.tearDown()

        _ = try! self.connectionPool.withConnection { connection in
            connection.simpleQuery("drop table if exists schema_migrations")
        }.wait()

        self.connectionPool.shutdown()
        try! self.eventLoopGroup.syncShutdownGracefully()
    }

    func testBasic() throws {
        runAsyncAndWaitFor {
            let migrations = (0 ..< 20).map { DatabaseMigrations.Entry(version: $0, statement: "select * from schema_migrations;") }
            let postgresMigrations = DatabaseMigrations.Postgres(self.connectionPool)
            let result = try await postgresMigrations.apply(migrations: migrations)
            XCTAssertEqual(result, migrations.count, "should migrate all versions")
        }
    }

    func testVersionRange() throws {
        runAsyncAndWaitFor {
            let postgresMigrations = DatabaseMigrations.Postgres(self.connectionPool)
            let result = try await postgresMigrations.apply(migrations: [.init(version: UInt32.min, statement: "select * from schema_migrations;"),
                                                                         .init(version: UInt32.max, statement: "select * from schema_migrations;"),
                                                                         .init(version: UInt32.max / 2, statement: "select * from schema_migrations;")])
            XCTAssertEqual(result, 3, "should migrate all versions")

            let versions = try await postgresMigrations.handler.versions().sorted()
            XCTAssertEqual(versions.count, 3, "expected number of versions to match")
            XCTAssertEqual(versions[0], UInt32.min, "version should match")
            XCTAssertEqual(versions[1], UInt32.max / 2, "version should match")
            XCTAssertEqual(versions[2], UInt32.max, "version should match")

            let rows = try self.connectionPool.withConnection { $0.simpleQuery("select version from schema_migrations order by version asc") }.wait()
            XCTAssertEqual(rows.count, 3, "expected number of rows to match")
            XCTAssertEqual(rows[0].column("version")?.int64, Int64(UInt32.min), "version should match")
            XCTAssertEqual(rows[1].column("version")?.int64, Int64(UInt32.max / 2), "version should match")
            XCTAssertEqual(rows[2].column("version")?.int64, Int64(UInt32.max), "version should match")
        }
    }
}

private extension XCTestCase {
    // TODO: remove once XCTest supports async functions
    func runAsyncAndWaitFor(_ closure: @escaping () async throws -> Void, _ timeout: TimeInterval = 1.0) {
        let finished = expectation(description: "finished")
        Task.detached {
            try await closure()
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)
    }
}
