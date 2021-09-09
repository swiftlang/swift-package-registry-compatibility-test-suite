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

final class LookupPackageIdentifiersTests: APITest {
    let configuration: Configuration

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, configuration: Configuration, httpClient: HTTPClient) {
        self.configuration = configuration
        super.init(registryURL: registryURL, authToken: authToken, apiVersion: apiVersion, httpClient: httpClient)
    }

    func run() async {
        for expectation in self.configuration.urls {
            self.log.append(await self.run(lookupURL: expectation.url, expectation: expectation))
            // Case-insensitivity
            self.log.append(await self.run(lookupURL: expectation.url.flipcased, expectation: expectation))
        }

        for url in self.configuration.unknownURLs {
            self.log.append(await TestCase(name: "Lookup package identifiers for unknown URL \(url)") { testCase in
                let url = "\(self.registryURL)/identifiers?url=\(url)"

                testCase.mark("HTTP request: GET \(url)")
                let response = try await self.get(url: url, mediaType: .json)

                // 4.4 Server should return 404 if URL is not recognized
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

    private func run(lookupURL: String, expectation: Configuration.URLExpectation) async -> TestCase {
        await TestCase(name: "Lookup package identifiers for URL \(lookupURL)") { testCase in
            let url = "\(self.registryURL)/identifiers?url=\(lookupURL)"

            testCase.mark("HTTP request: GET \(url)")
            let response = try await self.get(url: url, mediaType: .json)

            // 4.5 Server should return 200 if package identifiers are found
            testCase.mark("HTTP response status")
            guard response.status == .ok else {
                throw TestError("Expected HTTP status code 200 but got \(response.status.code)")
            }

            // 3.5 Server must set "Content-Type" and "Content-Version" headers
            self.checkContentTypeHeader(response.headers, expected: .json, for: &testCase)
            self.checkContentVersionHeader(response.headers, for: &testCase)

            testCase.mark("Parse response body")
            guard let responseBody = response.body else {
                throw TestError("Response body is empty")
            }
            guard let dictionary = try JSONSerialization.jsonObject(with: Data(buffer: responseBody), options: []) as? [String: Any] else {
                throw TestError("Failed to decode response JSON")
            }
            guard let packageIdentifiers = dictionary["identifiers"] as? [String] else {
                throw TestError("Response JSON does not have key \"identifiers\" or it is invalid")
            }

            testCase.mark("Package identifiers")
            if Set(packageIdentifiers) != expectation.packageIdentifiers {
                testCase.error("Expected package identifiers to be \(expectation.packageIdentifiers) but got \(packageIdentifiers)")
            }
        }
    }
}

extension LookupPackageIdentifiersTests {
    struct Configuration: Codable {
        /// URLs to test
        let urls: [URLExpectation]

        /// URLs that are not recognized by the registry. i.e., the registry should return HTTP status code `404` for these.
        let unknownURLs: Set<String>

        struct URLExpectation: Codable {
            /// Repository URL to query package identifiers for
            let url: String

            /// Expected package identifiers.
            let packageIdentifiers: Set<String>
        }
    }
}
