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

extension XCTest {
    func executeCommand(subcommand: String, generateData: Bool) throws -> (stdout: String, stderr: String) {
        let host = ProcessInfo.processInfo.environment["API_SERVER_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["API_SERVER_PORT"].flatMap(Int.init) ?? 9229
        let registryURL = "http://\(host):\(port)"

        let configPath = self.fixturePath(filename: generateData ? "gendata.json" : "local-registry.json")

        return try self.executeCommand(command: "package-registry-compatibility \(subcommand) \(registryURL) \(configPath) --allow-http \(generateData ? "--generate-data" : "")")
    }

    func fixturePath(filename: String) -> String {
        URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent("CompatibilityTestSuite", isDirectory: true)
            .appendingPathComponent(filename)
            .path
    }
}
