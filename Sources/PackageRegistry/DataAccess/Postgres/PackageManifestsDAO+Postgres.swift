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
    struct PackageManifests: PackageManifestsDAO {
        private static let tableName = "package_manifests"

        private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>

        init(_ connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
            self.connectionPool = connectionPool
        }

        func create(package: PackageIdentity,
                    version: Version,
                    swiftVersion: SwiftLanguageVersion?,
                    filename: String,
                    swiftToolsVersion: ToolsVersion,
                    bytes: Data) async throws -> PackageRegistryModel.PackageManifest {
            try await self.connectionPool.withConnectionThrowing { connection in
                let packageManifest = PackageManifest(scope: package.scope.description,
                                                      name: package.name.description,
                                                      version: version.description,
                                                      swift_version: swiftVersion?.description,
                                                      filename: filename,
                                                      swift_tools_version: swiftToolsVersion.description,
                                                      bytes: bytes)
                try await connection.insert(into: Self.tableName)
                    .model(packageManifest)
                    .run()
                return try packageManifest.model()
            }
        }

        func get(package: PackageIdentity, version: Version) async throws -> [PackageRegistryModel.PackageManifest] {
            try await self.connectionPool.withConnectionThrowing { connection in
                let manifests = try await connection.select()
                    .column("*")
                    .from(Self.tableName)
                    // Case-insensitivity comparison
                    .where(SQLFunction("lower", args: "scope"), .equal, SQLBind(package.scope.description.lowercased()))
                    .where(SQLFunction("lower", args: "name"), .equal, SQLBind(package.name.description.lowercased()))
                    .where(SQLFunction("lower", args: "version"), .equal, SQLBind(version.description.lowercased()))
                    .all(decoding: PackageManifest.self)
                return try manifests.map { try $0.model() }
            }
        }
    }
}

extension PostgresDataAccess.PackageManifests {
    private struct PackageManifest: Codable {
        var scope: String
        var name: String
        var version: String
        var swift_version: String?
        var filename: String
        var swift_tools_version: String
        var bytes: Data

        func model() throws -> PackageRegistryModel.PackageManifest {
            guard let package = PackageIdentity(scope: self.scope, name: self.name) else {
                throw DataAccessError.invalidData(detail: "Invalid scope ('\(self.scope)') or name ('\(self.name)')")
            }
            guard let version = Version(self.version) else {
                throw DataAccessError.invalidData(detail: "Invalid version '\(self.version)'")
            }

            var swiftVersion: SwiftLanguageVersion?
            if let swiftVersionString = self.swift_version {
                swiftVersion = SwiftLanguageVersion(string: swiftVersionString)
                guard swiftVersion != nil else {
                    throw DataAccessError.invalidData(detail: "Invalid Swift version '\(swiftVersionString)'")
                }
            }

            guard let swiftToolsVersion = ToolsVersion(string: self.swift_tools_version) else {
                throw DataAccessError.invalidData(detail: "Invalid Swift tools version '\(self.swift_tools_version)'")
            }

            return PackageRegistryModel.PackageManifest(
                package: package,
                version: version,
                swiftVersion: swiftVersion,
                filename: self.filename,
                swiftToolsVersion: swiftToolsVersion,
                bytes: self.bytes
            )
        }
    }
}
