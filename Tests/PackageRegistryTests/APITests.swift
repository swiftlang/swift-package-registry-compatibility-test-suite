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

    // MARK: - info and health endpoints

    func testInfo() throws {
        let response = try self.client.httpClient.get(url: self.url).wait()
        XCTAssertEqual(.ok, response.status)
    }

    func testHealth() throws {
        let response = try self.client.httpClient.get(url: self.url + "/__health").wait()
        XCTAssertEqual(.ok, response.status)
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
