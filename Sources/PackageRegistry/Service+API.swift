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

            let createController = CreatePackageReleaseController(configuration: configuration, dataAccess: dataAccess)
            let packageReleasesController = PackageReleasesController(configuration: configuration, dataAccess: dataAccess)
            let packageManifestsController = PackageManifestsController(configuration: configuration, dataAccess: dataAccess)
            let packageResourcesController = PackageResourcesController(dataAccess: dataAccess)
            let packageIdentifiersController = PackageIdentifiersController(dataAccess: dataAccess)

            // APIs
            let apiMiddleware: [Middleware] = [MetricsMiddleware(), APIVersionMiddleware()]
            let apiRoutes = self.vapor.routes.grouped(apiMiddleware)

            // 4.1 GET /{scope}/{name} - list package releases
            apiRoutes.get(":scope", ":name", use: packageReleasesController.listForPackage)

            // 4.2 and 4.4
            apiRoutes.get(":scope", ":name", ":version") { request async throws -> Response in
                guard let version = request.parameters.get("version") else {
                    throw PackageRegistry.APIError.badRequest("Invalid path: missing 'version'")
                }

                if version.hasSuffix(".zip", caseSensitive: false) {
                    // 4.4 GET /{scope}/{name}/{version}.zip - download source archive for a package release
                    return try await packageResourcesController.downloadSourceArchive(request: request)
                } else {
                    // 4.2 GET /{scope}/{name}/{version} - fetch information about a package release
                    return try await packageReleasesController.fetchPackageReleaseInfo(request: request)
                }
            }

            // 4.3 GET /{scope}/{name}/{version}/Package.swift{?swift-version} - fetch manifest for a package release
            apiRoutes.get(":scope", ":name", ":version", "Package.swift", use: packageManifestsController.fetchManifest)

            // 4.5 GET /identifiers{?url} - lookup package identifiers registered for a URL
            apiRoutes.get("identifiers", use: packageIdentifiersController.lookupByURL)

            // FIXME: publish endpoint should require auth
            // 4.6 PUT /{scope}/{name}/{version} - create package release
            apiRoutes.on(.PUT, ":scope", ":name", ":version", body: .collect(maxSize: "10mb"), use: createController.pushPackageRelease)

            // FIXME: delete endpoint should require auth
            // DELETE /{scope}/{name}/{version} - delete package release
            apiRoutes.delete(":scope", ":name", ":version", use: packageReleasesController.delete)

            // 4 A server should support `OPTIONS` requests
            apiRoutes.on(.OPTIONS, ":scope", ":name", use: makeOptionsRequestHandler(allowMethods: [.GET]))
            apiRoutes.on(.OPTIONS, ":scope", ":name", ":version") { request throws -> Response in
                guard let version = request.parameters.get("version") else {
                    throw PackageRegistry.APIError.badRequest("Invalid path: missing 'version'")
                }

                if version.hasSuffix(".zip", caseSensitive: false) {
                    // Download source archive (GET) or delete package release (DELETE)
                    return makeOptionsRequestHandler(allowMethods: [.GET, .DELETE])(request)
                } else if version.hasSuffix(".json", caseSensitive: false) {
                    // Fetch information about a package release
                    return makeOptionsRequestHandler(allowMethods: [.GET])(request)
                }

                // Else it could be one of:
                // - Fetch package release information (GET)
                // - Create package release (PUT)
                // - Delete package release (DELETE)
                return makeOptionsRequestHandler(allowMethods: [.GET, .PUT, .DELETE])(request)
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
        case unprocessableEntity(String)
        case resourceGone(String)
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
            case PackageRegistry.APIError.unprocessableEntity(let detail):
                response = Response.jsonError(status: .unprocessableEntity, detail: detail)
            case PackageRegistry.APIError.resourceGone(let detail):
                response = Response.jsonError(status: .gone, detail: detail)
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
        let (acceptAPIVersion, _) = request.parseAcceptHeader()
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
