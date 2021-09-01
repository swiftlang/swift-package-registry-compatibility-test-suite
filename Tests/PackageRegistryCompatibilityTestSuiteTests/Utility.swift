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

import XCTest

import ArgumentParser
import NIO
import PackageRegistryClient
import PackageRegistryModels
import TSCBasic

// From TSCTestSupport
func systemQuietly(_ args: [String]) throws {
    // Discard the output, by default.
    try Process.checkNonZeroExit(arguments: args)
}

// From https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParserTestHelpers/TestHelpers.swift with modifications
extension XCTest {
    var debugURL: URL {
        let bundleURL = Bundle(for: type(of: self)).bundleURL
        return bundleURL.lastPathComponent.hasSuffix("xctest")
            ? bundleURL.deletingLastPathComponent()
            : bundleURL
    }

    func executeCommand(
        command: String,
        exitCode: ExitCode = .success,
        file: StaticString = #file, line: UInt = #line
    ) throws -> (stdout: String, stderr: String) {
        let splitCommand = command.split(separator: " ")
        let arguments = splitCommand.dropFirst().map(String.init)

        let commandName = String(splitCommand.first!)
        let commandURL = self.debugURL.appendingPathComponent(commandName)
        guard (try? commandURL.checkResourceIsReachable()) ?? false else {
            throw CommandExecutionError.executableNotFound(commandURL.standardizedFileURL.path)
        }

        let process = Process()
        process.executableURL = commandURL
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        let error = Pipe()
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let outputActual = String(data: outputData, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)

        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let errorActual = String(data: errorData, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(process.terminationStatus, exitCode.rawValue, file: file, line: line)

        return (outputActual, errorActual)
    }

    enum CommandExecutionError: Error {
        case executableNotFound(String)
    }
}

extension XCTestCase {
    var registryURL: String {
        let host = ProcessInfo.processInfo.environment["API_SERVER_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["API_SERVER_PORT"].flatMap(Int.init) ?? 9229
        return "http://\(host):\(port)"
    }

    func executeCommand(subcommand: String, configPath: String, generateData: Bool) throws -> (stdout: String, stderr: String) {
        return try self.executeCommand(command: "package-registry-compatibility \(subcommand) \(self.registryURL) \(configPath) --allow-http \(generateData ? "--generate-data" : "")")
    }

    func fixturePath(subdirectory: String = "CompatibilityTestSuite", filename: String) -> String {
        self.fixtureURL(subdirectory: subdirectory, filename: filename).path
    }

    func fixtureURL(subdirectory: String = "CompatibilityTestSuite", filename: String) -> URL {
        URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(filename)
    }

    func createPackageReleases(scope: String, name: String, versions: [String], client: PackageRegistryClient, sourceArchives: [SourceArchiveMetadata]) {
        runAsyncAndWaitFor({
            for version in versions {
                guard let archiveMetadata = sourceArchives.first(where: { $0.name == name && $0.version == version }) else {
                    throw StringError(message: "Source archive for version \(version) not found")
                }

                let archiveURL = self.fixtureURL(subdirectory: "SourceArchives", filename: archiveMetadata.filename)
                let archive = try Data(contentsOf: archiveURL)
                let repositoryURL = archiveMetadata.repositoryURL.replacingOccurrences(of: archiveMetadata.scope, with: scope)
                let metadata = PackageReleaseMetadata(repositoryURL: repositoryURL, commitHash: archiveMetadata.commitHash)

                let response = try await client.createPackageRelease(scope: scope,
                                                                     name: name,
                                                                     version: version,
                                                                     sourceArchive: archive,
                                                                     metadata: metadata,
                                                                     deadline: NIODeadline.now() + .seconds(20))
                XCTAssertEqual(.created, response.status)
            }
        }, TimeInterval(versions.count * 20))
    }
}

private extension XCTestCase {
    // TODO: remove once XCTest supports async functions
    func runAsyncAndWaitFor(_ closure: @escaping () async throws -> Void, _ timeout: TimeInterval = 10.0) {
        let finished = expectation(description: "finished")
        Task.detached {
            try await closure()
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)
    }
}

struct SourceArchiveMetadata: Codable {
    let scope: String
    let name: String
    let version: String
    let repositoryURL: String
    let commitHash: String
    let checksum: String

    var filename: String {
        "\(self.name)@\(self.version).zip"
    }
}

struct StringError: Error {
    let message: String
}
