//
// AppDelegates.swift
// Meshy
//
// Application delegate classes for iOS and macOS platforms.
// Extracted from BitchatApp.swift during the Meshy refactoring.
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import SwiftUI
import UserNotifications

// MARK: - iOS App Delegate

#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var chatViewModel: ChatViewModel?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        chatViewModel?.applicationWillTerminate()
    }
}
#endif

// MARK: - macOS App Delegate

#if os(macOS)
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    weak var chatViewModel: ChatViewModel?
    
    func applicationWillTerminate(_ notification: Notification) {
        chatViewModel?.applicationWillTerminate()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var chatViewModel: ChatViewModel?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        
        // Check if this is a private message notification
        if identifier.hasPrefix("private-") {
            // Get peer ID from userInfo
            if let peerID = userInfo["peerID"] as? String {
                DispatchQueue.main.async {
                    self.chatViewModel?.startPrivateChat(with: PeerID(str: peerID))
                }
            }
        }
        // Handle deeplink (e.g., geohash activity)
        if let deep = userInfo["deeplink"] as? String, let url = URL(string: deep) {
            #if os(iOS)
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            #else
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            #endif
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        let userInfo = notification.request.content.userInfo
        
        // Check if this is a private message notification
        if identifier.hasPrefix("private-") {
            // Get peer ID from userInfo
            if let peerID = userInfo["peerID"] as? String {
                // Don't show notification if the private chat is already open
                // Access main-actor-isolated property via Task
                Task { @MainActor in
                    if self.chatViewModel?.selectedPrivateChatPeer == PeerID(str: peerID) {
                        completionHandler([])
                    } else {
                        completionHandler([.banner, .sound])
                    }
                }
                return
            }
        }
        // Suppress geohash activity notification if we're already in that geohash channel
        if identifier.hasPrefix("geo-activity-"),
           let deep = userInfo["deeplink"] as? String,
           let gh = deep.components(separatedBy: "/").last {
            if case .location(let ch) = LocationChannelManager.shared.selectedChannel, ch.geohash == gh {
                completionHandler([])
                return
            }
        }
        
        // Show notification in all other cases
        completionHandler([.banner, .sound])
    }
}
