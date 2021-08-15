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

import NIO
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
                manifests: [(SwiftLanguageVersion?, String, ToolsVersion, Data)]) -> EventLoopFuture<(PackageRegistryModel.PackageRelease, PackageRegistryModel.PackageResource, [PackageRegistryModel.PackageManifest])>

    func get(package: PackageIdentity, version: Version) -> EventLoopFuture<PackageRegistryModel.PackageRelease>
}

protocol PackageResourcesDAO {
    func create(package: PackageIdentity,
                version: Version,
                type: PackageRegistryModel.PackageResourceType,
                checksum: String,
                bytes: Data) -> EventLoopFuture<PackageRegistryModel.PackageResource>
}

protocol PackageManifestsDAO {
    func create(package: PackageIdentity,
                version: Version,
                swiftVersion: SwiftLanguageVersion?,
                filename: String,
                swiftToolsVersion: ToolsVersion,
                bytes: Data) -> EventLoopFuture<PackageRegistryModel.PackageManifest>
}

enum DataAccessError: Equatable, Error {
    case notFound
    case invalidData(detail: String)
}
