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

import NIO
import PostgresMigrations

extension DatabaseMigrations.Postgres {
    func apply(on eventLoopGroup: EventLoopGroup) -> EventLoopFuture<Int> {
        self.apply(on: eventLoopGroup, migrations: DatabaseMigrations.Postgres.all)
    }

    private static let all: [DatabaseMigrations.Entry] = [
        // MARK: - package_releases

        .init(version: 100, statement: """
        CREATE TABLE package_releases (
          scope TEXT NOT NULL,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          repository_url TEXT,
          commit_hash TEXT,
          status TEXT NOT NULL,
          created_at TIMESTAMPTZ NOT NULL,
          updated_at TIMESTAMPTZ NOT NULL,
          PRIMARY KEY(scope, name, version)
        );
        """),
        .init(version: 101, statement: "CREATE INDEX package_releases_repository_url_idx on package_releases (repository_url);"),
        .init(version: 102, statement: "CREATE INDEX package_releases_status_idx on package_releases (status);"),

        // MARK: - package_resources

        .init(version: 200, statement: """
        CREATE TABLE package_resources (
          scope TEXT NOT NULL,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          type TEXT NOT NULL,
          checksum TEXT NOT NULL,
          bytes BYTEA NOT NULL,
          PRIMARY KEY(scope, name, version, type)
        );
        """),

        // MARK: - package_manifests

        .init(version: 300, statement: """
        CREATE TABLE package_manifests (
          id SERIAL PRIMARY KEY,
          scope TEXT NOT NULL,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          swift_version TEXT,
          filename TEXT NOT NULL,
          swift_tools_version TEXT NOT NULL,
          bytes BYTEA NOT NULL
        );
        """),
        .init(version: 301, statement: "CREATE INDEX package_manifests_package_version_idx on package_manifests (scope, name, version);"),
        .init(version: 302, statement: "CREATE UNIQUE INDEX package_manifests_package_version_swift_version_idx on package_manifests (scope, name, version, swift_version);"),
        // Postgres treats NULL as distinct values. This unique index enforces one NULL only.
        .init(version: 303, statement: "CREATE UNIQUE INDEX package_manifests_package_version_null_swift_version_idx on package_manifests (scope, name, version, (swift_version IS NULL)) WHERE swift_version IS NULL;"),
    ]
}
