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

final class FetchPackageReleaseInfoTests: APITest {
    let configuration: Configuration

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        self.configuration = configuration
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() async {
        // 4.2 Client may append `.json` to the requested URI
        await self.run(appendDotJSON: false)
        await self.run(appendDotJSON: true)
        self.printLog()
    }

    private func run(appendDotJSON: Bool) async {
        for expectation in self.configuration.packageReleases {
            let scope = expectation.packageRelease.package.scope
            let name = expectation.packageRelease.package.name
            let version = expectation.packageRelease.version

            self.log.append(await self.run(scope: scope, name: name, version: version, appendDotJSON: appendDotJSON, expectation: expectation))
            // Case-insensitivity
            self.log.append(await self.run(scope: scope.flipcased, name: name.flipcased, version: version.flipcased,
                                           appendDotJSON: appendDotJSON, expectation: expectation))
        }

        for packageRelease in self.configuration.unknownPackageReleases {
            self.log.append(await TestCase(name: "Fetch metadata for unknown package release \(packageRelease.package.scope).\(packageRelease.package.name)@\(packageRelease.version) (with\(appendDotJSON ? "" : "out") .json in the URI)") { testCase in
                let url = "\(self.registryURL)/\(packageRelease.package.scope)/\(packageRelease.package.name)/\(packageRelease.version)\(appendDotJSON ? ".json" : "")"

                testCase.mark("HTTP request: GET \(url)")
                let response = try await self.get(url: url, mediaType: .json)

                // 4.2 Server should return 404 if package release is not found
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

    private func run(scope: String, name: String, version: String, appendDotJSON: Bool, expectation: Configuration.PackageReleaseExpectation) async -> TestCase {
        await TestCase(name: "Fetch info for package release \(scope).\(name)@\(version) (with\(appendDotJSON ? "" : "out") .json in the URI)") { testCase in
            let url = "\(self.registryURL)/\(scope)/\(name)/\(version)\(appendDotJSON ? ".json" : "")"

            testCase.mark("HTTP request: GET \(url)")
            let response = try await self.get(url: url, mediaType: .json)

            // 4.2 Server should return 200 if package release is found
            testCase.mark("HTTP response status")
            guard response.status == .ok else {
                throw TestError("Expected HTTP status code 200 but got \(response.status.code)")
            }

            // 3.5 Server must set "Content-Type" and "Content-Version" headers
            self.checkContentTypeHeader(response.headers, expected: .json, for: &testCase)
            self.checkContentVersionHeader(response.headers, for: &testCase)

            testCase.mark("Response body")
            guard let responseBody = response.body else {
                throw TestError("Response body is empty")
            }

            testCase.mark("Parse response body")
            guard let info = try JSONSerialization.jsonObject(with: Data(buffer: responseBody), options: []) as? [String: Any] else {
                throw TestError("Failed to decode response JSON")
            }

            // 4.2. Response body must contain key "id"
            testCase.mark("Key \"id\"")
            if let id = info["id"] as? String {
                if id.lowercased() != "\(scope).\(name)".lowercased() {
                    testCase.error("Value of \"id\" should be \"\(scope).\(name)\" but got \"\(id)\"")
                }
            } else {
                testCase.error("Response JSON does not have key \"id\" or it is invalid")
            }

            // 4.2. Response body must contain key "version"
            testCase.mark("Key \"version\"")
            if let responseVersion = info["version"] as? String {
                if responseVersion.lowercased() != version.lowercased() {
                    testCase.error("Value of \"version\" should be \"\(version)\" but got \"\(responseVersion)\"")
                }
            } else {
                testCase.error("Response JSON does not have key \"version\" or it is invalid")
            }

            self.checkResources(response: info, expectation: expectation, for: &testCase)
            self.checkMetadata(response: info, expectation: expectation, for: &testCase)

            // 4.2 Server may optionally include "latest-version", "successor-version", "predecessor-version", etc. relations in the "Link" header
            if let linkRelations = expectation.linkRelations {
                let links = response.parseLinkHeader()
                linkRelations.forEach { relation in
                    self.checkHasRelation(relation, in: links, for: &testCase)
                }
            }
        }
    }

    private func checkResources(response: [String: Any], expectation: Configuration.PackageReleaseExpectation, for testCase: inout TestCase) {
        // 4.2. Response body must contain key "resources"
        testCase.mark("Key \"resources\"")
        if let resources = response["resources"] as? [[String: Any]] {
            if resources.count != expectation.resources.count {
                testCase.error("Expected \(expectation.resources.count) resources but got \(resources.count)")
            } else {
                expectation.resources.forEach { expectedResource in
                    // 4.2.1 There can only be one resource item for each (name, type)
                    testCase.mark("Resource name=\(expectedResource.name), type=\(expectedResource.type)")
                    let filtered = resources.filter { $0["name"] as? String == expectedResource.name && $0["type"] as? String == expectedResource.type }
                    if filtered.isEmpty {
                        testCase.error("\"resources\" does not have item with name=\(expectedResource.name), type=\(expectedResource.type)")
                    } else if filtered.count != 1 {
                        testCase.error("\"resources\" has more than one item with name=\(expectedResource.name), type=\(expectedResource.type)")
                    } else {
                        let resource = filtered.first! // !-safe since `filtered` must have exactly one item
                        if let checksum = resource["checksum"] as? String {
                            if checksum != expectedResource.checksum {
                                testCase.error("Expected \"checksum\" to be \"\(expectedResource.checksum)\" but got \"\(checksum)\"")
                            }
                        } else {
                            testCase.error("\"checksum\" is either missing or invalid")
                        }
                    }
                }
            }
        } else {
            testCase.error("Response JSON does not have key \"resources\" or it is invalid")
        }
    }

    private func checkMetadata(response: [String: Any], expectation: Configuration.PackageReleaseExpectation, for testCase: inout TestCase) {
        // 4.2. Response body must contain key "metadata"
        testCase.mark("Key \"metadata\"")
        if let metadata = response["metadata"] as? [String: Any] {
            // Check metadata key-values. A registry may define its own metadata format.
            if let keyValues = expectation.keyValues {
                keyValues.forEach { key, expectedValue in
                    testCase.mark("Metadata key \"\(key)\"")
                    let value = metadata[key] as? String
                    if expectedValue != value {
                        testCase.error("Value of \"\(key)\" should be \"\(expectedValue)\" but got \"\(String(describing: value))\"")
                    }
                }
            }
        } else {
            testCase.error("Response JSON does not have key \"metadata\" or it is invalid")
        }
    }
}

extension FetchPackageReleaseInfoTests {
    struct Configuration: Codable {
        /// Package releases to test
        let packageReleases: [PackageReleaseExpectation]

        /// Package releases that do not exist in the registry. i.e., the registry should return HTTP status code `404` for these.
        let unknownPackageReleases: Set<PackageRelease>

        struct PackageReleaseExpectation: Codable {
            /// Package scope and name and release version
            let packageRelease: PackageRelease

            /// Expected resources of the package release (e.g., source archive)
            let resources: [PackageReleaseResource]

            /// Key-value pairs in this dictionary will be verified using `metadata` in the response
            let keyValues: [String: String]?

            /// The "Link" response header should include these relations.
            let linkRelations: Set<String>?
        }
    }
}
