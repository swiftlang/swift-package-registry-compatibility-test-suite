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

struct TestLog: CustomStringConvertible {
    var testCases: [TestCase]

    var failures: [TestCase] {
        self.testCases.filter { !$0.errors.isEmpty }
    }

    var warnings: [TestCase] {
        self.testCases.filter { !$0.warnings.isEmpty }
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

    var description: String {
        self.testCases.map { "\($0)\n" }.joined(separator: "\n")
    }
}

struct TestCase: CustomStringConvertible {
    let name: String
    var testPoints: [TestPoint]
    var currentTestPoint: String?

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

    init(name: String) {
        self.name = name
        self.testPoints = []
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

    mutating func endCurrentIfAny() {
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

        return """
        Test case: \(self.name)
        \(self.testPoints.map { "  \($0)" }.joined(separator: "\n"))
        \(errors.isEmpty ? "Passed" : "Failed \(errors.count)/\(self.testPoints.count) tests")\(warnings.isEmpty ? "" : " with \(warnings.count) warnings")
        """
    }
}

struct TestPoint: CustomStringConvertible {
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

enum TestPointResult: Equatable {
    case ok
    case warning(String)
    case error(String)
}
