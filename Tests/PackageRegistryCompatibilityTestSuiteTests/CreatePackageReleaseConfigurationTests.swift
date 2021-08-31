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
import XCTest

@testable import PackageRegistryCompatibilityTestSuite

final class CreatePackageReleaseConfigurationTests: XCTestCase {
    func testMaxProcessingTimeInSeconds_defaultIfUnspecified() throws {
        // The JSON key `maxProcessingTimeInSeconds` is missing, so default value should be used.
        let json = """
        {
            "packageReleases": []
        }
        """

        guard let data = json.data(using: .utf8) else {
            return XCTFail("Invalid JSON: \(json)")
        }

        let configuration = try JSONDecoder().decode(CreatePackageReleaseTests.Configuration.self, from: data)
        XCTAssertEqual(DecodableDefault.Sources.MaxPublicationTimeInSeconds.defaultValue, configuration.maxProcessingTimeInSeconds)
    }

    func testMaxProcessingTimeInSeconds_doNotDefaultIfSpecified() throws {
        // Set `maxProcessingTimeInSeconds` to some value other than the default
        let expectedValue = DecodableDefault.Sources.MaxPublicationTimeInSeconds.defaultValue + 6
        let json = """
        {
            "packageReleases": [],
            "maxProcessingTimeInSeconds": \(expectedValue)
        }
        """

        guard let data = json.data(using: .utf8) else {
            return XCTFail("Invalid JSON: \(json)")
        }

        let configuration = try JSONDecoder().decode(CreatePackageReleaseTests.Configuration.self, from: data)
        XCTAssertEqual(expectedValue, configuration.maxProcessingTimeInSeconds)
    }

    func testGeneratorConfig_maxProcessingTimeInSeconds_defaultIfUnspecified() throws {
        // The JSON key `maxProcessingTimeInSeconds` is missing, so default value should be used.
        let json = "{}"

        guard let data = json.data(using: .utf8) else {
            return XCTFail("Invalid JSON: \(json)")
        }

        let configuration = try JSONDecoder().decode(TestConfigurationGenerator.Configuration.CreatePackageRelease.self, from: data)
        XCTAssertEqual(DecodableDefault.Sources.MaxPublicationTimeInSeconds.defaultValue, configuration.maxProcessingTimeInSeconds)
    }

    func testGeneratorConfig_maxProcessingTimeInSeconds_doNotDefaultIfSpecified() throws {
        // Set `maxProcessingTimeInSeconds` to some value other than the default
        let expectedValue = DecodableDefault.Sources.MaxPublicationTimeInSeconds.defaultValue + 6
        let json = """
        {
            "packageReleases": [],
            "maxProcessingTimeInSeconds": \(expectedValue)
        }
        """

        guard let data = json.data(using: .utf8) else {
            return XCTFail("Invalid JSON: \(json)")
        }

        let configuration = try JSONDecoder().decode(TestConfigurationGenerator.Configuration.CreatePackageRelease.self, from: data)
        XCTAssertEqual(expectedValue, configuration.maxProcessingTimeInSeconds)
    }
}
