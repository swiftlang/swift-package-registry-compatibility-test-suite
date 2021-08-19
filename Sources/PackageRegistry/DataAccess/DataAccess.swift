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

import struct Foundation.Data

import PackageModel
import TSCUtility

protocol DataAccess {
    var packageReleases: PackageReleasesDAO { get }

    var packageResources: PackageResourcesDAO { get }

    var packageManifests: PackageManifestsDAO { get }

    func migrate() async throws
}

protocol PackageReleasesDAO {
    func create(package: PackageIdentity,
                version: Version,
                repositoryURL: String?,
                commitHash: String?,
                checksum: String,
                sourceArchive: Data,
                manifests: [(SwiftLanguageVersion?, String, ToolsVersion, Data)]) async throws -> (PackageRegistryModel.PackageRelease, PackageRegistryModel.PackageResource, [PackageRegistryModel.PackageManifest])

    func get(package: PackageIdentity, version: Version) async throws -> PackageRegistryModel.PackageRelease

    // Soft delete
    func delete(package: PackageIdentity, version: Version) async throws

    func list(for package: PackageIdentity) async throws -> [PackageRegistryModel.PackageRelease]
}

protocol PackageResourcesDAO {
    func create(package: PackageIdentity,
                version: Version,
                type: PackageRegistryModel.PackageResourceType,
                checksum: String,
                bytes: Data) async throws -> PackageRegistryModel.PackageResource

    func get(package: PackageIdentity, version: Version) async throws -> PackageRegistryModel.PackageResource
}

protocol PackageManifestsDAO {
    func create(package: PackageIdentity,
                version: Version,
                swiftVersion: SwiftLanguageVersion?,
                filename: String,
                swiftToolsVersion: ToolsVersion,
                bytes: Data) async throws -> PackageRegistryModel.PackageManifest
}

enum DataAccessError: Equatable, Error {
    case notFound
    case invalidData(detail: String)
    case noChange
}
