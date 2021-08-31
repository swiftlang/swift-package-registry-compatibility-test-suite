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

import TSCBasic

// FIXME: need @unchecked for `Lock`
struct TestLog: @unchecked Sendable, CustomStringConvertible {
    private var testCases: [TestCase]

    private let lock = Lock()

    var failures: [TestCase] {
        self.lock.withLock {
            self.testCases.filter { !$0.errors.isEmpty }
        }
    }

    var warnings: [TestCase] {
        self.lock.withLock {
            self.testCases.filter { !$0.warnings.isEmpty }
        }
    }

    var summary: String {
        let failed = self.failures.count
        let warnings = self.warnings.count

        if failed == 0, warnings == 0 {
            return "All tests passed."
        }
        return "\(failed) test cases failed. \(warnings) with warnings."
    }

    init() {
        self.testCases = []
    }

    mutating func append(_ testCase: TestCase) {
        var testCase = testCase
        testCase.end()
        self.lock.withLock {
            self.testCases.append(testCase)
        }
    }

    var description: String {
        self.lock.withLock {
            self.testCases.map { "\($0)\n" }.joined(separator: "\n")
        }
    }
}

// Not thread-safe
struct TestCase: Sendable, CustomStringConvertible {
    let name: String
    private var testPoints: [TestPoint]
    private var currentTestPoint: String?

    var errors: [TestPoint] {
        self.testPoints.filter {
            if case .error = $0.result {
                return true
            }
            return false
        }
    }

    var warnings: [TestPoint] {
        self.testPoints.filter {
            if case .warning = $0.result {
                return true
            }
            return false
        }
    }

    var count: Int {
        self.testPoints.count
    }

    init(name: String, body: (inout TestCase) async throws -> Void) async {
        self.name = name
        self.testPoints = []

        do {
            try await body(&self)
        } catch {
            self.error(error)
        }
    }

    mutating func mark(_ testPoint: String) {
        // Close the current test point before starting another
        self.endCurrentIfAny()
        self.currentTestPoint = testPoint
    }

    mutating func error(_ message: String) {
        guard let currentTestPoint = self.currentTestPoint else {
            preconditionFailure("'mark' method must be called before calling 'error'!")
        }
        self.testPoints.append(TestPoint(purpose: currentTestPoint, result: .error(message)))
        self.currentTestPoint = nil
    }

    mutating func error(_ error: Error) {
        if let testError = error as? TestError {
            self.error(testError.message)
        } else {
            self.error("\(error)")
        }
    }

    mutating func warning(_ message: String) {
        guard let currentTestPoint = self.currentTestPoint else {
            preconditionFailure("'mark' method must be called before calling 'warning'!")
        }
        self.testPoints.append(TestPoint(purpose: currentTestPoint, result: .warning(message)))
        self.currentTestPoint = nil
    }

    private mutating func endCurrentIfAny() {
        if let currentTestPoint = self.currentTestPoint {
            // Errors and warnings require calling `error` and `warning` methods explicitly, which also
            // reset `currentTestPoint`, so here we can assume the test point was ok.
            self.testPoints.append(TestPoint(purpose: currentTestPoint, result: .ok))
            self.currentTestPoint = nil
        }
    }

    mutating func end() {
        self.endCurrentIfAny()
    }

    var description: String {
        let errors = self.errors
        let warnings = self.warnings
        let testPoints = self.testPoints

        return """
        Test case: \(self.name)
        \(testPoints.map { "  \($0)" }.joined(separator: "\n"))
        \(errors.isEmpty ? "Passed" : "Failed \(errors.count)/\(testPoints.count) tests")\(warnings.isEmpty ? "" : " with \(warnings.count) warnings")
        """
    }
}

struct TestPoint: Sendable, CustomStringConvertible {
    let purpose: String
    let result: TestPointResult

    var description: String {
        switch self.result {
        case .ok:
            return "OK - \(self.purpose)"
        case .error(let message):
            return "Error - \(self.purpose): \(message)"
        case .warning(let message):
            return "Warning - \(self.purpose): \(message)"
        }
    }
}

enum TestPointResult: Sendable, Equatable {
    case ok
    case warning(String)
    case error(String)
}
