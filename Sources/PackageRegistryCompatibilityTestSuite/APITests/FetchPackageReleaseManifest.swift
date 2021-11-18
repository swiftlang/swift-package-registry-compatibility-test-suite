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

final class FetchPackageReleaseManifestTests: APITest {
    let configuration: Configuration

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        self.configuration = configuration
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() async {
        for fixture in self.configuration.packageReleases {
            let scope = fixture.packageRelease.package.scope
            let name = fixture.packageRelease.package.name
            let version = fixture.packageRelease.version

            // Package.swift
            self.log.append(await self.run(scope: scope, name: name, version: version, fixture: fixture))
            // Case-insensitivity
            self.log.append(await self.run(scope: scope.flipcased, name: name.flipcased, version: version.flipcased, fixture: fixture))

            let url = "\(self.registryURL)/\(scope)/\(name)/\(version)/Package.swift"

            // Version-specific manifests
            if let swiftVersions = fixture.swiftVersions {
                for swiftVersion in swiftVersions {
                    self.log.append(await TestCase(name: "Fetch Package@swift-\(swiftVersion).swift for package release \(scope).\(name)@\(version)") { testCase in
                        let manifestURL = "\(url)?swift-version=\(swiftVersion)"

                        // "alternate" relations are not set for version-specific manifests
                        try await self.fetchAndCheckResponse(url: manifestURL, packageRelease: fixture.packageRelease, checkLinkAlternate: false,
                                                             expectedFilename: "Package@swift-\(swiftVersion).swift", for: &testCase)
                    })
                }
            }

            // These Swift versions do not have version-specific manifest
            if let noSwiftVersions = fixture.noSwiftVersions {
                for swiftVersion in noSwiftVersions {
                    self.log.append(await TestCase(name: "Fetch missing Package@swift-\(swiftVersion).swift for package release \(scope).\(name)@\(version)") { testCase in
                        let manifestURL = "\(url)?swift-version=\(swiftVersion)"

                        // 4.3 Server should return 303 and redirect to unqualified (i.e., `Package.swift`) if version-specific manifest is not found
                        try await self.fetchAndCheckResponse(url: manifestURL, packageRelease: fixture.packageRelease, checkLinkAlternate: false,
                                                             expectedFilename: "Package.swift", for: &testCase)
                    })
                }
            }
        }

        for packageRelease in self.configuration.unknownPackageReleases {
            self.log.append(await TestCase(name: "Fetch Package.swift for unknown package release \(packageRelease.package.scope).\(packageRelease.package.name)@\(packageRelease.version)") { testCase in
                let url = "\(self.registryURL)/\(packageRelease.package.scope)/\(packageRelease.package.name)/\(packageRelease.version)/Package.swift"

                testCase.mark("HTTP request: GET \(url)")
                let response = try await self.get(url: url, mediaType: .swift)

                // 4.3 Server should return 404 if package release is not found
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

    private func run(scope: String, name: String, version: String, fixture: Configuration.PackageReleaseFixture) async -> TestCase {
        await TestCase(name: "Fetch Package.swift for package release \(scope).\(name)@\(version)") { testCase in
            let url = "\(self.registryURL)/\(scope)/\(name)/\(version)/Package.swift"

            let checkLinkAlternate = self.configuration.linkHeaderHasAlternateRelations && fixture.swiftVersions != nil
            try await self.fetchAndCheckResponse(url: url, packageRelease: fixture.packageRelease, checkLinkAlternate: checkLinkAlternate,
                                                 expectedFilename: "Package.swift", for: &testCase)
        }
    }

    private func fetchAndCheckResponse(url: String,
                                       packageRelease: PackageRelease,
                                       checkLinkAlternate: Bool,
                                       expectedFilename: String,
                                       for testCase: inout TestCase) async throws {
        testCase.mark("HTTP request: GET \(url)")
        let response = try await self.get(url: url, mediaType: .swift)

        // 4.3 Server should return 200 if manifest is found
        testCase.mark("HTTP response status")
        guard response.status == .ok else {
            throw TestError("Expected HTTP status code 200 but got \(response.status.code)")
        }

        // 3.5 Server must set "Content-Type" and "Content-Version" headers
        self.checkContentTypeHeader(response.headers, expected: .swift, for: &testCase)
        self.checkContentVersionHeader(response.headers, for: &testCase)

        // Response body should contain the manifest
        testCase.mark("Response body")
        if response.body == nil {
            testCase.error("Response body is empty")
        } else if let responseBody = response.body, responseBody.readableBytes <= 0 {
            testCase.error("Response body is empty")
        }

        // 4.3 Server may set these headers optionally
        self.checkContentDispositionHeader(response.headers, expectedFilename: expectedFilename,
                                           isRequired: self.configuration.contentDispositionHeaderIsSet, for: &testCase)
        self.checkContentLengthHeader(response.headers, responseBody: response.body,
                                      isRequired: self.configuration.contentLengthHeaderIsSet, for: &testCase)

        // 4.3 Server may include "Link" header with "alternate" relations referencing version-specific manifests
        if checkLinkAlternate {
            let links = response.headers.parseLinkHeader()
            self.checkHasRelation("alternate", in: links, for: &testCase)
        }
    }
}

extension FetchPackageReleaseManifestTests {
    struct Configuration: Codable {
        /// Package releases to test
        let packageReleases: [PackageReleaseFixture]

        /// Package releases that do not exist in the registry. i.e., the registry should return HTTP status code `404` for these.
        let unknownPackageReleases: Set<PackageRelease>

        /// If `true`, the registry sets the "Content-Length" response header.
        let contentLengthHeaderIsSet: Bool

        /// If `true`, the registry sets the "Content-Disposition" response header.
        let contentDispositionHeaderIsSet: Bool

        /// If `true`, the registry should include "alternate" relations in the "Link" response header when fetching the
        /// unqualified manifest (i.e., `Package.swift`), if the release has version-specific manifests.
        let linkHeaderHasAlternateRelations: Bool

        struct PackageReleaseFixture: Codable {
            /// Package scope and name and release version
            let packageRelease: PackageRelease

            /// Swift versions with version-specific manifest (i.e., `Package@swift-{swift-version}.swift`).
            /// The server is expected to return HTTP status code `200`.
            let swiftVersions: Set<String>?

            /// Swift versions that do NOT have version-specific manifest (i.e., `Package@swift-{swift-version}.swift`).
            /// The server is expected to return HTTP status code `303`.
            let noSwiftVersions: Set<String>?
        }
    }
}
