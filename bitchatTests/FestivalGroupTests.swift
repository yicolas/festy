//
// TripGroupTests.swift
// bitchatTests
//
// Tests for trip groups with invite-chain authorization
//

import Testing
import Foundation
@testable import bitchat

// MARK: - Mock Signature Verifier

/// Mock verifier that accepts all signatures (for testing logic without crypto)
struct MockSignatureVerifier: SignatureVerifier {
    var shouldVerify: Bool = true
    
    func verify(signature: String, data: Data, pubkey: String) -> Bool {
        return shouldVerify
    }
}

/// Mock signer for testing
struct MockSignatureProvider: SignatureProvider {
    let pubkey: String
    
    func sign(data: Data) throws -> String {
        // Return a deterministic "signature" based on data hash
        let hash = data.hashValue
        return String(format: "%064x", abs(hash))
    }
}

// MARK: - Trip Group Model Tests

struct TripGroupModelTests {
    
    @Test
    func group_generateId_isDeterministic() {
        let pubkey = "abc123"
        let date = Date(timeIntervalSince1970: 1700000000)
        
        let id1 = TripGroup.generateId(creatorPubkey: pubkey, createdAt: date)
        let id2 = TripGroup.generateId(creatorPubkey: pubkey, createdAt: date)
        
        #expect(id1 == id2)
        #expect(id1.count == 32)  // 16 bytes = 32 hex chars
    }
    
    @Test
    func group_generateId_differentInputsProduceDifferentIds() {
        let date = Date(timeIntervalSince1970: 1700000000)
        
        let id1 = TripGroup.generateId(creatorPubkey: "alice", createdAt: date)
        let id2 = TripGroup.generateId(creatorPubkey: "bob", createdAt: date)
        let id3 = TripGroup.generateId(creatorPubkey: "alice", createdAt: date.addingTimeInterval(1))
        
        #expect(id1 != id2)
        #expect(id1 != id3)
        #expect(id2 != id3)
    }
    
    @Test
    func groupChannel_identifiable() {
        let channel = TripGroup.GroupChannel(
            id: "general",
            name: "#general",
            description: "Main chat",
            icon: "bubble.left.and.bubble.right"
        )
        
        #expect(channel.id == "general")
    }
}

// MARK: - Invite Chain Tests

struct InviteChainTests {
    
    @Test
    func inviteChain_emptyChain_validForCreator() {
        let creatorPubkey = "creator123"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        let chain = InviteChain(groupId: group.id, memberPubkey: creatorPubkey, chain: [])
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == 0)
    }
    
    @Test
    func inviteChain_emptyChain_invalidForNonCreator() {
        let group = makeTestGroup(creatorPubkey: "creator123")
        let chain = InviteChain(groupId: group.id, memberPubkey: "someone_else", chain: [])
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == nil)
    }
    
    @Test
    func inviteChain_singleInvite_validForInvitee() {
        let creatorPubkey = "creator123"
        let inviteePubkey = "alice456"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        
        let invite = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: inviteePubkey,
            createdAt: Date(),
            signature: "valid_sig",
            parentInviteId: nil,
            depth: 1
        )
        
        let chain = InviteChain(groupId: group.id, memberPubkey: inviteePubkey, chain: [invite])
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == 1)
    }
    
    @Test
    func inviteChain_multipleInvites_validChain() {
        // creator -> alice -> bob -> carol (depth 3)
        let creatorPubkey = "creator"
        let alicePubkey = "alice"
        let bobPubkey = "bob"
        let carolPubkey = "carol"
        let group = makeTestGroup(creatorPubkey: creatorPubkey, maxDepth: 5)
        
        let invite1 = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: alicePubkey,
            createdAt: Date(),
            signature: "sig1",
            parentInviteId: nil,
            depth: 1
        )
        
        let invite2 = GroupInvite(
            groupId: group.id,
            inviterPubkey: alicePubkey,
            inviteePubkey: bobPubkey,
            createdAt: Date(),
            signature: "sig2",
            parentInviteId: invite1.id,
            depth: 2
        )
        
        let invite3 = GroupInvite(
            groupId: group.id,
            inviterPubkey: bobPubkey,
            inviteePubkey: carolPubkey,
            createdAt: Date(),
            signature: "sig3",
            parentInviteId: invite2.id,
            depth: 3
        )
        
        let chain = InviteChain(
            groupId: group.id,
            memberPubkey: carolPubkey,
            chain: [invite1, invite2, invite3]
        )
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == 3)
    }
    
    @Test
    func inviteChain_exceedsMaxDepth_invalid() {
        let creatorPubkey = "creator"
        let group = makeTestGroup(creatorPubkey: creatorPubkey, maxDepth: 2)
        
        // Create chain of depth 3 (exceeds max of 2)
        let invite1 = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: "alice",
            createdAt: Date(),
            signature: "sig1",
            parentInviteId: nil,
            depth: 1
        )
        
        let invite2 = GroupInvite(
            groupId: group.id,
            inviterPubkey: "alice",
            inviteePubkey: "bob",
            createdAt: Date(),
            signature: "sig2",
            parentInviteId: invite1.id,
            depth: 2
        )
        
        let invite3 = GroupInvite(
            groupId: group.id,
            inviterPubkey: "bob",
            inviteePubkey: "carol",
            createdAt: Date(),
            signature: "sig3",
            parentInviteId: invite2.id,
            depth: 3
        )
        
        let chain = InviteChain(
            groupId: group.id,
            memberPubkey: "carol",
            chain: [invite1, invite2, invite3]
        )
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == nil)  // Should fail because depth 3 > maxDepth 2
    }
    
    @Test
    func inviteChain_revokedMember_invalid() {
        let creatorPubkey = "creator"
        let alicePubkey = "alice"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        
        let invite = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: alicePubkey,
            createdAt: Date(),
            signature: "sig",
            parentInviteId: nil,
            depth: 1
        )
        
        let revocation = GroupRevocation(
            groupId: group.id,
            revokerPubkey: creatorPubkey,
            revokedPubkey: alicePubkey,
            createdAt: Date(),
            signature: "rev_sig",
            reason: "test"
        )
        
        let chain = InviteChain(groupId: group.id, memberPubkey: alicePubkey, chain: [invite])
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [revocation], signatureVerifier: verifier)
        
        #expect(depth == nil)  // Alice is revoked
    }
    
    @Test
    func inviteChain_revokedUpstream_invalidatesDownstream() {
        // creator -> alice -> bob
        // Revoking alice should invalidate bob
        let creatorPubkey = "creator"
        let alicePubkey = "alice"
        let bobPubkey = "bob"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        
        let invite1 = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: alicePubkey,
            createdAt: Date(),
            signature: "sig1",
            parentInviteId: nil,
            depth: 1
        )
        
        let invite2 = GroupInvite(
            groupId: group.id,
            inviterPubkey: alicePubkey,
            inviteePubkey: bobPubkey,
            createdAt: Date(),
            signature: "sig2",
            parentInviteId: invite1.id,
            depth: 2
        )
        
        // Revoke alice
        let revocation = GroupRevocation(
            groupId: group.id,
            revokerPubkey: creatorPubkey,
            revokedPubkey: alicePubkey,
            createdAt: Date(),
            signature: "rev_sig",
            reason: nil
        )
        
        // Bob's chain includes alice
        let bobChain = InviteChain(
            groupId: group.id,
            memberPubkey: bobPubkey,
            chain: [invite1, invite2]
        )
        
        let verifier = MockSignatureVerifier()
        let depth = bobChain.verify(group: group, revocations: [revocation], signatureVerifier: verifier)
        
        #expect(depth == nil)  // Bob's chain is invalid because alice is revoked
    }
    
    @Test
    func inviteChain_invalidSignature_rejected() {
        let creatorPubkey = "creator"
        let alicePubkey = "alice"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        
        let invite = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: alicePubkey,
            createdAt: Date(),
            signature: "bad_sig",
            parentInviteId: nil,
            depth: 1
        )
        
        let chain = InviteChain(groupId: group.id, memberPubkey: alicePubkey, chain: [invite])
        
        var verifier = MockSignatureVerifier()
        verifier.shouldVerify = false  // Simulate invalid signature
        
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == nil)
    }
    
    @Test
    func inviteChain_wrongGroupId_rejected() {
        let creatorPubkey = "creator"
        let alicePubkey = "alice"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        
        // Invite for a different group
        let invite = GroupInvite(
            groupId: "different_group_id",
            inviterPubkey: creatorPubkey,
            inviteePubkey: alicePubkey,
            createdAt: Date(),
            signature: "sig",
            parentInviteId: nil,
            depth: 1
        )
        
        let chain = InviteChain(groupId: group.id, memberPubkey: alicePubkey, chain: [invite])
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == nil)
    }
    
    @Test
    func inviteChain_brokenChain_rejected() {
        // Chain where inviter doesn't match expected
        let creatorPubkey = "creator"
        let group = makeTestGroup(creatorPubkey: creatorPubkey)
        
        // Alice claims to be invited by creator, but then bob claims to be invited by "eve" (not alice)
        let invite1 = GroupInvite(
            groupId: group.id,
            inviterPubkey: creatorPubkey,
            inviteePubkey: "alice",
            createdAt: Date(),
            signature: "sig1",
            parentInviteId: nil,
            depth: 1
        )
        
        let invite2 = GroupInvite(
            groupId: group.id,
            inviterPubkey: "eve",  // Wrong! Should be "alice"
            inviteePubkey: "bob",
            createdAt: Date(),
            signature: "sig2",
            parentInviteId: invite1.id,
            depth: 2
        )
        
        let chain = InviteChain(
            groupId: group.id,
            memberPubkey: "bob",
            chain: [invite1, invite2]
        )
        
        let verifier = MockSignatureVerifier()
        let depth = chain.verify(group: group, revocations: [], signatureVerifier: verifier)
        
        #expect(depth == nil)  // Chain is broken
    }
}

// MARK: - Invite ID Tests

struct InviteIdTests {
    
    @Test
    func groupInvite_id_isDeterministic() {
        let invite = GroupInvite(
            groupId: "group1",
            inviterPubkey: "alice",
            inviteePubkey: "bob",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            signature: "sig",
            parentInviteId: nil,
            depth: 1
        )
        
        let id1 = invite.id
        let id2 = invite.id
        
        #expect(id1 == id2)
    }
    
    @Test
    func groupInvite_differentInvites_differentIds() {
        let invite1 = GroupInvite(
            groupId: "group1",
            inviterPubkey: "alice",
            inviteePubkey: "bob",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            signature: "sig",
            parentInviteId: nil,
            depth: 1
        )
        
        let invite2 = GroupInvite(
            groupId: "group1",
            inviterPubkey: "alice",
            inviteePubkey: "carol",  // Different invitee
            createdAt: Date(timeIntervalSince1970: 1700000000),
            signature: "sig",
            parentInviteId: nil,
            depth: 1
        )
        
        #expect(invite1.id != invite2.id)
    }
    
    @Test
    func groupRevocation_id_isDeterministic() {
        let revocation = GroupRevocation(
            groupId: "group1",
            revokerPubkey: "alice",
            revokedPubkey: "bob",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            signature: "sig",
            reason: nil
        )
        
        let id1 = revocation.id
        let id2 = revocation.id
        
        #expect(id1 == id2)
    }
}

// MARK: - Signable Data Tests

struct SignableDataTests {
    
    @Test
    func groupInvite_signableData_containsAllFields() {
        let invite = GroupInvite(
            groupId: "group123",
            inviterPubkey: "alice",
            inviteePubkey: "bob",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            signature: "sig",
            parentInviteId: nil,
            depth: 3
        )
        
        let data = invite.signableData
        let str = String(data: data, encoding: .utf8)!
        
        #expect(str.contains("group123"))
        #expect(str.contains("alice"))
        #expect(str.contains("bob"))
        #expect(str.contains("1700000000"))
        #expect(str.contains("3"))  // depth
    }
    
    @Test
    func groupRevocation_signableData_containsAllFields() {
        let revocation = GroupRevocation(
            groupId: "group123",
            revokerPubkey: "alice",
            revokedPubkey: "bob",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            signature: "sig",
            reason: "test reason"
        )
        
        let data = revocation.signableData
        let str = String(data: data, encoding: .utf8)!
        
        #expect(str.contains("group123"))
        #expect(str.contains("alice"))
        #expect(str.contains("bob"))
        #expect(str.contains("1700000000"))
        // Note: reason is NOT in signable data (intentional)
    }
}

// MARK: - Test Helpers

private func makeTestGroup(
    creatorPubkey: String,
    maxDepth: Int = 5
) -> TripGroup {
    let now = Date()
    return TripGroup(
        id: TripGroup.generateId(creatorPubkey: creatorPubkey, createdAt: now),
        name: "Test Group",
        description: "A test group",
        creatorPubkey: creatorPubkey,
        createdAt: now,
        tripId: nil,
        geohash: nil,
        scheduledStart: nil,
        scheduledEnd: nil,
        channels: [],
        isPrivate: true,
        maxDepth: maxDepth
    )
}

// MARK: - Cleartext Encryptor Tests

struct CleartextEncryptorTests {
    
    @Test
    func cleartextEncryptor_encrypt_returnsOriginal() throws {
        let encryptor = CleartextGroupEncryptor()
        let content = "Hello, world!"
        let chain = InviteChain(groupId: "test", memberPubkey: "alice", chain: [])
        
        let encrypted = try encryptor.encrypt(content: content, groupId: "test", senderChain: chain)
        
        #expect(encrypted == content)
    }
    
    @Test
    func cleartextEncryptor_decrypt_returnsOriginal() throws {
        let encryptor = CleartextGroupEncryptor()
        let content = "Secret message"
        
        let decrypted = try encryptor.decrypt(ciphertext: content, groupId: "test", senderPubkey: "alice")
        
        #expect(decrypted == content)
    }
}

// MARK: - Tab Type Tests

struct TripTabTypeTests {
    
    @Test
    func tabType_groups_exists() {
        // Verify the groups tab type is defined
        let groupsType = TripTab.TabType.groups
        #expect(groupsType.rawValue == "groups")
    }
    
    @Test
    func defaultTabs_canIncludeGroups() {
        // Verify groups tab can be created
        let groupsTab = TripTab(
            id: "groups",
            name: "Groups",
            icon: "person.3",
            type: .groups
        )
        
        #expect(groupsTab.id == "groups")
        #expect(groupsTab.type == .groups)
    }
}
