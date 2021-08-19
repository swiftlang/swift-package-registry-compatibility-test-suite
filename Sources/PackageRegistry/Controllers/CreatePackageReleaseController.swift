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

import struct Foundation.Data

import MultipartKit
import NIOHTTP1
import PackageModel
import PackageRegistryModels
import TSCBasic
import TSCUtility
import Vapor

struct CreatePackageReleaseController {
    private typealias Manifest = (SwiftLanguageVersion?, String, ToolsVersion, Data)

    private let configuration: PackageRegistry.Configuration
    private let packageReleases: PackageReleasesDAO

    private let fileSystem: FileSystem
    private let archiver: Archiver

    init(configuration: PackageRegistry.Configuration, dataAccess: DataAccess) {
        self.configuration = configuration
        self.packageReleases = dataAccess.packageReleases

        self.fileSystem = localFileSystem
        self.archiver = ZipArchiver(fileSystem: self.fileSystem)
    }

    func pushPackageRelease(request: Request) async throws -> Response {
        guard let scopeString = request.parameters.get("scope") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'scope'")
        }
        // Validate scope
        let scope: PackageModel.PackageIdentity.Scope
        do {
            scope = try PackageModel.PackageIdentity.Scope(validating: scopeString)
        } catch {
            throw PackageRegistry.APIError.badRequest("Invalid scope '\(scopeString)': \(error)")
        }

        guard let nameString = request.parameters.get("name") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'name'")
        }
        // Validate name
        let name: PackageModel.PackageIdentity.Name
        do {
            name = try PackageModel.PackageIdentity.Name(validating: nameString)
        } catch {
            throw PackageRegistry.APIError.badRequest("Invalid name '\(nameString)': \(error)")
        }

        guard let versionString = request.parameters.get("version") else {
            throw PackageRegistry.APIError.badRequest("Invalid path: missing 'version'")
        }
        guard let version = Version(versionString) else {
            throw PackageRegistry.APIError.badRequest("Invalid version: '\(versionString)'")
        }

        guard let requestBody = request.body.string else {
            throw PackageRegistry.APIError.badRequest("Missing request body")
        }

        let package = PackageIdentity(scope: scope, name: name)

        do {
            _ = try await self.packageReleases.get(package: package, version: version)
            // A release already exists! Return 409 (4.6)
            return Response.jsonError(status: .conflict, detail: "\(package)@\(version) already exists")
        } catch DataAccessError.notFound {
            // Release doesn't exist yet. Proceed.
            let createRequest = try FormDataDecoder().decode(CreatePackageReleaseRequest.self, from: requestBody, boundary: "boundary")

            guard let archiveData = createRequest.sourceArchive else {
                throw PackageRegistry.APIError.unprocessableEntity("Source archive is either missing or invalid")
            }
            let metadata = createRequest.metadata

            // Analyze the source archive
            let (checksum, manifests) = try await self.processSourceArchive(archiveData)

            // Insert into database
            _ = try await self.packageReleases.create(
                package: package,
                version: version,
                repositoryURL: metadata?.repositoryURL,
                commitHash: metadata?.commitHash,
                checksum: checksum,
                sourceArchive: archiveData,
                manifests: manifests
            )

            let response = CreatePackageReleaseResponse(
                scope: scope.description,
                name: name.description,
                version: version.description,
                metadata: metadata,
                checksum: checksum
            )

            let location = "\(self.configuration.api.baseURL)/\(scope)/\(name)/\(version)"
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .location, value: location)

            return Response.json(status: .created, body: response, headers: headers)
        }
    }

    private func processSourceArchive(_ archiveData: Data) async throws -> (String, [Manifest]) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String, [Manifest]), Error>) in
            do {
                // Delete the directory ourselves instead of setting `removeTreeOnDeinit: true`
                // so we don't risk having the directory deleted prematurely.
                try withTemporaryDirectory(removeTreeOnDeinit: false) { directoryPath in
                    // Write the source archive to temp file
                    let archivePath = directoryPath.appending(component: "package.zip")
                    try self.fileSystem.writeFileContents(archivePath, bytes: ByteString(Array(archiveData)))

                    // Run `swift package compute-checksum` tool
                    let checksum = try Process.checkNonZeroExit(arguments: ["swift", "package", "compute-checksum", archivePath.pathString])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    let packagePath = directoryPath.appending(component: "package")
                    try self.fileSystem.createDirectory(packagePath, recursive: true)

                    // Unzip the source archive
                    self.archiver.extract(from: archivePath, to: packagePath) { result in
                        // Delete the temp directory when we are done
                        defer { _ = try? self.fileSystem.removeFileTree(directoryPath) }

                        switch result {
                        case .success:
                            do {
                                // Find manifests
                                let manifests = try self.getManifests(packagePath)
                                // Package.swift is required
                                guard manifests.first(where: { $0.0 == nil }) != nil else {
                                    throw PackageRegistry.APIError.unprocessableEntity("Package.swift is missing or invalid in the source archive")
                                }
                                continuation.resume(returning: (checksum, manifests))
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func getManifests(_ packageDirectory: AbsolutePath) throws -> [Manifest] {
        // Package.swift and version-specific manifests
        let regex = try NSRegularExpression(pattern: #"\APackage(@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?)?.swift\z"#, options: .caseInsensitive)
        return try self.fileSystem.getDirectoryContents(packageDirectory).compactMap { filename in
            guard let match = regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.count)) else {
                return nil
            }

            // Extract Swift version from filename
            var swiftVersion: SwiftLanguageVersion?
            if let majorVersion = Range(match.range(at: 2), in: filename).map({ String(filename[$0]) }) {
                let minorVersion = Range(match.range(at: 3), in: filename).map { String(filename[$0]) }
                let patchVersion = Range(match.range(at: 4), in: filename).map { String(filename[$0]) }
                let swiftVersionString = "\(majorVersion)\(minorVersion.map { ".\($0)" } ?? "")\(patchVersion.map { ".\($0)" } ?? "")"

                swiftVersion = SwiftLanguageVersion(string: swiftVersionString)
                guard swiftVersion != nil else {
                    return nil
                }
            }

            let manifestPath = packageDirectory.appending(component: filename)
            guard let manifestBytes = try? self.fileSystem.readFileContents(manifestPath) else {
                return nil
            }

            // Extract tools version from manifest
            guard let manifestContents = String(bytes: manifestBytes.contents, encoding: .utf8),
                  let toolsVersionLine = manifestContents.components(separatedBy: .newlines).first,
                  toolsVersionLine.hasPrefix("// swift-tools-version:"),
                  let swiftToolsVersion = ToolsVersion(string: String(toolsVersionLine.dropFirst("// swift-tools-version:".count))) else {
                return nil
            }

            return (swiftVersion, filename, swiftToolsVersion, Data(manifestBytes.contents))
        }
    }
}
