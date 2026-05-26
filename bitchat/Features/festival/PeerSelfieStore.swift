//
// PeerSelfieStore.swift
// bitchat
//
// Per-peer cache for selfies received over Nostr or BLE. Storage is keyed by
// Noise public key so it survives nickname changes; images live as files in
// Application Support and an in-memory dictionary mirrors them for fast lookup.
//

import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
final class PeerSelfieStore: ObservableObject {
    static let shared = PeerSelfieStore()

    private let directoryName = "ge136c-peer-selfies"
    private let manifestName = "manifest.json"

    private struct Entry: Codable {
        let timestamp: Date
        let file: String
        let nickname: String?
    }

    /// Bumped whenever the cache changes so SwiftUI views can re-render.
    @Published private(set) var generation: Int = 0

    private var entries: [String: Entry] = [:]
    #if os(iOS)
    private var imageCache: [String: UIImage] = [:]
    #endif

    private init() {
        load()
    }

    // MARK: - Public API

    #if os(iOS)
    /// Returns a cached selfie for the given Noise public key, if any.
    func cachedImage(forNoiseKey key: Data) -> UIImage? {
        let id = key.hexEncodedString()
        if let img = imageCache[id] { return img }
        guard let entry = entries[id] else { return nil }
        let url = directoryURL.appendingPathComponent(entry.file)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        imageCache[id] = img
        return img
    }
    #endif

    /// Returns the raw JPEG bytes for our own outbound responses or for re-broadcast.
    func cachedData(forNoiseKey key: Data) -> Data? {
        let id = key.hexEncodedString()
        guard let entry = entries[id] else { return nil }
        let url = directoryURL.appendingPathComponent(entry.file)
        return try? Data(contentsOf: url)
    }

    func nickname(forNoiseKey key: Data) -> String? {
        entries[key.hexEncodedString()]?.nickname
    }

    func timestamp(forNoiseKey key: Data) -> Date? {
        entries[key.hexEncodedString()]?.timestamp
    }

    func hasSelfie(forNoiseKey key: Data) -> Bool {
        entries[key.hexEncodedString()] != nil
    }

    /// Store/overwrite a peer selfie. Returns true if this is a new or newer copy.
    @discardableResult
    func store(imageData: Data, forNoiseKey key: Data, nickname: String?, timestamp: Date) -> Bool {
        let id = key.hexEncodedString()

        // Only replace if the incoming copy is newer (or we have nothing).
        if let existing = entries[id], existing.timestamp >= timestamp {
            return false
        }

        ensureDirectoryExists()
        let filename = "\(id).jpg"
        let url = directoryURL.appendingPathComponent(filename)
        do {
            try imageData.write(to: url, options: .atomic)
        } catch {
            return false
        }

        entries[id] = Entry(timestamp: timestamp, file: filename, nickname: nickname)
        #if os(iOS)
        imageCache[id] = UIImage(data: imageData)
        #endif
        persistManifest()
        generation &+= 1
        return true
    }

    func clear() {
        entries.removeAll()
        #if os(iOS)
        imageCache.removeAll()
        #endif
        try? FileManager.default.removeItem(at: directoryURL)
        generation &+= 1
    }

    // MARK: - Persistence

    private var directoryURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private var manifestURL: URL {
        directoryURL.appendingPathComponent(manifestName)
    }

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persistManifest() {
        ensureDirectoryExists()
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
}
