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

public struct CreatePackageReleaseRequest: Codable {
    public let sourceArchiveBase64: String
    public let metadataJSONString: String

    public var sourceArchive: Data? {
        Data(base64Encoded: self.sourceArchiveBase64)
    }

    public var metadata: PackageReleaseMetadata? {
        guard let data = self.metadataJSONString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(PackageReleaseMetadata.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case sourceArchiveBase64 = "source-archive"
        case metadataJSONString = "metadata"
    }
}

public struct CreatePackageReleaseResponse: Codable {
    public let scope: String
    public let name: String
    public let version: String
    public let metadata: PackageReleaseMetadata?
    public let checksum: String

    public init(scope: String,
                name: String,
                version: String,
                metadata: PackageReleaseMetadata?,
                checksum: String) {
        self.scope = scope
        self.name = name
        self.version = version
        self.metadata = metadata
        self.checksum = checksum
    }
}
