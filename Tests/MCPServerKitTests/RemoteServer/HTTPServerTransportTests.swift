//
//  HTTPServerTransportTests.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import MCP
import Testing
import Foundation
@testable import MCPServerKit

@Suite("HTTPServerTransport Integration")
struct HTTPServerTransportTests {
    /// Creates a test MCP server connected to an HTTPServerTransport on the given port.
    /// Returns the transport (for inspection) and a Task running the server.
    private func startTestServer(port: Int) async throws -> (transport: HTTPServerTransport, serverTask: Task<Void, any Error>) {
        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )

        // Register a simple echo tool
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(name: "echo", description: "Echo tool", inputSchema: .object(["type": .string("object")]))
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            CallTool.Result(content: [.text("echo: \(params.name)")])
        }

        let transport = HTTPServerTransport(
            host: "127.0.0.1",
            port: port,
            path: "/mcp"
        )

        let serverTask = Task {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        }

        // Give the server a moment to start
        try await Task.sleep(for: .milliseconds(500))

        return (transport, serverTask)
    }

    /// Helper to make a JSON-RPC POST request
    private func postRequest(port: Int, json: String, sessionId: String? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = json.data(using: .utf8)

        if let sessionId {
            request.addValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    // MARK: - Initialize Handshake
    @Test("Full initialize handshake returns valid response with session ID")
    func initializeHandshake() async throws {
        let port = 18100
        let (transport, serverTask) = try await startTestServer(port: port)
        defer {
            serverTask.cancel()
            Task { await transport.disconnect() }
        }

        let initJson = """
        {"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}
        """

        let (data, response) = try await postRequest(port: port, json: initJson)

        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true)

        // Should have session ID
        let sessionId = response.value(forHTTPHeaderField: "Mcp-Session-Id")
        #expect(sessionId != nil)

        // Response should be valid JSON-RPC
        let responseJson = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(responseJson["id"] as? Int == 1)
        #expect(responseJson["result"] != nil)
    }

    // MARK: - List Tools
    @Test("List tools after initialize returns registered tools")
    func listToolsAfterInitialize() async throws {
        let port = 18101
        let (transport, serverTask) = try await startTestServer(port: port)
        defer {
            serverTask.cancel()
            Task { await transport.disconnect() }
        }

        // Initialize first
        let initJson = """
        {"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}
        """
        let (_, initResponse) = try await postRequest(port: port, json: initJson)
        let sessionId = initResponse.value(forHTTPHeaderField: "Mcp-Session-Id")

        // Send initialized notification
        let notifJson = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let (_, notifResponse) = try await postRequest(port: port, json: notifJson, sessionId: sessionId)
        #expect(notifResponse.statusCode == 202)

        // List tools
        let listJson = #"{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}"#
        let (data, response) = try await postRequest(port: port, json: listJson, sessionId: sessionId)

        #expect(response.statusCode == 200)

        let responseJson = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(responseJson["id"] as? Int == 2)

        let result = responseJson["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        #expect(tools?.first?["name"] as? String == "echo")
    }

    // MARK: - Notification Returns 202
    @Test("Notification POST returns 202 Accepted")
    func notificationReturns202() async throws {
        let port = 18102
        let (transport, serverTask) = try await startTestServer(port: port)
        defer {
            serverTask.cancel()
            Task { await transport.disconnect() }
        }

        let notifJson = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let (_, response) = try await postRequest(port: port, json: notifJson)

        #expect(response.statusCode == 202)
    }

    // MARK: - Wrong Content-Type
    @Test("POST with wrong Content-Type returns 415")
    func wrongContentTypeReturns415() async throws {
        let port = 18103
        let (transport, serverTask) = try await startTestServer(port: port)
        defer {
            serverTask.cancel()
            Task { await transport.disconnect() }
        }

        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = "hello".data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 415)
    }

    // MARK: - Session ID Validation
    @Test("POST with wrong session ID returns 400")
    func wrongSessionIdReturns400() async throws {
        let port = 18104
        let (transport, serverTask) = try await startTestServer(port: port)
        defer {
            serverTask.cancel()
            Task { await transport.disconnect() }
        }

        // Initialize to establish session
        let initJson = """
        {"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}
        """
        _ = try await postRequest(port: port, json: initJson)

        // Send request with wrong session ID
        let listJson = #"{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}"#
        let (_, response) = try await postRequest(port: port, json: listJson, sessionId: "wrong-session-id")

        #expect(response.statusCode == 400)
    }

    // MARK: - DELETE Session Termination
    @Test("DELETE terminates session and returns 200")
    func deleteTerminatesSession() async throws {
        let port = 18105
        let (transport, serverTask) = try await startTestServer(port: port)
        defer {
            serverTask.cancel()
            Task { await transport.disconnect() }
        }

        // Initialize to establish session
        let initJson = """
        {"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}
        """
        let (_, initResponse) = try await postRequest(port: port, json: initJson)
        let sessionId = initResponse.value(forHTTPHeaderField: "Mcp-Session-Id")!

        // DELETE session
        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")

        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 200)

        // Subsequent POST should return 404 (terminated)
        let listJson = #"{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}"#
        let (_, postResponse) = try await postRequest(port: port, json: listJson, sessionId: sessionId)
        #expect(postResponse.statusCode == 404)
    }
}
