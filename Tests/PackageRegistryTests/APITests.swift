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
import NIOHTTP1
import PackageRegistryClient
import PackageRegistryModels

final class BasicAPITests: XCTestCase {
    private var sourceArchives: [SourceArchiveMetadata]!

    private var url: String!
    private var client: PackageRegistryClient!

    override func setUp() {
        do {
            let archivesJSON = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("source_archives.json")
            self.sourceArchives = try JSONDecoder().decode([SourceArchiveMetadata].self, from: Data(contentsOf: archivesJSON))
        } catch {
            XCTFail("Failed to load source_archives.json")
        }

        let host = ProcessInfo.processInfo.environment["API_SERVER_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["API_SERVER_PORT"].flatMap(Int.init) ?? 9229
        self.url = "http://\(host):\(port)"

        let clientConfiguration = PackageRegistryClient.Configuration(url: self.url, tls: false, defaultRequestTimeout: .seconds(1))
        self.client = PackageRegistryClient(eventLoopGroupProvider: .createNew, configuration: clientConfiguration)
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

        let archiveURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(archiveMetadata.filename)
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "\(archiveMetadata.scope)-\(UUID().uuidString.prefix(6))"
        let metadata: Data? = nil

        let response = try self.client.createPackageRelease(scope: scope,
                                                            name: name,
                                                            version: version,
                                                            sourceArchive: archive,
                                                            metadataJSON: metadata,
                                                            deadline: NIODeadline.now() + .seconds(3)).wait()

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

    func testCreatePackageRelease_withMetadata() throws {
        let name = "swift-service-discovery"
        let version = "1.0.0"
        guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
            return XCTFail("Source archive not found")
        }

        let archiveURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(archiveMetadata.filename)
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "\(archiveMetadata.scope)-\(UUID().uuidString.prefix(6))"
        let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
        let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

        let response = try self.client.createPackageRelease(scope: scope,
                                                            name: name,
                                                            version: version,
                                                            sourceArchive: archive,
                                                            metadata: metadata,
                                                            deadline: NIODeadline.now() + .seconds(3)).wait()

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

    func testCreatePackageRelease_shouldFailIfAlreadyExists() throws {
        let name = "swift-service-discovery"
        let version = "1.0.0"
        guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
            return XCTFail("Source archive not found")
        }

        let archiveURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(archiveMetadata.filename)
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "\(archiveMetadata.scope)-\(UUID().uuidString.prefix(6))"
        let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
        let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

        // First create should be ok
        do {
            let response = try self.client.createPackageRelease(scope: scope,
                                                                name: name,
                                                                version: version,
                                                                sourceArchive: archive,
                                                                metadata: metadata,
                                                                deadline: NIODeadline.now() + .seconds(3)).wait()
            XCTAssertEqual(.created, response.status)
        }

        // Package scope and name are case-insensitive, so create release again with uppercased name should fail.
        let nameUpper = name.uppercased()
        let response = try self.client.createPackageRelease(scope: scope,
                                                            name: nameUpper,
                                                            version: version,
                                                            sourceArchive: archive,
                                                            metadata: metadata,
                                                            deadline: NIODeadline.now() + .seconds(3)).wait()

        XCTAssertEqual(.conflict, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.conflict.code, problemDetails.status)
    }

    func testCreatePackageRelease_badArchive() throws {
        let archiveURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("bad-package.zip")
        let archive = try Data(contentsOf: archiveURL)

        // Create a unique scope to avoid conflicts between tests and test runs
        let scope = "test-\(UUID().uuidString.prefix(6))"
        let metadata: PackageReleaseMetadata? = nil

        let response = try self.client.createPackageRelease(scope: scope,
                                                            name: "bad",
                                                            version: "1.0.0",
                                                            sourceArchive: archive,
                                                            metadata: metadata,
                                                            deadline: NIODeadline.now() + .seconds(3)).wait()
        XCTAssertEqual(.unprocessableEntity, response.status)
        XCTAssertEqual(true, response.headers["Content-Type"].first?.contains("application/problem+json"))
        XCTAssertEqual("1", response.headers["Content-Version"].first)

        guard let problemDetails: ProblemDetails = try response.decodeBody() else {
            return XCTFail("ProblemDetails should not be nil")
        }
        XCTAssertEqual(HTTPResponseStatus.unprocessableEntity.code, problemDetails.status)
    }

    // MARK: - Delete package release

    func testDeletePackageRelease() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        try self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
        XCTAssertEqual(.noContent, response.status)
        XCTAssertEqual("1", response.headers["Content-Version"].first)
    }

    func testDeletePackageRelease_unknown() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"

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
        try self.createPackageReleases(scope: scope, name: name, versions: versions)

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
        // Create some releases for querying
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        try self.createPackageReleases(scope: scope, name: name, versions: versions)

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
            XCTAssertEqual(HTTPResponseStatus.gone.code, releasesResponse.releases["2.29.0"]!.problem!.status)

            let links = response.parseLinkHeader()
            XCTAssertNotNil(links.first { $0.relation == "latest-version" })
            XCTAssertNotNil(links.first { $0.relation == "canonical" })
        }
    }

    func testListPackageReleases_unknown() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"

        let response = try self.client.httpClient.get(url: "\(self.url!)/\(scope)/unknown").wait()
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
        try self.testOptions(path: "/scope/name/version.zip", expectedAllowedMethods: ["get", "delete"])
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

    private func createPackageReleases(scope: String, name: String, versions: [String]) throws {
        let futures: [EventLoopFuture<Void>] = versions.map { version in
            guard let archiveMetadata = self.sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
                return client.eventLoopGroup.next().makeFailedFuture(StringError(message: "Source archive not found"))
            }

            let archiveURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(archiveMetadata.filename)
            do {
                let archive = try Data(contentsOf: archiveURL)
                let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
                let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

                return self.client.createPackageRelease(scope: scope,
                                                        name: name,
                                                        version: version,
                                                        sourceArchive: archive,
                                                        metadata: metadata,
                                                        deadline: NIODeadline.now() + .seconds(10)).map { _ in }
            } catch {
                return client.eventLoopGroup.next().makeFailedFuture(error)
            }
        }

        try EventLoopFuture.andAllSucceed(futures, on: self.client.eventLoopGroup.next()).wait()
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
    public let relation: String
    public let url: String
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
            guard parts.count == 2 else {
                return nil
            }

            let url = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(1).dropLast(1) // Remove < > from beginning and end
            let rel = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst("rel=".count).dropFirst(1).dropLast(1) // Remove " from beginninng and end
            return Link(relation: String(rel), url: String(url))
        }
    }
}
