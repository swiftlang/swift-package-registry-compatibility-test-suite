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

import Logging
import Vapor

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
            var cors = CORS()

            var baseURL: String {
                ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://\(self.host):\(self.port)"
            }

            var description: String {
                "[\(API.self): host: \(self.host), port: \(self.port), cors: \(self.cors)]"
            }

            struct CORS: CustomStringConvertible {
                var domains = (ProcessInfo.processInfo.environment["API_SERVER_CORS_DOMAINS"] ?? "*").split(separator: ",").map(String.init)
                var allowedMethods: [HTTPMethod] = ProcessInfo.processInfo.environment["API_SERVER_CORS_METHODS"]?.split(separator: ",").map { .RAW(value: String($0)) } ??
                    [.OPTIONS, .GET, .POST, .PUT, .PATCH, .DELETE]
                var allowedHeaders: [HTTPHeaders.Name] = ProcessInfo.processInfo.environment["API_SERVER_CORS_HEADERS"]?.split(separator: ",").map { .init(String($0)) } ??
                    [.accept, .acceptLanguage, .contentType, .contentLanguage, .contentLength,
                     .origin, .userAgent, .accessControlAllowOrigin, .accessControlAllowHeaders]
                var allowCredentials = ProcessInfo.processInfo.environment["API_SERVER_CORS_CREDENTIALS"].flatMap(Bool.init) ?? true

                var description: String {
                    "[\(CORS.self): domains: \(self.domains), allowedMethods: \(self.allowedMethods), allowedHeaders: \(self.allowedHeaders), allowCredentials: \(self.allowCredentials)]"
                }
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
