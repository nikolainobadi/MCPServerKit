//
//  MessageClassificationTests.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Testing
import Foundation
@testable import MCPServerKit

@Suite("Message Classification")
struct MessageClassificationTests {
    let transport = HTTPServerTransport()

    // MARK: - Incoming: Request
    @Test("Classifies JSON-RPC request with integer ID")
    func classifiesRequestWithIntId() async {
        let json = #"{"jsonrpc":"2.0","method":"tools/call","id":1,"params":{}}"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .request(id: "1"))
    }

    @Test("Classifies JSON-RPC request with string ID")
    func classifiesRequestWithStringId() async {
        let json = #"{"jsonrpc":"2.0","method":"initialize","id":"abc-123","params":{}}"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .request(id: "abc-123"))
    }

    // MARK: - Incoming: Notification
    @Test("Classifies JSON-RPC notification (no id)")
    func classifiesNotification() async {
        let json = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .notification)
    }

    // MARK: - Incoming: Batch
    @Test("Classifies batch with requests")
    func classifiesBatchWithRequests() async {
        let json = #"[{"jsonrpc":"2.0","method":"tools/list","id":1},{"jsonrpc":"2.0","method":"tools/call","id":2,"params":{}}]"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .batch(requestIds: ["1", "2"]))
    }

    @Test("Classifies batch with only notifications as notification")
    func classifiesBatchOfNotificationsAsNotification() async {
        let json = #"[{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","method":"notifications/progress"}]"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .notification)
    }

    @Test("Classifies batch with mixed requests and notifications")
    func classifiesMixedBatch() async {
        let json = #"[{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","method":"tools/list","id":5}]"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .batch(requestIds: ["5"]))
    }

    // MARK: - Incoming: Invalid
    @Test("Classifies invalid JSON as invalid")
    func classifiesInvalidJson() async {
        let data = "not json at all".data(using: .utf8)!
        let result = await transport.classifyIncoming(data)
        #expect(result == .invalid)
    }

    @Test("Classifies empty object as invalid")
    func classifiesEmptyObject() async {
        let json = #"{}"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .invalid)
    }

    // MARK: - Outgoing: Response
    @Test("Classifies outgoing response with result")
    func classifiesResponseWithResult() async {
        let json = #"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#
        let result = await transport.classifyOutgoing(json.data(using: .utf8)!)
        #expect(result == .response(id: "1"))
    }

    @Test("Classifies outgoing response with error")
    func classifiesResponseWithError() async {
        let json = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"Invalid"}}"#
        let result = await transport.classifyOutgoing(json.data(using: .utf8)!)
        #expect(result == .response(id: "2"))
    }

    // MARK: - Outgoing: Batch Response
    @Test("Classifies outgoing batch response")
    func classifiesBatchResponse() async {
        let json = #"[{"jsonrpc":"2.0","id":1,"result":{}},{"jsonrpc":"2.0","id":2,"result":{}}]"#
        let result = await transport.classifyOutgoing(json.data(using: .utf8)!)
        #expect(result == .batchResponse(ids: ["1", "2"]))
    }

    // MARK: - Outgoing: Notification
    @Test("Classifies outgoing notification")
    func classifiesOutgoingNotification() async {
        let json = #"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#
        let result = await transport.classifyOutgoing(json.data(using: .utf8)!)
        #expect(result == .notification)
    }

    // MARK: - Outgoing: Server Request
    @Test("Classifies outgoing server request (has id + method)")
    func classifiesServerRequest() async {
        let json = #"{"jsonrpc":"2.0","method":"sampling/createMessage","id":99,"params":{}}"#
        let result = await transport.classifyOutgoing(json.data(using: .utf8)!)
        #expect(result == .serverRequest)
    }

    // MARK: - ID Stringification
    @Test("Stringifies integer ID from JSON")
    func stringifiesIntegerId() async {
        let json = #"{"jsonrpc":"2.0","method":"test","id":42,"params":{}}"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .request(id: "42"))
    }

    @Test("Stringifies string ID from JSON")
    func stringifiesStringId() async {
        let json = #"{"jsonrpc":"2.0","method":"test","id":"request-uuid","params":{}}"#
        let result = await transport.classifyIncoming(json.data(using: .utf8)!)
        #expect(result == .request(id: "request-uuid"))
    }
}
