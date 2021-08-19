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

import Crypto
import NIO
import Vapor

struct PackageResourcesController {
    private let packageReleases: PackageReleasesDAO
    private let packageResources: PackageResourcesDAO

    init(dataAccess: DataAccess) {
        self.packageReleases = dataAccess.packageReleases
        self.packageResources = dataAccess.packageResources
    }

    func downloadSourceArchive(request: Request) async throws -> Response {
        let package = try request.getPackageParam(validating: false)
        // Client may append .json extension to the URI (4.4)
        let version = try request.getVersionParam(removingExtension: ".zip")

        let release = try await self.packageReleases.get(package: package, version: version)
        guard release.status != .deleted else {
            throw PackageRegistry.APIError.resourceGone("\(package)@\(version) has been removed")
        }

        let sourceArchive = try await self.packageResources.get(package: package, version: version, type: .sourceArchive)

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .acceptRanges, value: "bytes")
        headers.replaceOrAdd(name: .cacheControl, value: "public, immutable")
        headers.contentType = .zip
        headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(package.name)-\(version).zip\"")
        headers.replaceOrAdd(name: "Digest", value: "sha-256=\(Data(SHA256.hash(data: sourceArchive.bytes)).base64EncodedString())")
        // Content-Length header is automatically set for us

        let response = Response(status: .ok, headers: headers)
        let buffer = ByteBuffer(data: sourceArchive.bytes)

        response.body = .init(stream: { stream in
            stream.write(.buffer(buffer))
                .whenComplete { result in
                    switch result {
                    case .success:
                        stream.write(.end, promise: nil)
                    case .failure(let error):
                        stream.write(.error(error), promise: nil)
                    }
                }
        }, count: buffer.readableBytes)

        return response
    }
}
