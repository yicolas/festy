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
    @Test
    func defaultsToEveryone_whenUnset() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: SelfieShareScope.storageKey)
        defaults.removeObject(forKey: SelfieShareScope.storageKey)
        defer { defaults.set(saved, forKey: SelfieShareScope.storageKey) }
        #expect(SelfieShareScope.current == .everyone)
    }

    @Test
    func readsStoredScope() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: SelfieShareScope.storageKey)
        defaults.set(SelfieShareScope.mutualFavorites.rawValue, forKey: SelfieShareScope.storageKey)
        defer { defaults.set(saved, forKey: SelfieShareScope.storageKey) }
        #expect(SelfieShareScope.current == .mutualFavorites)
    }
}
