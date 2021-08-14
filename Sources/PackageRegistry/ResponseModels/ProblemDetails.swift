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

import Foundation

/// 3.3. Error handling
/// A server SHOULD communicate any errors to the client using "problem details" objects, as described by [RFC 7807](https://tools.ietf.org/html/rfc7807).
public struct ProblemDetails: Codable {
    public let status: UInt?
    public let title: String?
    public let detail: String

    public init(detail: String) {
        self.init(status: nil, title: nil, detail: detail)
    }

    public init(status: UInt?, title: String?, detail: String) {
        self.status = status
        self.title = title
        self.detail = detail
    }

    public static let gone = ProblemDetails(status: 410, title: "Gone", detail: "This release was removed from the registry")
}
