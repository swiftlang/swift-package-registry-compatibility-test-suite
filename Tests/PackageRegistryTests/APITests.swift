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

    // MARK: - Create package release tests

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

    // MARK: - Delete package release tests

    func testDeletePackageRelease() throws {
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-service-discovery"
        let versions = ["1.0.0"]
        try self.createPackageReleases(scope: scope, name: name, versions: versions)

        let response = try self.client.httpClient.delete(url: "\(self.url!)/\(scope)/\(name)/\(versions[0])").wait()
        XCTAssertEqual(.noContent, response.status)
        XCTAssertEqual("1", response.headers["Content-Version"].first)
    }

    func testDeletePackageRelease_notFound() throws {
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

    // MARK: - info and health endpoints

    func testInfo() throws {
        let response = try self.client.httpClient.get(url: self.url).wait()
        XCTAssertEqual(.ok, response.status)
    }

    func testHealth() throws {
        let response = try self.client.httpClient.get(url: "\(self.url!)/__health").wait()
        XCTAssertEqual(.ok, response.status)
    }

    // MARK: - HEAD and OPTIONS requests

    func testOptions_scopeNameVersion() throws {
        let request = try HTTPClient.Request(url: self.url + "/scope/name/version", method: .OPTIONS)
        let response = try self.client.httpClient.execute(request: request).wait()

        XCTAssertEqual(.ok, response.status)
        XCTAssertNotNil(response.headers["Link"].first)

        let allowedMethods = Set(response.headers["Allow"].first?.lowercased().split(separator: ",").map(String.init) ?? [])
        let expectedAllowedMethods: Set<String> = ["get", "put", "delete"]
        XCTAssertEqual(expectedAllowedMethods, allowedMethods)
    }

    func testOptions_scopeNameVersionDotZip() throws {
        let request = try HTTPClient.Request(url: self.url + "/scope/name/version.zip", method: .OPTIONS)
        let response = try self.client.httpClient.execute(request: request).wait()

        XCTAssertEqual(.ok, response.status)
        XCTAssertNotNil(response.headers["Link"].first)

        let allowedMethods = Set(response.headers["Allow"].first?.lowercased().split(separator: ",").map(String.init) ?? [])
        let expectedAllowedMethods: Set<String> = ["get", "delete"]
        XCTAssertEqual(expectedAllowedMethods, allowedMethods)
    }

    // MARK: - Helpers

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
}
