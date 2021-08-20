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

public struct PackageReleasesResponse: Codable {
    public let releases: [String: ReleaseInfo]

    public init(releases: [String: ReleaseInfo]) {
        self.releases = releases
    }

    public struct ReleaseInfo: Codable {
        public let url: String
        public let problem: ProblemDetails?

        public init(url: String, problem: ProblemDetails?) {
            self.url = url
            self.problem = problem
        }
    }
}
