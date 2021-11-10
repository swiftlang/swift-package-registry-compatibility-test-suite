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

import ArgumentParser
import AsyncHTTPClient
import NIO
import NIOFoundationCompat
import NIOHTTP1
import PackageRegistryClient

@main
struct PackageRegistryTool: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "package-registry",
        abstract: "Interact with package registry",
        version: "0.0.1",
        subcommands: [
            CreatePackageRelease.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    struct CreatePackageRelease: ParsableCommand {
        @Option(help: "Package registry URL")
        var packageRegistry: String = "http://localhost:9229"

        @Argument(help: "Package scope")
        var scope: String

        @Argument(help: "Package name")
        var name: String

        @Argument(help: "Package release version")
        var version: String

        @Argument(help: "Source archive path")
        var archivePath: String

        @Option(help: "Metadata JSON. If this and '--metadata-path' are both specified, This will be used.")
        var metadata: String?

        @Option(help: "Path to metadata JSON file. If this and '--metadata' are both specified, '--metadata' will be used.")
        var metadataPath: String?

        func run() throws {
            let configuration = PackageRegistryClient.Configuration(url: self.packageRegistry)
            let registryClient = PackageRegistryClient(httpClientProvider: .createNew, configuration: configuration)
            defer { try! registryClient.syncShutdown() }

            let archiveURL = URL(fileURLWithPath: self.archivePath)
            let archiveData = try Data(contentsOf: archiveURL)
            print("Archive size: \(archiveData.count)")

            let promise = registryClient.httpClient.eventLoopGroup.next().makePromise(of: HTTPClient.Response.self)
            Task.detached {
                do {
                    let response: HTTPClient.Response
                    if let metadata = self.metadata {
                        response = try await registryClient.createPackageRelease(scope: self.scope,
                                                                                 name: self.name,
                                                                                 version: self.version,
                                                                                 sourceArchive: archiveData,
                                                                                 metadataJSON: metadata,
                                                                                 deadline: NIODeadline.now() + .seconds(5))
                    } else {
                        var metadata: Data?
                        if let metadataPath = self.metadataPath {
                            metadata = try Data(contentsOf: URL(fileURLWithPath: metadataPath))
                        }

                        response = try await registryClient.createPackageRelease(scope: self.scope,
                                                                                 name: self.name,
                                                                                 version: self.version,
                                                                                 sourceArchive: archiveData,
                                                                                 metadataJSON: metadata,
                                                                                 deadline: NIODeadline.now() + .seconds(5))
                    }
                    promise.succeed(response)
                } catch {
                    promise.fail(error)
                }
            }

            let response = try promise.futureResult.wait()

            guard response.status == .created || response.status == .accepted else {
                let responseBody = response.body
                let responseData = responseBody.map { Data(buffer: $0) }
                print("Publication failed with status \(response.status). \(String(describing: responseData.map { String(data: $0, encoding: .utf8) }))")
                return
            }
            print("Success!")
        }
    }
}
