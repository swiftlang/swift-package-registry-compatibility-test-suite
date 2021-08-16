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
