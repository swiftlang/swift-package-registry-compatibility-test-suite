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
import Atomics
import TSCBasic

private let defaultAPIVersion = "1"

// FIXME: put @main here when ArgumentParser supports async/await
// Currently @main is in PackageRegistryCompatibilityTestSuiteAsyncMain
struct PackageRegistryCompatibilityTestSuite: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "package-registry-compatibility",
        abstract: "Compatibility test suite for Swift Package Registry (SE-0292, SE-0321)",
        version: "0.0.1",
        subcommands: [
            CreatePackageRelease.self,
            ListPackageReleases.self,
            FetchPackageReleaseInfo.self,
            All.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    /// Command for testing the "create package release" API
    struct CreatePackageRelease: AsyncParsableCommand {
        @Argument(help: "Package registry URL")
        var url: String

        @Argument(help: "Path to the test configuration file")
        var configPath: String

        @Option(help: """
        Authentication token in the format of <type>:<token> where <type> is one of basic, bearer, or token.
        The value of <token> varies depending on <type>. e.g., for basic authentication, <token> would be
        username:password (i.e., basic:username:password).
        """)
        var authToken: String?

        @Option(help: "Package registry API version. Defaults to version \(defaultAPIVersion).")
        var apiVersion: String?

        @Flag(name: .long, help: "Warn instead of error in case of non-HTTPS")
        var allowHTTP: Bool = false

        @Flag(name: .long, help: "Generate test data according to the configuration file")
        var generateData: Bool = false

        func run() async throws {
            try self.checkRegistryURL(self.url, allowHTTP: self.allowHTTP)
            print("")

            try await self.readConfigAndRunTests(configPath: self.configPath, generateData: self.generateData, test: self.run)
        }

        private func run(configuration: Configuration) async throws {
            guard var createPackageReleaseConfig = configuration.createPackageRelease else {
                throw TestError("Test configuration not found")
            }

            // Convert file paths in the configuration to absolute paths if needed
            try createPackageReleaseConfig.ensureAbsolutePaths(relativeTo: self.configPath)

            print("Running other test preparations...")
            let httpClient = makeHTTPClient()
            defer { try! httpClient.syncShutdown() }

            var testPlan = TestPlan(registryURL: self.url, authToken: self.authToken, apiVersion: self.apiVersion, httpClient: httpClient)
            testPlan.addStep(.createPackageRelease(createPackageReleaseConfig))
            try await testPlan.execute()
        }
    }

    /// Command for testing the "list package releases" API
    struct ListPackageReleases: AsyncParsableCommand {
        @Argument(help: "Package registry URL")
        var url: String

        @Argument(help: "Path to the test configuration file")
        var configPath: String

        @Option(help: """
        Authentication token in the format of <type>:<token> where <type> is one of basic, bearer, or token.
        The value of <token> varies depending on <type>. e.g., for basic authentication, <token> would be
        username:password (i.e., basic:username:password).
        """)
        var authToken: String?

        @Option(help: "Package registry API version. Defaults to version \(defaultAPIVersion).")
        var apiVersion: String?

        @Flag(name: .long, help: "Warn instead of error in case of non-HTTPS")
        var allowHTTP: Bool = false

        @Flag(name: .long, help: "Generate test data according to the configuration file")
        var generateData: Bool = false

        func run() async throws {
            try self.checkRegistryURL(self.url, allowHTTP: self.allowHTTP)
            print("")

            try await self.readConfigAndRunTests(configPath: self.configPath, generateData: self.generateData, test: self.run)
        }

        private func run(configuration: Configuration) async throws {
            var createPackageReleaseConfig = configuration.createPackageRelease
            if self.generateData, createPackageReleaseConfig == nil {
                throw TestError("\"createPackageRelease\" configuration is required when --generate-data is set")
            }

            // Convert file paths in the configuration to absolute paths if needed
            try createPackageReleaseConfig?.ensureAbsolutePaths(relativeTo: self.configPath)

            guard let listPackageReleasesConfig = configuration.listPackageReleases else {
                throw TestError("Test configuration not found")
            }

            print("Running other test preparations...")
            let httpClient = makeHTTPClient()
            defer { try! httpClient.syncShutdown() }

            var testPlan = TestPlan(registryURL: self.url, authToken: self.authToken, apiVersion: self.apiVersion, httpClient: httpClient)
            if self.generateData {
                testPlan.addStep(.createPackageRelease(createPackageReleaseConfig!), required: true) // !-safe since we check for nil above
            }
            testPlan.addStep(.listPackageReleases(listPackageReleasesConfig))
            try await testPlan.execute()
        }
    }

    /// Command for testing "fetch information about a package release" API
    struct FetchPackageReleaseInfo: AsyncParsableCommand {
        @Argument(help: "Package registry URL")
        var url: String

        @Argument(help: "Path to the test configuration file")
        var configPath: String

        @Option(help: """
        Authentication token in the format of <type>:<token> where <type> is one of basic, bearer, or token.
        The value of <token> varies depending on <type>. e.g., for basic authentication, <token> would be
        username:password (i.e., basic:username:password).
        """)
        var authToken: String?

        @Option(help: "Package registry API version. Defaults to version \(defaultAPIVersion).")
        var apiVersion: String?

        @Flag(name: .long, help: "Warn instead of error in case of non-HTTPS")
        var allowHTTP: Bool = false

        @Flag(name: .long, help: "Generate test data according to the configuration file")
        var generateData: Bool = false

        func run() async throws {
            try self.checkRegistryURL(self.url, allowHTTP: self.allowHTTP)
            print("")

            try await self.readConfigAndRunTests(configPath: self.configPath, generateData: self.generateData, test: self.run)
        }

        private func run(configuration: Configuration) async throws {
            var createPackageReleaseConfig = configuration.createPackageRelease
            if self.generateData, createPackageReleaseConfig == nil {
                throw TestError("\"createPackageRelease\" configuration is required when --generate-data is set")
            }

            // Convert file paths in the configuration to absolute paths if needed
            try createPackageReleaseConfig?.ensureAbsolutePaths(relativeTo: self.configPath)

            guard let fetchPackageReleaseInfoConfig = configuration.fetchPackageReleaseInfo else {
                throw TestError("Test configuration not found")
            }

            print("Running other test preparations...")
            let httpClient = makeHTTPClient()
            defer { try! httpClient.syncShutdown() }

            var testPlan = TestPlan(registryURL: self.url, authToken: self.authToken, apiVersion: self.apiVersion, httpClient: httpClient)
            if self.generateData {
                testPlan.addStep(.createPackageRelease(createPackageReleaseConfig!), required: true) // !-safe since we check for nil above
            }
            testPlan.addStep(.fetchPackageReleaseInfo(fetchPackageReleaseInfoConfig))

            try await testPlan.execute()
        }
    }

    /// Command for testing all registry APIs
    struct All: AsyncParsableCommand {
        @Argument(help: "Package registry URL")
        var url: String

        @Argument(help: "Path to the test configuration file")
        var configPath: String

        @Option(help: """
        Authentication token in the format of <type>:<token> where <type> is one of basic, bearer, or token.
        The value of <token> varies depending on <type>. e.g., for basic authentication, <token> would be
        username:password (i.e., basic:username:password).
        """)
        var authToken: String?

        @Option(help: "Package registry API version. Defaults to version \(defaultAPIVersion).")
        var apiVersion: String?

        @Flag(name: .long, help: "Warn instead of error in case of non-HTTPS")
        var allowHTTP: Bool = false

        @Flag(name: .long, help: "Generate test data according to the configuration file")
        var generateData: Bool = false

        func run() async throws {
            try self.checkRegistryURL(self.url, allowHTTP: self.allowHTTP)
            print("")

            try await self.readConfigAndRunTests(configPath: self.configPath, generateData: self.generateData, test: self.run)
        }

        private func run(configuration: Configuration) async throws {
            var createPackageReleaseConfig = configuration.createPackageRelease
            if self.generateData, createPackageReleaseConfig == nil {
                throw TestError("\"createPackageRelease\" configuration is required when --generate-data is set")
            }

            // Convert file paths in the configuration to absolute paths if needed
            try createPackageReleaseConfig?.ensureAbsolutePaths(relativeTo: self.configPath)

            guard let listPackageReleasesConfig = configuration.listPackageReleases,
                  let fetchPackageReleaseInfoConfig = configuration.fetchPackageReleaseInfo else {
                throw TestError("Test configuration not found")
            }

            print("Running other test preparations...")
            let httpClient = makeHTTPClient()
            defer { try! httpClient.syncShutdown() }

            var testPlan = TestPlan(registryURL: self.url, authToken: self.authToken, apiVersion: self.apiVersion, httpClient: httpClient)
            if let createPackageReleaseConfig = createPackageReleaseConfig {
                testPlan.addStep(.createPackageRelease(createPackageReleaseConfig), required: self.generateData)
            }
            testPlan.addStep(.listPackageReleases(listPackageReleasesConfig))
            testPlan.addStep(.fetchPackageReleaseInfo(fetchPackageReleaseInfoConfig))

            try await testPlan.execute()
        }
    }
}

extension PackageRegistryCompatibilityTestSuite {
    struct Configuration: Codable {
        let createPackageRelease: CreatePackageReleaseTests.Configuration?
        let listPackageReleases: ListPackageReleasesTests.Configuration?
        let fetchPackageReleaseInfo: FetchPackageReleaseInfoTests.Configuration?

        init(createPackageRelease: CreatePackageReleaseTests.Configuration? = nil,
             listPackageReleases: ListPackageReleasesTests.Configuration? = nil,
             fetchPackageReleaseInfo: FetchPackageReleaseInfoTests.Configuration? = nil) {
            self.createPackageRelease = createPackageRelease
            self.listPackageReleases = listPackageReleases
            self.fetchPackageReleaseInfo = fetchPackageReleaseInfo
        }
    }
}

extension PackageRegistryCompatibilityTestSuite {
    static func runCreatePackageRelease(registryURL: String,
                                        authToken: AuthenticationToken?,
                                        apiVersion: String,
                                        configuration: CreatePackageReleaseTests.Configuration,
                                        httpClient: HTTPClient) async -> TestLog {
        let test = CreatePackageReleaseTests(
            registryURL: registryURL,
            authToken: authToken,
            apiVersion: apiVersion,
            configuration: configuration,
            httpClient: httpClient
        )
        await test.run()
        return test.log
    }

    static func runListPackageReleases(registryURL: String,
                                       authToken: AuthenticationToken?,
                                       apiVersion: String,
                                       configuration: ListPackageReleasesTests.Configuration,
                                       httpClient: HTTPClient) async -> TestLog {
        let test = ListPackageReleasesTests(
            registryURL: registryURL,
            authToken: authToken,
            apiVersion: apiVersion,
            configuration: configuration,
            httpClient: httpClient
        )
        await test.run()
        return test.log
    }

    static func runFetchPackageReleaseInfo(registryURL: String,
                                           authToken: AuthenticationToken?,
                                           apiVersion: String,
                                           configuration: FetchPackageReleaseInfoTests.Configuration,
                                           httpClient: HTTPClient) async -> TestLog {
        let test = FetchPackageReleaseInfoTests(
            registryURL: registryURL,
            authToken: authToken,
            apiVersion: apiVersion,
            configuration: configuration,
            httpClient: httpClient
        )
        await test.run()
        return test.log
    }
}

// Not thread-safe
// FIXME: need @unchecked for `HTTPClient` and `ManagedAtomic`
private struct TestPlan: @unchecked Sendable {
    let registryURL: String
    let authToken: AuthenticationToken?
    let apiVersion: String
    let httpClient: HTTPClient

    private var steps = [Step]()

    private let isExecuting = ManagedAtomic<Bool>(false)

    init(registryURL: String, authToken: String?, apiVersion: String?, httpClient: HTTPClient) {
        self.registryURL = registryURL
        self.authToken = authToken.flatMap { AuthenticationToken(string: $0) }
        self.apiVersion = apiVersion ?? defaultAPIVersion
        self.httpClient = httpClient
    }

    mutating func addStep(_ step: Step) {
        guard !self.isExecuting.load(ordering: .acquiring) else {
            preconditionFailure("Cannot invoke 'addStep' after 'execute'")
        }
        self.steps.append(step)
    }

    mutating func addStep(_ test: TestType, required: Bool = false) {
        self.addStep(.init(test: test, required: required))
    }

    func execute() async throws {
        if !self.isExecuting.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
            throw TestError("Test plan is being executed")
        }

        var summaries = [String]()
        for step in self.steps {
            print("")
            print("------------------------------------------------------------")
            print(step.test.label)
            print("------------------------------------------------------------")
            print(" - Package registry URL: \(self.registryURL)")
            print(" - API version: \(self.apiVersion)")
            print("")

            let testLog: TestLog
            switch step.test {
            case .createPackageRelease(let configuration):
                testLog = await PackageRegistryCompatibilityTestSuite.runCreatePackageRelease(registryURL: self.registryURL,
                                                                                              authToken: self.authToken,
                                                                                              apiVersion: self.apiVersion,
                                                                                              configuration: configuration,
                                                                                              httpClient: self.httpClient)
            case .listPackageReleases(let configuration):
                testLog = await PackageRegistryCompatibilityTestSuite.runListPackageReleases(registryURL: self.registryURL,
                                                                                             authToken: self.authToken,
                                                                                             apiVersion: self.apiVersion,
                                                                                             configuration: configuration,
                                                                                             httpClient: self.httpClient)
            case .fetchPackageReleaseInfo(let configuration):
                testLog = await PackageRegistryCompatibilityTestSuite.runFetchPackageReleaseInfo(registryURL: self.registryURL,
                                                                                                 authToken: self.authToken,
                                                                                                 apiVersion: self.apiVersion,
                                                                                                 configuration: configuration,
                                                                                                 httpClient: self.httpClient)
            }

            summaries.append(testLog.summary)

            if step.required, !testLog.failures.isEmpty {
                print("Stopping tests because the required step \"\(step.test.label)\" has failed: \(testLog.summary)")
                break
            }
        }

        print("")
        print("Test summary:")
        self.steps.enumerated().forEach { index, step in
            let summary = index < summaries.count ? summaries[index] : "did not run"
            print("\(step.test.label) - \(summary)")
        }
    }

    struct Step: Sendable {
        let test: TestType
        /// If `true`, test runner will stop if this step has any errors
        let required: Bool

        init(test: TestType, required: Bool = false) {
            self.test = test
            self.required = required
        }
    }

    enum TestType: Sendable {
        case createPackageRelease(CreatePackageReleaseTests.Configuration)
        case listPackageReleases(ListPackageReleasesTests.Configuration)
        case fetchPackageReleaseInfo(FetchPackageReleaseInfoTests.Configuration)

        var label: String {
            switch self {
            case .createPackageRelease:
                return "Create Package Release"
            case .listPackageReleases:
                return "List Package Releases"
            case .fetchPackageReleaseInfo:
                return "Fetch Package Release Information"
            }
        }
    }
}

// MARK: - Helpers

private extension ParsableCommand {
    func checkRegistryURL(_ url: String, allowHTTP: Bool) throws {
        print("Checking package registry URL...")
        if url.hasPrefix("https://") {
            return
        }
        if allowHTTP, url.hasPrefix("http://") {
            return print("Warning: Package registry URL must be HTTPS")
        }
        throw TestError("Package registry URL must be HTTPS")
    }

    func makeHTTPClient(followRedirects: Bool = true, maxFollows: Int = 3) -> HTTPClient {
        var configuration = HTTPClient.Configuration()
        configuration.redirectConfiguration = followRedirects ? .follow(max: maxFollows, allowCycles: false) : .disallow
        return HTTPClient(eventLoopGroupProvider: .createNew, configuration: configuration)
    }

    func readConfigAndRunTests(configPath: String, generateData: Bool,
                               test: (PackageRegistryCompatibilityTestSuite.Configuration) async throws -> Void) async throws {
        print("Reading configuration file at \(configPath)")
        let configData: Data
        do {
            configData = try readData(at: configPath)
        } catch {
            throw TestError("Failed to read configuration file: \(error)")
        }

        if generateData {
            var generatorConfig: TestConfigurationGenerator.Configuration = try self.decodeConfiguration(configData)

            // Convert `resourceBaseDirectory` to absolute path if needed. The generator has logic to transform
            // other file paths in the configuration so there is no need to do that here.
            if let resourceBaseDirectory = generatorConfig.resourceBaseDirectory {
                do {
                    let configDirectory = AbsolutePath(URL(fileURLWithPath: configPath).path).parentDirectory
                    generatorConfig.resourceBaseDirectory = try makeAbsolutePath(resourceBaseDirectory, relativeTo: configDirectory).pathString
                } catch {
                    throw TestError("Invalid \"resourceBaseDirectory\": \(error)")
                }
            }

            let generator = TestConfigurationGenerator(fileSystem: localFileSystem)
            do {
                try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
                    let configuration = try generator.run(configuration: generatorConfig, tmpDir: tmpDir)
                    try await test(configuration)
                }
            } catch {
                if error is TestError {
                    throw error
                }
                throw TestError("Failed to create temporary directory: \(error)")
            }
        } else {
            let configuration: PackageRegistryCompatibilityTestSuite.Configuration = try self.decodeConfiguration(configData)
            try await test(configuration)
        }
    }

    private func decodeConfiguration<Configuration: Decodable>(_ data: Data) throws -> Configuration {
        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            throw TestError("Failed to decode configuration: \(error)")
        }
    }
}

extension CreatePackageReleaseTests.Configuration {
    mutating func ensureAbsolutePaths(relativeTo basePath: String) throws {
        do {
            let configDirectory = AbsolutePath(URL(fileURLWithPath: basePath).path).parentDirectory
            self.packageReleases = try self.packageReleases.map { release in
                let sourceArchivePath = try makeAbsolutePath(release.sourceArchivePath, relativeTo: configDirectory).pathString
                let metadataPath = try release.metadataPath.map { try makeAbsolutePath($0, relativeTo: configDirectory).pathString }
                return .init(package: release.package, version: release.version, sourceArchivePath: sourceArchivePath, metadataPath: metadataPath)
            }
        } catch {
            throw TestError("Invalid file path found in configuration: \(error)")
        }
    }
}
