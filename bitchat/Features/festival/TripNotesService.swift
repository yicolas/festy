//
// TripNotesService.swift
// bitchat
//
// Trip-scoped pinned notes on the map. Each note carries a precise lat/lon,
// a short body, and an author nickname. Storage is local (JSON in Application
// Support); propagation is via Nostr (kind 30078, NIP-78 parameterized
// replaceable) with a shared `k` tag so every GE136C user fetches the same
// shared map layer.
//
// BLE-only propagation isn't wired yet — pre-trip and post-trip, Nostr does
// the work; mid-trip the Sierras have no signal but notes are still local
// and replicate when devices come back online.
//

import Foundation
import CoreLocation
import BitLogger

/// A pin dropped on the map by any trip participant.
struct TripNote: Identifiable, Codable, Equatable {
    /// Stable per-note UUID. Used as the `d`-tag suffix so the same note can
    /// be edited / overwritten by the original author later.
    let id: String
    let latitude: Double
    let longitude: Double
    let body: String
    let author: String
    /// Nostr pubkey of the author. Optional because the local creator may not
    /// have an identity yet at the moment of writing — but we tag with one
    /// before publishing.
    let authorNostrPubkey: String?
    let createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class TripNotesService: ObservableObject {
    static let shared = TripNotesService()

    /// All known trip notes, sorted newest-first. SwiftUI observers re-render
    /// whenever this changes.
    @Published private(set) var notes: [TripNote] = []

    private let filename = "ge136c-trip-notes.json"
    private var subscriptionID: String?
    private lazy var identityBridge = NostrIdentityBridge()

    private init() {
        load()
    }

    // MARK: - Public API

    /// Drop a new note at the given coordinate. Locally persisted immediately
    /// and queued for Nostr publish (NostrRelayManager defers until Tor + relay
    /// are ready, so this is safe to call offline).
    @discardableResult
    func addNote(at coordinate: CLLocationCoordinate2D,
                 body: String,
                 author: String) -> TripNote {
        let identity = try? identityBridge.getCurrentNostrIdentity()
        let note = TripNote(
            id: UUID().uuidString,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            body: body,
            author: author,
            authorNostrPubkey: identity?.publicKeyHex,
            createdAt: Date()
        )
        upsertLocally(note)
        publish(note: note)
        return note
    }

    /// Remove a note that the local user authored. Server-side replaceable
    /// events stay until expired by the relay; we just stop showing it locally.
    func removeNote(_ note: TripNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    /// Wire to Nostr. Called once from ChatViewModel init so the subscription
    /// is up before the user opens the map.
    func startNostrSubscription() {
        guard subscriptionID == nil else { return }
        let subID = "ge136c-trip-notes"
        subscriptionID = subID
        SecureLogger.info("📌 Subscribing to trip notes", category: .session)
        NostrRelayManager.shared.subscribe(filter: NostrFilter.tripNotes(), id: subID) { [weak self] event in
            Task { @MainActor in self?.handleNostrEvent(event) }
        }
    }

    /// Re-publish every locally-authored note. Useful after restoring or
    /// changing Nostr identity. Idempotent on the relay side because each
    /// note has its own parameterized-replaceable d-tag.
    func republishAllLocal() {
        guard let identity = try? identityBridge.getCurrentNostrIdentity() else { return }
        for note in notes where note.authorNostrPubkey?.lowercased() == identity.publicKeyHex.lowercased() {
            publish(note: note)
        }
    }

    // MARK: - Nostr ingest

    private func handleNostrEvent(_ event: NostrEvent) {
        guard event.kind == NostrProtocol.EventKind.appData.rawValue else { return }
        guard event.tags.contains(where: { $0.count >= 2 && $0[0] == "k" && $0[1] == NostrProtocol.tripNoteKTag }) else { return }
        guard event.isValidSignature() else {
            SecureLogger.warning("📌 Dropped note \(event.id.prefix(8))… — bad signature", category: .security)
            return
        }

        // Extract the per-note UUID from the d-tag (ge136c.note.<UUID>).
        guard let dTag = event.tags.first(where: { $0.count >= 2 && $0[0] == "d" })?.last,
              dTag.hasPrefix("ge136c.note.") else { return }
        let noteID = String(dTag.dropFirst("ge136c.note.".count))
        guard !noteID.isEmpty else { return }

        guard let payload = NotePayload.decode(event.content) else { return }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.created_at))

        let note = TripNote(
            id: noteID,
            latitude: payload.lat,
            longitude: payload.lon,
            body: payload.body,
            author: payload.nick ?? "anon",
            authorNostrPubkey: event.pubkey,
            createdAt: timestamp
        )

        // Only accept if newer than what we have (replaceable semantics).
        if let existing = notes.first(where: { $0.id == noteID }), existing.createdAt >= timestamp {
            return
        }
        upsertLocally(note)
        SecureLogger.info("📌 Stored Nostr note \(noteID.prefix(8))… by \(note.author)", category: .session)
    }

    // MARK: - Outbound

    private func publish(note: TripNote) {
        guard let identity = try? identityBridge.getCurrentNostrIdentity() else {
            SecureLogger.warning("📌 publish skipped: no Nostr identity", category: .session)
            return
        }
        // Only publish notes WE authored (or have no recorded author yet).
        if let authorKey = note.authorNostrPubkey?.lowercased(),
           authorKey != identity.publicKeyHex.lowercased() {
            return
        }
        let payload = NotePayload(v: 1,
                                   lat: note.latitude,
                                   lon: note.longitude,
                                   body: note.body,
                                   nick: note.author)
        guard let json = payload.encode() else { return }
        guard let event = try? NostrProtocol.createTripNoteEvent(noteID: note.id,
                                                                  content: json,
                                                                  senderIdentity: identity) else {
            SecureLogger.error("📌 Trip note sign failed", category: .session)
            return
        }
        SecureLogger.info("📌 TX trip note \(note.id.prefix(8))… (\(note.body.count) chars)", category: .session)
        NostrRelayManager.shared.sendEvent(event)
    }

    // MARK: - Local store

    private func upsertLocally(_ note: TripNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.append(note)
        }
        notes.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    private var fileURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(filename)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TripNote].self, from: data) else { return }
        notes = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Wire payload

private struct NotePayload: Codable {
    let v: Int
    let lat: Double
    let lon: Double
    let body: String
    let nick: String?

    func encode() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ content: String) -> NotePayload? {
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NotePayload.self, from: data)
    }
}
