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

/// 3.3. Error handling - a server SHOULD communicate any errors to the client using "problem details" objects,
/// as described by [RFC 7807](https://tools.ietf.org/html/rfc7807).
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
