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

final class ListPackageReleasesCommandTests: XCTestCase {
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
        XCTAssert(try executeCommand(command: "package-registry-compatibility list-package-releases --help")
            .stdout.contains("USAGE: package-registry-compatibility list-package-releases <url> <config-path>"))
    }

    func test_run() throws {
        // Create package releases
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions, client: self.registryClient, sourceArchives: self.sourceArchives)

        // Make version 2.29.0 unavailable by deleting it
        let deleteResponse = try self.registryClient.httpClient.delete(url: "\(self.registryURL)/\(scope)/\(name)/2.29.0").wait()
        XCTAssertEqual(.noContent, deleteResponse.status)

        let unknownScope = "test-\(UUID().uuidString.prefix(6))"

        let config = PackageRegistryCompatibilityTestSuite.Configuration(
            listPackageReleases: ListPackageReleasesTests.Configuration(
                packages: [
                    .init(
                        package: PackageIdentity(scope: scope, name: name),
                        numberOfReleases: versions.count,
                        versions: Set(versions),
                        unavailableVersions: ["2.29.0"],
                        linkRelations: ["latest-version", "canonical"]
                    ),
                ],
                unknownPackages: [PackageIdentity(scope: unknownScope, name: "unknown")],
                packageURLProvided: true,
                problemProvided: true,
                paginationSupported: false
            )
        )
        let configData = try JSONEncoder().encode(config)

        try withTemporaryDirectory(removeTreeOnDeinit: true) { directoryPath in
            let configPath = directoryPath.appending(component: "config.json")
            try localFileSystem.writeFileContents(configPath, bytes: ByteString(Array(configData)))

            XCTAssert(try self.executeCommand(subcommand: "list-package-releases", configPath: configPath.pathString, generateData: false)
                .stdout.contains("List Package Releases - All tests passed."))
        }
    }

    func test_run_generateConfig() throws {
        let configPath = self.fixturePath(filename: "gendata.json")
        XCTAssert(try self.executeCommand(subcommand: "list-package-releases", configPath: configPath, generateData: true)
            .stdout.contains("List Package Releases - All tests passed."))
    }
}
