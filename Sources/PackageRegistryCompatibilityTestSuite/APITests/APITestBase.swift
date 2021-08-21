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
import NIOHTTP1

class APITestBase {
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

    func get(url: String, mediaType: MediaType) throws -> EventLoopFuture<HTTPClient.Response> {
        var headers = HTTPHeaders()
        headers.setAuthorization(token: self.authToken)
        // Client should set the "Accept" header
        headers.replaceOrAdd(name: "Accept", value: "application/vnd.swift.registry.v\(self.apiVersion)+\(mediaType.rawValue)")

        let request = try HTTPClient.Request(url: url, method: .GET, headers: headers)
        return self.httpClient.execute(request: request)
    }

    func getAndWait(url: String, mediaType: MediaType) throws -> HTTPClient.Response {
        do {
            return try self.get(url: url, mediaType: mediaType).wait()
        } catch {
            throw TestError("Request failed: \(error)")
        }
    }

    func checkContentVersionHeader(_ headers: HTTPHeaders) {
        self.log.mark(testPoint: "\"Content-Version\" response header")
        guard headers["Content-Version"].first == self.apiVersion else {
            self.log.error("\"Content-Version\" header is required and must be \"\(self.apiVersion)\"")
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
