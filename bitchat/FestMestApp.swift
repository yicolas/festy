//
// MeshyApp.swift
// Meshy
//
// Trip companion app built on bitchat mesh networking.
// Original bitchat protocol: https://github.com/permissionlesstech/bitchat
//
// festy: this file replaces upstream's bitchat/BitchatApp.swift (excluded in
// Package.swift; git tracks it as a rename). Keep it structurally identical
// to upstream's BitchatApp so future merges stay mechanical — the only
// festy differences are the `MeshyApp` name (+ `BitchatApp` typealias), the
// `TripContentView` root, and injecting `runtime.chatViewModel` for the trip
// layer. App/notification delegates live in AppDelegates.swift.
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import UserNotifications

/// Upstream code refers to `BitchatApp.bundleID` / `BitchatApp.groupID`
/// (KeychainManager, AppRuntime, …); keep those references compiling.
typealias BitchatApp = MeshyApp

@main
struct MeshyApp: App {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.meshy.app"
    static let groupID = "group.\(bundleID)"

    @StateObject private var runtime: AppRuntime
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.matrix.rawValue
    #if os(iOS)
    @Environment(\.scenePhase) var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

    init() {
        _runtime = StateObject(wrappedValue: AppRuntime())
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            // festy: trip shell (tabs, map, onboarding) hosts ContentView.
            TripContentView()
                .environment(\.appTheme, AppTheme(rawValue: appThemeRawValue) ?? .matrix)
                // festy: the trip layer still talks to ChatViewModel directly.
                .environmentObject(runtime.chatViewModel)
                .environmentObject(runtime.publicChatModel)
                .environmentObject(runtime.privateInboxModel)
                .environmentObject(runtime.privateConversationModel)
                .environmentObject(runtime.verificationModel)
                .environmentObject(runtime.conversationUIModel)
                .environmentObject(runtime.locationChannelsModel)
                .environmentObject(runtime.peerListModel)
                .environmentObject(runtime.appChromeModel)
                .environmentObject(runtime.boardAlertsModel)
                .environmentObject(runtime.sharedContentImportModel)
                .onAppear {
                    appDelegate.runtime = runtime
                    TripChatState.shared.appRuntime = runtime // festy
                    runtime.start()
                }
                .onOpenURL { url in
                    // festy: `ge136c://join` invite links turn on trip mode.
                    if url.scheme == "ge136c", url.host == "join" {
                        TripModeManager.shared.enable()
                    }
                    runtime.handleOpenURL(url)
                }
                #if os(iOS)
                .onChange(of: scenePhase) { newPhase in
                    runtime.handleScenePhaseChange(newPhase)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    runtime.handleDidBecomeActiveNotification()
                }
                #elseif os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    runtime.handleMacDidBecomeActiveNotification()
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
}

// Note: AppDelegate, MacAppDelegate, and NotificationDelegate are defined in AppDelegates.swift
