import MCP
import ServiceLifecycle

struct MCPLifecycleService: Service {
    let server: Server
    let transport: any Transport

    func run() async throws {
        try await withGracefulShutdownHandler {
            try await server.start(transport: transport)
            try await server.notify(ToolListChangedNotification.message())
            try await server.notify(ResourceListChangedNotification.message())
            try await server.notify(PromptListChangedNotification.message())

            await server.waitUntilCompleted()
        } onGracefulShutdown: {
            Task {
                await server.stop()
            }
        }
    }
}
