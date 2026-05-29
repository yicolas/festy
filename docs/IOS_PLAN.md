# Festy (Fest-Mesh iOS) — architecture, design & forward plan

> Canonical iOS planning doc. Counterpart to `MDunitz/fest-mesh-android` `docs/ANDROID_PLAN.md`.
> **Issue tracking is currently disabled on this repo** — the forward-plan items below become issues once it's enabled.
> Complements existing docs: `TOR-INTEGRATION.md`, `GeohashPresenceSpec.md`, `SOURCE_ROUTING.md`, `privacy-assessment.md`.

## Goals
Privacy-first, offline-capable companion for festivals / group trips where cell service drops. Communication and shared context keep working off-grid over a **Bluetooth mesh**, and sync over the internet (**Nostr relays via Tor**) when reachable. No central server; identity is cryptographic; private messaging is E2E-encrypted. Built as a fork of **bitchat** with an additive festival/trip layer, configurable per trip via JSON. First real deployment: the Caltech **GE136C** field trip (May 2026). Cross-platform with the Android client (`fest-mesh-android`) — the two share wire formats, and **iOS is the canonical source** for them.

## Architecture (by layer)
- **Transport** (`Services/`): a `Transport`/`TransportConfig` abstraction over two transports — **BLE mesh** (`Services/BLE/BLEService`) for off-grid, and **Nostr** (`NostrTransport`) for internet. `MessageRouter` selects/falls back; supported by `MeshTopologyTracker`, `MessageDeduplicationService`, `RelayController`, `NetworkActivationService`.
- **Encryption** (`Noise/`): Noise Protocol (XX) sessions for E2E private messages over the mesh — `NoiseSessionManager`, `NoiseEncryptionService`, plus rate-limiter/validators.
- **Identity** (`Identity/`, `Nostr/`): dual identity — Noise static key (mesh peer id) + Nostr key (`NostrIdentity`/`NostrIdentityBridge`); `SecureIdentityStateManager`, `KeychainManager`, `Bech32`.
- **Nostr** (`Nostr/`): `NostrProtocol` (event kinds — gift-wrapped DMs, geohash ephemeral `20000` / presence `20001`, and **NIP-78 app-data kind `30078`** for shared festival layers), `NostrRelayManager` (relays run over **Tor**), `GeoRelayDirectory` (geo-scoped relays), `NostrEmbeddedBitChat`.
- **Sync** (`Sync/`): peer message reconciliation — `GossipSyncManager`, `RequestSyncManager`, `GCSFilter` (Golomb-coded set filter).
- **Wire protocol** (`Protocols/`, `Models/`): `BinaryProtocol` (BLE packet format), `BitchatPacket`/`BitchatMessage`, `NoisePayload` (payload type bytes incl. `0x20`), `Geohash`/`LocationChannel`.
- **App/coordination** (`ViewModels/`): `ChatViewModel` (central), `GeoChannelCoordinator`, public-timeline pipeline.
- **Geohash location channels** (`Services/`): location-scoped public channels — `GeohashPresenceService`, `GeohashParticipantTracker`, `LocationStateManager`, `LocationNotesManager`.
- **Festival/trip feature** (`Features/festival/`):
  - *Data:* `FestivalModels` — `TripData` / `TripScheduleManager` (`@Published tripData`, `configuredTabs`, `allLocations`, `mapConfig`, channels/infoSections), `TripSchedule.json`.
  - *UI host:* `TripMainView` (aliased `FestivalMainView`) — data-driven tabs (`TabType`); `FestivalScheduleView`, `FestivalChannelsView`, `FestivalAppInfoSection`.
  - *Map:* `FriendMapView` — `MKMapView` + `TileCacheManager`/`CachedTileOverlay` (offline OpenTopoMap/OSM raster tiles, tiers z9–13) + `RouteCache` (precomputed driving routes) + friend markers + trip-note pins + draft notes.
  - *Friend location:* `FriendLocationService` — marker-over-chat, mutual-favorite gated.
  - *Selfies:* `SelfieSyncService` + `UserSelfieStore`/`PeerSelfieStore` — **dual transport** (BLE marker + Nostr 30078).
  - *Trip notes:* `TripNotesService` — local JSON + Nostr NIP-78 30078, parameterized-replaceable.
  - `FestivalModeManager` (mode gate).

## Two notes systems — do not conflate
- `LocationNotesManager` (`Services/`): geohash-scoped public notes, **kind-1** text notes on geo relays (part of location channels).
- `TripNotesService` (`Features/festival/`): trip-wide shared notes, **NIP-78 kind 30078**, local-first JSON + Nostr. Full mechanism in the Android-side `docs/TRIP_NOTES_AUDIT.md`.

## Cross-platform wire contracts (iOS canonical — source of truth for Android parity)
- **Friend location** — `FriendLocationService`: marker `\u{1}GE136C-LOC\u{1}` + body `lat,lng,acc,ts` (ts = **Int seconds**) over chat; broadcast 30 s, staleness 120 s; mutual-favorite receive gate.
- **Selfie** — `SelfieSyncService`: BLE request `\u{1}GE136C-SELFIE-REQ\u{1}`+hex(peerKey) / response `\u{1}GE136C-SELFIE\u{1}`+base64(JPEG 0.65); **and** Nostr 30078 d-tag `ge136c.selfie`.
- **Trip notes** — `TripNotesService`: Nostr 30078, k-tag `ge136c.notes`, per-note d-tag `ge136c.note.<uuid>`, content `{v:1,lat,lon,body,nick?}`.
- **Geohash channels / presence** — see `GeohashPresenceSpec.md`.

## Flagged issues / hygiene — **decision: delete all dead code (confirmed)**
1. **Delete** the dead binary location-share stub — `FriendLocationService.locationSharePacketType = 0x20`, `handleLocationPacket(...)`, `LocationSharePayload.to/fromData()` (unreachable; misrepresents the wire format).
2. **Delete** `FestivalGroupManager` — ~868 lines, zero callers.
3. **Version the markers** — `\u{1}GE136C-LOC\u{1}` has no version; add e.g. `-V1` so wire changes don't silently break deployed clients.
4. **Pick one timestamp precision** — marker path uses Int seconds; the dormant binary path uses Long ms. Document seconds as canonical (and delete the dormant spec per #1).
5. **Document the wire format in-code** — top-of-file doc comments on `FriendLocationService.swift` / `SelfieSyncService.swift` / `TripNotesService.swift`.
6. **Delete** the `aeadKey` parameter on `handleLocationPacket` (goes with the function removed in #1).
7. **Marker robustness** — `U+0001`-bracketing is fragile (works only because users don't type control chars); flag for an eventual real protocol layer. Not urgent.
8. **Delete dead `FestivalContentView+MapTab.swift` scaffolding** — `FestivalTabWithMap` + `FestivalMainViewWithMap` have zero callers (live host is `TripMainView`). (`FestivalMapTab` itself is a live `typealias` to `TripMapTab` — keep.)

## Forward plan
1. **Generalize beyond GE136C (headline).** ~15 hardcoded `ge136c.*` literals — BLE markers (`GE136C-LOC`, `GE136C-SELFIE`), Nostr tags (`ge136c.notes`/`note`/`selfie`), and `AppStorage` keys (tiles, colors, cars, prompts, hidden days, meals) — block running any trip but GE136C. Derive them from the trip config / a trip id. **This is a cross-platform contract change** (the markers and k/d-tags are shared) — design the namespacing scheme jointly with Android before changing.
2. **Hygiene cleanups** — the flagged items above (mostly deletions + doc comments + marker versioning).
3. **Wire-format spec + versioning** — a single canonical wire-format doc (markers, bodies, Nostr kinds/tags, transports) so iOS/Android stay in sync as the protocol evolves.
4. **Live cross-platform verification** — two-device iOS↔Android interop pass (friend location, selfie, trip notes); the iOS side of `fest-mesh-android#7`.
5. **Re-enable issue tracking** on this repo so the above become trackable issues.

## Status
This doc is the plan. On approval, forward-plan items 1–5 become issues (requires issue tracking enabled). Hygiene decision: **delete all dead code** (confirmed) — no implement path.
