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

import _NIOConcurrency
import AsyncHTTPClient
import NIOHTTP1

class APITest: @unchecked Sendable {
    let registryURL: String
    let authToken: AuthenticationToken?
    let apiVersion: String
    let httpClient: HTTPClient

    var log = TestLog()

    init(registryURL: String, authToken: AuthenticationToken?, apiVersion: String, httpClient: HTTPClient) {
        self.registryURL = registryURL
        self.authToken = authToken
        self.apiVersion = apiVersion
        self.httpClient = httpClient
    }

    func get(url: String, mediaType: MediaType) async throws -> HTTPClient.Response {
        do {
            var headers = HTTPHeaders()
            headers.setAuthorization(token: self.authToken)
            // Client should set the "Accept" header
            headers.replaceOrAdd(name: "Accept", value: "application/vnd.swift.registry.v\(self.apiVersion)+\(mediaType.rawValue)")

            let request = try HTTPClient.Request(url: url, method: .GET, headers: headers)
            return try await self.httpClient.execute(request: request).get()
        } catch {
            throw TestError("Request failed: \(error)")
        }
    }

    func checkContentVersionHeader(_ headers: HTTPHeaders, for testCase: inout TestCase) {
        testCase.mark("\"Content-Version\" response header")
        guard headers["Content-Version"].first == self.apiVersion else {
            testCase.error("\"Content-Version\" header is required and must be \"\(self.apiVersion)\"")
            return
        }
    }

    func checkContentTypeHeader(_ headers: HTTPHeaders, expected: MediaType, for testCase: inout TestCase) {
        testCase.mark("\"Content-Type\" response header")
        guard headers["Content-Type"].first(where: { $0.contains(expected.contentType) }) != nil else {
            testCase.error("\"Content-Type\" header is required and must contain \"\(expected.contentType)\"")
            return
        }
    }

    func checkHasRelation(_ relation: String, in links: [Link], for testCase: inout TestCase) {
        testCase.mark("\"\(relation)\" relation in \"Link\" response header")
        guard links.first(where: { $0.relation == relation }) != nil else {
            testCase.error("\"Link\" header does not include \"\(relation)\" relation")
            return
        }
    }

    func printLog() {
        print("\(self.log)")
    }
}

enum MediaType: String {
    case json
    case zip
    case swift

    var contentType: String {
        switch self {
        case .json:
            return "application/json"
        case .zip:
            return "application/zip"
        case .swift:
            return "text/x-swift"
        }
    }
}

struct Link {
    let relation: String
    let url: String
}

extension AuthenticationToken {
    var authorizationHeader: String? {
        switch self.scheme {
        case .basic:
            guard let data = self.token.data(using: .utf8) else {
                return nil
            }
            return "Basic \(data.base64EncodedString())"
        case .bearer:
            return "Bearer \(self.token)"
        case .token:
            return "token \(self.token)"
        }
    }
}

extension HTTPHeaders {
    mutating func setAuthorization(token: AuthenticationToken?) {
        if let authorization = token?.authorizationHeader {
            self.replaceOrAdd(name: "Authorization", value: authorization)
        }
    }
}

extension HTTPClient.Response {
    func parseLinkHeader() -> [Link] {
        self.headers["Link"].map {
            $0.split(separator: ",").compactMap {
                let parts = $0.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ";")
                guard parts.count >= 2 else {
                    return nil
                }

                let url = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(1).dropLast(1) // Remove < > from beginning and end

                guard let rel = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter({ $0.hasPrefix("rel=") }).first else {
                    return nil
                }
                let relation = String(rel.dropFirst("rel=".count).dropFirst(1).dropLast(1)) // Remove " from beginning and end

                return Link(relation: relation, url: String(url))
            }
        }.flatMap { $0 }
    }
}
