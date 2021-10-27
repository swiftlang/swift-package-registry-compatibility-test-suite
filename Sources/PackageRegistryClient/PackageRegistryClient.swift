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
import NIOCore
import NIOHTTP1

public struct PackageRegistryClient {
    private typealias HTTPClientContainer = (value: HTTPClient, managed: Bool)

    private let httpClientContainer: HTTPClientContainer
    private let configuration: Configuration

    private let encoder: JSONEncoder
    private let logger: Logger

    private let isShutdown = ManagedAtomic<Bool>(false)

    public var url: String {
        self.configuration.url
    }

    public var httpClient: HTTPClient {
        self.httpClientContainer.value
    }

    public init(httpClientProvider: HTTPClientProvider = .createNew, configuration: Configuration, logger: Logger? = nil) {
        let httpClientContainer: HTTPClientContainer
        switch httpClientProvider {
        case .createNew:
            httpClientContainer = (value: HTTPClient(eventLoopGroupProvider: .createNew), managed: true)
        case .shared(let httpClient):
            httpClientContainer = (value: httpClient, managed: false)
        }

        self.httpClientContainer = httpClientContainer
        self.configuration = configuration
        self.encoder = JSONEncoder()
        self.logger = logger ?? Logger(label: "PackageRegistryClient")
    }

    public func syncShutdown() throws {
        if !self.isShutdown.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
            return
        }

        var lastError: Swift.Error?
        if self.httpClientContainer.managed {
            do {
                try self.httpClient.syncShutdown()
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
    ///   - headers: Optional HTTP headers. Authentication token should be supplied via this.
    ///   - deadline: The deadline by which the request must complete or else would result in timed out error.
    public func createPackageRelease(scope: String,
                                     name: String,
                                     version: String,
                                     sourceArchive: Data,
                                     metadataJSON: Data? = nil,
                                     headers: HTTPHeaders? = nil,
                                     deadline: NIODeadline? = nil) async throws -> HTTPClient.Response {
        guard !sourceArchive.isEmpty else {
            throw PackageRegistryClientError.emptySourceArchive
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
                throw PackageRegistryClientError.invalidMetadata
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
            throw PackageRegistryClientError.invalidRequestBody
        }

        var headers = headers ?? HTTPHeaders()
        headers.replaceOrAdd(name: "Accept", value: "application/vnd.swift.registry.v1+json")
        headers.replaceOrAdd(name: "Content-Type", value: "multipart/form-data;boundary=\"boundary\"")
        headers.replaceOrAdd(name: "Content-Length", value: "\(requestBodyData.count)")
        headers.replaceOrAdd(name: "Expect", value: "100-continue")

        let requestBody = HTTPClient.Body.data(requestBodyData)
        let url = "\(self.configuration.url)/\(scope)/\(name)/\(version)"

        let request: HTTPClient.Request
        do {
            request = try HTTPClient.Request(url: url, method: .PUT, headers: headers, body: requestBody)
        } catch {
            self.logger.warning("Failed to create request: \(error)")
            throw PackageRegistryClientError.invalidRequest
        }

        return try await self.httpClient.execute(request: request, deadline: deadline ?? (NIODeadline.now() + self.configuration.defaultRequestTimeout)).get()
    }

    public func createPackageRelease(scope: String,
                                     name: String,
                                     version: String,
                                     sourceArchive: Data,
                                     metadataJSON: String? = nil,
                                     headers: HTTPHeaders? = nil,
                                     deadline: NIODeadline? = nil) async throws -> HTTPClient.Response {
        let metadataJSON = metadataJSON.flatMap { $0.data(using: .utf8) }
        return try await self.createPackageRelease(scope: scope, name: name, version: version, sourceArchive: sourceArchive,
                                                   metadataJSON: metadataJSON, headers: headers, deadline: deadline)
    }

    public func createPackageRelease<Metadata: Codable>(scope: String,
                                                        name: String,
                                                        version: String,
                                                        sourceArchive: Data,
                                                        metadata: Metadata? = nil,
                                                        headers: HTTPHeaders? = nil,
                                                        deadline: NIODeadline? = nil) async throws -> HTTPClient.Response {
        let metadataJSON: Data?
        do {
            metadataJSON = try metadata.map { try self.encoder.encode($0) }
        } catch {
            self.logger.warning("Failed to encode metadata \(String(describing: metadata)): \(error)")
            throw PackageRegistryClientError.invalidMetadata
        }

        return try await self.createPackageRelease(scope: scope, name: name, version: version, sourceArchive: sourceArchive,
                                                   metadataJSON: metadataJSON, headers: headers, deadline: deadline)
    }

    public enum HTTPClientProvider {
        case shared(HTTPClient)
        case createNew
    }

    public struct Configuration {
        public var url: String
        public var defaultRequestTimeout: TimeAmount

        public init(url: String, defaultRequestTimeout: TimeAmount? = nil) {
            self.url = url
            self.defaultRequestTimeout = defaultRequestTimeout ?? .milliseconds(500)
        }
    }
}

public enum PackageRegistryClientError: Error {
    case emptySourceArchive
    case invalidMetadata
    case invalidRequestBody
    case invalidRequest
}
