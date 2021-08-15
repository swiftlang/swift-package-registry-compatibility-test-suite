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

import XCTest

@testable import PackageRegistry

final class AcceptHeaderParsingTests: XCTestCase {
    func testParseAcceptHeader() {
        do {
            let (apiVersion, mediaType) = parseAcceptHeader("application/vnd.swift.registry.v1+json")
            XCTAssertEqual("1", apiVersion)
            XCTAssertEqual("json", mediaType)
        }

        do {
            let (apiVersion, mediaType) = parseAcceptHeader("application/vnd.swift.registry.v1.1+json")
            XCTAssertEqual("1.1", apiVersion)
            XCTAssertEqual("json", mediaType)
        }

        do {
            let (apiVersion, mediaType) = parseAcceptHeader("application/vnd.swift.registry+json")
            XCTAssertNil(apiVersion)
            XCTAssertEqual("json", mediaType)
        }

        do {
            let (apiVersion, mediaType) = parseAcceptHeader("application/vnd.swift.registry.v1")
            XCTAssertEqual("1", apiVersion)
            XCTAssertNil(mediaType)
        }

        do {
            let (apiVersion, mediaType) = parseAcceptHeader("application/vnd.swift.registry")
            XCTAssertNil(apiVersion)
            XCTAssertNil(mediaType)
        }
    }
}
