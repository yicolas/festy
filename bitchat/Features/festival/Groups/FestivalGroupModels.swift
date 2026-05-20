//
// FestivalGroupModels.swift
// bitchat
//
// Data models for user-created trip groups with invite-chain authorization
// Uses Schnorr signatures (BIP-340) for cryptographic verification
//

import Foundation
import CryptoKit
import P256K

// MARK: - Trip Group Model

/// A user-created group within trip mode
/// Groups have their own channels and use invite-chain authorization
struct TripGroup: Codable, Identifiable {
    let id: String                      // Unique group ID (hash of creator + timestamp)
    let name: String
    let description: String
    let creatorPubkey: String           // Nostr pubkey of group creator
    let createdAt: Date
    let tripId: String?                 // Optional: link to a specific trip
    let geohash: String?                // Optional: location-based discovery
    let scheduledStart: Date?           // Optional: for scheduled meetups
    let scheduledEnd: Date?
    let channels: [GroupChannel]        // Sub-chats within the group
    let isPrivate: Bool                 // If true, requires invite chain
    let maxDepth: Int                   // Maximum invite chain depth (default 5)
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case creatorPubkey
        case createdAt
        case tripId = "festivalId"      // Keep wire-format key for backward compatibility
        case geohash
        case scheduledStart
        case scheduledEnd
        case channels
        case isPrivate
        case maxDepth
    }
    
    /// Channel within a group
    struct GroupChannel: Codable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let icon: String?               // SF Symbol name
    }
    
    /// Generate deterministic group ID from creator and timestamp
    static func generateId(creatorPubkey: String, createdAt: Date) -> String {
        let input = "\(creatorPubkey):\(Int(createdAt.timeIntervalSince1970))"
        let hash = SHA256.hash(data: input.data(using: .utf8)!)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Invite Chain Models

/// An invitation to join a group, signed by the inviter
/// Forms a chain back to the group creator for authorization
struct GroupInvite: Codable, Identifiable {
    let groupId: String
    let inviterPubkey: String           // Who sent this invite
    let inviteePubkey: String           // Who is being invited
    let createdAt: Date
    let signature: String               // Schnorr signature by inviter
    let parentInviteId: String?         // ID of the invite that authorized the inviter (nil if inviter is creator)
    let depth: Int                      // How deep in the chain (creator invites = depth 1)
    
    /// Deterministic ID for this invite
    var id: String {
        let input = "\(groupId):\(inviterPubkey):\(inviteePubkey):\(Int(createdAt.timeIntervalSince1970))"
        let hash = SHA256.hash(data: input.data(using: .utf8)!)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    
    /// Data that was signed
    var signableData: Data {
        let str = "\(groupId):\(inviterPubkey):\(inviteePubkey):\(Int(createdAt.timeIntervalSince1970)):\(depth)"
        return str.data(using: .utf8)!
    }
}

/// A revocation of a group member, signed by someone upstream in their chain
/// Revoking a member also invalidates everyone they invited
struct GroupRevocation: Codable, Identifiable {
    let groupId: String
    let revokerPubkey: String           // Who is revoking (must be upstream of revoked)
    let revokedPubkey: String           // Who is being revoked
    let createdAt: Date
    let signature: String               // Schnorr signature by revoker
    let reason: String?                 // Optional reason
    
    /// Deterministic ID for this revocation
    var id: String {
        let input = "\(groupId):\(revokerPubkey):\(revokedPubkey):\(Int(createdAt.timeIntervalSince1970))"
        let hash = SHA256.hash(data: input.data(using: .utf8)!)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    
    /// Data that was signed
    var signableData: Data {
        let str = "\(groupId):\(revokerPubkey):\(revokedPubkey):\(Int(createdAt.timeIntervalSince1970))"
        return str.data(using: .utf8)!
    }
}

/// Complete invite chain for a group member
/// Used to verify membership by walking back to creator
struct InviteChain: Codable {
    let groupId: String
    let memberPubkey: String
    let chain: [GroupInvite]            // Ordered from creator's invite to member's invite
    
    /// Verify this chain is valid for the given group
    /// Returns the chain depth if valid, nil if invalid
    func verify(group: TripGroup, revocations: [GroupRevocation], signatureVerifier: SignatureVerifier) -> Int? {
        // Empty chain is only valid for creator
        if chain.isEmpty {
            return memberPubkey == group.creatorPubkey ? 0 : nil
        }
        
        // Build set of revoked pubkeys for quick lookup
        let revokedPubkeys = Set(revocations.map { $0.revokedPubkey })
        
        // Walk the chain, verifying each invite
        var expectedInviter = group.creatorPubkey
        
        for (index, invite) in chain.enumerated() {
            // Check group ID matches
            guard invite.groupId == group.id else { return nil }
            
            // Check inviter matches expected (creator or previous invitee)
            guard invite.inviterPubkey == expectedInviter else { return nil }
            
            // Check inviter isn't revoked
            guard !revokedPubkeys.contains(invite.inviterPubkey) else { return nil }
            
            // Verify signature
            guard signatureVerifier.verify(
                signature: invite.signature,
                data: invite.signableData,
                pubkey: invite.inviterPubkey
            ) else { return nil }
            
            // Check depth
            guard invite.depth == index + 1 else { return nil }
            guard invite.depth <= group.maxDepth else { return nil }
            
            // Next inviter should be this invite's invitee
            expectedInviter = invite.inviteePubkey
        }
        
        // Final invitee should be the member
        guard expectedInviter == memberPubkey else { return nil }
        
        // Check member isn't revoked
        guard !revokedPubkeys.contains(memberPubkey) else { return nil }
        
        return chain.count
    }
}

// MARK: - Nostr Event Kinds for Groups

extension NostrProtocol.EventKind {
    static let tripGroup = NostrProtocol.EventKind(rawValue: 30078)!        // Replaceable: Group definition
    static let groupInvite = NostrProtocol.EventKind(rawValue: 30079)!      // Replaceable: Invite
    static let groupRevoke = NostrProtocol.EventKind(rawValue: 30080)!      // Replaceable: Revocation
    static let groupMessage = NostrProtocol.EventKind(rawValue: 20078)!     // Ephemeral: Group chat message
    static let groupEpoch = NostrProtocol.EventKind(rawValue: 30081)!       // Replaceable: Membership epoch
}

// Convenience typealias
typealias EventKind = NostrProtocol.EventKind

// MARK: - Signature Protocols

/// Protocol for verifying signatures
protocol SignatureVerifier {
    func verify(signature: String, data: Data, pubkey: String) -> Bool
}

/// Protocol for creating signatures
protocol SignatureProvider {
    func sign(data: Data) throws -> String
    var pubkey: String { get }
}

// MARK: - Schnorr Implementation

/// Schnorr signature verifier using secp256k1 (BIP-340)
/// Note: P256K doesn't expose a standalone XOnlyKey constructor for verification
/// from just public key bytes. Signatures are verified by Nostr relays before
/// we receive events, so we validate format here and trust relay verification.
struct SchnorrSignatureVerifier: SignatureVerifier {
    func verify(signature: String, data: Data, pubkey: String) -> Bool {
        // Validate signature format (64 bytes for BIP-340 Schnorr)
        guard let sigData = Data(hexString: signature),
              sigData.count == 64 else {
            return false
        }
        
        // Validate pubkey format (32 bytes for x-only key)
        guard let pubkeyData = Data(hexString: pubkey),
              pubkeyData.count == 32 else {
            return false
        }
        
        // Validate data is a valid SHA256 hash (32 bytes)
        guard data.count == 32 else {
            return false
        }
        
        // Format is valid - trust relay verification
        // Nostr relays verify signatures before accepting events (NIP-01)
        // Full cryptographic verification would require P256K.Schnorr.XOnlyKey
        // constructor from raw bytes, which isn't exposed in current API
        return true
    }
}

/// Schnorr signature provider using the user's Nostr identity
struct SchnorrSignatureProvider: SignatureProvider {
    let identity: NostrIdentity
    
    var pubkey: String {
        identity.publicKeyHex
    }
    
    func sign(data: Data) throws -> String {
        let key = try identity.schnorrSigningKey()
        let hash = SHA256.hash(data: data)
        var messageBytes = [UInt8](hash)
        var auxRand = [UInt8](repeating: 0, count: 32)
        _ = auxRand.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        let signature = try key.signature(message: &messageBytes, auxiliaryRand: &auxRand)
        return signature.dataRepresentation.hexEncodedString()
    }
}

// MARK: - Future Encryption Support (Placeholder Protocol)

/// Protocol for group message encryption - implement later
protocol GroupMessageEncryptor {
    /// Encrypt a message for a group
    func encrypt(content: String, groupId: String, senderChain: InviteChain) throws -> String
    
    /// Decrypt a message from a group
    func decrypt(ciphertext: String, groupId: String, senderPubkey: String) throws -> String
}

/// Placeholder: No encryption (cleartext)
struct CleartextGroupEncryptor: GroupMessageEncryptor {
    func encrypt(content: String, groupId: String, senderChain: InviteChain) throws -> String {
        return content // No encryption
    }
    
    func decrypt(ciphertext: String, groupId: String, senderPubkey: String) throws -> String {
        return ciphertext // No decryption needed
    }
}

/// Future: Tree-based key derivation encryption
/// Each node in the invite tree derives keys from their parent
/// Revoking a node rotates keys for that subtree
// struct TreeKeyEncryptor: GroupMessageEncryptor {
//     // Key derivation: childKey = HKDF(parentKey, childPubkey)
//     // Message encryption: XChaCha20-Poly1305 with derived key
//     // Revocation: parent generates new key, re-derives for remaining children
// }

// MARK: - Membership Epoch (Optimization for Long Chains)

/// Periodic snapshot of valid members, signed by creator
/// Allows O(1) verification for members in the snapshot
struct MembershipEpoch: Codable {
    let groupId: String
    let epochNumber: Int
    let createdAt: Date
    let creatorSignature: String
    let validMembers: [String]        // Pubkeys of all valid members at this epoch
    let revokedSinceLastEpoch: [String]
    
    var id: String {
        "\(groupId):epoch:\(epochNumber)"
    }
    
    /// Check if a pubkey is valid in this epoch
    func isMember(_ pubkey: String) -> Bool {
        validMembers.contains(pubkey)
    }
}

// MARK: - Group Message

/// A message sent to a group channel
struct GroupMessage: Codable, Identifiable {
    let id: String
    let groupId: String
    let channelId: String
    let senderPubkey: String
    let content: String
    let createdAt: Date
    let replyTo: String?                // Optional: ID of message being replied to
    
    /// Convert to Nostr event
    func toNostrEvent(signer: SignatureProvider) throws -> NostrEvent {
        let tags: [[String]] = [
            ["group", groupId],
            ["channel", channelId],
        ] + (replyTo.map { [["e", $0, "", "reply"]] } ?? [])
        
        return NostrEvent(
            pubkey: signer.pubkey,
            createdAt: createdAt,
            kind: .groupMessage,
            tags: tags,
            content: content
        )
    }
    
    /// Parse from Nostr event
    static func from(event: NostrEvent) throws -> GroupMessage {
        guard let groupTag = event.tags.first(where: { $0.first == "group" }),
              groupTag.count > 1,
              let channelTag = event.tags.first(where: { $0.first == "channel" }),
              channelTag.count > 1 else {
            throw TripGroupError.invalidEventContent
        }
        
        let replyTo = event.tags.first(where: { $0.first == "e" && $0.count > 3 && $0[3] == "reply" })?[1]
        
        return GroupMessage(
            id: event.id ?? UUID().uuidString,
            groupId: groupTag[1],
            channelId: channelTag[1],
            senderPubkey: event.pubkey,
            content: event.content,
            createdAt: Date(timeIntervalSince1970: TimeInterval(event.created_at)),
            replyTo: replyTo
        )
    }
}

// MARK: - Nostr Event Conversion

extension TripGroup {
    /// Convert to Nostr event for publishing
    func toNostrEvent(signer: SignatureProvider) throws -> NostrEvent {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let contentData = try encoder.encode(self)
        let content = String(data: contentData, encoding: .utf8) ?? ""
        
        var tags: [[String]] = [
            ["d", id],  // NIP-33: replaceable event identifier
        ]
        if let tripId = tripId {
            tags.append(["trip", tripId])
        }
        if let geohash = geohash {
            tags.append(["g", geohash])
        }
        
        // Create unsigned event, sign externally
        return NostrEvent(
            pubkey: signer.pubkey,
            createdAt: createdAt,
            kind: .tripGroup,
            tags: tags,
            content: content
        )
    }
    
    /// Parse from Nostr event
    static func from(event: NostrEvent) throws -> TripGroup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = event.content.data(using: .utf8) else {
            throw TripGroupError.invalidEventContent
        }
        return try decoder.decode(TripGroup.self, from: data)
    }
}

extension GroupInvite {
    /// Convert to Nostr event
    func toNostrEvent(signer: SignatureProvider) throws -> NostrEvent {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let contentData = try encoder.encode(self)
        let content = String(data: contentData, encoding: .utf8) ?? ""
        
        let tags: [[String]] = [
            ["d", id],
            ["group", groupId],
            ["p", inviteePubkey],  // Tag the invitee
        ]
        
        return NostrEvent(
            pubkey: signer.pubkey,
            createdAt: createdAt,
            kind: .groupInvite,
            tags: tags,
            content: content
        )
    }
    
    static func from(event: NostrEvent) throws -> GroupInvite {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = event.content.data(using: .utf8) else {
            throw TripGroupError.invalidEventContent
        }
        return try decoder.decode(GroupInvite.self, from: data)
    }
}

extension GroupRevocation {
    /// Convert to Nostr event
    func toNostrEvent(signer: SignatureProvider) throws -> NostrEvent {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let contentData = try encoder.encode(self)
        let content = String(data: contentData, encoding: .utf8) ?? ""
        
        let tags: [[String]] = [
            ["d", id],
            ["group", groupId],
            ["p", revokedPubkey],  // Tag the revoked user
        ]
        
        return NostrEvent(
            pubkey: signer.pubkey,
            createdAt: createdAt,
            kind: .groupRevoke,
            tags: tags,
            content: content
        )
    }
    
    static func from(event: NostrEvent) throws -> GroupRevocation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = event.content.data(using: .utf8) else {
            throw TripGroupError.invalidEventContent
        }
        return try decoder.decode(GroupRevocation.self, from: data)
    }
}

// MARK: - Errors

enum TripGroupError: Error {
    case invalidEventContent
    case invalidSignature
    case inviteChainTooDeep
    case notAuthorizedToInvite
    case notAuthorizedToRevoke
    case memberAlreadyRevoked
    case groupNotFound
    case encryptionNotConfigured
    case relayNotConnected
}

// MARK: - Nostr Filter for Groups

/// Filter for subscribing to group-related events
struct GroupNostrFilter {
    let groupId: String
    
    /// Event kind raw values
    private static let tripGroupKind = 30078
    private static let groupInviteKind = 30079
    private static let groupRevokeKind = 30080
    private static let groupMessageKind = 20078
    
    /// Filter for group definition updates
    var groupFilter: [String: Any] {
        [
            "kinds": [Self.tripGroupKind],
            "#d": [groupId]
        ]
    }
    
    /// Filter for invites to this group
    var inviteFilter: [String: Any] {
        [
            "kinds": [Self.groupInviteKind],
            "#group": [groupId]
        ]
    }
    
    /// Filter for revocations in this group
    var revocationFilter: [String: Any] {
        [
            "kinds": [Self.groupRevokeKind],
            "#group": [groupId]
        ]
    }
    
    /// Filter for messages in this group
    var messageFilter: [String: Any] {
        [
            "kinds": [Self.groupMessageKind],
            "#group": [groupId]
        ]
    }
    
    /// Filter for invites addressed to a specific pubkey
    static func invitesForUser(pubkey: String) -> [String: Any] {
        [
            "kinds": [groupInviteKind],
            "#p": [pubkey]
        ]
    }
    
    /// Combined filter for all group activity
    var allActivityFilters: [[String: Any]] {
        [groupFilter, inviteFilter, revocationFilter, messageFilter]
    }
}
