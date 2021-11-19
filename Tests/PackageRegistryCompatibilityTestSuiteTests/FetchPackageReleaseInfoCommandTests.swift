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
                        resources: [.sourceArchive(checksum: "02bc0388134a4b0bbc1145f56a50c6e3d0ce8f4b456661bb156861db394e732b")],
                        keyValues: [
                            "repositoryURL": "https://github.com/\(scope)/\(name)",
                            "commitHash": "8da5c5a",
                        ],
                        linkRelations: ["latest-version", "successor-version"]
                    ),
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "2.29.0"),
                        resources: [.sourceArchive(checksum: "24805ad6e2313cec79d92a8c805f6398aa7d46ea0c1aef03c76ce023a1fd5daf")],
                        keyValues: [
                            "repositoryURL": "https://github.com/\(scope)/\(name)",
                            "commitHash": "d161bf6",
                        ],
                        linkRelations: ["latest-version", "successor-version", "predecessor-version"]
                    ),
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "2.30.0"),
                        resources: [.sourceArchive(checksum: "cd5d6f66f60b88326174bcfcfe76f070edec66e38e50c15b6403eb6a8d2eccbc")],
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
