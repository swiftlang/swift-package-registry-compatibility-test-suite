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

public struct PackageReleaseInfo: Codable {
    public let id: String
    public let version: String
    public let resources: [ReleaseResource]
    public let metadata: PackageReleaseMetadata?

    public init(id: String, version: String, resource: ReleaseResource?, metadata: PackageReleaseMetadata?) {
        self.init(id: id, version: version, resources: resource.map { [$0] } ?? [], metadata: metadata)
    }

    public init(id: String, version: String, resources: [ReleaseResource], metadata: PackageReleaseMetadata?) {
        self.id = id
        self.version = version
        self.resources = resources
        self.metadata = metadata
    }

    public struct ReleaseResource: Codable {
        public let name: String
        public let type: String
        public let checksum: String

        public init(name: String, type: String, checksum: String) {
            self.name = name
            self.type = type
            self.checksum = checksum
        }

        public static func sourceArchive(checksum: String) -> ReleaseResource {
            ReleaseResource(name: "source-archive", type: "application/zip", checksum: checksum)
        }
    }
}
