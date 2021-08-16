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
