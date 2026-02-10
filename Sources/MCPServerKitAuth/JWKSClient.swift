//
//  JWKSClient.swift
//  MCPServerKitAuth
//
//  Created by Nikolai Nobadi on 2/10/26.
//

import Foundation
import JWTKit

/// Fetches and caches JWKS (JSON Web Key Sets) from the authorization server.
///
/// Keys are cached for the configured TTL and automatically refreshed on expiry.
/// If a token's `kid` is not found in the cached keys, a refresh is attempted once
/// before returning an error (handles key rotation).
public actor JWKSClient {
    private let jwksURL: URL
    private let cacheTTL: Duration
    private var cachedKeys: JWKS?
    private var lastFetch: ContinuousClock.Instant?

    public init(jwksURL: URL, cacheTTL: Duration = .seconds(3600)) {
        self.jwksURL = jwksURL
        self.cacheTTL = cacheTTL
    }

    /// Returns the current JWKS, fetching from the authorization server if needed.
    public func getKeys() async throws -> JWKS {
        if let cachedKeys, let lastFetch, ContinuousClock.now - lastFetch < cacheTTL {
            return cachedKeys
        }

        return try await fetchKeys()
    }

    /// Forces a refresh of the JWKS keys (e.g. on `kid` miss).
    public func refreshKeys() async throws -> JWKS {
        return try await fetchKeys()
    }

    private func fetchKeys() async throws -> JWKS {
        let (data, response) = try await URLSession.shared.data(from: jwksURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw JWKSError.fetchFailed(url: jwksURL)
        }

        let keys = try JSONDecoder().decode(JWKS.self, from: data)
        self.cachedKeys = keys
        self.lastFetch = ContinuousClock.now
        return keys
    }
}

// MARK: - Errors
public enum JWKSError: Error, Sendable {
    case fetchFailed(url: URL)
}
