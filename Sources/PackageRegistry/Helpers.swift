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

import NIO
import Vapor

func first<Value>(for request: Request, _ body: () -> EventLoopFuture<Value>) -> EventLoopFuture<Value> {
    body().hop(to: request.eventLoop)
}

func parseAcceptHeader(for request: Request) -> (apiVersion: String?, mediaType: String?) {
    parseAcceptHeader(request.headers[.accept].filter { $0.hasPrefix("application/vnd.swift.registry") }.first)
}

func parseAcceptHeader(_ acceptHeader: String?) -> (apiVersion: String?, mediaType: String?) {
    /// 3.5 API versioning - `Accept` header format
    guard let header = acceptHeader,
          let regex = try? NSRegularExpression(pattern: #"application/vnd.swift.registry(\.v([^+]+))?(\+(.+))?"#, options: .caseInsensitive),
          let match = regex.firstMatch(in: header, options: [], range: NSRange(location: 0, length: header.count)) else {
        return (nil, nil)
    }

    let apiVersion = Range(match.range(at: 2), in: header).map { String(header[$0]) }
    let mediaType = Range(match.range(at: 4), in: header).map { String(header[$0]) }
    return (apiVersion, mediaType)
}

extension Optional {
    func unwrap(orError error: Error) throws -> Wrapped {
        switch self {
        case .some(let value):
            return value
        case .none:
            throw error
        }
    }
}
