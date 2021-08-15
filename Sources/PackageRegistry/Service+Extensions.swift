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

import PackageRegistryModels
import Vapor

extension Response {
    static func json(_ body: Encodable) -> Response {
        Response.json(status: .ok, body: body)
    }

    static func json(status: HTTPResponseStatus, body: Encodable, headers: HTTPHeaders = HTTPHeaders()) -> Response {
        switch body.jsonString {
        case .success(let json):
            var headers = headers
            headers.contentType = .json
            return Response(status: status, headers: headers, body: Body(string: json))
        case .failure:
            return Response(status: .internalServerError)
        }
    }

    /// 3.3 `ProblemDetails` JSON object and Content-Type
    static func jsonError(status: HTTPResponseStatus, detail: String, headers: HTTPHeaders = HTTPHeaders()) -> Response {
        let body = ProblemDetails(status: status.code, title: nil, detail: detail)
        switch body.jsonString {
        case .success(let json):
            var headers = headers
            headers.replaceOrAdd(name: .contentType, value: "application/problem+json")
            return Response(status: status, headers: headers, body: Body(string: json))
        case .failure:
            return Response(status: .internalServerError)
        }
    }
}

extension Encodable {
    var jsonString: Swift.Result<String, Error> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(self)
            guard let json = String(data: data, encoding: .utf8) else {
                return .failure(JSONCodecError.unknownEncodingError)
            }
            return .success(json)
        } catch {
            return .failure(error)
        }
    }
}

enum JSONCodecError: Error {
    case unknownEncodingError
    case unknownDecodingError
}

struct APIVersionStorageKey: StorageKey {
    typealias Value = PackageRegistry.APIVersion
}
