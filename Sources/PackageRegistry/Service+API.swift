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

import Dispatch
import Foundation

import Logging
import Metrics
import Vapor

extension PackageRegistry {
    struct API {
        private let vapor: Application

        init(configuration: Configuration) {
            // We don't use Vapor's environment feature, so hard-code to .production
            self.vapor = Application(.production)
            // Disable command line arguments
            self.vapor.environment.arguments.removeLast(self.vapor.environment.arguments.count - 1)

            // HTTP server
            self.vapor.http.server.configuration.hostname = configuration.api.host
            self.vapor.http.server.configuration.port = configuration.api.port

            // Middlewares
            self.vapor.middleware.use(CORSMiddleware.make(for: configuration.api.corsDomains), at: .beginning)
            self.vapor.middleware.use(API.errorMiddleware)

            // Basic routes
            let infoController = InfoController()
            self.vapor.routes.get("", use: infoController.info)
            let healthController = HealthController()
            self.vapor.routes.get("__health", use: healthController.health)
        }

        func start() throws {
            Counter(label: "api.start").increment()
            try self.vapor.start()
        }

        func shutdown() throws {
            Counter(label: "api.shutdown").increment()
            self.vapor.shutdown()
        }
    }
}

// MARK: - Error middleware

extension PackageRegistry.API {
    private static var errorMiddleware: Middleware {
        ErrorMiddleware { request, error in
            request.logger.report(error: error)

            let response: Response
            switch error {
            case let abort as AbortError:
                response = Response.jsonError(status: abort.status, detail: abort.reason, headers: abort.headers)
            default:
                response = Response.jsonError(status: .internalServerError, detail: "The server has encountered an error. Please check logs for details.")
            }

            return response
        }
    }
}

// MARK: - CORS middleware

enum CORSMiddleware {
    static func make(for domains: [String]) -> Middleware {
        Vapor.CORSMiddleware(configuration: .init(
            // Ideally this logic would be done in Vapor when passing * and allowCredentials = true
            allowedOrigin: domains.first == "*" ? .originBased : .custom(domains.joined(separator: ",")),
            allowedMethods: [.OPTIONS, .GET, .POST, .PUT, .PATCH, .DELETE],
            allowedHeaders: [.accept, .acceptLanguage,
                             .contentType, .contentLanguage, .contentLength,
                             .origin, .userAgent,
                             .accessControlAllowOrigin, .accessControlAllowHeaders],
            allowCredentials: true
        ))
    }
}

// MARK: - Metrics middleware

struct MetricsMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        let start = DispatchTime.now().uptimeNanoseconds
        Counter(label: "api.server.request.count").increment()

        return next.respond(to: request).always { result in
            Metrics.Timer(label: "api.server.request.duration").recordNanoseconds(DispatchTime.now().uptimeNanoseconds - start)

            switch result {
            case .failure:
                Counter(label: "api.server.response.failure").increment()
            case .success:
                Counter(label: "api.server.response.success").increment()
            }
        }
    }
}
