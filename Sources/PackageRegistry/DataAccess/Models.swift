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

import struct Foundation.Data

import PackageModel
import TSCUtility

enum PackageRegistryModel {
    struct PackageRelease {
        let package: PackageIdentity
        let version: Version
        let repositoryURL: String?
        let commitHash: String?
        let status: Status

        enum Status: String {
            case published
            case deleted
        }
    }

    struct PackageResource {
        let package: PackageIdentity
        let version: Version
        let type: PackageResourceType
        let checksum: String
        let bytes: Data
    }

    enum PackageResourceType: String {
        case sourceArchive = "source_archive"
    }

    struct PackageManifest {
        let package: PackageIdentity
        let version: Version
        let swiftVersion: SwiftLanguageVersion?
        let filename: String
        let swiftToolsVersion: ToolsVersion
        let bytes: Data
    }
}

// TODO: Use SwiftPM's PackageIdentity when it supports scope and name
struct PackageIdentity: CustomStringConvertible {
    let scope: PackageModel.PackageIdentity.Scope
    let name: PackageModel.PackageIdentity.Name

    var description: String {
        "\(self.scope).\(self.name)"
    }
}
