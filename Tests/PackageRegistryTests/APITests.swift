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

import XCTest

import AsyncHTTPClient
import NIO
@testable import PackageRegistry

final class BasicAPITests: XCTestCase {
    func testInfo() {
        XCTAssertNoThrow(self.withServer { url, httpClient in
            let response = try httpClient.get(url: url).wait()
            XCTAssertEqual(.ok, response.status)
        })
    }

    func testHealth() {
        XCTAssertNoThrow(self.withServer { url, httpClient in
            let response = try httpClient.get(url: "\(url)/__health").wait()
            XCTAssertEqual(.ok, response.status)
        })
    }

    private func withServer(file: StaticString = #file, line: UInt = #line, testTask: (String, HTTPClient) throws -> Void) {
        do {
            let configuration = PackageRegistry.Configuration()

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            defer { try! eventLoopGroup.syncShutdownGracefully() }

            let api = PackageRegistry.API(configuration: configuration)
            defer { try! api.shutdown() }

            try api.start()

            let url = "http://\(configuration.api.host):\(configuration.api.port)"

            let clientConfiguration = HTTPClient.Configuration()
            let client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup), configuration: clientConfiguration)
            defer { try! client.syncShutdown() }

            try testTask(url, client)
        } catch {
            XCTFail(String(describing: error), file: file, line: line)
        }
    }
}
