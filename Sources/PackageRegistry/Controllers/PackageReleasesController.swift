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
import TSCBasic
import Vapor

struct PackageReleasesController {
    private let packageReleases: PackageReleasesDAO

    init(dataAccess: DataAccess) {
        self.packageReleases = dataAccess.packageReleases
    }

    func delete(request: Request) async throws -> Response {
        guard let scopeString = request.parameters.get("scope") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'scope'")
        }
        guard let scope = PackageModel.PackageIdentity.Scope(scopeString) else {
            throw PackageRegistry.APIError.badRequest("Invalid scope: \(scopeString)")
        }

        guard let nameString = request.parameters.get("name") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'name'")
        }
        guard let name = PackageModel.PackageIdentity.Name(nameString) else {
            throw PackageRegistry.APIError.badRequest("Invalid name: \(nameString)")
        }

        guard let versionString = request.parameters.get("version") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'version'")
        }
        // Client may append .zip extension to the URI
        let sanitizedVersionString = dropDotExtension(".zip", from: versionString)
        guard let version = Version(sanitizedVersionString) else {
            throw PackageRegistry.APIError.badRequest("Invalid version: '\(sanitizedVersionString)'")
        }

        let package = PackageIdentity(scope: scope, name: name)

        do {
            try await self.packageReleases.delete(package: package, version: version)
            return Response(status: .noContent)
        } catch DataAccessError.notFound {
            return Response.jsonError(status: .notFound, detail: "\(package)@\(version) not found")
        } catch DataAccessError.noChange {
            return Response.jsonError(status: .gone, detail: "\(package)@\(version) has already been removed")
        }
    }
}
