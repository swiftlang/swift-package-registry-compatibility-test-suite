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

struct PackageReleasesController {
    private let configuration: PackageRegistry.Configuration
    private let packageReleases: PackageReleasesDAO
    private let packageResources: PackageResourcesDAO

    init(configuration: PackageRegistry.Configuration, dataAccess: DataAccess) {
        self.configuration = configuration
        self.packageReleases = dataAccess.packageReleases
        self.packageResources = dataAccess.packageResources
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

    func fetchPackageReleaseInfo(request: Request) async throws -> Response {
        let package = try request.getPackageParam(validating: true)
        // Client may append .json extension to the URI (4.2)
        let version = try request.getVersionParam(removingExtension: ".json")

        let release = try await self.packageReleases.get(package: package, version: version)
        guard release.status != .deleted else {
            throw PackageRegistry.APIError.resourceGone("\(package)@\(version) has been removed")
        }

        let allReleases = try await self.packageReleases.list(for: package)
        guard !allReleases.isEmpty else {
            return Response.jsonError(status: .internalServerError, detail: "\(package) should have at least one release")
        }

        let sourceArchive: PackageRegistryModel.PackageResource?
        do {
            sourceArchive = try await self.packageResources.get(package: package, version: version, type: .sourceArchive)
        } catch DataAccessError.notFound {
            sourceArchive = nil
        } catch {
            throw error
        }

        let sortedReleases = allReleases.sorted { $0.version > $1.version }
        // The requested version is not found
        guard let releaseIndex = sortedReleases.firstIndex(where: { $0.version == version }) else {
            return Response.jsonError(status: .internalServerError, detail: "\(package)'s releases should include \(version)")
        }

        var links = [String]()
        // Link to the latest published release - `list` is already sorted with most recent first
        let latest = allReleases.first! // !-safe since list is not empty at this point
        links.append("<\(self.configuration.api.baseURL)/\(package.scope)/\(package.name)/\(latest.version)>; rel=\"latest-version\"")
        // Link to the next published release, if one exists
        if let successor = releaseIndex == 0 ? nil : sortedReleases[releaseIndex - 1] {
            links.append("<\(self.configuration.api.baseURL)/\(package.scope)/\(package.name)/\(successor.version)>; rel=\"successor-version\"")
        }
        // Link to the previously published release, if one exists
        if let predecessor = releaseIndex == (sortedReleases.count - 1) ? nil : sortedReleases[releaseIndex + 1] {
            links.append("<\(self.configuration.api.baseURL)/\(package.scope)/\(package.name)/\(predecessor.version)>; rel=\"predecessor-version\"")
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .link, value: links.joined(separator: ","))

        let response = PackageReleaseInfo(
            id: package.description,
            version: version.description,
            resource: sourceArchive.map { PackageReleaseInfo.ReleaseResource.sourceArchive(checksum: $0.checksum) },
            metadata: PackageReleaseMetadata(repositoryURL: release.repositoryURL, commitHash: release.commitHash)
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
