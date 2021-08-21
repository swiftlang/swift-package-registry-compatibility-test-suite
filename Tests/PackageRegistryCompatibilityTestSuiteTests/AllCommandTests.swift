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

final class AllCommandTests: XCTestCase {
    func test_help() throws {
        XCTAssert(try executeCommand(command: "package-registry-compatibility all --help")
            .stdout.contains("USAGE: package-registry-compatibility all <url> <config-path>"))
    }

    func test_run() throws {
        let stdout = try self.executeCommand(subcommand: "all", generateData: false).stdout
        XCTAssert(stdout.contains("Create Package Release - All tests passed."))
    }

    func test_run_generateData() throws {
        let stdout = try self.executeCommand(subcommand: "all", generateData: true).stdout
        XCTAssert(stdout.contains("Create Package Release - All tests passed."))
    }
}
