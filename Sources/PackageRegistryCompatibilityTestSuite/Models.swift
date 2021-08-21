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

struct PackageIdentity: Hashable, Codable, CustomStringConvertible {
    let scope: String
    let name: String

    var description: String {
        "\(self.scope).\(self.name)"
    }
}

struct TestError: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        self.message
    }
}

// MARK: - Authentication

enum AuthenticationScheme: String {
    case basic
    case bearer
    case token
}

struct AuthenticationToken {
    let scheme: AuthenticationScheme
    let token: String

    init?(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return nil
        }

        guard let scheme = AuthenticationScheme(rawValue: String(parts[0])) else {
            return nil
        }
        self.scheme = scheme
        self.token = String(parts[1])
    }
}
