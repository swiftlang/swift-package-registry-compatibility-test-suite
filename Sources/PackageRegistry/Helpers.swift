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

extension Optional {
    func unwrap(orError error: Error) throws -> Wrapped {
        switch self {
        case .some(let value):
            return value
        case .none:
            throw error
        }
    }
}

// For some APIs client may append .json extension to the request URI
func dropDotJSONExtension(_ s: String) -> String {
    dropDotExtension(".json", from: s)
}

func dropDotExtension(_ dotExtension: String, from s: String) -> String {
    if s.hasSuffix(dotExtension) {
        return String(s.dropLast(dotExtension.count))
    } else {
        return s
    }
}
