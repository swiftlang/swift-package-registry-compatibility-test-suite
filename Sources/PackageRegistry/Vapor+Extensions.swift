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

import PackageModel
import PackageRegistryModels
import TSCUtility
import Vapor

// MARK: - Request

extension Request {
    func parseAcceptHeader() -> (apiVersion: String?, mediaType: String?) {
        /// 3.5 API versioning - `Accept` header format
        guard let header = self.headers[.accept].filter({ $0.hasPrefix("application/vnd.swift.registry") }).first,
              let regex = try? NSRegularExpression(pattern: #"application/vnd.swift.registry(\.v([^+]+))?(\+(.+))?"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: header, options: [], range: NSRange(location: 0, length: header.count)) else {
            return (nil, nil)
        }

        let apiVersion = Range(match.range(at: 2), in: header).map { String(header[$0]) }
        let mediaType = Range(match.range(at: 4), in: header).map { String(header[$0]) }
        return (apiVersion, mediaType)
    }

    func getPackageScopeParam(validating: Bool = false) throws -> PackageModel.PackageIdentity.Scope {
        guard let scopeString = self.parameters.get("scope") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'scope'")
        }

        let scope: PackageModel.PackageIdentity.Scope
        if validating {
            guard let packageScope = PackageModel.PackageIdentity.Scope(scopeString) else {
                throw PackageRegistry.APIError.badRequest("Invalid scope: \(scopeString)")
            }
            scope = packageScope
        } else {
            do {
                scope = try PackageModel.PackageIdentity.Scope(validating: scopeString)
            } catch {
                throw PackageRegistry.APIError.badRequest("Invalid scope '\(scopeString)': \(error)")
            }
        }

        return scope
    }

    func getPackageNameParam(validating: Bool = false, removingExtension: String? = nil) throws -> PackageModel.PackageIdentity.Name {
        guard let nameString = self.parameters.get("name") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'name'")
        }

        let sanitizedNameString: String
        if let removingExtension = removingExtension {
            sanitizedNameString = nameString.dropDotExtension(removingExtension)
        } else {
            sanitizedNameString = nameString
        }

        let name: PackageModel.PackageIdentity.Name
        if validating {
            guard let packageName = PackageModel.PackageIdentity.Name(sanitizedNameString) else {
                throw PackageRegistry.APIError.badRequest("Invalid name: \(sanitizedNameString)")
            }
            name = packageName
        } else {
            do {
                name = try PackageModel.PackageIdentity.Name(validating: sanitizedNameString)
            } catch {
                throw PackageRegistry.APIError.badRequest("Invalid name '\(sanitizedNameString)': \(error)")
            }
        }

        return name
    }

    func getPackageParam(validating: Bool = false) throws -> PackageIdentity {
        let scope = try self.getPackageScopeParam(validating: validating)
        let name = try self.getPackageNameParam(validating: validating)
        return PackageIdentity(scope: scope, name: name)
    }

    func getVersionParam(removingExtension: String? = nil) throws -> Version {
        guard let versionString = self.parameters.get("version") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'version'")
        }

        let sanitizedVersionString: String
        if let removingExtension = removingExtension {
            sanitizedVersionString = versionString.dropDotExtension(removingExtension)
        } else {
            sanitizedVersionString = versionString
        }

        guard let version = Version(sanitizedVersionString) else {
            throw PackageRegistry.APIError.badRequest("Invalid version: '\(sanitizedVersionString)'")
        }
        return version
    }
}

// MARK: - Response

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

// MARK: - Request handler

extension RoutesBuilder {
    @discardableResult
    func get<Response>(_ path: PathComponent...,
                       use closure: @escaping (Request) async throws -> Response) -> Route where Response: ResponseEncodable {
        self.on(.GET, path, use: closure)
    }

    @discardableResult
    func delete<Response>(_ path: PathComponent...,
                          use closure: @escaping (Request) async throws -> Response) -> Route where Response: ResponseEncodable {
        self.on(.DELETE, path, use: closure)
    }

    @discardableResult
    func on<Response>(_ method: HTTPMethod,
                      _ path: PathComponent...,
                      body: HTTPBodyStreamStrategy = .collect,
                      use closure: @escaping (Request) async throws -> Response) -> Route where Response: ResponseEncodable {
        self.on(method, path, body: body, use: closure)
    }

    @discardableResult
    func on<Response>(_ method: HTTPMethod,
                      _ path: [PathComponent],
                      body: HTTPBodyStreamStrategy = .collect,
                      use closure: @escaping (Request) async throws -> Response) -> Route where Response: ResponseEncodable {
        self.on(method, path, body: body, use: { request -> EventLoopFuture<Response> in
            let promise = request.eventLoop.makePromise(of: Response.self)
            Task.detached {
                do {
                    let response = try await closure(request)
                    promise.succeed(response)
                } catch {
                    promise.fail(error)
                }
            }
            return promise.futureResult
        })
    }
}

// MARK: - Others

struct APIVersionStorageKey: StorageKey {
    typealias Value = PackageRegistry.APIVersion
}
