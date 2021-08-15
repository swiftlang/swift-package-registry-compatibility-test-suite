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
    /// 3.6.1 Package scope
    let scope: PackageModel.PackageIdentity.Scope
    /// 3.6.2 Package name
    let name: PackageModel.PackageIdentity.Name

    init?(scope: String, name: String) {
        guard let scope = PackageModel.PackageIdentity.Scope(scope) else {
            return nil
        }
        guard let name = PackageModel.PackageIdentity.Name(name) else {
            return nil
        }
        self.init(scope: scope, name: name)
    }

    init(scope: PackageModel.PackageIdentity.Scope, name: PackageModel.PackageIdentity.Name) {
        self.scope = scope
        self.name = name
    }

    var description: String {
        "\(self.scope).\(self.name)"
    }
}
