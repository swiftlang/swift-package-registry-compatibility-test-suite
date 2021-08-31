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

final class CreatePackageReleaseTests: APITest {
    let configuration: Configuration

    private let registryClient: PackageRegistryClient

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        let registryClientConfig = PackageRegistryClient.Configuration(url: registryURL)
        self.registryClient = PackageRegistryClient(httpClientProvider: .shared(httpClient), configuration: registryClientConfig)

        self.configuration = configuration
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() async {
        let randomString = randomAlphaNumericString(length: 6)
        let randomScope = "test-\(randomString)"
        let randomName = "package-\(randomString)"

        for packageRelease in self.configuration.packageReleases {
            let scope = packageRelease.package?.scope ?? randomScope
            let name = packageRelease.package?.name ?? randomName
            var testCase = TestCase(name: "Create package release \(scope).\(name)@\(packageRelease.version)")

            do {
                let response = try await self.createPackageRelease(packageRelease, scope: scope, name: name, for: &testCase)

                testCase.mark("HTTP response status")
                switch response.status {
                // 4.6.3.1 Server must return 201 if publication is done synchronously
                case .created:
                    // 3.5 Server must set "Content-Version" header
                    self.checkContentVersionHeader(response.headers, for: &testCase)

                    // 4.6.3.1 Server should set "Location" header
                    testCase.mark("\"Location\" response header")
                    let locationHeader = response.headers["Location"].first
                    if locationHeader == nil {
                        testCase.warning("\"Location\" header should be set")
                    }
                // 4.6.3.2 Server must return 202 if publication is done asynchronously
                case .accepted:
                    // 3.5 Server must set "Content-Version" header
                    self.checkContentVersionHeader(response.headers, for: &testCase)

                    // 4.6.3.2 Server must set "Location" header
                    testCase.mark("\"Location\" response header")
                    guard let locationHeader = response.headers["Location"].first else {
                        throw TestError("Missing \"Location\" header")
                    }

                    // Poll status until it finishes
                    testCase.mark("Poll \(locationHeader) until publication finishes")
                    try await Task.detached {
                        try await self.poll(url: locationHeader, after: self.getRetryTimestamp(headers: response.headers),
                                            deadline: DispatchTime.now() + .seconds(self.configuration.maxProcessingTimeInSeconds))
                    }.value
                default:
                    throw TestError("Expected HTTP status code 201 or 202 but got \(response.status.code)")
                }
            } catch {
                testCase.error(error)
            }

            self.log.append(testCase)
        }

        for packageRelease in self.configuration.packageReleases {
            let scope = packageRelease.package?.scope ?? randomScope
            let name = packageRelease.package?.name ?? randomName
            var testCase = TestCase(name: "Publish duplicate package release \(scope).\(name)@\(packageRelease.version)")

            do {
                let response = try await self.createPackageRelease(packageRelease, scope: scope, name: name, for: &testCase)

                // 4.6 Server should return 409 if package release already exists
                testCase.mark("HTTP response status")
                guard response.status == .conflict else {
                    throw TestError("Expected HTTP status code 409 but got \(response.status.code)")
                }

                // 3.3 Server should communicate errors using "problem details" object
                testCase.mark("Response body")
                if response.body == nil {
                    testCase.warning("Response should include problem details")
                }
            } catch {
                testCase.error(error)
            }

            self.log.append(testCase)
        }

        self.printLog()
    }

    private func createPackageRelease(_ packageRelease: Configuration.PackageReleaseInfo,
                                      scope: String,
                                      name: String,
                                      for testCase: inout TestCase) async throws -> HTTPClient.Response {
        testCase.mark("Read source archive file")
        let sourceArchive = try readData(at: packageRelease.sourceArchivePath)

        var metadata: Data?
        if let metadataPath = packageRelease.metadataPath {
            testCase.mark("Read metadata file")
            metadata = try readData(at: metadataPath)
        }

        // Auth token
        var headers = HTTPHeaders()
        headers.setAuthorization(token: self.authToken)

        testCase.mark("HTTP request to create package release")
        let deadline = NIODeadline.now() + .seconds(Int64(self.configuration.maxProcessingTimeInSeconds))
        do {
            return try await self.registryClient.createPackageRelease(scope: scope, name: name, version: packageRelease.version, sourceArchive: sourceArchive,
                                                                      metadataJSON: metadata, headers: headers, deadline: deadline)
        } catch {
            throw TestError("Request failed: \(error)")
        }
    }

    private func poll(url: String, after timestamp: DispatchTime, deadline: DispatchTime) async throws {
        while DispatchTime.now() < timestamp {
            sleep(2)
        }

        guard DispatchTime.now() < deadline else {
            throw TestError("Maximum processing time (\(self.configuration.maxProcessingTimeInSeconds)s) reached. Giving up.")
        }

        let response = try await self.get(url: url, mediaType: .json)
        switch response.status.code {
        // 4.6.3.2 Server returns 301 redirect to package release location if successful
        case 200:
            return
        // 4.6.3.2 Server returns 202 when publication is still in-progress
        case 202:
            return try await self.poll(url: url, after: self.getRetryTimestamp(headers: response.headers), deadline: deadline)
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
        @DecodableDefault.MaxPublicationTimeInSeconds var maxProcessingTimeInSeconds: Int

        init(packageReleases: [PackageReleaseInfo], maxProcessingTimeInSeconds: Int) {
            self.packageReleases = packageReleases
            self.maxProcessingTimeInSeconds = maxProcessingTimeInSeconds
        }

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
