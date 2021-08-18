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
import PackageRegistryModels
import TSCBasic
import Vapor

struct PackageReleasesController {
    private let configuration: PackageRegistry.Configuration
    private let packageReleases: PackageReleasesDAO

    init(configuration: PackageRegistry.Configuration, dataAccess: DataAccess) {
        self.configuration = configuration
        self.packageReleases = dataAccess.packageReleases
    }

    func listForPackage(request: Request) async throws -> Response {
        let scope = try request.getPackageScopeParam()
        // Client may append .json extension to the URI (4.1)
        let name = try request.getPackageNameParam(removingExtension: ".json")
        let package = PackageIdentity(scope: scope, name: name)

        let list = try await self.packageReleases.list(for: package)

        guard !list.isEmpty else {
            throw DataAccessError.notFound
        }

        var links = [String]()
        // Link to the latest published release - `list` is already sorted with most recent first
        let latest = list.first! // !-safe since list is not empty at this point
        links.append("<\(self.configuration.api.baseURL)/\(package.scope)/\(package.name)/\(latest.version)>; rel=\"latest-version\"")
        // Link to source repository, if any
        if let repositoryURL = latest.repositoryURL {
            links.append("<\(repositoryURL)>; rel=\"canonical\"")
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .link, value: links.joined(separator: ","))

        let response = PackageReleasesResponse(
            releases: Dictionary(list.map { ($0.version.description, PackageReleasesResponse.ReleaseInfo.from($0, baseURL: self.configuration.api.baseURL)) },
                                 uniquingKeysWith: { first, _ in first })
        )
        return Response.json(status: .ok, body: response, headers: headers)
    }

    func delete(request: Request) async throws -> Response {
        let package = try request.getPackageParam(validating: true)
        // Client may append .zip extension to the URI (4.1)
        let version = try request.getVersionParam(removingExtension: ".zip")

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

private extension PackageReleasesResponse.ReleaseInfo {
    static func from(_ packageRelease: PackageRegistryModel.PackageRelease, baseURL: String) -> PackageReleasesResponse.ReleaseInfo {
        let problem: ProblemDetails?
        switch packageRelease.status {
        case .deleted:
            problem = .gone
        default:
            problem = nil
        }

        return PackageReleasesResponse.ReleaseInfo(
            url: "\(baseURL)/\(packageRelease.package.scope)/\(packageRelease.package.name)/\(packageRelease.version.description)",
            problem: problem
        )
    }
}
