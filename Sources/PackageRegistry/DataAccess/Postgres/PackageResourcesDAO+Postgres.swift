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

import PostgresKit
import TSCUtility

extension PostgresDataAccess {
    struct PackageResources: PackageResourcesDAO {
        private static let tableName = "package_resources"

        private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>

        init(_ connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
            self.connectionPool = connectionPool
        }

        func create(package: PackageIdentity,
                    version: Version,
                    type: PackageRegistryModel.PackageResourceType,
                    checksum: String,
                    bytes: Data) async throws -> PackageRegistryModel.PackageResource {
            try await self.connectionPool.withConnectionThrowing { connection in
                let packageResource = PackageResource(scope: package.scope.description,
                                                      name: package.name.description,
                                                      version: version.description,
                                                      type: type.rawValue,
                                                      checksum: checksum,
                                                      bytes: bytes)
                try await connection.insert(into: Self.tableName)
                    .model(packageResource)
                    .run()
                return try packageResource.model()
            }
        }
    }
}

extension PostgresDataAccess.PackageResources {
    private struct PackageResource: Codable {
        var scope: String
        var name: String
        var version: String
        var type: String
        var checksum: String
        var bytes: Data

        func model() throws -> PackageRegistryModel.PackageResource {
            guard let package = PackageIdentity(scope: self.scope, name: self.name) else {
                throw DataAccessError.invalidData(detail: "Invalid scope ('\(self.scope)') or name ('\(self.name)')")
            }
            guard let version = Version(self.version) else {
                throw DataAccessError.invalidData(detail: "Invalid version '\(self.version)'")
            }
            guard let type = PackageRegistryModel.PackageResourceType(rawValue: self.type) else {
                throw DataAccessError.invalidData(detail: "Unknown type '\(self.type)'")
            }

            return PackageRegistryModel.PackageResource(
                package: package,
                version: version,
                type: type,
                checksum: self.checksum,
                bytes: self.bytes
            )
        }
    }
}
