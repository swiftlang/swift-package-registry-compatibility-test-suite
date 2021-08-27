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

@testable import PackageRegistryCompatibilityTestSuite

final class UtilityTests: XCTestCase {
    func testStringFlipcased() {
        XCTAssertEqual("ABC", "abc".flipcased)
        XCTAssertEqual("abc", "ABC".flipcased)
        XCTAssertEqual("aBc", "AbC".flipcased)
        XCTAssertEqual("578", "578".flipcased)
        XCTAssertEqual("ABc5-d", "abC5-D".flipcased)
    }
}
