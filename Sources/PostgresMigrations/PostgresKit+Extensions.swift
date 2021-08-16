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
import PostgresKit

public extension EventLoopGroupConnectionPool where Source == PostgresConnectionSource {
    func withConnectionThrowing<Result>(_ closure: @escaping (PostgresConnection) throws -> EventLoopFuture<Result>) -> EventLoopFuture<Result> {
        self.withConnection { connection in
            do {
                return try closure(connection)
            } catch {
                return self.eventLoopGroup.future(error: error)
            }
        }
    }
}

extension PostgresConnection: SQLDatabase {
    public var dialect: SQLDialect {
        PostgresDialect()
    }

    public func execute(sql query: SQLExpression, _ onRow: @escaping (SQLRow) -> Void) -> EventLoopFuture<Void> {
        self.sql().execute(sql: query, onRow)
    }
}
