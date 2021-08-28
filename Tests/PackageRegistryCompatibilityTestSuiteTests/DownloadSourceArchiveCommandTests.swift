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

import PackageRegistryClient
@testable import PackageRegistryCompatibilityTestSuite
import TSCBasic

final class DownloadSourceArchiveCommandTests: XCTestCase {
    private var sourceArchives: [SourceArchiveMetadata]!
    private var registryClient: PackageRegistryClient!

    override func setUp() {
        do {
            let archivesJSON = self.fixtureURL(subdirectory: "SourceArchives", filename: "source_archives.json")
            self.sourceArchives = try JSONDecoder().decode([SourceArchiveMetadata].self, from: Data(contentsOf: archivesJSON))
        } catch {
            XCTFail("Failed to load source_archives.json")
        }

        let clientConfiguration = PackageRegistryClient.Configuration(url: self.registryURL, defaultRequestTimeout: .seconds(1))
        self.registryClient = PackageRegistryClient(httpClientProvider: .createNew, configuration: clientConfiguration)
    }

    override func tearDown() {
        try! self.registryClient.syncShutdown()
    }

    func test_help() throws {
        XCTAssert(try executeCommand(command: "package-registry-compatibility download-source-archive --help")
            .stdout.contains("USAGE: package-registry-compatibility download-source-archive <url> <config-path>"))
    }

    func test_run() throws {
        // Create package releases
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions, client: self.registryClient, sourceArchives: self.sourceArchives)

        let unknownScope = "test-\(UUID().uuidString.prefix(6))"

        let config = PackageRegistryCompatibilityTestSuite.Configuration(
            downloadSourceArchive: DownloadSourceArchiveTests.Configuration(
                sourceArchives: [
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "2.30.0"),
                        hasDuplicateLinks: false
                    ),
                ],
                unknownSourceArchives: [PackageRelease(package: PackageIdentity(scope: unknownScope, name: "unknown"), version: "1.0.0")],
                contentDispositionHeaderIsSet: true,
                digestHeaderIsSet: true
            )
        )
        let configData = try JSONEncoder().encode(config)

        try withTemporaryDirectory(removeTreeOnDeinit: true) { directoryPath in
            let configPath = directoryPath.appending(component: "config.json")
            try localFileSystem.writeFileContents(configPath, bytes: ByteString(Array(configData)))

            XCTAssert(try self.executeCommand(subcommand: "download-source-archive", configPath: configPath.pathString, generateData: false)
                .stdout.contains("Download Source Archive - All tests passed."))
        }
    }

    func test_run_generateConfig() throws {
        let configPath = self.fixturePath(filename: "gendata.json")
        XCTAssert(try self.executeCommand(subcommand: "download-source-archive", configPath: configPath, generateData: true)
            .stdout.contains("Download Source Archive - All tests passed."))
    }
}
