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

import Dispatch
import Foundation

import AsyncHTTPClient
import NIO
import NIOHTTP1
import PackageRegistryClient

final class CreatePackageReleaseTests: APITestBase {
    let configuration: Configuration

    private let registryClient: PackageRegistryClient

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        self.configuration = configuration
        self.registryClient = PackageRegistryClient(url: registryURL, client: httpClient)
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() {
        let randomString = randomAlphaNumericString(length: 6)
        let randomScope = "test-\(randomString)"
        let randomName = "package-\(randomString)"

        self.configuration.packageReleases.forEach {
            let scope = $0.package?.scope ?? randomScope
            let name = $0.package?.name ?? randomName
            self.log.start(testCase: "Create package release \(scope).\(name)@\($0.version)")

            do {
                let response = try self.createPackageRelease($0, scope: scope, name: name)

                self.log.mark(testPoint: "HTTP response status")
                switch response.status {
                // 4.6.3.1 Server must return 201 if publication is done synchronously
                case .created:
                    // 3.5 Server must set "Content-Version" header
                    self.checkContentVersionHeader(response.headers)

                    // 4.6.3.1 Server should set "Location" header
                    self.log.mark(testPoint: "\"Location\" response header")
                    let locationHeader = response.headers["Location"].first
                    if locationHeader == nil {
                        self.log.warning("\"Location\" header should be set")
                    }
                // 4.6.3.2 Server must return 202 if publication is done asynchronously
                case .accepted:
                    // 3.5 Server must set "Content-Version" header
                    self.checkContentVersionHeader(response.headers)

                    // 4.6.3.2 Server must set "Location" header
                    self.log.mark(testPoint: "\"Location\" response header")
                    guard let locationHeader = response.headers["Location"].first else {
                        throw TestError("Missing \"Location\" header")
                    }

                    // Poll status until it finishes
                    self.log.mark(testPoint: "Poll \(locationHeader) until publication finishes")
                    try self.poll(url: locationHeader, after: self.getRetryTimestamp(headers: response.headers),
                                  deadline: DispatchTime.now() + .seconds(self.configuration.maxProcessingTimeInSeconds))
                default:
                    throw TestError("Expected HTTP status code 201 or 202 but got \(response.status.code)")
                }
            } catch {
                self.log.error(error)
            }

            self.log.endCurrentTestCase()
        }

        self.configuration.packageReleases.forEach {
            let scope = $0.package?.scope ?? randomScope
            let name = $0.package?.name ?? randomName
            self.log.start(testCase: "Publish duplicate package release \(scope).\(name)@\($0.version)")

            do {
                let response = try self.createPackageRelease($0, scope: scope, name: name)

                // 4.6 Server should return 409 if package release already exists
                self.log.mark(testPoint: "HTTP response status")
                guard response.status == .conflict else {
                    throw TestError("Expected HTTP status code 409 but got \(response.status.code)")
                }

                // 3.3 Server should communicate errors using "problem details" object
                self.log.mark(testPoint: "Response body")
                if response.body == nil {
                    self.log.warning("Response should include problem details")
                }
            } catch {
                self.log.error(error)
            }

            self.log.endCurrentTestCase()
        }

        self.printLog()
    }

    private func readData(at path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TestError("Failed to read \(path): \(error)")
        }
    }

    private func createPackageRelease(_ packageRelease: Configuration.PackageReleaseInfo, scope: String, name: String) throws -> HTTPClient.Response {
        self.log.mark(testPoint: "Read source archive file")
        let sourceArchive = try readData(at: packageRelease.sourceArchivePath)

        var metadata: Data?
        if let metadataPath = packageRelease.metadataPath {
            self.log.mark(testPoint: "Read metadata file")
            metadata = try self.readData(at: metadataPath)
        }

        // Auth token
        var headers = HTTPHeaders()
        headers.setAuthorization(token: self.authToken)

        self.log.mark(testPoint: "HTTP request to create package release")
        let deadline = NIODeadline.now() + .seconds(Int64(self.configuration.maxProcessingTimeInSeconds))
        do {
            return try self.registryClient.createPackageRelease(scope: scope, name: name, version: packageRelease.version, sourceArchive: sourceArchive,
                                                                metadataJSON: metadata, headers: headers, deadline: deadline).wait()
        } catch {
            throw TestError("Request failed: \(error)")
        }
    }

    private func poll(url: String, after timestamp: DispatchTime, deadline: DispatchTime) throws {
        while DispatchTime.now() < timestamp {
            sleep(2)
        }

        guard DispatchTime.now() < deadline else {
            throw TestError("Maximum processing time (\(self.configuration.maxProcessingTimeInSeconds)s) reached. Giving up.")
        }

        let response = try self.getAndWait(url: url, mediaType: .json)
        switch response.status.code {
        // 4.6.3.2 Server returns 301 redirect to package release location if successful
        case 200:
            return
        // 4.6.3.2 Server returns 202 when publication is still in-progress
        case 202:
            return try self.poll(url: url, after: self.getRetryTimestamp(headers: response.headers), deadline: deadline)
        // 4.6.3.2 Server returns client error 4xx when publication failed
        case 400 ..< 500:
            throw TestError("Publication failed with HTTP status code \(response.status.code)")
        default:
            throw TestError("Unexpected HTTP status code \(response.status.code)")
        }
    }

    private func getRetryTimestamp(headers: HTTPHeaders) -> DispatchTime {
        var afterSeconds = 3
        if let retryAfterHeader = headers["Retry-After"].first, let retryAfter = Int(retryAfterHeader) {
            afterSeconds = retryAfter
        }
        return DispatchTime.now() + .seconds(afterSeconds)
    }
}

extension CreatePackageReleaseTests {
    struct Configuration: Codable {
        /// Package releases to create
        var packageReleases: [PackageReleaseInfo]

        /// Maximum processing time in seconds before the test considers publication has failed
        let maxProcessingTimeInSeconds: Int

        struct PackageReleaseInfo: Codable {
            /// Package scope and name. These will be used for publication if specified,
            /// otherwise the test will generate random values.
            let package: PackageIdentity?

            /// Package release version
            let version: String

            /// Absolute path of the source archive
            let sourceArchivePath: String

            /// Absolute path of the metadata JSON file
            let metadataPath: String?
        }
    }
}
