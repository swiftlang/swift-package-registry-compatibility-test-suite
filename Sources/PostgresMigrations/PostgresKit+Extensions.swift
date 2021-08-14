//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPackageRegistryCompatibilityTestSuite open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftPackageRegistryCompatibilityTestSuite project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPackageRegistryCompatibilityTestSuite project authors
//
// SPDX-License-Identifier: Apache-2.0
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
