//
//  MCPLifecycleService.swift
//  Felix
//
//  Created by Nikolai Nobadi on 1/21/26.
//

import MCP
import ServiceLifecycle

struct MCPLifecycleService: Service {
    let server: Server
    let transport: any Transport

    func run() async throws {
        try await withGracefulShutdownHandler {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } onGracefulShutdown: {
            Task {
                await server.stop()
            }
        }
    }
}
