# RemoteMCPServer Implementation Plan

## MCPServerKit — Adding HTTP Transport for Remote MCP Serving

**Date:** 2026-02-09
**Package:** MCPServerKit (`/Users/nelix/Desktop/mystuff/FelixGroup/MCPServerKit`)
**Goal:** Add `RemoteMCPServer` alongside `LocalMCPServer`, enabling MCP servers to be hosted remotely over HTTP using the MCP Streamable HTTP transport specification.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [What Changes vs What Stays](#2-what-changes-vs-what-stays)
3. [New Dependencies](#3-new-dependencies)
4. [Package.swift Changes](#4-packageswift-changes)
5. [New File Structure](#5-new-file-structure)
6. [HTTPServerTransport — The Core Implementation](#6-httpservertransport--the-core-implementation)
7. [RemoteMCPServer — The Public API](#7-remotemcpserver--the-public-api)
8. [Extracting Shared Server Logic](#8-extracting-shared-server-logic)
9. [The Correlation Mechanism — Routing send() Back to HTTP Responses](#9-the-correlation-mechanism)
10. [Session Management](#10-session-management)
11. [SSE Streaming](#11-sse-streaming)
12. [Error Handling](#12-error-handling)
13. [Testing Strategy](#13-testing-strategy)
14. [Implementation Order](#14-implementation-order)
15. [Consumer Migration (iGetGroceriesMCPServer)](#15-consumer-migration)
16. [Dockerfile Template](#16-dockerfile-template)
17. [Open Questions](#17-open-questions)

---

## 1. Architecture Overview

### Current Architecture (LocalMCPServer)

```
Consumer Code
    │
    ▼
LocalMCPServer
    │  - Creates Server (swift-sdk)
    │  - Registers features via Registrars
    │  - Creates StdioTransport (hardcoded)
    │  - Wraps in MCPLifecycleService
    │  - Runs via ServiceGroup
    ▼
StdioTransport ←→ Server (swift-sdk)
    │
    ▼
stdin/stdout ←→ MCP Client (Claude Desktop spawns as subprocess)
```

### Target Architecture (RemoteMCPServer)

```
Consumer Code
    │
    ▼
RemoteMCPServer
    │  - Creates Server (swift-sdk)
    │  - Registers features via Registrars (same as Local)
    │  - Creates HTTPServerTransport (NEW)
    │  - Wraps in MCPLifecycleService (same)
    │  - Runs via ServiceGroup (same)
    ▼
HTTPServerTransport ←→ Server (swift-sdk)
    │
    │  (internally runs Hummingbird HTTP server)
    │
    ▼
HTTP POST/GET/DELETE on :port/mcp ←→ MCP Client (Claude Code, Claude Desktop via mcp-remote)
```

### Key Insight

`MCPLifecycleService` already accepts `any Transport`. The entire registration pipeline (ToolRegistrar, ResourceRegistrar, PromptRegistrar) is transport-agnostic. The only thing that changes is which `Transport` is created in the `start()` method.

---

## 2. What Changes vs What Stays

### Stays Exactly The Same
- `FeatureModule`, `FeatureCapability` — composition model
- `ToolHandler`, `MCPToolDescriptor`, `ToolModule`, `ToolModuleAdapter` — tool stack
- `ResourceModule`, `MCPResourceDescriptor` — resource stack
- `PromptModule`, `MCPPromptDescriptor` — prompt stack
- `ToolRegistrar`, `ResourceRegistrar`, `PromptRegistrar` — registration pipeline
- `ToolError`, `ToolErrorConvertible`, `ToolHandlerHelpers` — error handling
- `Schema` — JSON schema builder
- `MCPLifecycleService` — lifecycle wrapper (already accepts `any Transport`)
- `Exports.swift` — re-exports

### New Files
- `HTTPServerTransport` — custom Transport actor for HTTP
- `RemoteMCPServer` — public API class (parallel to LocalMCPServer)
- Shared server logic extraction (optional refactor)

### Modified Files
- `Package.swift` — add Hummingbird dependency
- `LocalMCPServer` — optionally extract shared logic into a base

---

## 3. New Dependencies

### Hummingbird (HTTP Server)

- **Package:** `https://github.com/hummingbird-project/hummingbird.git`
- **Version:** `from: "2.0.0"` (current: 2.20.0)
- **Product:** `Hummingbird`
- **Why:** Lightweight, async-first Swift HTTP server. Standard choice for server-side Swift. Built on SwiftNIO.
- **Alternatives considered:**
  - **Vapor** — heavier, more opinionated, larger dependency tree
  - **Raw SwiftNIO** — too low-level, would need to implement HTTP parsing
  - **Foundation URLSession server** — doesn't exist

### SSE Support

Two options:

**Option A: Use SSEKit**
- **Package:** `https://github.com/orlandos-nl/SSEKit.git`
- **Version:** `from: "1.1.0"`
- **Why:** Provides `ServerSentEvent` struct with proper SSE formatting (`makeBuffer()`)
- **Cost:** One additional small dependency

**Option B: Manual SSE formatting**
- SSE format is simple: `data: {json}\n\n`
- Can be done with string formatting, no extra dependency
- Loses edge-case handling (multiline data, event types, IDs)

**Recommendation:** Start with Option B (manual SSE) to minimize dependencies. SSE format is trivial for our use case. Upgrade to SSEKit later if needed.

---

## 4. Package.swift Changes

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MCPServerKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MCPServerKit",
            targets: ["MCPServerKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),
        // NEW:
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "MCPServerKit",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                // NEW:
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .testTarget(
            name: "MCPServerKitTests",
            dependencies: [
                "MCPServerKit",
                // NEW (for testing):
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
```

### Consideration: Conditional Dependency

If you want consumers who only use `LocalMCPServer` to avoid pulling in Hummingbird, you could split into two targets:

```swift
products: [
    .library(name: "MCPServerKit", targets: ["MCPServerKit"]),
    .library(name: "MCPServerKitRemote", targets: ["MCPServerKitRemote"]),
],
targets: [
    .target(name: "MCPServerKit", dependencies: ["MCP", "ServiceLifecycle"]),
    .target(name: "MCPServerKitRemote", dependencies: ["MCPServerKit", "Hummingbird"]),
]
```

**Recommendation:** Start simple — single target with Hummingbird included. Split later if dependency size becomes a concern. Hummingbird is lightweight compared to Vapor.

---

## 5. New File Structure

```
Sources/MCPServerKit/
├── LocalServer/
│   ├── LocalMCPServer.swift           (existing, unchanged or minimal refactor)
│   └── MCPLifecycleService.swift      (existing, unchanged)
├── RemoteServer/                       ← NEW DIRECTORY
│   ├── RemoteMCPServer.swift          ← NEW: Public API
│   ├── HTTPServerTransport.swift      ← NEW: Transport actor
│   ├── SessionManager.swift           ← NEW: Session ID management
│   └── SSEWriter.swift                ← NEW: SSE formatting helper
├── Feature/                            (unchanged)
├── Tool/                               (unchanged)
├── Resource/                           (unchanged)
├── Prompt/                             (unchanged)
├── Registar/                           (unchanged)
├── Schema/                             (unchanged)
└── Exports.swift                       (unchanged)
```

---

## 6. HTTPServerTransport — The Core Implementation

This is the most complex piece. It bridges Hummingbird's request/response model to the MCP `Transport` protocol's stream model.

### Protocol Requirements

```swift
public protocol Transport: Actor {
    var logger: Logger { get }
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
    func receive() -> AsyncThrowingStream<Data, Swift.Error>
}
```

### Design

```swift
public actor HTTPServerTransport: Transport {
    // MARK: - Transport Protocol
    public nonisolated let logger: Logger

    // The stream that Server reads from
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    // MARK: - HTTP State
    private let port: Int
    private let host: String
    private let path: String  // e.g., "/mcp"

    // MARK: - Correlation (see Section 9)
    private var pendingRequests: [JSONRPCId: CheckedContinuation<Data, any Error>] = [:]

    // MARK: - SSE State (see Section 11)
    private var sseWriter: ResponseBodyWriter? = nil

    // MARK: - Session (see Section 10)
    private let sessionManager: SessionManager

    // MARK: - Hummingbird
    private var applicationTask: Task<Void, any Error>?
}
```

### connect()

```swift
public func connect() async throws {
    // 1. Build Hummingbird router with POST/GET/DELETE handlers
    // 2. Create Application
    // 3. Start application in a background Task
    // 4. Wait for the server to be ready (listening)

    let router = buildRouter()
    let app = Application(
        router: router,
        configuration: .init(address: .hostname(host, port: port))
    )

    applicationTask = Task {
        try await app.run()
    }

    // Brief delay or readiness check to ensure server is listening
    // (Hummingbird provides onServerRunning callback)
}
```

### disconnect()

```swift
public func disconnect() async {
    // 1. Close any open SSE writers
    // 2. Cancel all pending request continuations
    // 3. Stop Hummingbird application
    // 4. Finish the message stream

    if let writer = sseWriter {
        try? await writer.finish(nil)
        sseWriter = nil
    }

    for (id, continuation) in pendingRequests {
        continuation.resume(throwing: CancellationError())
    }
    pendingRequests.removeAll()

    applicationTask?.cancel()
    messageContinuation.finish()
}
```

### receive()

```swift
public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
    return messageStream
}
```

Simple — returns the pre-made stream. Data is fed in by the POST handler.

### send()

This is the complex one — see Section 9 for the full correlation mechanism.

```swift
public func send(_ data: Data) async throws {
    // 1. Parse just enough JSON to determine message type
    // 2. If it's a response (has "id" + "result"/"error"):
    //    → Find and resume the pending request continuation
    // 3. If it's a notification or server request:
    //    → Write to the SSE stream (if open)
    //    → Otherwise drop/buffer (spec says MAY)

    let messageType = classifyMessage(data)

    switch messageType {
    case .response(let id):
        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            logger.warning("No pending request for response ID \(id)")
            return
        }
        continuation.resume(returning: data)

    case .notification, .request:
        if let writer = sseWriter {
            let sseEvent = formatSSE(data: data)
            try await writer.write(sseEvent)
        }
    }
}
```

### buildRouter() — HTTP Route Handlers

```swift
private func buildRouter() -> Router<some RequestContext> {
    let router = Router(context: BasicRequestContext.self)

    // POST /mcp — Client sends JSON-RPC messages
    router.post(path) { [weak self] request, context -> Response in
        guard let self else { throw HTTPError(.serviceUnavailable) }
        return try await self.handlePost(request: request, context: context)
    }

    // GET /mcp — Client opens SSE stream for server-initiated messages
    router.get(path) { [weak self] request, context -> Response in
        guard let self else { throw HTTPError(.serviceUnavailable) }
        return try await self.handleGet(request: request, context: context)
    }

    // DELETE /mcp — Client terminates session
    router.delete(path) { [weak self] request, context -> Response in
        guard let self else { throw HTTPError(.serviceUnavailable) }
        return try await self.handleDelete(request: request, context: context)
    }

    return router
}
```

### handlePost() — The Main Handler

```swift
private func handlePost(request: Request, context: BasicRequestContext) async throws -> Response {
    // 1. Validate session (if session exists)
    try sessionManager.validate(request: request)

    // 2. Read request body
    let body = try await request.body.collect(upTo: 1_048_576) // 1MB limit
    let data = Data(buffer: body)

    // 3. Classify the incoming message(s)
    let classification = classifyIncoming(data)

    switch classification {
    case .notificationsOnly:
        // No response expected — yield to server, return 202
        messageContinuation.yield(data)
        return Response(status: .accepted)

    case .singleRequest(let id):
        // Yield to server, wait for response via continuation
        let responseData = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            messageContinuation.yield(data)
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        sessionManager.addSessionHeader(to: &headers)

        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: responseData))
        )

    case .batch(let ids):
        // More complex — collect all responses, return as batch
        // See Section 9 for batch handling
        ...
    }
}
```

### handleGet() — SSE Stream

```swift
private func handleGet(request: Request, context: BasicRequestContext) async throws -> Response {
    // 1. Validate session
    try sessionManager.validate(request: request)

    // 2. Validate Accept header
    guard request.headers[.accept]?.contains("text/event-stream") == true else {
        return Response(status: .badRequest)
    }

    // 3. Return SSE stream response
    var headers = HTTPFields()
    headers[.contentType] = "text/event-stream"
    headers[.cacheControl] = "no-cache"
    headers[values: "Connection"] = "keep-alive"
    sessionManager.addSessionHeader(to: &headers)

    return Response(
        status: .ok,
        headers: headers,
        body: .init { writer in
            // Store writer for send() to use
            self.sseWriter = writer

            // Keep the stream open until disconnect or client closes
            // This will block until the writer is finished
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.sseStreamContinuation = continuation
            }
        }
    )
}
```

### handleDelete() — Session Termination

```swift
private func handleDelete(request: Request, context: BasicRequestContext) async throws -> Response {
    try sessionManager.validate(request: request)
    sessionManager.terminate()

    // Close SSE stream if open
    if let writer = sseWriter {
        try await writer.finish(nil)
        sseWriter = nil
    }

    return Response(status: .ok)
}
```

---

## 7. RemoteMCPServer — The Public API

The consumer-facing class. Mirrors `LocalMCPServer` but uses `HTTPServerTransport`.

```swift
public final class RemoteMCPServer {
    private let server: Server
    private let features: [FeatureModule]
    private let port: Int
    private let host: String
    private let path: String

    public init(
        name: String,
        version: String,
        instructions: String? = nil,
        strictConfig: Bool = false,
        features: [FeatureModule],
        port: Int = 8000,
        host: String = "0.0.0.0",  // Listen on all interfaces (for Docker)
        path: String = "/mcp"
    ) {
        self.server = .init(
            name: name,
            version: version,
            instructions: instructions,
            capabilities: .init(
                logging: .init(),
                prompts: .init(listChanged: true),
                resources: .init(listChanged: true),
                sampling: .init(),
                tools: .init(listChanged: true)
            ),
            configuration: strictConfig ? .strict : .default
        )
        self.features = features
        self.port = port
        self.host = host
        self.path = path
    }

    public func start() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "com.nobadi.Felix.remote")

        // Create HTTP transport instead of Stdio
        let transport = HTTPServerTransport(
            host: host,
            port: port,
            path: path,
            logger: logger
        )

        // Register all features (identical to LocalMCPServer)
        await ToolRegistrar.register(modules: features.flatMap(\.tools), on: server)
        await ResourceRegistrar.register(modules: features.flatMap(\.resources), on: server)
        await PromptRegistrar.register(modules: features.flatMap(\.prompts), on: server)

        // Wrap in lifecycle service (identical to LocalMCPServer)
        let mcpService = MCPLifecycleService(server: server, transport: transport)

        let serviceConfig = ServiceGroupConfiguration.ServiceConfiguration(
            service: mcpService,
            successTerminationBehavior: .gracefullyShutdownGroup,
            failureTerminationBehavior: .gracefullyShutdownGroup
        )
        let groupConfig = ServiceGroupConfiguration(
            services: [serviceConfig],
            gracefulShutdownSignals: [.sigint, .sigterm],
            cancellationSignals: [],
            logger: logger
        )
        let group = ServiceGroup(configuration: groupConfig)

        fputs("Remote MCP server listening on http://\(host):\(port)\(path)\n", stderr)
        try await group.run()
    }
}
```

---

## 8. Extracting Shared Server Logic (Optional Refactor)

`RemoteMCPServer.start()` and `LocalMCPServer.start()` share ~80% of their code. Consider extracting:

```swift
// Internal helper (not public API)
enum MCPServerBootstrap {
    static func configureServer(
        _ server: Server,
        features: [FeatureModule],
        transport: any Transport,
        loggerLabel: String
    ) async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: loggerLabel)

        await ToolRegistrar.register(modules: features.flatMap(\.tools), on: server)
        await ResourceRegistrar.register(modules: features.flatMap(\.resources), on: server)
        await PromptRegistrar.register(modules: features.flatMap(\.prompts), on: server)

        let mcpService = MCPLifecycleService(server: server, transport: transport)

        let serviceConfig = ServiceGroupConfiguration.ServiceConfiguration(
            service: mcpService,
            successTerminationBehavior: .gracefullyShutdownGroup,
            failureTerminationBehavior: .gracefullyShutdownGroup
        )
        let groupConfig = ServiceGroupConfiguration(
            services: [serviceConfig],
            gracefulShutdownSignals: [.sigint, .sigterm],
            cancellationSignals: [],
            logger: logger
        )
        let group = ServiceGroup(configuration: groupConfig)
        try await group.run()
    }
}
```

Then both `LocalMCPServer.start()` and `RemoteMCPServer.start()` become thin wrappers that create their transport and call the shared bootstrap.

**Recommendation:** Do this refactor. It prevents drift between the two server types and makes testing the shared logic easier.

---

## 9. The Correlation Mechanism — Routing send() Back to HTTP Responses

This is the hardest design problem. The MCP `Server` calls `transport.send(data)` with no context about which HTTP request the response belongs to. We must figure it out from the JSON-RPC message content.

### JSON-RPC Message Types

| Type | Has `id`? | Has `method`? | Has `result`/`error`? | Direction |
|------|-----------|---------------|----------------------|-----------|
| Request | Yes | Yes | No | Client→Server or Server→Client |
| Response | Yes | No | Yes | Server→Client (response to request) |
| Notification | No | Yes | No | Either direction |

### The ID Type

JSON-RPC IDs can be strings or numbers. The swift-sdk uses `RequestID` (which is `Value` — could be `.string` or `.int`). We need a hashable wrapper:

```swift
enum JSONRPCId: Hashable {
    case string(String)
    case int(Int)

    init?(_ value: Any) {
        // Parse from JSON
    }
}
```

### Lightweight JSON Classification

We don't need full JSON decoding — just extract top-level fields:

```swift
struct MessageClassification {
    enum Kind {
        case response(JSONRPCId)
        case request(JSONRPCId)
        case notification
        case batch([MessageClassification])
    }
}

func classifyMessage(_ data: Data) -> MessageClassification.Kind {
    // Use JSONSerialization for lightweight top-level parsing
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        // Could be a batch (array)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return .batch(array.map { classifySingle($0) })
        }
        return .notification // fallback
    }
    return classifySingle(json)
}

private func classifySingle(_ json: [String: Any]) -> MessageClassification.Kind {
    let hasId = json["id"] != nil
    let hasMethod = json["method"] != nil
    let hasResult = json["result"] != nil || json["error"] != nil

    if hasId && hasResult {
        return .response(extractId(json["id"]!))
    } else if hasId && hasMethod {
        return .request(extractId(json["id"]!))
    } else {
        return .notification
    }
}
```

### Full send() Flow

```
Server calls transport.send(data)
    │
    ▼
classifyMessage(data)
    │
    ├── .response(id) ──→ pendingRequests[id]?.resume(returning: data)
    │                      Remove from pendingRequests
    │
    ├── .notification ──→ sseWriter?.write(formatSSE(data))
    │                      (drop if no SSE stream open)
    │
    ├── .request(id) ───→ sseWriter?.write(formatSSE(data))
    │                      (server-initiated request to client)
    │
    └── .batch([...]) ──→ Process each element recursively
```

### Timeout Handling

If the MCP Server never responds (bug, crash), the pending continuation would hang forever, and the HTTP client would timeout. Add a safety timeout:

```swift
let responseData = try await withThrowingTaskGroup(of: Data.self) { group in
    group.addTask {
        try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation
            self.messageContinuation.yield(data)
        }
    }
    group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw HTTPServerTransportError.requestTimeout
    }
    let result = try await group.next()!
    group.cancelAll()
    return result
}
```

### Batch Handling

For batch requests (array of JSON-RPC messages), the transport must:

1. Extract all request IDs from the batch
2. Register a continuation for each
3. Yield the entire batch as one `Data` to the receive stream
4. Collect all responses as they come back via `send()`
5. Return them as a JSON array in the HTTP response

This adds complexity. A simpler initial approach: **only support single requests per POST** and return 400 for batch requests. Add batch support in a later version.

---

## 10. Session Management

### SessionManager

```swift
actor SessionManager {
    private var sessionId: String?
    private var isTerminated = false

    func getOrCreateSessionId() -> String {
        if let existing = sessionId {
            return existing
        }
        let new = UUID().uuidString
        sessionId = new
        return new
    }

    func validate(request: Request) throws {
        guard !isTerminated else {
            throw HTTPError(.notFound) // Session terminated
        }

        // If we have a session, require it on all non-initialization requests
        if let expected = sessionId {
            let provided = request.headers[values: "Mcp-Session-Id"].first
            guard provided == expected else {
                throw HTTPError(.badRequest) // Missing or wrong session ID
            }
        }
    }

    func addSessionHeader(to headers: inout HTTPFields) {
        if let id = sessionId {
            headers[values: "Mcp-Session-Id"] = id
        }
    }

    func terminate() {
        isTerminated = true
        sessionId = nil
    }
}
```

### When Session ID is Created

The spec says the server MAY assign a session ID during the `InitializeResult` response. The transport should assign it on the first POST response (which will be the initialize handshake).

---

## 11. SSE Streaming

### SSE Format (Manual — No SSEKit Dependency)

```swift
enum SSEFormatter {
    static func format(data: Data, id: String? = nil, event: String? = nil) -> ByteBuffer {
        var output = ""

        if let event {
            output += "event: \(event)\n"
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            // SSE requires splitting multiline data
            for line in jsonString.split(separator: "\n", omittingEmptySubsequences: false) {
                output += "data: \(line)\n"
            }
        }

        if let id {
            output += "id: \(id)\n"
        }

        output += "\n" // Empty line terminates the event

        return ByteBuffer(string: output)
    }
}
```

### When SSE is Used

1. **POST response streaming (optional):** Instead of returning a single JSON response, the server could return `Content-Type: text/event-stream` and send multiple events. For simplicity, start with single JSON responses.

2. **GET SSE stream (server-initiated):** The client opens a long-lived GET connection. The transport holds the writer and sends server-initiated notifications/requests through it.

### Keepalive

To prevent proxy timeouts (Cloudflare's ~100s idle timeout), send periodic SSE comments:

```swift
// In the GET handler's writer closure
Task {
    while !Task.isCancelled {
        try await Task.sleep(for: .seconds(30))
        try await writer.write(ByteBuffer(string: ": keepalive\n\n"))
    }
}
```

---

## 12. Error Handling

### Transport-Level Errors

```swift
enum HTTPServerTransportError: Error {
    case requestTimeout
    case invalidSessionId
    case sessionTerminated
    case invalidContentType
    case payloadTooLarge
    case serverNotReady
}
```

### HTTP Status Codes

| Scenario | Status Code |
|----------|-------------|
| Successful response | 200 OK |
| Notification only (no response) | 202 Accepted |
| Invalid/missing session ID | 400 Bad Request |
| Missing Accept header on GET | 400 Bad Request |
| Session terminated | 404 Not Found |
| GET not supported (if we skip it initially) | 405 Method Not Allowed |
| Payload too large | 413 Content Too Large |
| Internal error | 500 Internal Server Error |

---

## 13. Testing Strategy

### Unit Tests

1. **Message Classification Tests**
   - Classify single request, response, notification
   - Classify batch messages
   - Handle malformed JSON gracefully
   - Extract string and int IDs

2. **SSE Formatting Tests**
   - Single-line data
   - Multi-line data
   - With/without event type
   - With/without ID
   - Keepalive comment format

3. **Session Management Tests**
   - Session ID generation
   - Validation of correct session ID
   - Rejection of wrong session ID
   - Termination behavior

### Integration Tests (using HummingbirdTesting)

4. **POST Handler Tests**
   - Send a JSON-RPC request, receive a response
   - Send a notification, receive 202
   - Send with wrong session ID, receive 400
   - Send oversized payload, receive 413

5. **Full Round-Trip Tests**
   - Create HTTPServerTransport + Server
   - Register a simple tool handler
   - Send HTTP POST with tool call
   - Verify correct JSON-RPC response

6. **GET SSE Stream Tests**
   - Open GET, verify SSE headers
   - Verify keepalive comments arrive
   - Verify server-initiated notifications arrive on stream

### End-to-End Tests

7. **HTTPClientTransport ↔ HTTPServerTransport**
   - Use the swift-sdk's `HTTPClientTransport` as the client
   - Use `HTTPServerTransport` as the server
   - Full MCP handshake (initialize, list tools, call tool)
   - This validates spec compliance

---

## 14. Implementation Order

### Phase 1: Minimal Viable Transport (MVP)

**Goal:** POST-only, single requests, no SSE, no session management. Get a tool call working over HTTP.

1. **Add Hummingbird to Package.swift**
2. **Create `HTTPServerTransport` with:**
   - `connect()` — starts Hummingbird
   - `disconnect()` — stops Hummingbird
   - `receive()` — returns the stream
   - `send()` — routes responses to pending continuations
   - `handlePost()` — accepts JSON-RPC, yields to stream, waits for response
   - Message classification (response vs notification)
   - Correlation via `pendingRequests` dictionary
3. **Create `RemoteMCPServer` with:**
   - Same init as LocalMCPServer + port/host/path params
   - `start()` using HTTPServerTransport
4. **Write basic integration test:**
   - Register a tool, send POST, verify response

**Estimated scope:** ~4 files, ~300-400 lines of new code.

### Phase 2: Session Management

5. **Add `SessionManager`**
6. **Add session ID to POST responses**
7. **Validate session on incoming requests**
8. **Handle DELETE for session termination**

**Estimated scope:** ~1 file, ~80 lines.

### Phase 3: GET SSE Stream

9. **Add `handleGet()` with SSE response**
10. **Route server-initiated messages to SSE writer in `send()`**
11. **Add keepalive timer**

**Estimated scope:** ~100 lines added to HTTPServerTransport.

### Phase 4: Hardening

12. **Add SSE formatting helper**
13. **Add timeout handling for pending requests**
14. **Add payload size limits**
15. **Add CORS headers** (configurable)
16. **Batch request support** (optional)
17. **Refactor shared logic between Local and Remote**

### Phase 5: Testing

18. **Unit tests for classification, SSE, session**
19. **Integration tests with HummingbirdTesting**
20. **End-to-end test with HTTPClientTransport**

---

## 15. Consumer Migration (iGetGroceriesMCPServer)

### Before (Local/stdio)

```swift
@main
struct iGetGroceriesMCPServer {
    static func main() async throws {
        let dataSource = try await makeDataSource()
        let features = makeFeatures(dataSource: dataSource)
        let launcher = LocalMCPServer(
            name: "iGetGroceriesMCPServer",
            version: "0.1.0",
            features: features
        )
        try await launcher.start()
    }
}
```

### After (Remote/HTTP)

```swift
@main
struct iGetGroceriesMCPServer {
    static func main() async throws {
        let dataSource = try await makeDataSource()
        let features = makeFeatures(dataSource: dataSource)

        let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8000") ?? 8000

        let launcher = RemoteMCPServer(
            name: "iGetGroceriesMCPServer",
            version: "0.1.0",
            features: features,
            port: port
        )
        try await launcher.start()
    }
}
```

**Changes:**
- `LocalMCPServer` → `RemoteMCPServer`
- Add `port` parameter (read from `PORT` env var for cloud platforms)
- Everything else (features, data source, auth) is identical

### Supporting Both Modes

If you want the same binary to support both local and remote:

```swift
let mode = ProcessInfo.processInfo.environment["MCP_TRANSPORT"] ?? "stdio"

switch mode {
case "http":
    let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8000") ?? 8000
    let launcher = RemoteMCPServer(
        name: "iGetGroceriesMCPServer", version: "0.1.0",
        features: features, port: port
    )
    try await launcher.start()
default:
    let launcher = LocalMCPServer(
        name: "iGetGroceriesMCPServer", version: "0.1.0",
        features: features
    )
    try await launcher.start()
}
```

---

## 16. Dockerfile Template

With RemoteMCPServer, the Dockerfile is clean — just Swift:

```dockerfile
# Stage 1: Build
FROM swift:6.0-noble AS builder
WORKDIR /build
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources/ Sources/
RUN swift build -c release

# Stage 2: Runtime
FROM swift:6.0-noble-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/.build/release/iGetGroceriesMCPServer /app/
WORKDIR /app
EXPOSE 8000

ENV PORT=8000
ENV MCP_TRANSPORT=http
ENTRYPOINT ["/app/iGetGroceriesMCPServer"]
```

No Node.js. No supergateway. Single Swift binary.

---

## 17. Open Questions

### Q1: Hummingbird Lifecycle Integration

Hummingbird has its own `Application.run()` lifecycle. We're also using `ServiceGroup.run()` from ServiceLifecycle. These need to coexist. Options:
- Run Hummingbird in a background `Task` inside `connect()` (simplest)
- Make Hummingbird a `Service` in the same `ServiceGroup` (cleanest)
- Need to verify that both can share signal handling gracefully

### Q2: Actor Isolation and Hummingbird Route Handlers

The transport is an `actor`. Hummingbird route handlers are `@Sendable` closures. The closures need to call into the actor to yield data and register continuations. This should work via `await self.someMethod()` but needs careful attention to avoid deadlocks.

### Q3: Linux Compatibility

Hummingbird works on Linux. The swift-sdk `Transport` protocol works on Linux. But the consuming app (`iGetGroceriesMCPServer`) needs `#if canImport(FoundationNetworking)` for URLSession on Linux. This is a consumer-side fix, not an MCPServerKit issue.

### Q4: Multiple Concurrent Clients

The current design supports one session at a time (matching `LocalMCPServer`'s single-client model). For multi-client support, each session would need its own `Server` instance and correlation state. This is a future enhancement.

### Q5: Batch Request Support

The MCP spec allows batch JSON-RPC messages. Phase 1 skips this. When added later, the correlation mechanism needs to track multiple IDs per POST and collect all responses before sending the HTTP response.

### Q6: Platform Constraint

MCPServerKit currently requires macOS 15+. For Docker/Linux deployment, the Package.swift platform constraint may need adjustment. SPM ignores `.platforms` on Linux, but it's worth making the constraint accurate (e.g., adding a note or conditional).

---

## Summary

The implementation adds ~500-700 lines of new code across 4-5 files, with zero changes to existing tool/resource/prompt infrastructure. The hardest piece is the correlation mechanism in `send()`, but the design (pending continuations keyed by JSON-RPC ID) is well-understood and testable. Phase 1 (MVP) gets a working remote server with ~300-400 lines. Phases 2-5 add production hardening.

The consumer (iGetGroceriesMCPServer) changes one line: `LocalMCPServer` → `RemoteMCPServer`.
