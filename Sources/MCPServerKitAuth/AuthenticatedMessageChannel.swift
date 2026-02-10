//
//  AuthenticatedMessageChannel.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Foundation
import MCPServerKit

/// FIFO channel that pairs raw MCP message data with the authenticated user context.
///
/// The HTTP transport enqueues `(Data, AuthContext?)` when requests arrive.
/// The pull-based `AsyncThrowingStream(unfolding:)` dequeues them one at a time,
/// setting the auth context before the MCP Server processes each message.
actor AuthenticatedMessageChannel {
    private var buffer: [(Data, AuthContext?)] = []
    private var waiting: CheckedContinuation<(Data, AuthContext?)?, any Error>?
    private var isFinished = false

    /// Enqueue a message with its associated auth context.
    func send(_ data: Data, authContext: AuthContext?) {
        if let continuation = waiting {
            self.waiting = nil
            continuation.resume(returning: (data, authContext))
        } else {
            buffer.append((data, authContext))
        }
    }

    /// Dequeue the next message. Suspends if the buffer is empty.
    /// Returns `nil` when the channel is finished.
    func next() async throws -> (Data, AuthContext?)? {
        if !buffer.isEmpty {
            return buffer.removeFirst()
        }
        if isFinished { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
        }
    }

    /// Signal that no more messages will be sent.
    func finish() {
        isFinished = true
        if let continuation = waiting {
            self.waiting = nil
            continuation.resume(returning: nil)
        }
    }

    /// Signal an error and terminate the channel.
    func fail(_ error: any Error) {
        isFinished = true
        if let continuation = waiting {
            self.waiting = nil
            continuation.resume(throwing: error)
        }
    }
}
