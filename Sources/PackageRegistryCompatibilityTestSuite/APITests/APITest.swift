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

import AsyncHTTPClient
import NIO
import NIOCore
import NIOFoundationCompat
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
            let request = try HTTPClient.Request(url: url, method: .GET, headers: self.defaultRequestHeaders(mediaType: mediaType))
            return try await self.httpClient.execute(request: request).get()
        } catch {
            throw TestError("Request failed: \(error)")
        }
    }

    func get<Delegate: HTTPClientResponseDelegate>(url: String, mediaType: MediaType, delegate: Delegate) async throws -> Delegate.Response {
        do {
            let request = try HTTPClient.Request(url: url, method: .GET, headers: self.defaultRequestHeaders(mediaType: mediaType))
            return try await self.httpClient.execute(request: request, delegate: delegate).futureResult.get()
        } catch {
            throw TestError("Request failed: \(error)")
        }
    }

    private func defaultRequestHeaders(mediaType: MediaType) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.setAuthorization(token: self.authToken)
        // Client should set the "Accept" header
        headers.replaceOrAdd(name: "Accept", value: "application/vnd.swift.registry.v\(self.apiVersion)+\(mediaType.rawValue)")
        return headers
    }

    func checkContentVersionHeader(_ headers: HTTPHeaders, for testCase: inout TestCase) {
        testCase.mark("\"Content-Version\" response header")
        guard headers["Content-Version"].first == self.apiVersion else {
            testCase.error("\"Content-Version\" header is required and must be \"\(self.apiVersion)\"")
            return
        }
    }

    func checkContentDispositionHeader(_ headers: HTTPHeaders, expectedFilename: String, isRequired: Bool, for testCase: inout TestCase) {
        testCase.mark("\"Content-Disposition\" response header")
        let contentDispositionHeader = headers["Content-Disposition"].first
        if contentDispositionHeader == nil {
            if isRequired {
                testCase.error("Missing \"Content-Disposition\" header")
            } else {
                testCase.warning("\"Content-Disposition\" header should be set")
            }
        } else {
            let expected = "attachment; filename=\"\(expectedFilename)\""
            if let contentDispositionHeader = contentDispositionHeader, contentDispositionHeader.lowercased() != expected.lowercased() {
                testCase.error("Expected \"\(expected)\" for \"Content-Disposition\" header but got \"\(contentDispositionHeader)\"")
            }
        }
    }

    func checkContentLengthHeader(_ headers: HTTPHeaders, responseBody: ByteBuffer?, isRequired: Bool, for testCase: inout TestCase) {
        testCase.mark("\"Content-Length\" response header")
        let contentLengthHeader = headers["Content-Length"].first
        if contentLengthHeader == nil {
            if isRequired {
                testCase.error("Missing \"Content-Length\" header")
            } else {
                testCase.warning("\"Content-Length\" header should be set")
            }
        }

        if let contentLengthHeader = contentLengthHeader, let responseBody = responseBody, Int(contentLengthHeader) != responseBody.readableBytes {
            testCase.error("Content-Length header (\(contentLengthHeader)) does not match response body length (\(responseBody.readableBytes))")
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

struct Digest: Equatable, CustomStringConvertible {
    let algorithm: HashAlgorithm
    let checksum: String

    init(algorithm: HashAlgorithm, checksum: String) {
        self.algorithm = algorithm
        self.checksum = checksum
    }

    var description: String {
        "\(self.algorithm)=\(self.checksum)"
    }
}

enum HashAlgorithm: String, Equatable, CustomStringConvertible {
    case sha256 = "sha-256"

    var description: String {
        self.rawValue
    }
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

extension HTTPHeaders {
    func parseLinkHeader() -> [Link] {
        self["Link"].map {
            $0.split(separator: ",").compactMap {
                let parts = $0.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ";")
                guard parts.count >= 2 else {
                    return nil
                }

                let url = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(1).dropLast(1) // Remove < > from beginning and end

                guard let rel = parts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ $0.hasPrefix("rel=") }).first else {
                    return nil
                }
                let relation = String(rel.dropFirst("rel=".count).dropFirst(1).dropLast(1)) // Remove " from beginning and end

                return Link(relation: relation, url: String(url))
            }
        }.flatMap { $0 }
    }

    func parseDigestHeader(for testCase: inout TestCase) throws -> Digest? {
        testCase.mark("Parse \"Digest\" response header")
        guard let digestHeader = self["Digest"].first else {
            return nil
        }

        let parts = digestHeader.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
            throw TestError("\"Digest\" header is invalid")
        }

        let algorithmString = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let algorithm = HashAlgorithm(rawValue: algorithmString) else {
            throw TestError("Unsupported algorithm \"\(algorithmString)\" in the \"Digest\" header")
        }
        let checksum = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return Digest(algorithm: algorithm, checksum: checksum)
    }
}
