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

import Logging

/// DatabaseMigrations is a generic migrations API.
///
/// DatabaseMigrations is designed to provide a consistent API across implementations of database migrations.
/// It defines the `DatabaseMigrations.Handler` protocol which concrete database migrations libraries implement.
/// It also provides a generic logical implementation for the sequence of operations in typical database migrations.
///
/// - note: This library designed to be used by implementations of the DatabaseMigrations API, not end-users.
///
/// - Authors:
///  Tomer Doron (tomer@apple.com)
///
public enum DatabaseMigrations {
    public typealias Handler = DatabaseMigrationsHandler

    /// Applies the  `migrations` on the `eventLoopGroup` using `handler`.
    ///
    /// - note: This method is designed to be called by implmentations of the DatabaseMigrations API.
    ///
    /// - parameters:
    ///    - handler: `Handler` to performs the migrations.
    ///    - migrations: collection of `DatabaseMigrations.Entry`.
    ///    - to: maximum version of migrations to run.
    public static func apply(handler: Handler, migrations: [Entry], to version: UInt32 = UInt32.max) async throws -> Int {
        try await Migrator(handler: handler, migrations: migrations).migrate(to: version)
    }

    internal struct Migrator {
        private let logger = Logger(label: "\(Migrator.self)")
        private let handler: Handler
        private let migrations: [Entry]

        init(handler: Handler, migrations: [Entry]) {
            self.handler = handler
            self.migrations = migrations
        }

        func needsBootstrapping() async throws -> Bool {
            try await self.handler.needsBootstrapping()
        }

        func bootstrap() async throws {
            try await self.handler.bootstrap()
        }

        func maxVersion() async throws -> UInt32 {
            guard try await !self.needsBootstrapping() else {
                return 0
            }
            let versions = try await self.handler.versions()
            return versions.max() ?? 0
        }

        func minVersion() async throws -> UInt32 {
            guard try await !self.needsBootstrapping() else {
                return 0
            }
            let versions = try await self.handler.versions()
            return versions.min() ?? 0
        }

        func appliedVersions() async throws -> [UInt32] {
            guard try await !self.needsBootstrapping() else {
                return []
            }
            return try await self.handler.versions()
        }

        func pendingMigrations() async throws -> [Entry] {
            guard try await !self.needsBootstrapping() else {
                return []
            }
            let versions = try await self.appliedVersions()
            return self.migrations.filter { !versions.contains($0.version) }
        }

        func needsMigration() async throws -> Bool {
            guard try await !self.needsBootstrapping() else {
                return true
            }
            let migrations = try await self.pendingMigrations()
            return !migrations.isEmpty
        }

        func migrate(to version: UInt32 = UInt32.max) async throws -> Int {
            self.logger.info("running migration to version \(version)")

            self.logger.debug("checking if migrations bootstrapping is required")
            if try await self.needsBootstrapping() {
                self.logger.info("bootstrapping migrations")
                try await self.bootstrap()
            }

            let migrations = try await self.pendingMigrations().filter { $0.version <= version }
            if migrations.isEmpty {
                self.logger.info("migrations are up to date")
                return 0
            }

            self.logger.debug("running \(migrations.count) migrations")
            // apply by order!
            return try await self.apply(migrations: migrations, index: 0)
        }

        private func apply(migrations: [DatabaseMigrations.Entry], index: Int) async throws -> Int {
            if index >= migrations.count {
                return index
            }

            let migration = migrations[index]
            self.logger.debug("running migration \(migration.version): \(migration.description ?? migration.statement)")
            try await self.handler.apply(version: migration.version, statement: migration.statement)
            return try await self.apply(migrations: migrations, index: index + 1)
        }
    }

    /// Database migrations entry.
    public struct Entry: Equatable {
        public let version: UInt32
        public let description: String?
        public let statement: String

        public init(version: UInt32, description: String? = nil, statement: String) {
            self.version = version
            self.description = description
            self.statement = statement
        }
    }
}

/// This protocol is required to be implemented by database migrations libraries.
///
/// `DatabaseMigrationsHandler` requires the migration library to
/// retain a list of previously applied versions which are used to compute
/// the next version to apply.
public protocol DatabaseMigrationsHandler {
    /// Does the migration need bootstrapping? For example, doe the migrations metadata table exist?
    func needsBootstrapping() async throws -> Bool

    /// Bootstraps the migration. For example create the migrations metadata table.
    func bootstrap() async throws

    /// Returns the list of existing migration versions.
    func versions() async throws -> [UInt32]

    /// Applies a migration.
    /// - parameters:
    ///    - version: The migration version, can be used as a unique identifier.
    ///    - statement: The migration statement, for example a SQL statement.
    func apply(version: UInt32, statement: String) async throws
}
