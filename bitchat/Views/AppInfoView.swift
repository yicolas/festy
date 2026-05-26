//
// AppInfoView.swift
// Meshy
//
// Unified "How to use & Settings" page — the only place for user controls,
// privacy disclosures, and the trip-specific walkthrough.
//

import SwiftUI

struct AppInfoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var networkService = NetworkActivationService.shared
    @State private var showClearChatConfirm: Bool = false
    @State private var showTextColorPicker: Bool = false
    #if os(iOS)
    @ObservedObject private var selfieStore = UserSelfieStore.shared
    @ObservedObject private var locationService = FriendLocationService.shared
    @State private var showSelfieCamera: Bool = false
    @State private var pickedSelfie: UIImage?
    #endif
    @AppStorage("ge136c.colorScheme") private var colorSchemePreference: String = "system"
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        TripTheme.uiTint
    }
    
    private var secondaryTextColor: Color {
        TripTheme.uiTint.opacity(0.8)
    }
    
    // MARK: - Constants
    private enum Strings {
        static let appName: LocalizedStringKey = "app_info.app_name"
        static let tagline: LocalizedStringKey = "app_info.tagline"

        enum Features {
            static let title: LocalizedStringKey = "app_info.features.title"
            static let offlineComm = AppInfoFeatureInfo(
                icon: "wifi.slash",
                title: "app_info.features.offline.title",
                description: "app_info.features.offline.description"
            )
            static let encryption = AppInfoFeatureInfo(
                icon: "lock.shield",
                title: "app_info.features.encryption.title",
                description: "app_info.features.encryption.description"
            )
            static let extendedRange = AppInfoFeatureInfo(
                icon: "antenna.radiowaves.left.and.right",
                title: "app_info.features.extended_range.title",
                description: "app_info.features.extended_range.description"
            )
            static let mentions = AppInfoFeatureInfo(
                icon: "at",
                title: "app_info.features.mentions.title",
                description: "app_info.features.mentions.description"
            )
            static let favorites = AppInfoFeatureInfo(
                icon: "star.fill",
                title: "app_info.features.favorites.title",
                description: "app_info.features.favorites.description"
            )
            static let geohash = AppInfoFeatureInfo(
                icon: "number",
                title: "app_info.features.geohash.title",
                description: "app_info.features.geohash.description"
            )
        }

        enum Privacy {
            static let title: LocalizedStringKey = "app_info.privacy.title"
            static let noTracking = AppInfoFeatureInfo(
                icon: "eye.slash",
                title: "app_info.privacy.no_tracking.title",
                description: "app_info.privacy.no_tracking.description"
            )
            static let ephemeral = AppInfoFeatureInfo(
                icon: "shuffle",
                title: "app_info.privacy.ephemeral.title",
                description: "app_info.privacy.ephemeral.description"
            )
            static let panic = AppInfoFeatureInfo(
                icon: "hand.raised.fill",
                title: "app_info.privacy.panic.title",
                description: "app_info.privacy.panic.description"
            )
        }

        enum HowToUse {
            static let title: LocalizedStringKey = "app_info.how_to_use.title"
            static let instructions: [LocalizedStringKey] = [
                "app_info.how_to_use.set_nickname",
                "app_info.how_to_use.change_channels",
                "app_info.how_to_use.open_sidebar",
                "app_info.how_to_use.start_dm",
                "app_info.how_to_use.clear_chat",
                "app_info.how_to_use.commands"
            ]
        }

    }
    
    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Custom header for macOS
            HStack {
                Spacer()
                Button("app_info.done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(textColor)
                .padding()
            }
            .background(backgroundColor.opacity(0.95))
            
            ScrollView {
                infoContent
            }
            .background(backgroundColor)
        }
        .frame(width: 600, height: 700)
        #else
        NavigationView {
            ScrollView {
                infoContent
            }
            .background(backgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("app_info.close")
                }
            }
        }
        #endif
    }
    
    @ViewBuilder
    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header — Meshy/GE136C rebrand. Tagline calls out that this page
            // doubles as the how-to guide AND the settings hub.
            VStack(alignment: .center, spacing: 10) {
                Image("MeshyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Meshy")
                    .font(.bitchatSystem(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor)

                Text("GE136C Spring — Sierras 2026")
                    .font(.bitchatSystem(size: 13, design: .monospaced))
                    .foregroundColor(secondaryTextColor)

                Text("How to use & Settings")
                    .font(.bitchatSystem(size: 14, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)

            // How to Use — trip-specific guide moved here from the Info tab
            // so there's one canonical place for the walkthrough.
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("HOW TO USE")

                howSection("Tabs at the bottom", items: [
                    ("calendar", "Schedule — every stop + presenter for each day"),
                    ("number", "Channels — jump to a #channel chat"),
                    ("map", "Map — pins, routes, friend dots, notes"),
                    ("bubble.left.and.bubble.right", "Chat — talk to the group, filtered by channel"),
                    ("info.circle", "Info — schedule details + about page entry")
                ])
                howSection("Channels", items: [
                    ("person.3.fill", "#main — main trip chat, start here"),
                    ("megaphone.fill", "#announcements — instructor-only high-priority notices"),
                    ("car.fill", "#cars — pick your car by driver's first name, then chat with carmates"),
                    ("speedometer", "#driving — ETAs, regrouping, driver changes"),
                    ("fork.knife", "#meals — dinner menus & food coordination"),
                    ("backpack.fill", "#gear — broken / missing / lost & found")
                ])
                howSection("Map buttons (left side)", items: [
                    ("list.bullet", "Live — see who's sharing location right now"),
                    ("figure.hiking", "Trails — view the Kings Canyon / South Creek hike polylines"),
                    ("calendar", "Routes — toggle which day routes appear on the map"),
                    ("scope", "Fit — zoom out to fit every stop + friend"),
                    ("note.text.badge.plus", "Notes — drop a draggable yellow pin, then add a note"),
                    ("arrow.down.circle", "Offline — download topo tiles + driving routes for no-service areas")
                ])
                howSection("Top-right menu", items: [
                    ("line.3.horizontal", "Switch tabs, share invite, open this How to use & Settings page")
                ])
                howSection("Pro tips", items: [
                    ("location.fill", "Turn on Share live location to see your dot on the map and unlock the map view"),
                    ("hand.tap.fill", "Tap a channel from Channels OR from #filter to jump straight in"),
                    ("square.and.pencil", "Typing in #driving auto-appends the tag — no need to type the # yourself")
                ])
            }

            // Settings — all user-controlled toggles + actions in one place.
            settingsSection

            // Features
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(Strings.Features.title)

                FeatureRow(info: Strings.Features.offlineComm)

                FeatureRow(info: Strings.Features.encryption)

                FeatureRow(info: Strings.Features.extendedRange)

                FeatureRow(info: Strings.Features.favorites)

                FeatureRow(info: Strings.Features.geohash)

                FeatureRow(info: Strings.Features.mentions)
            }

            // Privacy
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(Strings.Privacy.title)

                FeatureRow(info: Strings.Privacy.noTracking)

                FeatureRow(info: Strings.Privacy.ephemeral)
                // Panic-mode row removed: panic clear is out of scope for the
                // trip use case and was removed from the app.
            }

            // Network & Privacy Settings
            NetworkPrivacySection()

            // Trip Mode
            TripAppInfoSection()

            // Data & Third Parties
            DataDisclosureSection()

            // About & Attribution
            AboutSection()
        }
        .padding()
        .confirmationDialog("Clear chat history?",
                            isPresented: $showClearChatConfirm,
                            titleVisibility: .visible) {
            Button("Clear chat", role: .destructive) {
                viewModel.clearCurrentPublicTimeline()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes messages from this device only. Other phones keep their copies.")
        }
        #if os(iOS)
        .sheet(isPresented: $showTextColorPicker) {
            TextColorPickerSheet()
        }
        .sheet(isPresented: $showSelfieCamera, onDismiss: {
            if let img = pickedSelfie {
                selfieStore.save(img)
                pickedSelfie = nil
            }
        }) {
            CameraPicker(image: $pickedSelfie)
                .ignoresSafeArea()
        }
        #endif
    }

    /// User-controlled settings consolidated. Appears between "How to use" and
    /// the static feature/privacy descriptions so the most interactive controls
    /// are near the top.
    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("SETTINGS")

            #if os(iOS)
            // Selfie management
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let img = selfieStore.image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(TripTheme.accent, lineWidth: 1.5))
                    } else {
                        Image(systemName: "person.crop.circle.fill.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(TripTheme.accent)
                            .frame(width: 44, height: 44)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile picture")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                    Text(selfieStore.image == nil ? "Add a selfie for the map" : "Tap to retake")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                Spacer()
                if selfieStore.image != nil {
                    Button(role: .destructive) { selfieStore.delete() } label: {
                        Image(systemName: "trash")
                    }
                }
                Button { showSelfieCamera = true } label: {
                    Image(systemName: "camera")
                        .foregroundColor(textColor)
                }
            }
            .padding(.vertical, 4)
            #endif

            // Appearance (light/dark/system)
            Menu {
                Button { colorSchemePreference = "system" } label: {
                    Label("System default", systemImage: colorSchemePreference == "system" ? "checkmark" : "iphone")
                }
                Button { colorSchemePreference = "light" } label: {
                    Label("Light", systemImage: colorSchemePreference == "light" ? "checkmark" : "sun.max")
                }
                Button { colorSchemePreference = "dark" } label: {
                    Label("Dark", systemImage: colorSchemePreference == "dark" ? "checkmark" : "moon")
                }
            } label: {
                settingsRow(icon: "circle.lefthalf.filled",
                             title: "Appearance",
                             subtitle: appearanceSubtitle)
            }

            #if os(iOS)
            Button(action: { showTextColorPicker = true }) {
                settingsRow(icon: "paintpalette",
                             title: "Text color",
                             subtitle: "Pick the color your messages display in")
            }
            .buttonStyle(.plain)

            // Location sharing toggle
            Toggle(isOn: Binding(
                get: { locationService.isSharing },
                set: { newValue in
                    if newValue { locationService.startSharing() }
                    else { locationService.stopSharing() }
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: locationService.isSharing ? "location.fill" : "location.slash")
                        .font(.system(size: 18))
                        .foregroundColor(textColor)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share my location")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
                        Text("Broadcasts your position to trip peers every ~30s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            .tint(textColor)
            #endif

            // Clear chat
            Button(action: { showClearChatConfirm = true }) {
                settingsRow(icon: "trash",
                             title: "Clear chat history",
                             subtitle: "Removes locally cached messages. Peers keep theirs.")
            }
            .buttonStyle(.plain)

            // Favorites list
            NavigationLink {
                FavoritesListView()
            } label: {
                settingsRow(icon: "star.fill",
                             title: "Favorites",
                             subtitle: "\(FavoritesPersistenceService.shared.favorites.count) saved",
                             chevron: true)
            }
        }
    }

    /// Trip-specific guide block reused inside the How-To section.
    @ViewBuilder
    private func howSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(TripTheme.accent)
            ForEach(items, id: \.1) { icon, desc in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .foregroundColor(TripTheme.accent)
                        .frame(width: 18)
                    Text(desc)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var appearanceSubtitle: String {
        switch colorSchemePreference {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "Follows system"
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(textColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor)
                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Read-only list of favorited peers (mutual + one-way). Lives inside the
/// Settings sheet so users can audit who they've added.
struct FavoritesListView: View {
    @ObservedObject private var favorites = FavoritesPersistenceService.shared

    var body: some View {
        let entries = favorites.favorites.values.sorted { $0.peerNickname < $1.peerNickname }
        List {
            if entries.isEmpty {
                Text("No favorites yet. Star someone in a DM to add them.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            } else {
                ForEach(entries, id: \.peerNoisePublicKey) { fav in
                    HStack(spacing: 10) {
                        Image(systemName: fav.isMutual ? "person.2.fill" : "person.fill")
                            .foregroundColor(TripTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fav.peerNickname)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(TripTheme.primaryText)
                            Text(fav.isMutual ? "Mutual" : "You favorited them")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(TripTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Network & Privacy Settings Section

struct NetworkPrivacySection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var networkService = NetworkActivationService.shared
    
    private var textColor: Color {
        TripTheme.uiTint
    }
    
    private var secondaryTextColor: Color {
        TripTheme.uiTint.opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("NETWORK SETTINGS")
            
            // Tor Toggle
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { networkService.userTorEnabled },
                    set: { networkService.setUserTorEnabled($0) }
                )) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.system(size: 20))
                            .foregroundColor(textColor)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tor Network")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(textColor)
                            
                            Text("Route internet traffic through Tor to hide your IP address from Nostr relays")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(textColor)
                
                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(networkService.userTorEnabled ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(networkService.userTorEnabled 
                         ? "Your IP is hidden from relays" 
                         : "Relays can see your IP address")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.leading, 42)
            }
            .padding()
            .background(textColor.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(textColor.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Data Disclosure Section

struct DataDisclosureSection: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    
    private var textColor: Color {
        TripTheme.uiTint
    }
    
    private var secondaryTextColor: Color {
        TripTheme.uiTint.opacity(0.8)
    }
    
    private var warningColor: Color {
        colorScheme == .dark ? Color.orange : Color.orange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("DATA & THIRD PARTIES")
            
            // Internet Features Warning
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(warningColor)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When Using Internet Features")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Text("Location channels, distant private messages, and trip groups use third-party Nostr relays when internet is available.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Expandable details
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        // What relays see
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Relays CAN see:")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(warningColor)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                BulletPoint("Your public key (not your real identity)")
                                BulletPoint("Approximate location (~150m) when using location channels")
                                BulletPoint("Encrypted message content (unreadable)")
                                BulletPoint("Timestamps")
                            }
                        }
                        
                        Divider()
                            .background(textColor.opacity(0.3))
                        
                        // What relays cannot see
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Relays CANNOT see:")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                BulletPoint("Your real name, email, or phone number")
                                BulletPoint("Decrypted message content")
                                BulletPoint("Your exact GPS location")
                                BulletPoint("Your IP address (when Tor is enabled)")
                            }
                        }
                        
                        Divider()
                            .background(textColor.opacity(0.3))
                        
                        // Relay list
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Default Relays:")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(textColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(defaultRelays, id: \.self) { relay in
                                    Text(relay)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(isExpanded ? "Hide Details" : "Show Details")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                }
                .tint(textColor)
            }
            .padding()
            .background(warningColor.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(warningColor.opacity(0.3), lineWidth: 1)
            )
            
            // Location disclosure
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 20))
                        .foregroundColor(textColor)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location Data")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Text("Location is only accessed when you use location channels or friend sharing. Your GPS is converted to an approximate area (~150m) before being shared. Location is never stored or tracked in the background.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .background(textColor.opacity(0.05))
            .cornerRadius(8)
            
            // Privacy policy link removed — no canonical policy URL for Meshy
            // yet. Reintroduce when the repo + policy doc exist.
        }
    }
    
    private var defaultRelays: [String] {
        [
            "relay.damus.io",
            "nos.lol", 
            "relay.primal.net",
            "offchain.pub",
            "nostr21.com"
        ]
    }
}

// MARK: - About Section

struct AboutSection: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        TripTheme.uiTint
    }
    
    private var secondaryTextColor: Color {
        TripTheme.uiTint.opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("ABOUT")
            
            VStack(alignment: .leading, spacing: 12) {
                // Attribution to upstream bitchat protocol
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Built on bitchat")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)

                        Text("Meshy is built on top of bitchat, an open-source Bluetooth mesh chat protocol created by Jack Dorsey. Thank you to the bitchat team for making decentralized communication accessible to everyone.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Co-developers
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 20))
                        .foregroundColor(TripTheme.accent)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Co-developers")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)

                        Text("Nick Anderson & Madison Dunitz")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                }

                // Links
                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/permissionlesstech/bitchat")!) {
                        HStack {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                            Text("Original bitchat Project")
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(textColor)
                    }

                    Link(destination: URL(string: "https://github.com/MDunitz")!) {
                        HStack {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                            Text("Madison Dunitz on GitHub")
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(textColor)
                    }
                }
                .padding(.leading, 42)
                
                // License
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 20))
                        .foregroundColor(textColor)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Source")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Text("Released into the public domain under The Unlicense. You are free to use, modify, and distribute this software.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .background(textColor.opacity(0.05))
            .cornerRadius(8)
            
            // Version
            HStack {
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                Spacer()
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Helper Views

struct BulletPoint: View {
    let text: String
    @Environment(\.colorScheme) var colorScheme
    
    private var secondaryTextColor: Color {
        TripTheme.uiTint.opacity(0.8)
    }
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 12, design: .monospaced))
            Text(text)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundColor(secondaryTextColor)
    }
}

struct AppInfoFeatureInfo {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        TripTheme.uiTint
    }
    
    init(_ title: LocalizedStringKey) {
        self.title = title
    }
    
    init(_ title: String) {
        self.title = LocalizedStringKey(title)
    }
    
    var body: some View {
        Text(title)
            .font(.bitchatSystem(size: 16, weight: .bold, design: .monospaced))
            .foregroundColor(textColor)
            .padding(.top, 8)
    }
}

struct FeatureRow: View {
    let info: AppInfoFeatureInfo
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        TripTheme.uiTint
    }
    
    private var secondaryTextColor: Color {
        TripTheme.uiTint.opacity(0.8)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: info.icon)
                .font(.bitchatSystem(size: 20))
                .foregroundColor(textColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(.bitchatSystem(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor)
                
                Text(info.description)
                    .font(.bitchatSystem(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

#Preview("Default") {
    AppInfoView()
}

#Preview("Dynamic Type XXL") {
    AppInfoView()
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Dynamic Type XS") {
    AppInfoView()
        .environment(\.sizeCategory, .extraSmall)
}
