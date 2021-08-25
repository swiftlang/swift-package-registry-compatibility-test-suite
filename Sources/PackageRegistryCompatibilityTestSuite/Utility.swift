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

import struct Foundation.Data
import struct Foundation.URL

import TSCBasic

func randomAlphaNumericString(length: Int) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
    return String((0 ..< length).map { _ in letters.randomElement()! })
}

func makeAbsolutePath(_ path: String, relativeTo basePath: AbsolutePath?) throws -> AbsolutePath {
    do {
        return try AbsolutePath(validating: path)
    } catch {
        guard let basePath = basePath else {
            throw TestError("Base directory path is required when relative paths are used")
        }
        return AbsolutePath(path, relativeTo: basePath)
    }
}

func readData(at path: String) throws -> Data {
    let url = URL(fileURLWithPath: path)
    do {
        return try Data(contentsOf: url)
    } catch {
        throw TestError("Failed to read \(path): \(error)")
    }
}
