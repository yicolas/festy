//
// FestivalGroupViews.swift
// bitchat
//
// SwiftUI views for creating and managing trip groups
//

import SwiftUI

// MARK: - Group List View

struct TripGroupsView: View {
    @StateObject private var groupManager = TripGroupManager.shared
    @State private var showingCreateGroup = false
    
    var body: some View {
        List {
            // My Groups Section
            if !groupManager.myGroups.isEmpty {
                Section("My Groups") {
                    ForEach(groupManager.myGroups) { group in
                        NavigationLink(destination: TripGroupDetailView(group: group)) {
                            GroupRowView(group: group, isCreator: true)
                        }
                    }
                }
            }
            
            // Joined Groups Section
            if !groupManager.joinedGroups.isEmpty {
                Section("Joined Groups") {
                    ForEach(groupManager.joinedGroups) { group in
                        NavigationLink(destination: TripGroupDetailView(group: group)) {
                            GroupRowView(group: group, isCreator: false)
                        }
                    }
                }
            }
            
            // Pending Invites Section
            if !groupManager.pendingInvites.isEmpty {
                Section("Pending Invites") {
                    ForEach(groupManager.pendingInvites, id: \.id) { invite in
                        PendingInviteRow(invite: invite)
                    }
                }
            }
            
            // Empty State
            if groupManager.myGroups.isEmpty && 
               groupManager.joinedGroups.isEmpty && 
               groupManager.pendingInvites.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Groups Yet")
                            .font(.headline)
                        Text("Create a group to coordinate with friends on the trip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingCreateGroup = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView()
        }
    }
}

// MARK: - Group Row

struct GroupRowView: View {
    let group: TripGroup
    let isCreator: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Group Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: group.isPrivate ? "lock.fill" : "person.3.fill")
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(group.name)
                        .font(.headline)
                    if isCreator {
                        Text("Creator")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(group.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let start = group.scheduledStart {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(start, style: .date)
                            .font(.caption)
                        Text("at")
                            .font(.caption)
                        Text(start, style: .time)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Channel count badge
            Text("\(group.channels.count)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(12)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pending Invite Row

struct PendingInviteRow: View {
    let invite: GroupInvite
    @StateObject private var groupManager = TripGroupManager.shared
    @State private var isAccepting = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Invite to join group")
                    .font(.headline)
                Text("From: \(invite.inviterPubkey.prefix(16))...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Depth: \(invite.depth)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: acceptInvite) {
                if isAccepting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Accept")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAccepting)
        }
    }
    
    private func acceptInvite() {
        isAccepting = true
        do {
            try groupManager.acceptInvite(invite)
        } catch {
            print("Failed to accept invite: \(error)")
        }
        isAccepting = false
    }
}

// MARK: - Create Group View

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupManager = TripGroupManager.shared
    
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true
    @State private var hasSchedule = false
    @State private var scheduledStart = Date()
    @State private var scheduledEnd = Date().addingTimeInterval(3600)
    @State private var maxDepth = 5
    @State private var channels: [TripGroup.GroupChannel] = []
    @State private var showingAddChannel = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section("Group Info") {
                    TextField("Group Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Privacy
                Section {
                    Toggle("Private Group", isOn: $isPrivate)
                    if isPrivate {
                        Stepper("Max Invite Depth: \(maxDepth)", value: $maxDepth, in: 1...10)
                        Text("Members can invite others up to \(maxDepth) levels deep")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    if isPrivate {
                        Text("Private groups require an invite chain to join. Revoking someone also revokes everyone they invited.")
                    }
                }
                
                // Schedule
                Section("Schedule (Optional)") {
                    Toggle("Has Scheduled Time", isOn: $hasSchedule)
                    if hasSchedule {
                        DatePicker("Start", selection: $scheduledStart)
                        DatePicker("End", selection: $scheduledEnd)
                    }
                }
                
                // Channels
                Section {
                    ForEach(channels) { channel in
                        HStack {
                            Image(systemName: channel.icon ?? "bubble.left")
                            VStack(alignment: .leading) {
                                Text(channel.name)
                                    .font(.headline)
                                Text(channel.description ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteChannel)
                    
                    Button(action: { showingAddChannel = true }) {
                        Label("Add Channel", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Channels")
                } footer: {
                    Text("Channels are sub-chats within your group. Default channels will be created if you don't add any.")
                }
                
                // Error
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createGroup() }
                        .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddChannel) {
                AddChannelView(channels: $channels)
            }
        }
    }
    
    private func deleteChannel(at offsets: IndexSet) {
        channels.remove(atOffsets: offsets)
    }
    
    private func createGroup() {
        do {
            _ = try groupManager.createGroup(
                name: name,
                description: description,
                tripId: nil,  // Could be linked to current trip
                geohash: nil,     // Could use current location
                scheduledStart: hasSchedule ? scheduledStart : nil,
                scheduledEnd: hasSchedule ? scheduledEnd : nil,
                channels: channels,
                isPrivate: isPrivate,
                maxDepth: maxDepth
            )
            dismiss()
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
        }
    }
}

// MARK: - Add Channel View

struct AddChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var channels: [TripGroup.GroupChannel]
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon = "bubble.left.and.bubble.right"
    
    let availableIcons = [
        "bubble.left.and.bubble.right",
        "megaphone",
        "music.note",
        "mappin.and.ellipse",
        "car",
        "fork.knife",
        "cross.case",
        "questionmark.circle",
        "heart",
        "star"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Channel Info") {
                    TextField("Channel Name", text: $name)
                    TextField("Description", text: $description)
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addChannel() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func addChannel() {
        let channelId = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let channel = TripGroup.GroupChannel(
            id: channelId,
            name: "#\(name.lowercased())",
            description: description,
            icon: selectedIcon
        )
        channels.append(channel)
        dismiss()
    }
}

// MARK: - Group Detail View

struct TripGroupDetailView: View {
    let group: TripGroup
    @StateObject private var groupManager = TripGroupManager.shared
    @State private var showingInvite = false
    @State private var showingMembers = false
    
    var isCreator: Bool {
        groupManager.myGroups.contains { $0.id == group.id }
    }
    
    var body: some View {
        List {
            // Group Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.name)
                            .font(.title2)
                            .bold()
                        Spacer()
                        if group.isPrivate {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(group.description)
                        .foregroundColor(.secondary)
                    
                    if let start = group.scheduledStart {
                        Divider()
                        HStack {
                            Image(systemName: "calendar")
                            Text(start, style: .date)
                            Text("at")
                            Text(start, style: .time)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            // Channels
            Section("Channels") {
                ForEach(group.channels) { channel in
                    NavigationLink(destination: GroupChannelView(group: group, channel: channel)) {
                        HStack {
                            Image(systemName: channel.icon ?? "bubble.left")
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(channel.name)
                                    .font(.headline)
                                Text(channel.description ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Actions
            Section {
                if isCreator || group.isPrivate {
                    Button(action: { showingInvite = true }) {
                        Label("Invite Someone", systemImage: "person.badge.plus")
                    }
                }
                
                Button(action: { showingMembers = true }) {
                    Label("View Members", systemImage: "person.3")
                }
            }
            
            // Group Info
            Section("Group Info") {
                LabeledContent("Created", value: group.createdAt.formatted())
                LabeledContent("Max Invite Depth", value: "\(group.maxDepth)")
                if group.isPrivate {
                    LabeledContent("Privacy", value: "Invite Only")
                } else {
                    LabeledContent("Privacy", value: "Public")
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingInvite) {
            InviteMemberView(group: group)
        }
        .sheet(isPresented: $showingMembers) {
            GroupMembersView(group: group)
        }
    }
}

// MARK: - Invite Member View

struct InviteMemberView: View {
    let group: TripGroup
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupManager = TripGroupManager.shared
    
    @State private var pubkeyInput = ""
    @State private var errorMessage: String?
    @State private var createdInvite: GroupInvite?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nostr Public Key (npub or hex)", text: $pubkeyInput)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Invite Member")
                } footer: {
                    Text("Enter the Nostr public key of the person you want to invite. They can then invite others up to \(group.maxDepth) levels deep.")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                if let invite = createdInvite {
                    Section("Invite Created") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Share this invite with the person:")
                                .font(.subheadline)
                            Text(invite.id)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Invite to \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") { createInvite() }
                        .disabled(pubkeyInput.isEmpty || createdInvite != nil)
                }
            }
        }
    }
    
    private func createInvite() {
        // Convert npub to hex if needed
        let pubkey = pubkeyInput.hasPrefix("npub") 
            ? convertNpubToHex(pubkeyInput) ?? pubkeyInput 
            : pubkeyInput
        
        do {
            createdInvite = try groupManager.invite(
                groupId: group.id,
                inviteePubkey: pubkey
            )
        } catch {
            errorMessage = "Failed to create invite: \(error.localizedDescription)"
        }
    }
    
    private func convertNpubToHex(_ npub: String) -> String? {
        // Would use Bech32 decoding - placeholder
        return nil
    }
}

// MARK: - Group Members View

struct GroupMembersView: View {
    let group: TripGroup
    @StateObject private var groupManager = TripGroupManager.shared
    @State private var members: [String] = []
    @State private var showingRevokeAlert = false
    @State private var memberToRevoke: String?
    
    var isCreator: Bool {
        groupManager.myGroups.contains { $0.id == group.id }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Creator") {
                    MemberRow(pubkey: group.creatorPubkey, isCreator: true)
                }
                
                Section("Members (\(members.count))") {
                    ForEach(members.filter { $0 != group.creatorPubkey }, id: \.self) { pubkey in
                        MemberRow(pubkey: pubkey, isCreator: false)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if isCreator {
                                    Button("Revoke", role: .destructive) {
                                        memberToRevoke = pubkey
                                        showingRevokeAlert = true
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                members = groupManager.getMembers(groupId: group.id)
            }
            .alert("Revoke Access", isPresented: $showingRevokeAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Revoke", role: .destructive) {
                    if let pubkey = memberToRevoke {
                        revokeMember(pubkey)
                    }
                }
            } message: {
                Text("This will revoke access for this member and everyone they invited. This action cannot be undone.")
            }
        }
    }
    
    private func revokeMember(_ pubkey: String) {
        do {
            _ = try groupManager.revoke(
                groupId: group.id,
                memberPubkey: pubkey,
                reason: "Removed by creator"
            )
            members = groupManager.getMembers(groupId: group.id)
        } catch {
            print("Failed to revoke: \(error)")
        }
    }
}

struct MemberRow: View {
    let pubkey: String
    let isCreator: Bool
    
    var body: some View {
        HStack {
            // Avatar placeholder
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(pubkey.prefix(2)).uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
            
            VStack(alignment: .leading) {
                Text(pubkey.prefix(16) + "...")
                    .font(.system(.body, design: .monospaced))
                if isCreator {
                    Text("Creator")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}


// MARK: - Group Channel View (Chat)

/// Chat view for a specific channel within a group
/// Integrates with the existing chat infrastructure
struct GroupChannelView: View {
    let group: TripGroup
    let channel: TripGroup.GroupChannel
    
    @EnvironmentObject var chatViewModel: ChatViewModel
    @ObservedObject var groupManager = TripGroupManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    @State private var messageText = ""
    @State private var messages: [GroupMessage] = []
    @State private var isLoading = true
    @FocusState private var isInputFocused: Bool
    
    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.7) : Color(red: 0.102, green: 0.102, blue: 0.306)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else if messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(messages) { message in
                                GroupMessageBubble(
                                    message: message,
                                    isOwnMessage: message.senderPubkey == groupManager.myPubkey
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input bar
            inputBar
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { loadMessages() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(action: {}) {
                        Label("Channel Info", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadMessages()
            subscribeToChannel()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: channel.icon ?? "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No messages yet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Be the first to say something in \(channel.name)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message \(channel.name)", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(20)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(sendMessage)
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? .secondary : textColor)
            }
            .disabled(messageText.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    private func loadMessages() {
        isLoading = true
        Task {
            // Load messages from group manager
            let loaded = await groupManager.loadMessages(groupId: group.id, channelId: channel.id)
            await MainActor.run {
                messages = loaded
                isLoading = false
            }
        }
    }
    
    private func subscribeToChannel() {
        // Subscribe to new messages for this channel
        groupManager.subscribeToGroupMessages(groupId: group.id, channelId: channel.id) { newMessage in
            // Avoid duplicates
            if !messages.contains(where: { $0.id == newMessage.id }) {
                messages.append(newMessage)
            }
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        messageText = ""
        isInputFocused = false
        
        Task {
            do {
                let message = try await groupManager.sendMessage(
                    groupId: group.id,
                    channelId: channel.id,
                    content: text
                )
                await MainActor.run {
                    messages.append(message)
                }
            } catch {
                print("Failed to send message: \(error)")
                // Restore message on failure
                await MainActor.run {
                    messageText = text
                }
            }
        }
    }
}

// MARK: - Group Message Bubble

struct GroupMessageBubble: View {
    let message: GroupMessage
    let isOwnMessage: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    private var bubbleColor: Color {
        if isOwnMessage {
            return colorScheme == .dark ? Color(red: 0.3, green: 0.3, blue: 0.5) : Color(red: 0.8, green: 0.8, blue: 0.95)
        } else {
            return colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.25) : Color(red: 0.9, green: 0.9, blue: 0.92)
        }
    }
    
    var body: some View {
        HStack {
            if isOwnMessage { Spacer(minLength: 60) }
            
            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                if !isOwnMessage {
                    Text(message.senderPubkey.prefix(8) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .cornerRadius(16)
                
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isOwnMessage { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TripGroupsView()
    }
}
