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

import AsyncHTTPClient
import Atomics
import Logging
import NIO
import NIOHTTP1

public struct PackageRegistryClient {
    private typealias EventLoopGroupContainer = (value: EventLoopGroup, managed: Bool)
    private typealias HTTPClientContainer = (value: HTTPClient, managed: Bool)

    public let url: String
    private let defaultRequestTimeout: TimeAmount

    private let eventLoopGroupContainer: EventLoopGroupContainer
    private let clientContainer: HTTPClientContainer
    private let logger: Logger

    private let encoder: JSONEncoder

    private let isShutdown = ManagedAtomic<Bool>(false)

    public var httpClient: HTTPClient {
        self.clientContainer.value
    }

    public var eventLoopGroup: EventLoopGroup {
        self.eventLoopGroupContainer.value
    }

    public init(url: String, tls: Bool, defaultRequestTimeout: TimeAmount? = nil, eventLoopGroupProvider: EventLoopGroupProvider = .createNew, logger: Logger? = nil) {
        self.url = url
        self.defaultRequestTimeout = defaultRequestTimeout ?? .milliseconds(500)

        let eventLoopGroupContainer: EventLoopGroupContainer
        switch eventLoopGroupProvider {
        case .createNew:
            eventLoopGroupContainer = (value: MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount), managed: true)
        case .shared(let eventLoopGroup):
            eventLoopGroupContainer = (value: eventLoopGroup, managed: false)
        }
        self.eventLoopGroupContainer = eventLoopGroupContainer

        var clientConfig = HTTPClient.Configuration()
        if tls {
            clientConfig.tlsConfiguration = .clientDefault
        }
        let client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroupContainer.value), configuration: clientConfig)
        self.clientContainer = (value: client, managed: true)

        self.logger = logger ?? Logger(label: "PackageRegistryClient")
        self.encoder = JSONEncoder()
    }

    public init(url: String, defaultRequestTimeout: TimeAmount? = nil, client: HTTPClient, logger: Logger? = nil) {
        self.url = url
        self.defaultRequestTimeout = defaultRequestTimeout ?? .milliseconds(500)
        self.eventLoopGroupContainer = (value: client.eventLoopGroup, managed: false)
        self.clientContainer = (value: client, managed: false)
        self.logger = logger ?? Logger(label: "PackageRegistryClient")
        self.encoder = JSONEncoder()
    }

    public func syncShutdown() throws {
        if !self.isShutdown.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
            return
        }

        var lastError: Swift.Error?
        if self.clientContainer.managed {
            do {
                try self.httpClient.syncShutdown()
            } catch {
                lastError = error
            }
        }
        if self.eventLoopGroupContainer.managed {
            do {
                try self.eventLoopGroup.syncShutdownGracefully()
            } catch {
                lastError = error
            }
        }
        if let error = lastError {
            throw error
        }
    }

    /// 4.6 `PUT /{scope}/{name}/{version}` - create a package release
    ///
    /// - Parameters:
    ///   - scope: Package scope. Must match regex pattern in 3.6.1.
    ///   - name: Package name. Must match regex pattern in 3.6.2.
    ///   - version: Package release version. Must be semver.
    ///   - sourceArchive: Source archive bytes. The archive must be generated using the `swift package archive-source` tool.
    ///                    The server will then use the `swift package compute-checksum` tool to compute the checksum.
    ///   - metadataJSON: Optional JSON-encoded metadata for the package release. See server documentation for the supported format.
    ///   - deadline: The deadline by which the request must complete or else would result in timed out error.
    ///
    /// - Todo: support authentication
    public func createPackageRelease(scope: String,
                                     name: String,
                                     version: String,
                                     sourceArchive: Data,
                                     metadataJSON: Data? = nil,
                                     headers: HTTPHeaders? = nil,
                                     deadline: NIODeadline? = nil) -> EventLoopFuture<HTTPClient.Response> {
        guard !sourceArchive.isEmpty else {
            return self.eventLoopGroup.next().makeFailedFuture(PackageRegistryClientError.emptySourceArchive)
        }

        let sourceArchivePart = """
        Content-Disposition: form-data; name="source-archive"\r
        Content-Type: application/zip\r
        Content-Transfer-Encoding: base64\r
        Content-Length: \(sourceArchive.count)\r
        \r
        \(sourceArchive.base64EncodedString())\r
        """

        var metadataJSONString: String!
        if let metadataJSON = metadataJSON {
            metadataJSONString = String(data: metadataJSON, encoding: .utf8)
            guard metadataJSONString != nil else {
                self.logger.warning("Failed to convert metadata to JSON string")
                return self.eventLoopGroup.next().makeFailedFuture(PackageRegistryClientError.invalidMetadata)
            }
        } else {
            metadataJSONString = "{}"
        }

        let metadataPart = """
        Content-Disposition: form-data; name="metadata"\r
        Content-Type: application/json\r
        Content-Transfer-Encoding: quoted-printable\r
        Content-Length: \(metadataJSONString.map(\.count) ?? 0)\r
        \r
        \(metadataJSONString!)\r
        """

        let requestBodyString = """
        --boundary\r
        \(sourceArchivePart)
        --boundary\r
        \(metadataPart)
        --boundary--\r\n
        """

        guard let requestBodyData = requestBodyString.data(using: .utf8) else {
            return self.eventLoopGroup.next().makeFailedFuture(PackageRegistryClientError.invalidRequestBody)
        }

        var headers = headers ?? HTTPHeaders()
        headers.replaceOrAdd(name: "Accept", value: "application/vnd.swift.registry.v1+json")
        headers.replaceOrAdd(name: "Content-Type", value: "multipart/form-data;boundary=\"boundary\"")
        headers.replaceOrAdd(name: "Content-Length", value: "\(requestBodyData.count)")
        headers.replaceOrAdd(name: "Expect", value: "100-continue")

        let requestBody = HTTPClient.Body.data(requestBodyData)
        let url = "\(self.url)/\(scope)/\(name)/\(version)"

        do {
            let request = try HTTPClient.Request(url: url, method: .PUT, headers: headers, body: requestBody)
            return self.httpClient.execute(request: request, deadline: deadline ?? (NIODeadline.now() + self.defaultRequestTimeout))
        } catch {
            self.logger.warning("Failed to create request: \(error)")
            return self.eventLoopGroup.next().makeFailedFuture(PackageRegistryClientError.invalidRequest)
        }
    }

    public func createPackageRelease(scope: String,
                                     name: String,
                                     version: String,
                                     sourceArchive: Data,
                                     metadataJSON: String? = nil,
                                     deadline: NIODeadline? = nil) -> EventLoopFuture<HTTPClient.Response> {
        let metadataJSON = metadataJSON.flatMap { $0.data(using: .utf8) }
        return self.createPackageRelease(scope: scope, name: name, version: version, sourceArchive: sourceArchive,
                                         metadataJSON: metadataJSON, deadline: deadline)
    }

    public func createPackageRelease<Metadata: Codable>(scope: String,
                                                        name: String,
                                                        version: String,
                                                        sourceArchive: Data,
                                                        metadata: Metadata? = nil,
                                                        deadline: NIODeadline? = nil) -> EventLoopFuture<HTTPClient.Response> {
        do {
            let metadataJSON = try metadata.map { try self.encoder.encode($0) }
            return self.createPackageRelease(scope: scope, name: name, version: version, sourceArchive: sourceArchive,
                                             metadataJSON: metadataJSON, deadline: deadline)
        } catch {
            self.logger.warning("Failed to encode metadata \(String(describing: metadata)): \(error)")
            return self.eventLoopGroup.next().makeFailedFuture(PackageRegistryClientError.invalidMetadata)
        }
    }

    public enum EventLoopGroupProvider {
        case shared(EventLoopGroup)
        case createNew
    }
}

public enum PackageRegistryClientError: Error {
    case emptySourceArchive
    case invalidMetadata
    case invalidRequestBody
    case invalidRequest
}
