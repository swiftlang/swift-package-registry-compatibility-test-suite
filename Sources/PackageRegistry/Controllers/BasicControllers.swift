//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPackageRegistryCompatibilityTestSuite open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftPackageRegistryCompatibilityTestSuite project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPackageRegistryCompatibilityTestSuite project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Vapor

struct HealthController {
    // GET /__health
    func health(_: Request) -> Response {
        Response(status: .ok)
    }
}

struct InfoController {
    // GET /
    func info(_: Request) -> Response {
        let addresses = (try? System.enumerateDevices()) ?? []
        let banner = """
        Package Registry Service
        Addresses: \(addresses.map(\.address))
        """
        return Response(status: .ok, body: .init(string: banner))
    }
}
