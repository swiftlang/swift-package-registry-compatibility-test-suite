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

import Foundation

import Logging

extension PackageRegistry {
    struct Configuration: CustomStringConvertible {
        var app = App()
        var postgres = Postgres()
        var api = API()

        struct App: CustomStringConvertible {
            var logLevel: Logger.Level = ProcessInfo.processInfo.environment["LOG_LEVEL"].flatMap(Logger.Level.init(rawValue:)) ?? .info
            var metricsPort = ProcessInfo.processInfo.environment["METRICS_PORT"].flatMap(Int.init)

            var description: String {
                "App: logLevel: \(self.logLevel), metricsPort: \(self.metricsPort ?? -1)"
            }
        }

        struct Postgres: PostgresDataAccess.Configuration, CustomStringConvertible {
            var host = ProcessInfo.processInfo.environment["POSTGRES_HOST"] ?? "127.0.0.1"
            var port = ProcessInfo.processInfo.environment["POSTGRES_PORT"].flatMap(Int.init) ?? 5432
            var tls = ProcessInfo.processInfo.environment["POSTGRES_TLS"].flatMap(Bool.init) ?? false
            var database = ProcessInfo.processInfo.environment["POSTGRES_DATABASE"] ?? "package_registry"
            var username = ProcessInfo.processInfo.environment["POSTGRES_USER"] ?? "postgres"
            var password = ProcessInfo.processInfo.environment["POSTGRES_PASSWORD"] ?? "postgres"

            var description: String {
                "[\(Postgres.self): host: \(self.host), port: \(self.port), tls: \(self.tls), database: \(self.database), username: \(self.username), password: *****]"
            }
        }

        struct API: CustomStringConvertible {
            var host = ProcessInfo.processInfo.environment["API_SERVER_HOST"] ?? "127.0.0.1"
            var port = ProcessInfo.processInfo.environment["API_SERVER_PORT"].flatMap(Int.init) ?? 9229
            var corsDomains = (ProcessInfo.processInfo.environment["API_SERVER_CORS_DOMAINS"] ?? "*").split(separator: ",").map(String.init)

            var description: String {
                "[\(API.self): host: \(self.host), port: \(self.port), corsDomains: \(self.corsDomains)]"
            }
        }

        var description: String {
            """
            \(Configuration.self):
              \(self.postgres)
              \(self.api)
            """
        }
    }
}
