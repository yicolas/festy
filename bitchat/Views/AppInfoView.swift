//
// AppInfoView.swift
// FestMest
//
// App information, settings, and privacy disclosures
//

import SwiftUI

struct AppInfoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var networkService = NetworkActivationService.shared
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
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
            // Header
            VStack(alignment: .center, spacing: 8) {
                Text(Strings.appName)
                    .font(.bitchatSystem(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor)
                
                Text(Strings.tagline)
                    .font(.bitchatSystem(size: 16, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            
            // How to Use
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(Strings.HowToUse.title)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(Strings.HowToUse.instructions.enumerated()), id: \.offset) { _, instruction in
                        Text(instruction)
                    }
                }
                .font(.bitchatSystem(size: 14, design: .monospaced))
                .foregroundColor(textColor)
            }

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

                FeatureRow(info: Strings.Privacy.panic)
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
    }
}

// MARK: - Network & Privacy Settings Section

struct NetworkPrivacySection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var networkService = NetworkActivationService.shared
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
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
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
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
            
            // Privacy Policy Link
            Link(destination: URL(string: "https://github.com/MDunitz/festmest/blob/main/PRIVACY_POLICY.md")!) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                    Text("View Full Privacy Policy")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                }
                .foregroundColor(textColor)
                .padding()
                .background(textColor.opacity(0.05))
                .cornerRadius(8)
            }
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
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("ABOUT")
            
            VStack(alignment: .leading, spacing: 12) {
                // Attribution
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Built on bitchat")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Text("FestMest is built on top of bitchat, an open-source Bluetooth mesh chat protocol created by Jack Dorsey. Thank you to the bitchat team for making decentralized communication accessible to everyone.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
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
                    
                    Link(destination: URL(string: "https://github.com/MDunitz/festmest")!) {
                        HStack {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                            Text("FestMest Source Code")
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
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
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
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
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
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
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
