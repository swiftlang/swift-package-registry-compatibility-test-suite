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
import Crypto
import NIO
import NIOHTTP1
import PackageRegistryClient
import PackageRegistryModels

final class BasicAPITests: XCTestCase {
    private var sourceArchives: [SourceArchiveMetadata]!

    private var url: String!
    private var client: PackageRegistryClient!

    override func setUp() {
        do {
            let archivesJSON = self.fixtureURL(filename: "source_archives.json")
            self.sourceArchives = try JSONDecoder().decode([SourceArchiveMetadata].self, from: Data(contentsOf: archivesJSON))
        } catch {
            XCTFail("Failed to load source_archives.json")
        }

        let host = ProcessInfo.processInfo.environment["API_SERVER_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["API_SERVER_PORT"].flatMap(Int.init) ?? 9229
        self.url = "http://\(host):\(port)"

        let clientConfiguration = PackageRegistryClient.Configuration(url: self.url, defaultRequestTimeout: .seconds(1))
        self.client = PackageRegistryClient(httpClientProvider: .createNew, configuration: clientConfiguration)
    }

    override func tearDown() {
        try! self.client.syncShutdown()
    }

    // MARK: - Create package release

    func testCreatePackageRelease_withoutMetadata() throws {
        let name = "swift-service-discovery"
        let version = "1.0.0"
        guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
            return XCTFail("Source archive not found")
        }

        let archiveURL = self.fixtureURL(filename: archiveMetadata.filename)
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "\(archiveMetadata.scope)-\(UUID().uuidString.prefix(6))"
        let metadata: Data? = nil

        runAsyncAndWaitFor {
            let response = try await self.client.createPackageRelease(scope: scope,
                                                                      name: name,
                                                                      version: version,
                                                                      sourceArchive: archive,
                                                                      metadataJSON: metadata,
                                                                      deadline: NIODeadline.now() + .seconds(3))

            XCTAssertEqual(.created, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)
            XCTAssertEqual(self.url + "/\(scope)/\(name)/\(version)", response.headers["Location"].first)

            guard let createResponse: CreatePackageReleaseResponse = try response.decodeBody() else {
                return XCTFail("CreatePackageReleaseResponse should not be nil")
            }
            XCTAssertNil(createResponse.metadata?.repositoryURL)
            XCTAssertNil(createResponse.metadata?.commitHash)
            XCTAssertEqual(archiveMetadata.checksum, createResponse.checksum)
        }
    }

    func testCreatePackageRelease_withMetadata() throws {
        let name = "swift-service-discovery"
        let version = "1.0.0"
        guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
            return XCTFail("Source archive not found")
        }

        let archiveURL = self.fixtureURL(filename: archiveMetadata.filename)
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "\(archiveMetadata.scope)-\(UUID().uuidString.prefix(6))"
        let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
        let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

        runAsyncAndWaitFor {
            let response = try await self.client.createPackageRelease(scope: scope,
                                                                      name: name,
                                                                      version: version,
                                                                      sourceArchive: archive,
                                                                      metadata: metadata,
                                                                      deadline: NIODeadline.now() + .seconds(3))

            XCTAssertEqual(.created, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)
            XCTAssertEqual(self.url + "/\(scope)/\(name)/\(version)", response.headers["Location"].first)

            guard let createResponse: CreatePackageReleaseResponse = try response.decodeBody() else {
                return XCTFail("CreatePackageReleaseResponse should not be nil")
            }
            XCTAssertEqual(repositoryURL, createResponse.metadata?.repositoryURL)
            XCTAssertEqual(archiveMetadata.commitHash, createResponse.metadata?.commitHash)
            XCTAssertEqual(archiveMetadata.checksum, createResponse.checksum)
        }
    }

    func testCreatePackageRelease_alreadyExists() throws {
        let name = "swift-service-discovery"
        let version = "1.0.0"
        guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
            return XCTFail("Source archive not found")
        }

        let archiveURL = self.fixtureURL(filename: archiveMetadata.filename)
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "\(archiveMetadata.scope)-\(UUID().uuidString.prefix(6))"
        let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
        let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

        runAsyncAndWaitFor {
            // First create should be ok
            do {
                let response = try await self.client.createPackageRelease(scope: scope,
                                                                          name: name,
                                                                          version: version,
                                                                          sourceArchive: archive,
                                                                          metadata: metadata,
                                                                          deadline: NIODeadline.now() + .seconds(3))
                XCTAssertEqual(.created, response.status)
            }

            // Package scope and name are case-insensitive, so create release again with uppercased name should fail.
            let nameUpper = name.uppercased()
            let response = try await self.client.createPackageRelease(scope: scope,
                                                                      name: nameUpper,
                                                                      version: version,
                                                                      sourceArchive: archive,
                                                                      metadata: metadata,
                                                                      deadline: NIODeadline.now() + .seconds(3))

            XCTAssertEqual(.conflict, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let problemDetails: ProblemDetails = try response.decodeBody() else {
                return XCTFail("ProblemDetails should not be nil")
            }
            XCTAssertEqual(HTTPResponseStatus.conflict.code, problemDetails.status)
        }
    }

    func testCreatePackageRelease_badArchive() throws {
        let archiveURL = self.fixtureURL(filename: "bad-package.zip")
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "test-\(UUID().uuidString.prefix(6))"
        let metadata: PackageReleaseMetadata? = nil

        runAsyncAndWaitFor {
            let response = try await self.client.createPackageRelease(scope: scope,
                                                                      name: "bad",
                                                                      version: "1.0.0",
                                                                      sourceArchive: archive,
                                                                      metadata: metadata,
                                                                      deadline: NIODeadline.now() + .seconds(3))
            XCTAssertEqual(.unprocessableEntity, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let problemDetails: ProblemDetails = try response.decodeBody() else {
                return XCTFail("ProblemDetails should not be nil")
            }
            XCTAssertEqual(HTTPResponseStatus.unprocessableEntity.code, problemDetails.status)
        }
    }

    // MARK: - Delete package release

    func testDeletePackageRelease() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
        XCTAssertEqual(.noContent, response.status)
        XCTAssertEqual("1", response.headers["Content-Version"].first)
    }

    func testDeletePackageRelease_unknown() throws {
        let scope = "test-\(UUID().uuidString.prefix(6))"

        let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/unknown/1.0.0").wait()
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    func testDeletePackageRelease_alreadyDeleted() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // First delete should be ok (with .zip)
        do {
            let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0]).zip").wait()
            XCTAssertEqual(.noContent, response.status)
        }

        // Package scope and name are case-insensitive, so delete release again with uppercased name should fail.
        let nameUpper = name.uppercased()
        let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(nameUpper)/\(versions[0])").wait()

        XCTAssertEqual(.gone, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.gone.code, problemDetails.status)
    }

    // MARK: - List package releases

    func testListPackageReleases() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Delete one of the versions
        do {
            let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/2.29.0").wait()
            XCTAssertEqual(.noContent, response.status)
        }

        // Test .json suffix, case-insensitivity
        let urls = ["\(self.url!)/\(scope)/\(name)", "\(self.url!)/\(scope)/\(name).json", "\(self.url!)/\(scope)/\(name.uppercased())"]
        try urls.forEach {
            try self.testHead(url: $0)

            let response = try self.client.httpClient.get(url: $0).wait()
            XCTAssertEqual(.ok, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let releasesResponse: PackageReleasesResponse = try response.decodeBody() else {
                return XCTFail("PackageReleasesResponse should not be nil")
            }

            XCTAssertEqual(Set(versions), Set(releasesResponse.releases.keys))
            XCTAssertEqual(1, releasesResponse.releases.values.filter { $0.problem != nil }.count)
            XCTAssertEqual(HTTPResponseStatus.gone.code, releasesResponse.releases["2.29.0"]?.problem?.status)

            let links = response.parseLinkHeader()
            XCTAssertNotNil(links.first { $0.relation == "latest-version" })
            XCTAssertNotNil(links.first { $0.relation == "canonical" })
        }
    }

    func testListPackageReleases_unknown() throws {
        let scope = "test-\(UUID().uuidString.prefix(6))"

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/unknown").wait()
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    // MARK: - Fetch information about a package release

    func testFetchPackageReleaseInfo() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Test .json suffix, case-insensitivity
        let urls = [
            "\(self.url!)/\(scope)/\(name)/2.29.0",
            "\(self.url!)/\(scope)/\(name)/2.29.0.json",
            "\(self.url!)/\(scope)/\(name.uppercased())/2.29.0",
        ]
        try urls.forEach {
            try self.testHead(url: $0)

            let response = try self.client.httpClient.get(url: $0).wait()
            XCTAssertEqual(.ok, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let infoResponse: PackageReleaseInfo = try response.decodeBody() else {
                return XCTFail("PackageReleaseInfo should not be nil")
            }

            XCTAssertNotNil(infoResponse.metadata?.repositoryURL)
            XCTAssertNotNil(infoResponse.metadata?.commitHash)

            let links = response.parseLinkHeader()
            XCTAssertNotNil(links.first { $0.relation == "latest-version" })
            XCTAssertNotNil(links.first { $0.relation == "successor-version" })
            XCTAssertNotNil(links.first { $0.relation == "predecessor-version" })
        }

        do {
            let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/2.30.0").wait()
            XCTAssertEqual(.ok, response.status)

            let links = response.parseLinkHeader()
            XCTAssertNotNil(links.first { $0.relation == "latest-version" })
            XCTAssertNil(links.first { $0.relation == "successor-version" }) // 2.30.0 is the latest version
            XCTAssertNotNil(links.first { $0.relation == "predecessor-version" })
        }

        do {
            let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/1.14.2").wait()
            XCTAssertEqual(.ok, response.status)

            let links = response.parseLinkHeader()
            XCTAssertNotNil(links.first { $0.relation == "latest-version" })
            XCTAssertNotNil(links.first { $0.relation == "successor-version" })
            XCTAssertNil(links.first { $0.relation == "predecessor-version" }) // 1.14.2 is the first version
        }
    }

    func testFetchPackageReleaseInfo_deletedRelease() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Delete the package release
        do {
            let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
            XCTAssertEqual(.noContent, response.status)
        }

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
        XCTAssertEqual(.gone, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.gone.code, problemDetails.status)
    }

    func testFetchPackageReleaseInfo_unknownPackage() throws {
        let scope = "test-\(UUID().uuidString.prefix(6))"

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/unknown/1.0.0").wait()
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    func testFetchPackageReleaseInfo_unknownPackageRelease() throws {
        // Create some release for the package
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/1.0.0").wait() // 1.0.0 does not exist
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    // MARK: - Fetch package release manifest

    func testFetchPackageReleaseManifest() throws {
        let scope = "sunshinejr-\(UUID().uuidString.prefix(6))"
        let name = "SwiftyUserDefaults"
        let versions = ["5.3.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Case-insensitivity
        let urls = ["\(self.url!)/\(scope)/\(name)/5.3.0/Package.swift", "\(self.url!)/\(scope)/\(name.uppercased())/5.3.0/Package.swift"]
        try urls.forEach {
            try self.testHead(url: $0)

            let response = try self.client.httpClient.get(url: $0).wait()
            XCTAssertEqual(.ok, response.status)
            XCTAssertEqual("public, immutable", response.headers["Cache-Control"].first)
            XCTAssertEqual("text/x-swift", response.headers["Content-Type"].first)
            XCTAssertEqual("attachment; filename=\"Package.swift\"", response.headers["Content-Disposition"].first)
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let responseBody = response.body else {
                return XCTFail("Response body is empty")
            }
            XCTAssertEqual(responseBody.readableBytes, response.headers["Content-Length"].first.map { Int(String($0)) ?? -1 })

            let manifest = String(data: Data(buffer: responseBody), encoding: .utf8)!
            XCTAssertNotNil(manifest.range(of: "\"https://github.com/Quick/Quick.git\", .upToNextMajor(from: \"2.0.0\")", options: .caseInsensitive))

            let links = response.parseLinkHeader()
            XCTAssertNotNil(links.first { $0.relation == "alternate" })
        }

        // Version-specific manifest
        do {
            let url = "\(self.url!)/\(scope)/\(name)/5.3.0/Package.swift?swift-version=4.2"

            try self.testHead(url: url)

            let response = try self.client.httpClient.get(url: url).wait()
            XCTAssertEqual(.ok, response.status)
            XCTAssertEqual("public, immutable", response.headers["Cache-Control"].first)
            XCTAssertEqual("text/x-swift", response.headers["Content-Type"].first)
            XCTAssertEqual("attachment; filename=\"Package@swift-4.2.swift\"", response.headers["Content-Disposition"].first)
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let responseBody = response.body else {
                return XCTFail("Response body is empty")
            }
            XCTAssertEqual(responseBody.readableBytes, response.headers["Content-Length"].first.map { Int(String($0)) ?? -1 })

            let manifest = String(data: Data(buffer: responseBody), encoding: .utf8)!
            XCTAssertNotNil(manifest.range(of: "\"https://github.com/Quick/Quick.git\", .upToNextMajor(from: \"1.3.0\")", options: .caseInsensitive))

            let links = response.parseLinkHeader()
            XCTAssertNil(links.first { $0.relation == "alternate" })
        }
    }

    func testFetchPackageReleaseManifest_redirectIfVersionedManifestNotFound() throws {
        let scope = "sunshinejr-\(UUID().uuidString.prefix(6))"
        let name = "SwiftyUserDefaults"
        let versions = ["5.3.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/5.3.0/Package.swift?swift-version=5.0").wait()
        XCTAssertEqual(.ok, response.status)
        // Redirects to Package.swift
        XCTAssertEqual("attachment; filename=\"Package.swift\"", response.headers["Content-Disposition"].first)

        guard let responseBody = response.body else {
            return XCTFail("Response body is empty")
        }

        let manifest = String(data: Data(buffer: responseBody), encoding: .utf8)!
        XCTAssertNotNil(manifest.range(of: "\"https://github.com/Quick/Quick.git\", .upToNextMajor(from: \"2.0.0\")", options: .caseInsensitive))
    }

    func testFetchPackageReleaseManifest_deletedRelease() throws {
        let scope = "sunshinejr-\(UUID().uuidString.prefix(6))"
        let name = "SwiftyUserDefaults"
        let versions = ["5.3.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Delete the package release
        do {
            let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
            XCTAssertEqual(.noContent, response.status)
        }

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])/Package.swift").wait()
        XCTAssertEqual(.gone, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.gone.code, problemDetails.status)
    }

    func testFetchPackageReleaseManifest_unknownPackage() throws {
        let scope = "test-\(UUID().uuidString.prefix(6))"

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/unknown/1.0.0/Package.swift").wait()
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    func testFetchPackageReleaseManifest_unknownPackageRelease() throws {
        // Create some release for the package
        let scope = "sunshinejr-\(UUID().uuidString.prefix(6))"
        let name = "SwiftyUserDefaults"
        let versions = ["5.3.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/1.0.0/Package.swift").wait() // 1.0.0 does not exist
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    // MARK: - Download source archive

    func testDownloadSourceArchive() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Case-insensitivity
        let urls = ["\(self.url!)/\(scope)/\(name)/1.0.0.zip", "\(self.url!)/\(scope)/\(name.uppercased())/1.0.0.zip"]
        try urls.forEach {
            try self.testHead(url: $0)

            let response = try self.client.httpClient.get(url: $0).wait()
            XCTAssertEqual(.ok, response.status)
            XCTAssertEqual("bytes", response.headers["Accept-Ranges"].first)
            XCTAssertEqual("public, immutable", response.headers["Cache-Control"].first)
            XCTAssertEqual("application/zip", response.headers["Content-Type"].first)
            XCTAssertEqual("attachment; filename=\"\(name)-1.0.0.zip\"".lowercased, response.headers["Content-Disposition"].first?.lowercased())
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let responseBody = response.body, responseBody.readableBytes > 0 else {
                return XCTFail("Response body is empty")
            }
            XCTAssertEqual(responseBody.readableBytes, response.headers["Content-Length"].first.map { Int(String($0)) ?? -1 })

            guard let digest = response.parseDigestHeader() else {
                return XCTFail("Missing 'Digest' header")
            }
            XCTAssertEqual("sha-256", digest.algorithm)

            let responseData = Data(buffer: responseBody)
            let checksum = Data(SHA256.hash(data: responseData)).base64EncodedString()
            XCTAssertEqual(checksum, digest.checksum)
        }
    }

    func testDownloadSourceArchive_deletedRelease() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        // Delete the package release
        do {
            let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
            XCTAssertEqual(.noContent, response.status)
        }

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/\(versions[0]).zip").wait()
        XCTAssertEqual(.gone, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.gone.code, problemDetails.status)
    }

    func testDownloadSourceArchive_unknownPackage() throws {
        let scope = "test-\(UUID().uuidString.prefix(6))"

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/unknown/1.0.0.zip").wait()
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    func testDownloadSourceArchive_unknownPackageRelease() throws {
        // Create some release for the package
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/\(name)/0.0.1.zip").wait() // 0.0.1 does not exist
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    // MARK: - Lookup package identifiers by URL

    func testLookupPackageIdentifiersByURL() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"

        func createPackageRelease(name: String, version: String) throws -> String {
            guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
                throw StringError(message: "Source archive not found")
            }

            let archiveURL = self.fixtureURL(filename: archiveMetadata.filename)
            let archive = try Data(contentsOf: archiveURL)
            let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
            let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

            runAsyncAndWaitFor {
                let response = try await self.client.createPackageRelease(scope: scope,
                                                                          name: name,
                                                                          version: version,
                                                                          sourceArchive: archive,
                                                                          metadata: metadata,
                                                                          deadline: NIODeadline.now() + .seconds(3))

                XCTAssertEqual(.created, response.status)
            }

            return repositoryURL
        }

        // Register package identifier with repository URL
        let sdRepositoryURL = try createPackageRelease(name: "swift-service-discovery", version: "1.0.0")
        let nioRepositoryURL = try createPackageRelease(name: "swift-nio", version: "1.14.2")

        // swift-service-discovery repository URL
        // Case-insensitivity
        let urls = ["\(self.url!)/identifiers?url=\(sdRepositoryURL)", "\(self.url!)/identifiers?url=\(sdRepositoryURL.uppercased())"]
        try urls.forEach {
            try self.testHead(url: $0)

            let response = try self.client.httpClient.get(url: $0).wait()
            XCTAssertEqual(.ok, response.status)
            XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/json"))
            XCTAssertEqual("1", response.headers["Content-Version"].first)

            guard let identifiersResponse: PackageIdentifiersResponse = try response.decodeBody() else {
                return XCTFail("PackageIdentifiersResponse should not be nil")
            }
            XCTAssertEqual(["\(scope).swift-service-discovery"], identifiersResponse.identifiers)
        }

        // swift-nio repository URL
        let response = try self.client.httpClient.get(url: "\(self.url!)/identifiers?url=\(nioRepositoryURL)").wait()
        XCTAssertEqual(.ok, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let identifiersResponse: PackageIdentifiersResponse = try response.decodeBody() else {
            return XCTFail("PackageIdentifiersResponse should not be nil")
        }
        XCTAssertEqual(["\(scope).swift-nio"], identifiersResponse.identifiers)
    }

    func testLookupPackageIdentifiersByURL_unknownURL() throws {
        let scope = "test-\(UUID().uuidString.prefix(6))"
        let repositoryURL = "https://test.repo.com/\(scope)/unknown"

        let response = try self.client.httpClient.get(url: "\(self.url!)/identifiers?url=\(repositoryURL)").wait()
        XCTAssertEqual(.notFound, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.notFound.code, problemDetails.status)
    }

    // MARK: - info and health endpoints

    func testInfo() throws {
        let response = try self.client.httpClient.get(url: self.url).wait()
        XCTAssertEqual(.ok, response.status)
    }

    func testHealth() throws {
        let response = try self.client.httpClient.get(url: "\(self.url!)/__health").wait()
        XCTAssertEqual(.ok, response.status)
    }

    // MARK: - OPTIONS requests

    func testOptions() throws {
        try self.testOptions(path: "/scope/name", expectedAllowedMethods: ["get"])
        try self.testOptions(path: "/scope/name.json", expectedAllowedMethods: ["get"])
        try self.testOptions(path: "/scope/name/version", expectedAllowedMethods: ["get", "put", "delete"])
        try self.testOptions(path: "/scope/name/version.json", expectedAllowedMethods: ["get"])
        try self.testOptions(path: "/scope/name/version/Package.swift", expectedAllowedMethods: ["get"])
        try self.testOptions(path: "/scope/name/version.zip", expectedAllowedMethods: ["get", "delete"])
        try self.testOptions(path: "/identifiers", expectedAllowedMethods: ["get"])
    }

    // MARK: - Helpers

    private func testHead(url: String) throws {
        let request = try HTTPClient.Request(url: url, method: .HEAD)
        let response = try self.client.httpClient.execute(request: request).wait()
        XCTAssertEqual(.ok, response.status)
    }

    private func testOptions(path: String, expectedAllowedMethods: Set<String>) throws {
        let request = try HTTPClient.Request(url: "\(self.url!)\(path)", method: .OPTIONS)
        let response = try self.client.httpClient.execute(request: request).wait()

        XCTAssertEqual(.ok, response.status)
        XCTAssertNotNil(response.headers["Link"].first)

        let allowedMethods = Set(response.headers["Allow"].first?.lowercased().split(separator: ",").map(String.init) ?? [])
        XCTAssertEqual(expectedAllowedMethods, allowedMethods)
    }

    private func createPackageReleases(scope: String, name: String, versions: [String]) {
        runAsyncAndWaitFor({
            for version in versions {
                guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
                    throw StringError(message: "Source archive for version \(version) not found")
                }

                let archiveURL = self.fixtureURL(filename: archiveMetadata.filename)
                let archive = try Data(contentsOf: archiveURL)
                let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
                let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

                let response = try await self.client.createPackageRelease(scope: scope,
                                                                          name: name,
                                                                          version: version,
                                                                          sourceArchive: archive,
                                                                          metadata: metadata,
                                                                          deadline: NIODeadline.now() + .seconds(20))
                XCTAssertEqual(.created, response.status)
            }
        }, TimeInterval(versions.count * 20))
    }

    private func fixtureURL(filename: String) -> URL {
        URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent("SourceArchives", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

private struct SourceArchiveMetadata: Codable {
    let scope: String
    let name: String
    let version: String
    let repositoryURL: String
    let commitHash: String
    let checksum: String

    var filename: String {
        "\(self.name)@\(self.version).zip"
    }
}

private struct Link {
    let relation: String
    let url: String
}

private struct Digest {
    let algorithm: String
    let checksum: String
}

private struct StringError: Error {
    let message: String
}

private extension HTTPClient.Response {
    func decodeBody<T: Codable>() throws -> T? {
        guard let responseBody = self.body else {
            return nil
        }
        let responseData = Data(buffer: responseBody)
        return try JSONDecoder().decode(T.self, from: responseData)
    }

    func parseLinkHeader() -> [Link] {
        (self.headers["Link"].first?.split(separator: ",") ?? []).compactMap {
            let parts = $0.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ";")
            guard parts.count >= 2 else {
                return nil
            }

            let url = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(1).dropLast(1) // Remove < > from beginning and end
            let rel = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst("rel=".count).dropFirst(1).dropLast(1) // Remove " from beginninng and end
            return Link(relation: String(rel), url: String(url))
        }
    }

    func parseDigestHeader() -> Digest? {
        guard let digestHeader = self.headers["Digest"].first else {
            return nil
        }

        let parts = digestHeader.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
            return nil
        }

        let algorithm = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let checksum = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return Digest(algorithm: algorithm, checksum: checksum)
    }
}

private extension XCTestCase {
    // TODO: remove once XCTest supports async functions
    func runAsyncAndWaitFor(_ closure: @escaping () async throws -> Void, _ timeout: TimeInterval = 10.0) {
        let finished = expectation(description: "finished")
        Task.detached {
            try await closure()
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)
    }
}
