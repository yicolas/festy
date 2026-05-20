//
// FestivalGroupManager.swift
// bitchat
//
// Service for creating and managing trip groups with invite-chain auth
// Uses local caching for O(1) membership verification after first check
//

import Foundation
import Combine

// MARK: - Group Event Kinds (Nostr NIP-compatible)

/// Event kind constants for trip groups
private enum GroupEventKind {
    static let tripGroup = 30078        // Replaceable: Group definition
    static let groupInvite = 30079      // Replaceable: Invite
    static let groupRevoke = 30080      // Replaceable: Revocation
    static let groupMessage = 20078     // Ephemeral: Group chat message
}

/// Manages user-created trip groups and their authorization chains
@MainActor
final class TripGroupManager: ObservableObject {
    static let shared = TripGroupManager()
    
    // MARK: - Published State
    
    @Published private(set) var myGroups: [TripGroup] = []           // Groups I created
    @Published private(set) var joinedGroups: [TripGroup] = []       // Groups I'm a member of
    @Published private(set) var pendingInvites: [GroupInvite] = []   // Invites I haven't accepted
    @Published private(set) var isLoading = false
    
    // MARK: - Dependencies
    
    private let signatureVerifier: SignatureVerifier
    private let encryptor: GroupMessageEncryptor
    private var signatureProvider: SignatureProvider?
    
    // MARK: - Internal State
    
    /// All known groups (by ID)
    private var groups: [String: TripGroup] = [:]
    
    /// All invites for each group (by group ID)
    private var invitesByGroup: [String: [GroupInvite]] = [:]
    
    /// All revocations for each group (by group ID)
    private var revocationsByGroup: [String: [GroupRevocation]] = [:]
    
    /// My invite chains for groups I'm a member of (by group ID)
    private var myChains: [String: InviteChain] = [:]
    
    // MARK: - Membership Cache (Key Performance Optimization)
    
    /// Cache of verified members per group
    /// Key: groupId, Value: Set of pubkeys verified as members
    /// This provides O(1) lookups after first verification
    private var verifiedMembersCache: [String: Set<String>] = [:]
    
    /// Cache of verified invite chains per group
    /// Key: groupId, Value: Dictionary of pubkey -> their verified InviteChain
    /// Allows re-verification without re-fetching chain data
    private var verifiedChainsCache: [String: [String: InviteChain]] = [:]
    
    /// Timestamp of last revocation per group (for cache invalidation)
    private var lastRevocationTime: [String: Date] = [:]
    
    // MARK: - Messaging State
    
    /// Message subscription handlers by group+channel
    private var messageHandlers: [String: (GroupMessage) -> Void] = [:]
    
    /// Cached messages by group+channel
    private var messageCache: [String: [GroupMessage]] = [:]
    
    /// Active subscription IDs for cleanup
    private var activeSubscriptions: [String: String] = [:]  // key -> subscription ID
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init(
        signatureVerifier: SignatureVerifier = SchnorrSignatureVerifier(),
        encryptor: GroupMessageEncryptor = CleartextGroupEncryptor()
    ) {
        self.signatureVerifier = signatureVerifier
        self.encryptor = encryptor
    }
    
    /// Configure with the user's signing identity
    func configure(with identity: NostrIdentity) {
        self.identity = identity
        self.signatureProvider = SchnorrSignatureProvider(identity: identity)
        refreshMyMemberships()
        
        // Subscribe to invites addressed to me
        subscribeToMyInvites()
    }
    
    // MARK: - Group Creation
    
    /// Create a new trip group
    func createGroup(
        name: String,
        description: String,
        tripId: String? = nil,
        geohash: String? = nil,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil,
        channels: [TripGroup.GroupChannel] = [],
        isPrivate: Bool = true,
        maxDepth: Int = 5
    ) throws -> TripGroup {
        guard let signer = signatureProvider else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        let now = Date()
        let id = TripGroup.generateId(creatorPubkey: signer.pubkey, createdAt: now)
        
        // Default channels if none provided
        let groupChannels = channels.isEmpty ? [
            TripGroup.GroupChannel(id: "general", name: "#general", description: "Main chat", icon: "bubble.left.and.bubble.right"),
            TripGroup.GroupChannel(id: "meetup", name: "#meetup", description: "Coordinate meetups", icon: "mappin.and.ellipse")
        ] : channels
        
        let group = TripGroup(
            id: id,
            name: name,
            description: description,
            creatorPubkey: signer.pubkey,
            createdAt: now,
            tripId: tripId,
            geohash: geohash,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            channels: groupChannels,
            isPrivate: isPrivate,
            maxDepth: maxDepth
        )
        
        // Store locally
        groups[id] = group
        myGroups.append(group)
        
        // Creator is automatically a member (depth 0, no chain needed)
        verifiedMembersCache[id] = [signer.pubkey]
        myChains[id] = InviteChain(groupId: id, memberPubkey: signer.pubkey, chain: [])
        
        // Publish to relay
        Task {
            do {
                let event = try group.toNostrEvent(signer: signer)
                try await publishEvent(event)
            } catch {
                print("Failed to publish group: \(error)")
            }
        }
        
        return group
    }
    
    // MARK: - Invitations
    
    /// Invite someone to a group (must be a member with invite permission)
    func invite(
        groupId: String,
        inviteePubkey: String
    ) throws -> GroupInvite {
        guard let signer = signatureProvider else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        guard let group = groups[groupId] else {
            throw TripGroupError.groupNotFound
        }
        
        // Get my chain to determine depth
        guard let myChain = myChains[groupId] else {
            throw TripGroupError.notAuthorizedToInvite
        }
        
        let myDepth = myChain.chain.count
        let newDepth = myDepth + 1
        
        // Check depth limit
        guard newDepth <= group.maxDepth else {
            throw TripGroupError.inviteChainTooDeep
        }
        
        // Check invitee isn't already revoked
        let revocations = revocationsByGroup[groupId] ?? []
        let revokedPubkeys = Set(revocations.map { $0.revokedPubkey })
        guard !revokedPubkeys.contains(inviteePubkey) else {
            throw TripGroupError.memberAlreadyRevoked
        }
        
        // Create and sign invite
        let now = Date()
        let parentInviteId = myChain.chain.last?.id
        
        // Build signable data
        let signableStr = "\(groupId):\(signer.pubkey):\(inviteePubkey):\(Int(now.timeIntervalSince1970)):\(newDepth)"
        let signableData = signableStr.data(using: .utf8)!
        let signature = try signer.sign(data: signableData)
        
        let invite = GroupInvite(
            groupId: groupId,
            inviterPubkey: signer.pubkey,
            inviteePubkey: inviteePubkey,
            createdAt: now,
            signature: signature,
            parentInviteId: parentInviteId,
            depth: newDepth
        )
        
        // Store locally
        var groupInvites = invitesByGroup[groupId] ?? []
        groupInvites.append(invite)
        invitesByGroup[groupId] = groupInvites
        
        // Publish to relay
        Task {
            do {
                let event = try invite.toNostrEvent(signer: signer)
                try await publishEvent(event)
            } catch {
                print("Failed to publish invite: \(error)")
            }
        }
        
        return invite
    }
    
    /// Accept an invite and join a group
    func acceptInvite(_ invite: GroupInvite) throws {
        guard let signer = signatureProvider else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        // Verify the invite is for me
        guard invite.inviteePubkey == signer.pubkey else {
            throw TripGroupError.invalidSignature
        }
        
        // Build my chain by finding all ancestors
        let chain = try buildChain(for: invite)
        
        // Verify chain is valid
        guard let group = groups[invite.groupId] else {
            // Fetch group from relay if not cached
            Task { await fetchGroup(id: invite.groupId) }
            throw TripGroupError.groupNotFound
        }
        
        let revocations = revocationsByGroup[invite.groupId] ?? []
        guard chain.verify(group: group, revocations: revocations, signatureVerifier: signatureVerifier) != nil else {
            throw TripGroupError.invalidSignature
        }
        
        // Store my chain
        myChains[invite.groupId] = chain
        
        // Add to joined groups
        if !joinedGroups.contains(where: { $0.id == group.id }) {
            joinedGroups.append(group)
        }
        
        // Remove from pending
        pendingInvites.removeAll { $0.id == invite.id }
        
        // Cache myself as verified member
        var members = verifiedMembersCache[invite.groupId] ?? []
        members.insert(signer.pubkey)
        verifiedMembersCache[invite.groupId] = members
        
        // Subscribe to group activity
        subscribeToGroup(groupId: invite.groupId)
    }
    
    /// Build the invite chain for an invite by finding ancestors
    private func buildChain(for invite: GroupInvite) throws -> InviteChain {
        var chain: [GroupInvite] = []
        var currentInvite: GroupInvite? = invite
        
        while let inv = currentInvite {
            chain.insert(inv, at: 0) // Build chain from root to leaf
            
            if let parentId = inv.parentInviteId {
                // Find parent invite
                let groupInvites = invitesByGroup[inv.groupId] ?? []
                currentInvite = groupInvites.first { $0.id == parentId }
            } else {
                // Reached root (creator's direct invite)
                currentInvite = nil
            }
        }
        
        guard let signer = signatureProvider else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        return InviteChain(groupId: invite.groupId, memberPubkey: signer.pubkey, chain: chain)
    }
    
    // MARK: - Revocations
    
    /// Revoke a member (must be upstream of them in the chain)
    func revoke(
        groupId: String,
        memberPubkey: String,
        reason: String? = nil
    ) throws -> GroupRevocation {
        guard let signer = signatureProvider else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        guard let group = groups[groupId] else {
            throw TripGroupError.groupNotFound
        }
        
        // Verify I can revoke this member (I must be upstream)
        guard canRevoke(revokerPubkey: signer.pubkey, targetPubkey: memberPubkey, groupId: groupId) else {
            throw TripGroupError.notAuthorizedToRevoke
        }
        
        // Check not already revoked
        let existingRevocations = revocationsByGroup[groupId] ?? []
        guard !existingRevocations.contains(where: { $0.revokedPubkey == memberPubkey }) else {
            throw TripGroupError.memberAlreadyRevoked
        }
        
        // Create and sign revocation
        let now = Date()
        let signableStr = "\(groupId):\(signer.pubkey):\(memberPubkey):\(Int(now.timeIntervalSince1970))"
        let signableData = signableStr.data(using: .utf8)!
        let signature = try signer.sign(data: signableData)
        
        let revocation = GroupRevocation(
            groupId: groupId,
            revokerPubkey: signer.pubkey,
            revokedPubkey: memberPubkey,
            createdAt: now,
            signature: signature,
            reason: reason
        )
        
        // Store locally
        var groupRevocations = revocationsByGroup[groupId] ?? []
        groupRevocations.append(revocation)
        revocationsByGroup[groupId] = groupRevocations
        
        // Invalidate cache for this group
        invalidateCache(for: groupId)
        
        // Publish to relay
        Task {
            do {
                let event = try revocation.toNostrEvent(signer: signer)
                try await publishEvent(event)
            } catch {
                print("Failed to publish revocation: \(error)")
            }
        }
        
        return revocation
    }
    
    /// Check if revoker can revoke target (must be upstream in chain)
    private func canRevoke(revokerPubkey: String, targetPubkey: String, groupId: String) -> Bool {
        guard let group = groups[groupId] else { return false }
        
        // Creator can revoke anyone
        if revokerPubkey == group.creatorPubkey { return true }
        
        // Find target's chain and check if revoker is in it
        let groupInvites = invitesByGroup[groupId] ?? []
        
        // Find invite where target is the invitee
        guard let targetInvite = groupInvites.first(where: { $0.inviteePubkey == targetPubkey }) else {
            return false
        }
        
        // Walk up the chain to see if revoker is an ancestor
        var currentInvite: GroupInvite? = targetInvite
        while let invite = currentInvite {
            if invite.inviterPubkey == revokerPubkey {
                return true // Revoker is upstream
            }
            
            if let parentId = invite.parentInviteId {
                currentInvite = groupInvites.first { $0.id == parentId }
            } else {
                currentInvite = nil
            }
        }
        
        return false
    }
    
    // MARK: - Membership Verification (with Caching)
    
    /// Check if a pubkey is a member of a group (O(1) after first check)
    func isMember(pubkey: String, groupId: String) -> Bool {
        // Check cache first (O(1))
        if let cached = verifiedMembersCache[groupId], cached.contains(pubkey) {
            return true
        }
        
        // Not in cache - need to verify chain
        guard let group = groups[groupId] else { return false }
        
        // Creator is always a member
        if pubkey == group.creatorPubkey {
            var members = verifiedMembersCache[groupId] ?? []
            members.insert(pubkey)
            verifiedMembersCache[groupId] = members
            return true
        }
        
        // Find and verify their chain
        let groupInvites = invitesByGroup[groupId] ?? []
        guard let theirInvite = groupInvites.first(where: { $0.inviteePubkey == pubkey }) else {
            return false // No invite found
        }
        
        // Build their chain
        guard let chain = try? buildChainFor(pubkey: pubkey, groupId: groupId) else {
            return false
        }
        
        // Verify chain
        let revocations = revocationsByGroup[groupId] ?? []
        guard chain.verify(group: group, revocations: revocations, signatureVerifier: signatureVerifier) != nil else {
            return false
        }
        
        // Cache the result
        var members = verifiedMembersCache[groupId] ?? []
        members.insert(pubkey)
        verifiedMembersCache[groupId] = members
        
        var chains = verifiedChainsCache[groupId] ?? [:]
        chains[pubkey] = chain
        verifiedChainsCache[groupId] = chains
        
        return true
    }
    
    /// Build chain for any pubkey (not just self)
    private func buildChainFor(pubkey: String, groupId: String) throws -> InviteChain {
        let groupInvites = invitesByGroup[groupId] ?? []
        
        // Find the invite where this pubkey is invitee
        guard let theirInvite = groupInvites.first(where: { $0.inviteePubkey == pubkey }) else {
            throw TripGroupError.groupNotFound
        }
        
        var chain: [GroupInvite] = []
        var currentInvite: GroupInvite? = theirInvite
        
        while let inv = currentInvite {
            chain.insert(inv, at: 0)
            
            if let parentId = inv.parentInviteId {
                currentInvite = groupInvites.first { $0.id == parentId }
            } else {
                currentInvite = nil
            }
        }
        
        return InviteChain(groupId: groupId, memberPubkey: pubkey, chain: chain)
    }
    
    /// Invalidate cache for a group (called on revocation)
    private func invalidateCache(for groupId: String) {
        verifiedMembersCache.removeValue(forKey: groupId)
        verifiedChainsCache.removeValue(forKey: groupId)
        lastRevocationTime[groupId] = Date()
    }
    
    /// Get all verified members of a group
    func getMembers(groupId: String) -> [String] {
        guard let group = groups[groupId] else { return [] }
        
        var members: Set<String> = [group.creatorPubkey]
        
        let groupInvites = invitesByGroup[groupId] ?? []
        for invite in groupInvites {
            if isMember(pubkey: invite.inviteePubkey, groupId: groupId) {
                members.insert(invite.inviteePubkey)
            }
        }
        
        return Array(members)
    }
    
    // MARK: - Messaging
    
    /// Current user's pubkey (if configured)
    var myPubkey: String? {
        signatureProvider?.pubkey
    }
    
    /// Load messages for a channel
    func loadMessages(groupId: String, channelId: String) async -> [GroupMessage] {
        let key = "\(groupId):\(channelId)"
        
        // Return cached if available
        if let cached = messageCache[key], !cached.isEmpty {
            return cached
        }
        
        // Fetch from relay
        await fetchMessagesFromRelay(groupId: groupId, channelId: channelId)
        
        return messageCache[key] ?? []
    }
    
    /// Subscribe to new messages for a channel
    func subscribeToGroupMessages(groupId: String, channelId: String, handler: @escaping (GroupMessage) -> Void) {
        let key = "\(groupId):\(channelId)"
        messageHandlers[key] = handler
        
        // Subscribe to relay for this group's messages
        subscribeToChannelMessages(groupId: groupId, channelId: channelId)
    }
    
    /// Send a message to a group channel
    func sendMessage(groupId: String, channelId: String, content: String, replyTo: String? = nil) async throws -> GroupMessage {
        guard let signer = signatureProvider else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        // Verify we're a member
        guard isMember(pubkey: signer.pubkey, groupId: groupId) else {
            throw TripGroupError.notAuthorizedToInvite
        }
        
        let message = GroupMessage(
            id: UUID().uuidString,
            groupId: groupId,
            channelId: channelId,
            senderPubkey: signer.pubkey,
            content: content,
            createdAt: Date(),
            replyTo: replyTo
        )
        
        // Convert to Nostr event and publish
        let event = try message.toNostrEvent(signer: signer)
        try await publishEvent(event)
        
        // Cache locally
        let key = "\(groupId):\(channelId)"
        var messages = messageCache[key] ?? []
        messages.append(message)
        messageCache[key] = messages
        
        return message
    }
    
    // MARK: - Relay Integration
    
    /// Stored identity for signing
    private var identity: NostrIdentity?
    
    /// Publish a Nostr event to relays
    private func publishEvent(_ event: NostrEvent) async throws {
        guard let identity = identity else {
            throw TripGroupError.encryptionNotConfigured
        }
        
        // Sign the event with our identity
        let signingKey = try identity.schnorrSigningKey()
        let signedEvent = try event.sign(with: signingKey)
        
        // Use NostrRelayManager to send
        await MainActor.run {
            NostrRelayManager.shared.sendEvent(signedEvent)
        }
    }
    
    /// Subscribe to invites addressed to me
    private func subscribeToMyInvites() {
        guard let pubkey = signatureProvider?.pubkey else { return }
        
        // Create filter for invites tagged with my pubkey
        var filter = NostrFilter()
        filter.kinds = [GroupEventKind.groupInvite]
        filter.setTagFilter("p", values: [pubkey])
        
        let subscriptionId = "group-invites-\(pubkey.prefix(8))"
        
        NostrRelayManager.shared.subscribe(
            filter: filter,
            id: subscriptionId,
            handler: { [weak self] event in
                Task { @MainActor in
                    self?.handleIncomingInvite(event)
                }
            }
        )
        
        activeSubscriptions["my-invites"] = subscriptionId
    }
    
    /// Subscribe to all activity for a group
    private func subscribeToGroup(groupId: String) {
        // Subscribe to invites for this group
        var inviteFilter = NostrFilter()
        inviteFilter.kinds = [GroupEventKind.groupInvite]
        inviteFilter.setTagFilter("group", values: [groupId])
        
        let inviteSubId = "group-\(groupId.prefix(8))-invites"
        NostrRelayManager.shared.subscribe(
            filter: inviteFilter,
            id: inviteSubId,
            handler: { [weak self] event in
                Task { @MainActor in
                    self?.handleIncomingInvite(event)
                }
            }
        )
        activeSubscriptions["invites-\(groupId)"] = inviteSubId
        
        // Subscribe to revocations for this group
        var revokeFilter = NostrFilter()
        revokeFilter.kinds = [GroupEventKind.groupRevoke]
        revokeFilter.setTagFilter("group", values: [groupId])
        
        let revokeSubId = "group-\(groupId.prefix(8))-revokes"
        NostrRelayManager.shared.subscribe(
            filter: revokeFilter,
            id: revokeSubId,
            handler: { [weak self] event in
                Task { @MainActor in
                    self?.handleIncomingRevocation(event)
                }
            }
        )
        activeSubscriptions["revokes-\(groupId)"] = revokeSubId
    }
    
    /// Subscribe to messages for a specific channel
    private func subscribeToChannelMessages(groupId: String, channelId: String) {
        var filter = NostrFilter()
        filter.kinds = [GroupEventKind.groupMessage]
        filter.setTagFilter("group", values: [groupId])
        filter.setTagFilter("channel", values: [channelId])
        filter.limit = 100  // Last 100 messages
        
        let subscriptionId = "group-\(groupId.prefix(8))-\(channelId)"
        
        NostrRelayManager.shared.subscribe(
            filter: filter,
            id: subscriptionId,
            handler: { [weak self] event in
                Task { @MainActor in
                    self?.handleIncomingMessage(event)
                }
            }
        )
        
        activeSubscriptions["\(groupId):\(channelId)"] = subscriptionId
    }
    
    /// Fetch historical messages from relay
    private func fetchMessagesFromRelay(groupId: String, channelId: String) async {
        // The subscription handler will populate the cache
        subscribeToChannelMessages(groupId: groupId, channelId: channelId)
        
        // Give relay time to send historical messages
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    /// Fetch a group definition from relay
    private func fetchGroup(id: String) async {
        var filter = NostrFilter()
        filter.kinds = [GroupEventKind.tripGroup]
        filter.setTagFilter("d", values: [id])
        filter.limit = 1
        
        let subscriptionId = "fetch-group-\(id.prefix(8))"
        
        NostrRelayManager.shared.subscribe(
            filter: filter,
            id: subscriptionId,
            handler: { [weak self] event in
                Task { @MainActor in
                    self?.handleIncomingGroup(event)
                }
            },
            onEOSE: {
                // Unsubscribe after fetching
                NostrRelayManager.shared.unsubscribe(id: subscriptionId)
            }
        )
    }
    
    // MARK: - Event Handlers
    
    /// Handle incoming group definition
    private func handleIncomingGroup(_ event: NostrEvent) {
        guard event.kind == GroupEventKind.tripGroup else { return }
        
        do {
            let group = try TripGroup.from(event: event)
            groups[group.id] = group
            
            // Check if this is one of my groups
            if group.creatorPubkey == signatureProvider?.pubkey {
                if !myGroups.contains(where: { $0.id == group.id }) {
                    myGroups.append(group)
                }
            }
        } catch {
            print("Failed to parse group: \(error)")
        }
    }
    
    /// Handle incoming invite
    private func handleIncomingInvite(_ event: NostrEvent) {
        guard event.kind == GroupEventKind.groupInvite else { return }
        
        do {
            let invite = try GroupInvite.from(event: event)
            
            // Store invite
            var groupInvites = invitesByGroup[invite.groupId] ?? []
            if !groupInvites.contains(where: { $0.id == invite.id }) {
                groupInvites.append(invite)
                invitesByGroup[invite.groupId] = groupInvites
            }
            
            // Check if this invite is for me
            if invite.inviteePubkey == signatureProvider?.pubkey {
                if !pendingInvites.contains(where: { $0.id == invite.id }) {
                    pendingInvites.append(invite)
                    
                    // Fetch the group if we don't have it
                    if groups[invite.groupId] == nil {
                        Task { await fetchGroup(id: invite.groupId) }
                    }
                }
            }
        } catch {
            print("Failed to parse invite: \(error)")
        }
    }
    
    /// Handle incoming revocation
    private func handleIncomingRevocation(_ event: NostrEvent) {
        guard event.kind == GroupEventKind.groupRevoke else { return }
        
        do {
            let revocation = try GroupRevocation.from(event: event)
            
            // Store revocation
            var groupRevocations = revocationsByGroup[revocation.groupId] ?? []
            if !groupRevocations.contains(where: { $0.id == revocation.id }) {
                groupRevocations.append(revocation)
                revocationsByGroup[revocation.groupId] = groupRevocations
            }
            
            // CRITICAL: Invalidate cache when revocation arrives
            invalidateCache(for: revocation.groupId)
            
            // If I'm revoked, remove from joined groups
            if revocation.revokedPubkey == signatureProvider?.pubkey {
                joinedGroups.removeAll { $0.id == revocation.groupId }
                myChains.removeValue(forKey: revocation.groupId)
            }
            
            // Refresh memberships
            refreshMyMemberships()
        } catch {
            print("Failed to parse revocation: \(error)")
        }
    }
    
    /// Handle incoming message
    private func handleIncomingMessage(_ event: NostrEvent) {
        guard event.kind == GroupEventKind.groupMessage else { return }
        
        guard let groupTag = event.tags.first(where: { $0.first == "group" }),
              groupTag.count > 1,
              let channelTag = event.tags.first(where: { $0.first == "channel" }),
              channelTag.count > 1 else { return }
        
        let groupId = groupTag[1]
        let channelId = channelTag[1]
        
        // Verify sender is a member (uses cache - O(1) after first check)
        guard isMember(pubkey: event.pubkey, groupId: groupId) else {
            return // Unauthorized sender - drop message
        }
        
        do {
            let message = try GroupMessage.from(event: event)
            
            // Cache the message
            let key = "\(groupId):\(channelId)"
            var messages = messageCache[key] ?? []
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                // Sort by date
                messages.sort { $0.createdAt < $1.createdAt }
                messageCache[key] = messages
                
                // Notify handler
                messageHandlers[key]?(message)
            }
        } catch {
            print("Failed to parse group message: \(error)")
        }
    }
    
    /// Refresh membership status for all my groups
    private func refreshMyMemberships() {
        for (groupId, chain) in myChains {
            guard let group = groups[groupId] else {
                myChains.removeValue(forKey: groupId)
                continue
            }
            
            let revocations = revocationsByGroup[groupId] ?? []
            if chain.verify(group: group, revocations: revocations, signatureVerifier: signatureVerifier) == nil {
                // My chain is no longer valid
                myChains.removeValue(forKey: groupId)
                joinedGroups.removeAll { $0.id == groupId }
            }
        }
    }
    
    /// Cleanup subscriptions when leaving a group
    func leaveGroup(groupId: String) {
        // Unsubscribe from relay
        if let subId = activeSubscriptions["invites-\(groupId)"] {
            NostrRelayManager.shared.unsubscribe(id: subId)
        }
        if let subId = activeSubscriptions["revokes-\(groupId)"] {
            NostrRelayManager.shared.unsubscribe(id: subId)
        }
        
        // Clean up message subscriptions
        for (key, subId) in activeSubscriptions where key.hasPrefix(groupId) {
            NostrRelayManager.shared.unsubscribe(id: subId)
            activeSubscriptions.removeValue(forKey: key)
        }
        
        // Remove from local state
        joinedGroups.removeAll { $0.id == groupId }
        myChains.removeValue(forKey: groupId)
        messageCache = messageCache.filter { !$0.key.hasPrefix(groupId) }
    }
}

// MARK: - Message Payload

struct GroupMessagePayload: Codable {
    let content: String
    let channelId: String
    let senderChainDepth: Int
}
