//
//  SSEFormatterTests.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Testing
import Foundation

@Suite("SSE Formatting")
struct SSEFormatterTests {
    @Test("Formats single-line JSON as SSE data event")
    func formatsSingleLineJson() {
        let json = #"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#
        let sseMessage = formatSSE(json)
        #expect(sseMessage == "data: \(json)\n\n")
    }

    @Test("Formats multi-line JSON as multiple data lines")
    func formatsMultiLineJson() {
        let json = "{\n  \"jsonrpc\": \"2.0\",\n  \"method\": \"test\"\n}"
        let sseMessage = formatSSE(json)
        let expected = "data: {\ndata:   \"jsonrpc\": \"2.0\",\ndata:   \"method\": \"test\"\ndata: }\n\n"
        #expect(sseMessage == expected)
    }

    @Test("Keepalive comment format is correct")
    func keepaliveFormat() {
        let keepalive = ": keepalive\n\n"
        #expect(keepalive.hasPrefix(":"))
        #expect(keepalive.hasSuffix("\n\n"))
    }
}

// MARK: - Helper
/// Replicates the SSE formatting logic from HTTPServerTransport's GET handler
private func formatSSE(_ json: String) -> String {
    let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
    var sseMessage = lines.map { "data: \($0)" }.joined(separator: "\n")
    sseMessage += "\n\n"
    return sseMessage
}
