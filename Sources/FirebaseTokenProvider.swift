//
//  File.swift
//  MTAuthHelper
//
//  Created by Armstrong Liu on 21/03/2026.
//

import Foundation
@preconcurrency import FirebaseAuth

@MainActor
public protocol FirebaseTokenProviderProtocol {
    func idToken(from user: User) async throws -> String
}

public final class FirebaseTokenProvider: FirebaseTokenProviderProtocol {
    public init() {}

    public func idToken(from user: User) async throws -> String {
        try await user.getIDToken()
    }
}
