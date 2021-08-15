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

import Dispatch
import Foundation

import Logging
import Metrics
import Vapor

extension PackageRegistry {
    struct API {
        private let vapor: Application

        init(configuration: Configuration, dataAccess: DataAccess) {
            // We don't use Vapor's environment feature, so hard-code to .production
            self.vapor = Application(.production)
            // Disable command line arguments
            self.vapor.environment.arguments.removeLast(self.vapor.environment.arguments.count - 1)

            // HTTP server
            self.vapor.http.server.configuration.hostname = configuration.api.host
            self.vapor.http.server.configuration.port = configuration.api.port

            // Middlewares
            self.vapor.middleware.use(CORSMiddleware.make(for: configuration.api.cors), at: .beginning)
            self.vapor.middleware.use(API.errorMiddleware)

            // Basic routes
            let infoController = InfoController()
            self.vapor.routes.get("", use: infoController.info)
            let healthController = HealthController()
            self.vapor.routes.get("__health", use: healthController.health)

            // APIs
            let apiMiddleware: [Middleware] = [MetricsMiddleware(), APIVersionMiddleware()]
            let apiRoutes = self.vapor.routes.grouped(apiMiddleware)

            // FIXME: publish endpoints should require auth
            let createController = CreatePackageReleaseController(configuration: configuration, dataAccess: dataAccess)
            // 4.6 POST /{scope}/{name}/{version} - create package release
            apiRoutes.on(.POST, ":scope", ":name", ":version", body: .collect(maxSize: "10mb"), use: createController.pushPackageRelease)

            // 4 A server should support `OPTIONS` requests
            apiRoutes.on(.OPTIONS, ":scope", ":name", use: makeOptionsRequestHandler(allowMethods: [.GET]))
            apiRoutes.on(.OPTIONS, ":scope", ":name", ":version") { request throws -> Response in
                guard let version = request.parameters.get("version") else {
                    throw PackageRegistry.APIError.badRequest("Invalid path: missing 'version'")
                }

                // Download source archive API is always GET only
                if version.hasSuffix(".zip") {
                    return makeOptionsRequestHandler(allowMethods: [.GET])(request)
                }

                // Else it could be one of:
                // - Fetch package release information (GET)
                // - Create package release (POST)
                // - Delete package release (DELETE)
                return makeOptionsRequestHandler(allowMethods: [.GET, .POST, .DELETE])(request)
            }
            apiRoutes.on(.OPTIONS, ":scope", ":name", ":version", "Package.swift", use: makeOptionsRequestHandler(allowMethods: [.GET]))
            apiRoutes.on(.OPTIONS, "identifiers", use: makeOptionsRequestHandler(allowMethods: [.GET]))
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

private func makeOptionsRequestHandler(allowMethods: [HTTPMethod]) -> ((Request) -> Response) {
    { _ in
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .allow, value: allowMethods.map(\.string).joined(separator: ","))
        let links = [
            "<https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md>; rel=\"service-doc\"",
            "<https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#appendix-a---openapi-document>; rel=\"service-desc\"",
        ]
        headers.replaceOrAdd(name: .link, value: links.joined(separator: ","))
        return Response(status: .ok, headers: headers)
    }
}

extension PackageRegistry {
    enum APIVersion: String {
        case v1 = "1"
    }

    enum APIError: Error {
        case badRequest(String)
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
                // Attempt to serialize the error to json
                response = Response.jsonError(status: abort.status, detail: abort.reason, headers: abort.headers)
            case DataAccessError.notFound:
                response = Response.jsonError(status: .notFound, detail: "Not found")
            case PackageRegistry.APIError.badRequest(let detail):
                response = Response.jsonError(status: .badRequest, detail: detail)
            default:
                response = Response.jsonError(status: .internalServerError, detail: "The server has encountered an error. Please check logs for details.")
            }

            if let apiVersion = request.storage.get(APIVersionStorageKey.self) {
                response.headers.replaceOrAdd(name: .contentVersion, value: apiVersion.rawValue)
            }

            return response
        }
    }
}

// MARK: - API version middleware

struct APIVersionMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        // 3.5 API versioning - a client should set the `Accept` header to specify the API version
        let (acceptAPIVersion, _) = parseAcceptHeader(for: request)
        let parsedAPIVersion = acceptAPIVersion.flatMap { PackageRegistry.APIVersion(rawValue: $0) }

        // An unknown API version is specified
        if let acceptAPIVersion = acceptAPIVersion, parsedAPIVersion == nil {
            return request.eventLoop.makeSucceededFuture(Response.jsonError(status: .badRequest, detail: "Unknown API version \"\(acceptAPIVersion)\""))
        }

        // Default to v1
        let apiVersion = parsedAPIVersion ?? .v1
        request.storage.set(APIVersionStorageKey.self, to: apiVersion)

        return next.respond(to: request).map { response in
            // 3.5 `Content-Version` header must be set
            response.headers.replaceOrAdd(name: .contentVersion, value: apiVersion.rawValue)

            // 3.5 `Content-Type` header must be set (except for 204 and redirects (3xx), and `OPTIONS` requests)
            if request.method == .OPTIONS {
                return response
            }
            if response.status.code != 204, !(300 ... 399).contains(response.status.code) {
                guard !response.headers[.contentType].isEmpty else {
                    // FIXME: this is for us to catch coding error during development; should not do this in production
                    preconditionFailure("Content-Type header is not set!")
                }
            }

            return response
        }
    }
}

// MARK: - CORS middleware

enum CORSMiddleware {
    static func make(for configuration: PackageRegistry.Configuration.API.CORS) -> Middleware {
        Vapor.CORSMiddleware(configuration: .init(
            allowedOrigin: configuration.domains.first == "*" ? .originBased : .custom(configuration.domains.joined(separator: ",")),
            allowedMethods: configuration.allowedMethods,
            allowedHeaders: configuration.allowedHeaders,
            allowCredentials: configuration.allowCredentials
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
