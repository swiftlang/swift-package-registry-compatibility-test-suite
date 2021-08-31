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

import ArgumentParser
import TSCBasic

// MARK: - Argument parser

protocol AsyncParsableCommand: ParsableCommand {
    mutating func run() async throws
}

extension AsyncParsableCommand {
    mutating func run() async throws {
        throw CleanExit.helpRequest(self)
    }

    // Cannot define async main in AsyncParsableCommand because compiler
    // will confuse it with main in ParsableCommand
}

// FIXME: remove PackageRegistryCompatibilityTestSuiteAsyncMain and add @main
// to PackageRegistryCompatibilityTestSuite when ArgumentParser supports async/await
@main
enum PackageRegistryCompatibilityTestSuiteAsyncMain {
    static func main(_ arguments: [String]?) async {
        do {
            var command = try PackageRegistryCompatibilityTestSuite.parseAsRoot(arguments)
            if var command = command as? AsyncParsableCommand {
                try await command.run()
            } else {
                try command.run()
            }
        } catch {
            PackageRegistryCompatibilityTestSuite.exit(withError: error)
        }
    }

    static func main() async {
        await self.main(nil)
    }
}

// MARK: - TSC

func withTemporaryDirectory<Result>(dir: AbsolutePath? = nil,
                                    prefix: String = "TemporaryDirectory",
                                    removeTreeOnDeinit: Bool = false, _ body: (AbsolutePath) async throws -> Result) async throws -> Result {
    let tmpDir = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AbsolutePath, Error>) in
        do {
            try withTemporaryDirectory(dir: dir, prefix: prefix, removeTreeOnDeinit: false) { tmpDir in
                continuation.resume(returning: tmpDir)
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }

    defer {
        if removeTreeOnDeinit {
            _ = try? localFileSystem.removeFileTree(tmpDir)
        }
    }

    return try await body(tmpDir)
}
