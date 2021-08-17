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
import XCTest

import AsyncHTTPClient
import NIO

final class BasicAPITests: XCTestCase {
    private var url: String!
    private var client: HTTPClient!

    override func setUp() {
        let host = ProcessInfo.processInfo.environment["API_SERVER_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["API_SERVER_PORT"].flatMap(Int.init) ?? 9229
        self.url = "http://\(host):\(port)"

        let clientConfiguration = HTTPClient.Configuration()
        self.client = HTTPClient(eventLoopGroupProvider: .createNew, configuration: clientConfiguration)
    }

    override func tearDown() {
        try! self.client.syncShutdown()
    }

    func testInfo() throws {
        let response = try self.client.get(url: self.url).wait()
        XCTAssertEqual(.ok, response.status)
    }

    func testHealth() throws {
        let response = try self.client.get(url: self.url + "/__health").wait()
        XCTAssertEqual(.ok, response.status)
    }
}
