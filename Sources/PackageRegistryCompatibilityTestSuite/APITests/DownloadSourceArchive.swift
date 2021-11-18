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

import AsyncHTTPClient
import Crypto
import NIOHTTP1
import TSCBasic

final class DownloadSourceArchiveTests: APITest {
    let configuration: Configuration

    private let fileSystem: FileSystem

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        self.configuration = configuration
        self.fileSystem = localFileSystem
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() async {
        for fixture in self.configuration.sourceArchives {
            let scope = fixture.packageRelease.package.scope
            let name = fixture.packageRelease.package.name
            let version = fixture.packageRelease.version

            self.log.append(await self.run(scope: scope, name: name, version: version, fixture: fixture))
            // Case-insensitivity
            self.log.append(await self.run(scope: scope.flipcased, name: name.flipcased, version: version.flipcased, fixture: fixture))
        }

        for packageRelease in self.configuration.unknownSourceArchives {
            self.log.append(await TestCase(name: "Fetch source archive for unknown package release \(packageRelease.package.scope).\(packageRelease.package.name)@\(packageRelease.version)") { testCase in
                let url = "\(self.registryURL)/\(packageRelease.package.scope)/\(packageRelease.package.name)/\(packageRelease.version).zip"

                testCase.mark("HTTP request: GET \(url)")
                let response = try await self.get(url: url, mediaType: .zip)

                // 4.4 Server should return 404 if package release archive is not found
                testCase.mark("HTTP response status")
                guard response.status == .notFound else {
                    throw TestError("Expected HTTP status code 404 but got \(response.status.code)")
                }

                // 3.3 Server should communicate errors using "problem details" object
                testCase.mark("Response body")
                if response.body == nil {
                    testCase.warning("Response should include problem details")
                }
            })
        }

        self.printLog()
    }

    private func run(scope: String, name: String, version: String, fixture: Configuration.SourceArchiveFixture) async -> TestCase {
        await TestCase(name: "Download source archive for package release \(scope).\(name)@\(version)") { testCase in
            let url = "\(self.registryURL)/\(scope)/\(name)/\(version).zip"

            testCase.mark("HTTP request: GET \(url)")
            let (responseHead, progress, responseData) = try await withTemporaryDirectory(removeTreeOnDeinit: true) { directoryPath -> (HTTPResponseHead?, FileDownloadDelegate.Progress, Data) in
                let lock = Lock()
                var responseHead: HTTPResponseHead?

                let filename = "\(name)-1.0.0.zip"
                let path = directoryPath.appending(component: filename)
                let delegate = try FileDownloadDelegate(
                    path: path.pathString,
                    reportHead: { head in
                        lock.withLock {
                            responseHead = head
                        }
                    }
                )
                let progress = try await self.get(url: url, mediaType: .zip, delegate: delegate)
                let responseData = Data(try localFileSystem.readFileContents(path).contents)

                return (responseHead, progress, responseData)
            }

            guard let responseHead = responseHead else {
                throw TestError("Did not receive HTTP status and headers")
            }

            // 4.4 Server should return 200 if package release archive is found
            testCase.mark("HTTP response status")
            guard responseHead.status == .ok else {
                throw TestError("Expected HTTP status code 200 but got \(responseHead.status.code)")
            }

            // 3.5 Server must set "Content-Type" and "Content-Version" headers
            self.checkContentTypeHeader(responseHead.headers, expected: .zip, for: &testCase)
            self.checkContentVersionHeader(responseHead.headers, for: &testCase)

            // 4.4 Server may set "Content-Disposition" header
            let expectedFilename = "\(name)-\(version).zip"
            self.checkContentDispositionHeader(responseHead.headers, expectedFilename: expectedFilename,
                                               isRequired: self.configuration.contentDispositionHeaderIsSet, for: &testCase)

            // 4.4 Server must set "Content-Length" header
            self.checkContentLengthHeader(responseHead.headers, responseBody: nil, isRequired: true, for: &testCase)

            testCase.mark("Response stream")
            guard let totalBytes = progress.totalBytes, totalBytes > 0 else {
                throw TestError("Expected bytes should be greater than 0")
            }
            guard totalBytes == progress.receivedBytes else {
                throw TestError("Expected to receive \(totalBytes) bytes but got \(progress.receivedBytes)")
            }
            guard responseData.count == progress.receivedBytes else {
                throw TestError("Received \(progress.receivedBytes) bytes but saved \(responseData.count)")
            }

            // 4.4 Server may set "Digest" header
            if self.configuration.digestHeaderIsSet {
                if let digest = try responseHead.headers.parseDigestHeader(for: &testCase) {
                    testCase.mark("Digest response header")
                    switch digest.algorithm {
                    case .sha256:
                        let checksum = Data(SHA256.hash(data: responseData)).base64EncodedString()
                        if checksum != digest.checksum {
                            testCase.error("Computed \(digest.algorithm) checksum \"\(checksum)\" does not match that in header \"\(digest.checksum)\"")
                        }
                    }
                } else {
                    testCase.error("Missing \"Digest\" header")
                }
            }

            // Verify integrity of downloaded archive
            try await self.integrityCheck(scope: scope, name: name, version: version, responseData: responseData, for: &testCase)

            // 4.4 Server may include "duplicate" relations in the "Link" header
            if fixture.hasDuplicateLinks {
                let links = responseHead.headers.parseLinkHeader()
                self.checkHasRelation("duplicate", in: links, for: &testCase)
            }
        }
    }

    private func getChecksum(scope: String, name: String, version: String, for testCase: inout TestCase) async throws -> String {
        // 4.4.1 Verify integrity using checksum returned by the fetch package release info API (4.2.1)
        let url = "\(self.registryURL)/\(scope)/\(name)/\(version)"
        testCase.mark("Get checksum for integrity check at \(url)")

        let response = try await self.get(url: url, mediaType: .json)

        // 4.2 Server should return status 200
        guard response.status == .ok else {
            throw TestError("Expected HTTP status code 200 but got \(response.status.code)")
        }
        guard let responseBody = response.body else {
            throw TestError("Response body is empty")
        }
        guard let info = try JSONSerialization.jsonObject(with: Data(buffer: responseBody), options: []) as? [String: Any] else {
            throw TestError("Failed to decode response JSON")
        }

        // 4.2. Response body must contain key "resources"
        guard let resources = info["resources"] as? [[String: Any]] else {
            throw TestError("Response JSON does not have key \"resources\" or it is invalid")
        }
        // There should be one resource with name=source-archive and type=application/zip
        guard let resource = resources.first(where: { $0["name"] as? String == "source-archive" && $0["type"] as? String == "application/zip" }) else {
            throw TestError("No source archive resource found")
        }
        guard let checksum = resource["checksum"] as? String else {
            throw TestError("Missing key \"checksum\" in source archive resource JSON object")
        }

        return checksum
    }

    private func integrityCheck(scope: String, name: String, version: String, responseData: Data, for testCase: inout TestCase) async throws {
        // Client is supposed to use checksum returned by the /{scope}/{name}/{version} (4.2) to verify integrity
        let serverChecksum = try await self.getChecksum(scope: scope, name: name, version: version, for: &testCase)

        // 4.4.1 Client must verify integrity
        testCase.mark("Run 'compute-checksum' tool on downloaded archive")
        try withTemporaryDirectory(removeTreeOnDeinit: true) { directoryPath in
            let archivePath = directoryPath.appending(component: "source-archive.zip")
            do {
                try self.fileSystem.writeFileContents(archivePath, bytes: ByteString(Array(responseData)))
            } catch {
                throw TestError("Failed to write archive to \(archivePath): \(error)")
            }

            do {
                let checksum = try Process.checkNonZeroExit(arguments: ["swift", "package", "compute-checksum", archivePath.pathString])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                testCase.mark("Integrity of downloaded archive")
                if checksum != serverChecksum {
                    testCase.error("Computed checksum \"\(checksum)\" does not match that returned by server \"\(serverChecksum)\"")
                }
            } catch {
                throw TestError("Failed to run 'compute-checksum' tool on \(archivePath): \(error)")
            }
        }
    }
}

extension DownloadSourceArchiveTests {
    struct Configuration: Codable {
        /// Source archives to test
        let sourceArchives: [SourceArchiveFixture]

        /// Package release archives that do not exist in the registry. i.e., the registry should return HTTP status code `404` for these.
        let unknownSourceArchives: Set<PackageRelease>

        /// If `true`, the registry sets the "Content-Disposition" response header.
        let contentDispositionHeaderIsSet: Bool

        /// If `true`, the registry sets the "Digest" response header.
        /// The test will verify the downloaded archive has matching digest.
        let digestHeaderIsSet: Bool

        struct SourceArchiveFixture: Codable {
            /// Package release that the source archive is associated with
            let packageRelease: PackageRelease

            /// If `true`, the "Link" response header should include "duplicate" relations.
            let hasDuplicateLinks: Bool
        }
    }
}
