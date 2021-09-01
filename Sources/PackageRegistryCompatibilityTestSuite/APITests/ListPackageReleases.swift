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
import NIO

final class ListPackageReleasesTests: APITest {
    let configuration: Configuration

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        self.configuration = configuration
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() async {
        // 4.1 Client may append `.json` to the requested URI
        await self.run(appendDotJSON: false)
        await self.run(appendDotJSON: true)
        self.printLog()
    }

    private func run(appendDotJSON: Bool) async {
        func _run(scope: String, name: String, expectation: Configuration.PackageExpectation) async -> TestCase {
            await TestCase(name: "List releases for package \(scope).\(name) (with\(appendDotJSON ? "" : "out") .json in the URI)") { testCase in
                let url = "\(self.registryURL)/\(scope)/\(name)\(appendDotJSON ? ".json" : "")"

                testCase.mark("HTTP request: GET \(url)")
                let response = try await self.get(url: url, mediaType: .json)

                // 4.1 Server should return 200 if package is found
                testCase.mark("HTTP response status")
                guard response.status == .ok else {
                    throw TestError("Expected HTTP status code 200 but got \(response.status.code)")
                }

                // 3.5 Server must set "Content-Type" and "Content-Version" headers
                self.checkContentTypeHeader(response.headers, expected: .json, for: &testCase)
                self.checkContentVersionHeader(response.headers, for: &testCase)

                if self.configuration.paginationSupported {
                    try await self.checkPaginated(response: response, expectation: expectation, for: &testCase)
                } else {
                    try self.checkNonPaginated(response: response, expectation: expectation, for: &testCase)
                }
            }
        }

        for expectation in self.configuration.packages {
            let scope = expectation.package.scope
            let name = expectation.package.name

            self.log.append(await _run(scope: scope, name: name, expectation: expectation))
            // Case-insensitivity
            self.log.append(await _run(scope: scope.flipcased, name: name.flipcased, expectation: expectation))
        }

        for package in self.configuration.unknownPackages {
            self.log.append(await TestCase(name: "List releases for unknown package \(package.scope).\(package.name) (with\(appendDotJSON ? "" : "out") .json in the URI)") { testCase in
                let url = "\(self.registryURL)/\(package.scope)/\(package.name)\(appendDotJSON ? ".json" : "")"

                testCase.mark("HTTP request: GET \(url)")
                let response = try await self.get(url: url, mediaType: .json)

                // 4.1 Server should return 404 if package is not found
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
    }

    private func parseResponseBody(_ response: HTTPClient.Response, for testCase: inout TestCase) throws -> [String: Any] {
        testCase.mark("Parse response body")
        // 4.1 Response body must contain JSON object with top-level "releases" key,
        // whose keys are versions and values are objects containing optional "url" and "problem" keys.
        guard let responseBody = response.body else {
            throw TestError("Response body is empty")
        }
        guard let dictionary = try JSONSerialization.jsonObject(with: Data(buffer: responseBody), options: []) as? [String: Any] else {
            throw TestError("Failed to decode response JSON")
        }
        guard let releases = dictionary["releases"] as? [String: Any] else {
            throw TestError("Response JSON does not have key \"releases\" or it is invalid")
        }
        return releases
    }

    private func checkPaginated(response: HTTPClient.Response, expectation: Configuration.PackageExpectation, for testCase: inout TestCase) async throws {
        self.checkLinkRelations(response: response, expectation: expectation, for: &testCase)

        // Paginate using "Link" header to collect all releases
        func collect(_ response: HTTPClient.Response, accumulated: [String: Any]) async throws -> [String: Any] {
            let releases = try self.parseResponseBody(response, for: &testCase)
            let newAccumulated = accumulated.merging(releases, uniquingKeysWith: { _, last in last })

            let links = response.parseLinkHeader()

            // We are on the last page
            guard let nextPage = links.first(where: { $0.relation == "next" }) else {
                return newAccumulated
            }

            // Fetch next page
            let nextResponse = try await self.get(url: nextPage.url, mediaType: .json)
            guard nextResponse.status == .ok else {
                throw TestError("Failed to fetch \(nextPage.url), status: \(nextResponse.status)")
            }
            return try await collect(nextResponse, accumulated: newAccumulated)
        }

        let releases: [String: Any]
        do {
            testCase.mark("Paginate to collect all package releases")
            releases = try await collect(response, accumulated: [:])
        } catch {
            throw TestError("Release pagination failed: \(error)")
        }
        try self.checkReleases(releases, expectation: expectation, for: &testCase)
    }

    private func checkNonPaginated(response: HTTPClient.Response, expectation: Configuration.PackageExpectation, for testCase: inout TestCase) throws {
        self.checkLinkRelations(response: response, expectation: expectation, for: &testCase)

        // Response includes all releases
        let releases = try self.parseResponseBody(response, for: &testCase)
        try self.checkReleases(releases, expectation: expectation, for: &testCase)
    }

    private func checkReleases(_ releases: [String: Any], expectation: Configuration.PackageExpectation, for testCase: inout TestCase) throws {
        testCase.mark("Number of releases")
        if expectation.numberOfReleases != releases.count {
            testCase.error("The number of releases should be \(expectation.numberOfReleases) but got \(releases.count)")
        }

        testCase.mark("Release versions")
        if !expectation.versions.isSubset(of: Set(releases.keys)) {
            testCase.error("\(expectation.versions) is not a subset of \(releases.keys)")
        }

        let unavailableVersions: Set<String> = expectation.unavailableVersions ?? []
        try releases.forEach { version, value in
            testCase.mark("Parse details object for release \(version)")
            guard let details = value as? [String: Any] else {
                throw TestError("Response JSON is invalid")
            }

            // Check for "url" key in the release details
            testCase.mark("\"url\" for release \(version)")
            if self.configuration.packageURLProvided, details["url"] == nil {
                testCase.error("\(version) does not have \"url\"")
            }

            // Unavailable release should have "problem" key but it's not a requirement
            if unavailableVersions.contains(version), details["problem"] == nil {
                testCase.mark("Problem details for unavailable release \(version)")
                if self.configuration.problemProvided {
                    testCase.error("\(version) does not have \"problem\"")
                } else {
                    testCase.warning("\(version) should include \"problem\" to indicate unavailability")
                }
            }
        }
    }

    private func checkLinkRelations(response: HTTPClient.Response, expectation: Configuration.PackageExpectation, for testCase: inout TestCase) {
        // 4.1 Server may optionally include "latest-version", "canonical", "alternate", etc. relations in the "Link" header
        if let linkRelations = expectation.linkRelations {
            let links = response.parseLinkHeader()
            linkRelations.forEach { relation in
                self.checkHasRelation(relation, in: links, for: &testCase)
            }
        }
    }
}

extension ListPackageReleasesTests {
    struct Configuration: Codable {
        /// Packages to test
        let packages: [PackageExpectation]

        /// Packages that do not exist in the registry. i.e., the registry should return HTTP status code `404` for these.
        let unknownPackages: Set<PackageIdentity>

        /// If `true`, each release object in the response must include the `url` key.
        let packageURLProvided: Bool

        /// If `true`, an unavailable release in the response must include problem details.
        let problemProvided: Bool

        /// If `true`, the `Link` HTTP response header will include `next`, `prev`, etc. and
        /// a response may only contain a subset of a package's releases.
        let paginationSupported: Bool

        struct PackageExpectation: Codable {
            /// Package scope and name
            let package: PackageIdentity

            /// The total number of releases for the package.
            /// If pagination is supported, the test will fetch all pages to obtain the total.
            let numberOfReleases: Int

            /// Versions that must be present. This can be a subset of all versions.
            /// If pagination is supported, the test will fetch all pages and check against all results.
            let versions: Set<String>

            /// Versions that are unavailable.
            /// If `problemProvided` is `true`, these versions must include problem details (i.e., "problem" key).
            /// If pagination is supported, the test will fetch all pages and check against all results.
            let unavailableVersions: Set<String>?

            /// The "Link" response header should include these relations.
            let linkRelations: Set<String>?
        }
    }
}
