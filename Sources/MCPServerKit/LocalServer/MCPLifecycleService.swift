//
//  MCPLifecycleService.swift
//  Felix
//
//  Created by Nikolai Nobadi on 1/21/26.
//

import MCP
import ServiceLifecycle

public struct MCPLifecycleService: Service {
    public let server: Server
    public let transport: any Transport

    public init(server: Server, transport: any Transport) {
        self.server = server
        self.transport = transport
    }

    public func run() async throws {
        try await server.start(transport: transport)
        try await server.notify(ToolListChangedNotification.message())
        try await server.notify(ResourceListChangedNotification.message())
        try await server.notify(PromptListChangedNotification.message())
        await server.waitUntilCompleted()
    }

    public func shutdown() async throws {
        await server.stop()
    }
}
