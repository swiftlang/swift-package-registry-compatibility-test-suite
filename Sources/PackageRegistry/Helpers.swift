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

extension String {
    func hasSuffix(_ suffix: String, caseSensitive: Bool) -> Bool {
        caseSensitive ? self.hasSuffix(suffix) : self.lowercased().hasSuffix(suffix.lowercased())
    }

    func dropDotExtension(_ dotExtension: String) -> String {
        let lowercasedString = self.lowercased()
        let lowercasedExtension = dotExtension.lowercased()

        if lowercasedString.hasSuffix(lowercasedExtension) {
            return String(self.dropLast(dotExtension.count))
        } else {
            return self
        }
    }
}
