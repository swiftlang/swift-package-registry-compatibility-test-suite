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

final class FetchPackageReleaseInfoCommandTests: XCTestCase {
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
        XCTAssert(try executeCommand(command: "package-registry-compatibility fetch-package-release-info --help")
            .stdout.contains("USAGE: package-registry-compatibility fetch-package-release-info <url> <config-path>"))
    }

    func test_run() throws {
        // Create package releases
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions, client: self.registryClient, sourceArchives: self.sourceArchives)

        let unknownScope = "test-\(UUID().uuidString.prefix(6))"

        let config = PackageRegistryCompatibilityTestSuite.Configuration(
            fetchPackageReleaseInfo: FetchPackageReleaseInfoTests.Configuration(
                packageReleases: [
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "1.14.2"),
                        resources: [.sourceArchive(checksum: "43c63aad4ff999ca48aff499d879ebf68ce3afc7d69dcabe2ae2b1033646e983")],
                        keyValues: [
                            "repositoryURL": "https://github.com/\(scope)/\(name)",
                            "commitHash": "8da5c5a",
                        ],
                        linkRelations: ["latest-version", "successor-version"]
                    ),
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "2.29.0"),
                        resources: [.sourceArchive(checksum: "f44ce7dcc5d4fadf95e9a95c0e4345d0ae25a203ec63460883e1ca771e0b347b")],
                        keyValues: [
                            "repositoryURL": "https://github.com/\(scope)/\(name)",
                            "commitHash": "d161bf6",
                        ],
                        linkRelations: ["latest-version", "successor-version", "predecessor-version"]
                    ),
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "2.30.0"),
                        resources: [.sourceArchive(checksum: "e9a5540d37bf4fa0b5d5a071b366eeca899b37ece4ce93b26cc14286d57fbcef")],
                        keyValues: [
                            "repositoryURL": "https://github.com/\(scope)/\(name)",
                            "commitHash": "d79e333",
                        ],
                        linkRelations: ["latest-version", "predecessor-version"]
                    ),
                ],
                unknownPackageReleases: [PackageRelease(package: PackageIdentity(scope: unknownScope, name: "unknown"), version: "1.0.0")]
            )
        )
        let configData = try JSONEncoder().encode(config)

        try withTemporaryDirectory(removeTreeOnDeinit: true) { directoryPath in
            let configPath = directoryPath.appending(component: "config.json")
            try localFileSystem.writeFileContents(configPath, bytes: ByteString(Array(configData)))

            XCTAssert(try self.executeCommand(subcommand: "fetch-package-release-info", configPath: configPath.pathString, generateData: false)
                .stdout.contains("Fetch Package Release Information - All tests passed."))
        }
    }

    func test_run_generateConfig() throws {
        let configPath = self.fixturePath(filename: "gendata.json")
        XCTAssert(try self.executeCommand(subcommand: "fetch-package-release-info", configPath: configPath, generateData: true)
            .stdout.contains("Fetch Package Release Information - All tests passed."))
    }
}
