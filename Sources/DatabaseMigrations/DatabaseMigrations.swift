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

import Logging
import NIO

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
    ///    - on: `EventLoopGroup` to run the migrations on.
    ///    - handler: `Handler` to performs the migrations.
    ///    - migrations: collection of `DatabaseMigrations.Entry`.
    ///    - to: maximum version of migrations to run.
    public static func apply(on eventLoopGroup: EventLoopGroup, handler: Handler, migrations: [Entry], to version: UInt32 = UInt32.max) -> EventLoopFuture<Int> {
        Migrator(eventLoopGroup: eventLoopGroup, handler: handler, migrations: migrations).migrate(to: version)
    }

    internal struct Migrator {
        private let logger = Logger(label: "\(Migrator.self)")
        private let eventLoopGroup: EventLoopGroup
        private let handler: Handler
        private let migrations: [Entry]

        init(eventLoopGroup: EventLoopGroup, handler: Handler, migrations: [Entry]) {
            self.eventLoopGroup = eventLoopGroup
            self.handler = handler
            self.migrations = migrations
        }

        func needsBootstrapping() -> EventLoopFuture<Bool> {
            self.handler.needsBootstrapping()
        }

        func bootstrap() -> EventLoopFuture<Void> {
            self.handler.bootstrap()
        }

        func maxVersion() -> EventLoopFuture<UInt32> {
            self.needsBootstrapping().flatMap { needed in
                needed ? self.eventLoopGroup.next().makeSucceededFuture(0) :
                    self.handler.versions().map { versions in
                        versions.max() ?? 0
                    }
            }
        }

        func minVersion() -> EventLoopFuture<UInt32> {
            self.needsBootstrapping().flatMap { needed in
                needed ? self.eventLoopGroup.next().makeSucceededFuture(0) :
                    self.handler.versions().map { versions in
                        versions.min() ?? 0
                    }
            }
        }

        func appliedVersions() -> EventLoopFuture<[UInt32]> {
            self.needsBootstrapping().flatMap { needed in
                needed ? self.eventLoopGroup.next().makeSucceededFuture([]) : self.handler.versions()
            }
        }

        func pendingMigrations() -> EventLoopFuture<[Entry]> {
            self.needsBootstrapping().flatMap { needed in
                needed ? self.eventLoopGroup.next().makeSucceededFuture([]) :
                    self.appliedVersions().map { versions in
                        self.migrations.filter { !versions.contains($0.version) }
                    }
            }
        }

        func needsMigration() -> EventLoopFuture<Bool> {
            self.needsBootstrapping().flatMap { needed in
                needed ? self.eventLoopGroup.next().makeSucceededFuture(true) :
                    self.pendingMigrations().map { migrations in
                        !migrations.isEmpty
                    }
            }
        }

        func migrate(to version: UInt32 = UInt32.max) -> EventLoopFuture<Int> {
            self.logger.info("running migration to version \(version)")
            self.logger.debug("checking if migrations bootstrapping is required")
            return self.needsBootstrapping().flatMap { needed -> EventLoopFuture<Void> in
                if !needed {
                    return self.eventLoopGroup.next().makeSucceededFuture(())
                }
                self.logger.info("bootstrapping migrations")
                return self.bootstrap()
            }.flatMap { _ -> EventLoopFuture<[DatabaseMigrations.Entry]> in
                self.pendingMigrations()
            }.flatMap { migrations -> EventLoopFuture<Int> in
                let migrations = migrations.filter { $0.version <= version }
                if migrations.isEmpty {
                    self.logger.info("migrations are up to date")
                    return self.eventLoopGroup.next().makeSucceededFuture(0)
                }
                self.logger.debug("running \(migrations.count) migrations")
                // apply by order!
                return self.apply(migrations: migrations, index: 0)
            }
        }

        private func apply(migrations: [DatabaseMigrations.Entry], index: Int) -> EventLoopFuture<Int> {
            if index >= migrations.count {
                return self.eventLoopGroup.next().makeSucceededFuture(index)
            }
            let migration = migrations[index]
            self.logger.debug("running migration \(migration.version): \(migration.description ?? migration.statement)")
            return self.handler.apply(version: migration.version, statement: migration.statement).flatMap { _ in
                self.apply(migrations: migrations, index: index + 1)
            }
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
    func needsBootstrapping() -> EventLoopFuture<Bool>

    /// Bootstraps the migration. For example create the migrations metadata table.
    func bootstrap() -> EventLoopFuture<Void>

    /// Returns the list of existing migration versions.
    func versions() -> EventLoopFuture<[UInt32]>

    /// Applies a migration.
    /// - parameters:
    ///    - version: The migration version, can be used as a unique identifier.
    ///    - statement: The migration statement, for example a SQL statement.
    func apply(version: UInt32, statement: String) -> EventLoopFuture<Void>
}
