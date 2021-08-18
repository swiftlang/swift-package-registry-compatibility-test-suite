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

extension Encodable {
    var jsonString: Swift.Result<String, Error> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(self)
            guard let json = String(data: data, encoding: .utf8) else {
                return .failure(JSONCodecError.unknownEncodingError)
            }
            return .success(json)
        } catch {
            return .failure(error)
        }
    }
}

enum JSONCodecError: Error {
    case unknownEncodingError
    case unknownDecodingError
}
