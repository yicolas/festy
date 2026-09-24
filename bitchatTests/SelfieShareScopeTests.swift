//
// SelfieShareScopeTests.swift
// bitchatTests
//

import Testing
import Foundation
@testable import bitchat

struct NostrPubkeyFormatTests {
    // NIP-19 reference vector.
    private let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
    private let hex = "7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e"

    @Test
    func npub_decodesToHex() {
        #expect(NostrPubkeyFormat.hex(npub) == hex)
    }

    @Test
    func hex_isLowercasedPassthrough() {
        #expect(NostrPubkeyFormat.hex(hex.uppercased()) == hex)
    }

    @Test
    func invalid_returnsNil() {
        #expect(NostrPubkeyFormat.hex("") == nil)
        #expect(NostrPubkeyFormat.hex("npub1notvalid") == nil)
        #expect(NostrPubkeyFormat.hex("abc123") == nil)
    }
}

struct SelfieShareScopeTests {
    // Each test gets its own defaults suite: Swift Testing runs tests in
    // parallel, and sharing UserDefaults.standard made these two race (one
    // removed the key while the other had just set it).
    private func freshDefaults() -> UserDefaults {
        let name = "SelfieShareScopeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func defaultsToEveryone_whenUnset() {
        #expect(SelfieShareScope.stored(in: freshDefaults()) == .everyone)
    }

    @Test
    func readsStoredScope() {
        let defaults = freshDefaults()
        defaults.set(SelfieShareScope.mutualFavorites.rawValue, forKey: SelfieShareScope.storageKey)
        #expect(SelfieShareScope.stored(in: defaults) == .mutualFavorites)
    }
}
