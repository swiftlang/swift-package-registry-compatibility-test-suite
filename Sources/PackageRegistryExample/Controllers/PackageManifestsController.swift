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

import PackageModel
import TSCUtility
import Vapor

struct PackageManifestsController {
    private let configuration: PackageRegistry.Configuration
    private let packageReleases: PackageReleasesDAO
    private let packageManifests: PackageManifestsDAO

    init(configuration: PackageRegistry.Configuration, dataAccess: DataAccess) {
        self.configuration = configuration
        self.packageReleases = dataAccess.packageReleases
        self.packageManifests = dataAccess.packageManifests
    }

    func fetchManifest(request: Request) async throws -> Response {
        let package = try request.getPackageParam()
        let version = try request.getVersionParam()

        var swiftVersion: SwiftLanguageVersion?
        if let swiftVersionString: String = request.query["swift-version"] {
            swiftVersion = SwiftLanguageVersion(string: swiftVersionString)
            guard swiftVersion != nil else {
                throw PackageRegistry.APIError.badRequest("Invalid Swift version: '\(swiftVersionString)'")
            }
        }

        let release = try await self.packageReleases.get(package: package, version: version)
        guard release.status != .deleted else {
            throw PackageRegistry.APIError.resourceGone("\(package)@\(version) has been removed")
        }

        let manifests = try await self.packageManifests.get(package: package, version: version)
        guard !manifests.isEmpty else {
            throw PackageRegistry.APIError.notFound("No manifests found for \(package)@\(version)")
        }

        // `swiftVersion` is nil means we are fetching `Package.swift`, else it's a version-specific manifest.
        if let manifest = manifests.first(where: { $0.swiftVersion == swiftVersion }) {
            guard let manifestString = String(data: manifest.bytes, encoding: .utf8) else {
                throw PackageRegistry.APIError.serverError("Invalid manifest bytes")
            }

            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .cacheControl, value: "public, immutable")
            headers.replaceOrAdd(name: .contentType, value: "text/x-swift")
            headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(manifest.filename)\"")
            // Content-Length header is automatically set for us

            // If we are sending back `Package.swift`, link to other manifest(s) if any
            if swiftVersion == nil {
                let links = manifests.filter { $0.swiftVersion != nil }.map {
                    // !-safe since we filter by non-nil swiftVersion
                    "<\(self.configuration.api.baseURL)/\(package.scope)/\(package.name)/\(version)/Package.swift?swift-version=\($0.swiftVersion!)>; rel=\"alternate\"; filename=\"\($0.filename)\"; swift-tools-version=\"\($0.swiftToolsVersion)\""
                }
                if !links.isEmpty {
                    headers.setLinkHeader(links)
                }
            }

            return Response(status: .ok, headers: headers, body: Response.Body(string: manifestString))
        } else {
            // No manifest found for the Swift version, redirect to `Package.swift` if found
            if swiftVersion != nil, manifests.first(where: { $0.swiftVersion == nil }) != nil {
                var urlComponents = URLComponents()
                urlComponents.scheme = request.url.scheme
                urlComponents.host = request.url.host
                urlComponents.port = request.url.port
                urlComponents.path = request.url.path
                // Exclude query params

                guard let redirectTo = urlComponents.url?.absoluteString else {
                    throw PackageRegistry.APIError.serverError("Cannot determine redirect URL")
                }

                // !-safe since swiftVersion != nil
                request.logger.info("Package@swift-\(swiftVersion!).swift not found for \(package)@\(version). Redirecting to \(redirectTo).")
                return request.redirect(to: redirectTo, type: .normal)
            } else {
                throw PackageRegistry.APIError.notFound("No manifests found for \(package)@\(version)")
            }
        }
    }
}
