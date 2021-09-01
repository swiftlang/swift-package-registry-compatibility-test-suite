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

final class CreatePackageReleaseCommandTests: XCTestCase {
    func test_help() throws {
        XCTAssert(try executeCommand(command: "package-registry-compatibility create-package-release --help")
            .stdout.contains("USAGE: package-registry-compatibility create-package-release <url> <config-path>"))
    }

    func test_run() throws {
        let configPath = self.fixturePath(filename: "local-registry.json")
        XCTAssert(try self.executeCommand(subcommand: "create-package-release", configPath: configPath, generateData: false)
            .stdout.contains("Create Package Release - All tests passed."))
    }

    func test_run_generateConfig() throws {
        let configPath = self.fixturePath(filename: "gendata.json")
        XCTAssert(try self.executeCommand(subcommand: "create-package-release", configPath: configPath, generateData: true)
            .stdout.contains("Create Package Release - All tests passed."))
    }
}
