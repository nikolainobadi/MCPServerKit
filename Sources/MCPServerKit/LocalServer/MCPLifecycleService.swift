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
        try await server.start(transport: transport)
        try await server.notify(ToolListChangedNotification.message())
        try await server.notify(ResourceListChangedNotification.message())
        try await server.notify(PromptListChangedNotification.message())
        await server.waitUntilCompleted()
    }

    func shutdown() async throws {
        await server.stop()
    }
}
