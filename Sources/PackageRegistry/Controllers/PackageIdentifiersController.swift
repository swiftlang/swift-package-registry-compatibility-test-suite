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

import PackageRegistryModels
import Vapor

struct PackageIdentifiersController {
    private let packageReleases: PackageReleasesDAO

    init(dataAccess: DataAccess) {
        self.packageReleases = dataAccess.packageReleases
    }

    func lookupByURL(request: Request) async throws -> Response {
        guard let url: String = request.query["url"] else {
            throw PackageRegistry.APIError.badRequest("Missing 'url' query parameter")
        }

        let releases = try await self.packageReleases.findBy(repositoryURL: url)
        guard !releases.isEmpty else {
            throw DataAccessError.notFound
        }

        let identifiers = Set(releases.map { "\($0.package)" })
        return Response.json(PackageIdentifiersResponse(identifiers: identifiers))
    }
}
