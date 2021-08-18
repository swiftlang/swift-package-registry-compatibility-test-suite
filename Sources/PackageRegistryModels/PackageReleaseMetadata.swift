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

public struct PackageReleaseMetadata: Codable {
    public let repositoryURL: String?
    public let commitHash: String?

    public init(repositoryURL: String?, commitHash: String?) {
        self.repositoryURL = repositoryURL
        self.commitHash = commitHash
    }
}
