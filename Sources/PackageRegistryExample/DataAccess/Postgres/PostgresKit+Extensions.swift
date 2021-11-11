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

import AsyncKit
import NIOCore
import PostgresKit
import PostgresNIO
import SQLKit

extension EventLoopGroupConnectionPool where Source == PostgresConnectionSource {
    func withConnectionThrowing<Result>(_ closure: @escaping (Source.Connection) async throws -> Result) async throws -> Result {
        let connection = try await self.requestConnection().get()
        defer { self.releaseConnection(connection) }
        return try await closure(connection)
    }
}

extension SQLQueryBuilder {
    func run() async throws {
        let future: EventLoopFuture<Void> = self.run()
        try await future.get()
    }
}

extension SQLQueryFetcher {
    func first<D>(decoding: D.Type) async throws -> D? where D: Decodable {
        let future: EventLoopFuture<D?> = self.first(decoding: D.self)
        return try await future.get()
    }

    func all<D>(decoding: D.Type) async throws -> [D] where D: Decodable {
        let future: EventLoopFuture<[D]> = self.all().flatMapThrowing {
            try $0.map { try $0.decode(model: D.self) }
        }
        return try await future.get()
    }
}

extension PostgresDatabase {
    @discardableResult
    func query(_ string: String, _ binds: [PostgresNIO.PostgresData] = []) async throws -> PostgresNIO.PostgresQueryResult {
        let future: EventLoopFuture<PostgresNIO.PostgresQueryResult> = self.query(string, binds)
        return try await future.get()
    }
}
