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

import Foundation

import PackageModel
import PostgresKit
import TSCUtility

extension PostgresDataAccess {
    struct PackageReleases: PackageReleasesDAO {
        typealias CreateResult = (PackageRegistryModel.PackageRelease, PackageRegistryModel.PackageResource, [PackageRegistryModel.PackageManifest])

        private static let tableName = "package_releases"

        private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>
        private let packageResources: PackageResourcesDAO
        private let packageManifests: PackageManifestsDAO

        init(_ connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>, packageResources: PackageResourcesDAO, packageManifests: PackageManifestsDAO) {
            self.connectionPool = connectionPool
            self.packageResources = packageResources
            self.packageManifests = packageManifests
        }

        func create(package: PackageIdentity,
                    version: Version,
                    repositoryURL: String?,
                    commitHash: String?,
                    checksum: String,
                    sourceArchive: Data,
                    manifests: [(SwiftLanguageVersion?, String, ToolsVersion, Data)]) async throws -> CreateResult {
            try await self.connectionPool.withConnectionThrowing { connection in
                // Insert into three tables, commit iff all succeed
                try await connection.query("BEGIN;")

                // package_resources
                let packageResource = try await self.packageResources.create(package: package, version: version, type: .sourceArchive,
                                                                             checksum: checksum, bytes: sourceArchive)
                // package_manifests
                let packageManifests: [PackageRegistryModel.PackageManifest] =
                    try await withThrowingTaskGroup(of: PackageRegistryModel.PackageManifest.self) { group in
                        var packageManifests = [PackageRegistryModel.PackageManifest]()
                        for manifest in manifests {
                            group.addTask {
                                try await self.packageManifests.create(package: package, version: version, swiftVersion: manifest.0,
                                                                       filename: manifest.1, swiftToolsVersion: manifest.2, bytes: manifest.3)
                            }
                        }
                        while let manifest = try await group.next() {
                            packageManifests.append(manifest)
                        }
                        return packageManifests
                    }
                // package_releases
                let packageRelease = try await self.create(package: package, version: version, repositoryURL: repositoryURL, commitHash: commitHash)

                try await connection.query("COMMIT;")

                return (packageRelease, packageResource, packageManifests)
            }
        }

        func create(package: PackageIdentity,
                    version: Version,
                    repositoryURL: String?,
                    commitHash: String?) async throws -> PackageRegistryModel.PackageRelease {
            try await self.connectionPool.withConnectionThrowing { connection in
                let packageRelease = PackageRelease(scope: package.scope.description,
                                                    name: package.name.description,
                                                    version: version.description,
                                                    repository_url: repositoryURL,
                                                    commit_hash: commitHash,
                                                    status: PackageRegistryModel.PackageRelease.Status.published.rawValue,
                                                    created_at: Date(),
                                                    updated_at: Date())
                try await connection.insert(into: Self.tableName)
                    .model(packageRelease)
                    .run()
                return try packageRelease.model()
            }
        }

        func get(package: PackageIdentity, version: Version) async throws -> PackageRegistryModel.PackageRelease {
            try await self.fetch(package: package, version: version).model()
        }

        func delete(package: PackageIdentity, version: Version) async throws {
            let packageRelease = try await self.fetch(package: package, version: version)

            guard packageRelease.status != PackageRegistryModel.PackageRelease.Status.deleted.rawValue else {
                throw DataAccessError.noChange
            }

            try await self.connectionPool.withConnectionThrowing { connection in
                let packageRelease = PackageRelease(scope: packageRelease.scope,
                                                    name: packageRelease.name,
                                                    version: packageRelease.version,
                                                    repository_url: packageRelease.repository_url,
                                                    commit_hash: packageRelease.commit_hash,
                                                    status: PackageRegistryModel.PackageRelease.Status.deleted.rawValue,
                                                    created_at: packageRelease.created_at,
                                                    updated_at: Date())
                try await connection.update(Self.tableName)
                    .set(model: packageRelease)
                    // `packageRelease` holds actual database values, so there's no need to worry about case-insensitivity
                    .where("scope", .equal, SQLBind(packageRelease.scope))
                    .where("name", .equal, SQLBind(packageRelease.name))
                    .where("version", .equal, SQLBind(packageRelease.version))
                    .run()
            }
        }

        private func fetch(package: PackageIdentity, version: Version) async throws -> PackageRelease {
            try await self.connectionPool.withConnectionThrowing { connection in
                try await connection.select()
                    .column("*")
                    .from(Self.tableName)
                    // Case-insensitivity comparison
                    .where(SQLFunction("lower", args: "scope"), .equal, SQLBind(package.scope.description.lowercased()))
                    .where(SQLFunction("lower", args: "name"), .equal, SQLBind(package.name.description.lowercased()))
                    .where(SQLFunction("lower", args: "version"), .equal, SQLBind(version.description.lowercased()))
                    .first(decoding: PackageRelease.self)
                    .unwrap(orError: DataAccessError.notFound)
            }
        }

        func list(for package: PackageIdentity) async throws -> [PackageRegistryModel.PackageRelease] {
            try await self.connectionPool.withConnectionThrowing { connection in
                let packageReleases = try await connection.select()
                    .column("*")
                    .from(Self.tableName)
                    // Case-insensitivity comparison
                    .where(SQLFunction("lower", args: "scope"), .equal, SQLBind(package.scope.description.lowercased()))
                    .where(SQLFunction("lower", args: "name"), .equal, SQLBind(package.name.description.lowercased()))
                    .orderBy("created_at", .descending)
                    .all(decoding: PackageRelease.self)
                return try packageReleases.map { try $0.model() }
            }
        }

        func findBy(repositoryURL: String) async throws -> [PackageRegistryModel.PackageRelease] {
            try await self.connectionPool.withConnectionThrowing { connection in
                let packageReleases = try await connection.select()
                    .column("*")
                    .from(Self.tableName)
                    // Case-insensitivity comparison
                    .where(SQLFunction("lower", args: "repository_url"), .equal, SQLBind(repositoryURL.lowercased()))
                    .all(decoding: PackageRelease.self)
                return try packageReleases.map { try $0.model() }
            }
        }
    }
}

extension PostgresDataAccess.PackageReleases {
    struct PackageRelease: Codable {
        var scope: String
        var name: String
        var version: String
        var repository_url: String?
        var commit_hash: String?
        var status: String
        var created_at: Date
        var updated_at: Date

        func model() throws -> PackageRegistryModel.PackageRelease {
            guard let package = PackageIdentity(scope: self.scope, name: self.name) else {
                throw DataAccessError.invalidData(detail: "Invalid scope ('\(self.scope)') or name ('\(self.name)')")
            }
            guard let version = Version(self.version) else {
                throw DataAccessError.invalidData(detail: "Invalid version '\(self.version)'")
            }
            guard let status = PackageRegistryModel.PackageRelease.Status(rawValue: self.status) else {
                throw DataAccessError.invalidData(detail: "Unknown status '\(self.status)'")
            }

            return PackageRegistryModel.PackageRelease(
                package: package,
                version: version,
                repositoryURL: self.repository_url,
                commitHash: self.commit_hash,
                status: status
            )
        }
    }
}
