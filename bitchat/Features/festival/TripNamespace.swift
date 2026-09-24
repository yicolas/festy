import Foundation

/// Per-trip namespace for everything that must not leak between trips:
/// Nostr tags on shared relays, per-trip UserDefaults keys, and per-trip
/// files (trip notes, cached routes, the public mesh timeline).
///
/// The value comes from `trip.namespace` in the active trip JSON
/// (`Features/festival/trips/<MESHY_TRIP>.json`, falling back to `trip.id`).
/// Starting a new trip = add a trip JSON and point MESHY_TRIP at it.
///
/// For `"ge136c"` every derived key equals the literal it replaced, so
/// installs from the GE136C trip keep their data and stay wire-compatible.
///
/// Not trip-scoped (deliberately): BLE chat markers (`GE136C-LOC`,
/// `GE136C-SELFIE*`) are wire protocol shared with Android — versioning them
/// is yicolas/festy#7. Personal preferences (color scheme, text color, own
/// selfie, map tile source) and private chats are app-level and live in
/// `AppStorageKeys`. Map tiles ARE trip-scoped: the first-run download prompt
/// is skipped when the tile directory is non-empty, so a shared cache would
/// suppress it for the new trip's region.
enum TripNamespace {
    /// Loaded once from the bundled trip JSON. Nonisolated so background
    /// services (Nostr, persistence) can read it without hopping to main.
    static let value: String = {
        TripData.bundled?.trip.storageNamespace ?? legacy
    }()

    /// Namespace of the first deployed trip; used only when no trip JSON loads.
    static let legacy = "ge136c"

    /// UserDefaults key scoped to this trip: `<ns>.<name>`.
    static func key(_ name: String) -> String { "\(value).\(name)" }

    /// Filename scoped to this trip: `<ns>-<name>`.
    static func file(_ name: String) -> String { "\(value)-\(name)" }

    // MARK: Nostr (NIP-78 kind 30078) tags — cross-platform contract

    /// d-tag for a user's selfie within this trip.
    static var selfieDTag: String { key("selfie") }
    /// Shared k-tag so subscribers fetch every author's notes for this trip.
    static var tripNoteKTag: String { key("notes") }
    /// Prefix of the per-note d-tag: `<ns>.note.<uuid>`.
    static var tripNoteDTagPrefix: String { key("note.") }
}

/// App-level (not trip-scoped) UserDefaults keys and filenames. The literal
/// `ge136c` prefix is historical and kept so existing installs keep their
/// preferences; it is not user-visible and does not need to change per trip.
enum AppStorageKeys {
    static let colorScheme = "ge136c.colorScheme"
    static let userTextColor = "ge136c.userTextColor"
    #if os(iOS)
    // Own selfie + offline map tiles exist only in the iOS app.
    static let hasPromptedSelfie = "ge136c.hasPromptedSelfie"
    static let tileSource = "ge136c.tileSource"
    static let tileDetail = "ge136c.tileDetail"
    static let selfieFile = "ge136c-selfie.jpg"
    #endif

    static let peerSelfiesDirectory = "ge136c-peer-selfies"
    static let privateChatsFile = "ge136c-private-chats.json"
}
