# Upstream merge — 2026-09 (bitchat → festy/Meshy)

Branch: `mcb-upstream-merge` (real merge commit, not a rebase/squash).

| | |
|---|---|
| festy base | `origin/main` @ `a0cf29e` |
| upstream merged | `permissionlesstech/bitchat` `upstream/main` @ `774c88e` (Cap packet payload size per type and bound sync stores by bytes, #1719) |
| previous merge-base | `e47c5ae` (2026-02-22) |
| upstream commits pulled in | 255 (`git log e47c5ae..774c88e`) |
| conflicted paths | 40 (38 content, 2 modify/delete) |

A second merge commit then brought in festy `origin/main` @ `2e18ac1`, which added
yicolas/festy#14 (trip config) and #15 (selfie share scope) after this work had started.
See [Follow-up merge of festy main](#follow-up-merge-of-festy-main-14-15).

**Built without a compiler.** This container has no Swift toolchain or Xcode. Every
resolution was checked by reading the code and grepping for each symbol it uses. Nothing
has been compiled or run. See [Risks](#risks-that-need-an-xcode-build--device-test) before
you ship.

---

## Resolution policy that was applied

* **Core (mesh / crypto / transport / sync / Nostr internals / BitFoundation): taken from
  upstream.** This brings in upstream's security and reliability fixes, including
  registry-key verification (8378ff9), the peer-ID rotation heal (#1401), #1554, #1566,
  #1428, #1349, #1432, #1645 and the per-type payload caps (#1719).
* **Each festy hook sits on upstream's new structure as a small `// festy:` hook.** Where
  possible, the festy logic moved out of core files into `bitchat/Features/festival/`, so
  core files carry only one-line calls:
  * `ChatViewModel+Trip.swift`: every trip behavior that used to be inline in
    ChatViewModel.
  * `TripTimelinePersistence.swift`: the on-disk mesh timeline and DM history.
  * `TripAppInfoView.swift`: festy's "How to use & Settings" page.
* **Keep Meshy's identity.** That means the bundle IDs and teams as festy's pbxproj pinned
  them, the `ge136c` URL scheme, the display name Meshy, the icons, and empty app-group
  entitlements.

`grep -rn "festy:" bitchat` lists every hook in a core file.

---

## Conflicted files and how each was resolved

| File | Resolution |
|---|---|
| `README.md`, `PRIVACY_POLICY.md` | Kept festy's text. Upstream's privacy-policy rewrite covers bitchat features festy doesn't use yet (bridge, couriers). Review it later. |
| `Justfile` | Took upstream's (artifact-only clean, repo-local DerivedData, `test`/`test-ios`) and changed only the banner. festy's version pointed at a non-existent `FestMest (macOS)` scheme. `scripts/check-just-clean-safety.sh` passes. |
| `Package.swift` | Kept festy's names: product/target `FestMest`, test target `FestMestTests`, the `BitchatApp.swift` exclude and the `Features/festival/TripSchedule.json` resource. Took upstream's `BitFoundation` dependency, including for the test target. |
| `Configs/Release.xcconfig` | Kept festy's team `9ZYQ3XT8L9` and bundle ID `com.meshed.app`. Took upstream's `APP_GROUP_ID` mechanism, set to `group.com.meshed.app`, and kept `APP_GROUP_IDENTIFIER = $(APP_GROUP_ID)` as an alias. `MARKETING_VERSION` went from festy's 1.5.1 to **1.7.1** (upstream's base, and monotonic for festy). |
| `Configs/Local.xcconfig.example` | Kept festy's values and added `APP_GROUP_ID`. |
| `bitchat.xcodeproj/project.pbxproj` | Started from upstream's, which adds BitFoundation, the share-extension synced group, `DEVELOPMENT_ASSET_PATHS` and project-level `DEVELOPMENT_TEAM`. Re-applied every per-target festy override: teams (`9ZYQ3XT8L9` for tests/macOS, `QH3CULU8Z7` for the iOS app and share extension, as festy had them), `PRODUCT_BUNDLE_IDENTIFIER` (`com.meshy.app` / `com.meshy.app.ShareExtension` / `com.meshed.app*`), display name `Meshy`, category `utilities`, and deployment targets. Dropped the per-target `MARKETING_VERSION = 1.5.1` so the xcconfig version applies, as upstream does. `STRING_CATALOG_GENERATE_SYMBOLS` follows upstream (`NO`). |
| `bitchat/Assets.xcassets/AppIcon.appiconset/*.png` (10) | Kept festy's Meshy icons. |
| `bitchat/Info.plist` | Kept festy's display name, `ge136c` scheme, `LSApplicationQueriesSchemes` (Organic Maps / Google Maps) and Meshy usage strings. Took upstream's `AppGroupID` key and new usage-string wording, rebranded. **The location usage string is now accurate:** friend-location sharing does broadcast your position to trip peers. Category is `utilities`, matching festy's pbxproj. |
| `bitchat/bitchat.entitlements`, `bitchatShareExtension/*.entitlements` | Kept festy's empty `application-groups` arrays. festy removed app groups on purpose to get running on iOS 18. |
| `bitchat/bitchat-macOS.entitlements` | Upstream's file with festy's empty app-group array. This keeps upstream's `device.camera` key. |
| `bitchatShareExtension/ShareViewController.swift` | Took upstream and kept festy's group-ID derivation from the extension bundle ID (`// festy:`). Upstream reads `AppGroupID` from Info.plist, which would resolve to `group.com.meshed.app` while the app uses `group.com.meshy.app`. The share-extension display name is set to Meshy. |
| `bitchat/FestMestApp.swift` (rename of `BitchatApp.swift`) | Rewritten as upstream's `BitchatApp` structure: `AppRuntime` plus all feature models injected as environment objects. It is renamed `MeshyApp`, with `typealias BitchatApp = MeshyApp` so upstream references (`BitchatApp.groupID`, KeychainManager) compile unchanged. The root is `TripContentView`, with `runtime.chatViewModel` injected for the trip layer. `ge136c://join` turns on trip mode. |
| `bitchat/AppDelegates.swift` (festy-only file) | Replaced its bodies with upstream's runtime-based `AppDelegate` / `MacAppDelegate` / `NotificationDelegate`, taken verbatim from `BitchatApp.swift`. |
| `bitchat/Localizable.xcstrings` | Three-way JSON merge. Upstream wins on shared keys. festy's 6 branding edits are re-applied per locale (`app_info.app_name`, `app_info.tagline`, three bluetooth alerts). festy's 155 extracted keys are appended with `shouldTranslate: false`: they are English-only trip UI, and this keeps upstream's `LocalizationCoverageTests` green. Six upstream English strings that name "bitchat" were rebranded (nearby notification, redacted-preview body, panic-blocked banner, panic note, empty-state hint, language restart note). |
| `bitchat/Nostr/NostrProtocol.swift` | Union of both sides. Upstream's new `deletion`/`courierDrop` kinds plus festy's `appData = 30078`, `selfieDTag`, `tripNoteKTag`, `createSelfieEvent` and `createTripNoteEvent`. |
| `bitchat/Nostr/NostrRelayManager.swift` | Union of both sides. Upstream's `bridgeRendezvous`/`courierDrops` filters plus festy's `setTagFilter`, `tripSelfies` and `tripNotes`. |
| `bitchat/Services/BLE/BLEService.swift` | **Upstream.** festy's only change was letting relayed frames skip per-link sender binding. Upstream now does this properly in `BLEIngressLinkRegistry.packetContext`: only `requestSync` needs direct binding, and relayed frames keep their original sender. The festy patch is no longer needed. |
| `bitchat/Services/KeychainManager.swift` | Upstream. `BitchatApp.bundleID` resolves through the typealias, so the keychain service name is unchanged: it is the bundle ID, as before. |
| `bitchat/Services/NotificationService.swift` | Upstream plus festy's `sendChannelMessageNotification`. It now honors upstream's hide-previews setting and uses the injectable request deliverer. The nearby title default is "👥 friends nearby!". |
| `bitchat/Services/MessageFormattingEngine.swift` (auto-merged) | **Reverted to upstream.** festy's `selfColor` protocol requirement was dead code: the engine isn't on any render path in festy or upstream. It would also have broken upstream's `MockMessageFormattingContext` tests. |
| `bitchat/ViewModels/ChatViewModel.swift` | **Upstream, plus 3 one-line hooks** (see below). All of festy's inline code moved to `Features/festival/ChatViewModel+Trip.swift`. |
| `bitchat/ViewModels/PublicTimelineStore.swift` (modify/delete) | **Deleted, following upstream.** festy's persistence moved to `Features/festival/TripTimelinePersistence.swift`. See [the decision](#publictimelinestore--meshtimelinepersistence-decision). |
| `bitchat/Views/LocationNotesView.swift` (modify/delete) | Deleted, following upstream (replaced by `NoticesView`). festy's one-line change was a color, and nothing festy-specific references the view. |
| `bitchat/Views/AppInfoView.swift` | **Upstream verbatim.** festy's rewritten page moved to `Features/festival/TripAppInfoView.swift` (`TripAppInfoView`). Its helper views are renamed `TripSectionHeader` / `TripFeatureRow` / `TripBulletPoint` / `TripAppInfoFeatureInfo` to avoid colliding with upstream's. The trip UI's two `AppInfoView()` call sites now use `TripAppInfoView()`. A new "Advanced mesh settings" row opens upstream's `AppInfoView` (tor, bridge/gateway, relays, theme, notification previews, panic wipe), with the runtime's models injected explicitly. |
| `bitchat/Views/ContentView.swift` | Upstream (now split into `ContentHeaderView`, `MessageListView`, `ContentComposerView` and `ContentSheetViews`), plus festy's `hidesChatHeader` environment key. When set, the upstream header is hidden but the panic-blocked and connectivity banners still show. The rest of festy's ContentView changes were re-homed into the split files (see the hook table). |
| `bitchat/Views/LocationChannelsSheet.swift` | Upstream plus two hooks: the trip state vars, and a `tripChannelsSection` call at the top of the list. festy's trip channel and car rows moved into a same-file extension. They now read the filter from `TripChatState`, select through `locationChannelsModel`, and read the mesh timeline through `TripChatState.meshMessages()`. |
| `bitchat/Views/{FingerprintView,VerificationViews}.swift`, `Views/Components/{CommandSuggestionsView,DeliveryStatusView,PaymentChipView}.swift` | Upstream. festy's only change in each was `TripTheme.uiTint` instead of terminal green. Upstream now routes those colors through the theme palette, so one hook in `Utils/Theme.swift` (`ThemePalette.matrix`: `green = TripTheme.uiTint`) re-applies the tint app-wide. |

Other files festy changed that auto-merged cleanly: `LaunchScreen.storyboard`, `AccentColor`,
`bitchatTests/Info.plist` and the schemes. They were left as merged, in festy's form.

---

## festy hooks: old location → new location

| Behavior | Pre-merge (festy `origin/main`) | Post-merge |
|---|---|---|
| Location/selfie broadcaster wiring | `ChatViewModel.init` ~489-522 | `ChatViewModel.init` → `festyConfigureTripLayer()` (`Features/festival/ChatViewModel+Trip.swift`). Called right after upstream's `ChatViewModelBootstrapper.configure()` and skipped under tests. |
| Selfie Nostr sub refresh, publish own selfie, `TripNotesService.startNostrSubscription` / `republishAllLocal` | `ChatViewModel.init` | Same: `festyConfigureTripLayer()` |
| Mesh timeline and DM restore, save on background, 60 s DM snapshot | `ChatViewModel.init` + `PublicTimelineStore.swift` | `TripTimelinePersistenceController` (`TripTimelinePersistence.swift`). It restores into `ConversationStore` via `appendPublicMessage` / `appendPrivateMessage`, saves (debounced 5 s) on `ConversationStore.changes`, and flushes on `willResignActive`. |
| `seedMealPlaceholdersIfNeeded` (#meals dinner seeds, v3) | `ChatViewModel` ~3733 | `ChatViewModel+Trip.swift`. Uses `conversations.removeMessage(withID:from:)` and `appendPublicMessage(_:to: .mesh)`. |
| Public-message marker interception (location, selfie req/resp), `didReceivePublicMessage` path | `ChatViewModel` ~3267-3290 | `ChatTransportEventCoordinator.handlePublicMessage(from:…)`: one `// festy:` line calling `context.festyInterceptTripControlMessage(...)`. This is the path `BLEPublicMessageHandler` → `.publicMessageReceived` delivers on. |
| Same interception, `didReceiveMessage` path | `ChatViewModel` ~3021-3050 | `ChatTransportEventCoordinator.handleReceivedMessage`: one `// festy:` block, after upstream's block/empty guards. Returns `true` (accepted, so the transport may ACK). |
| `autoFavoriteTripPeer` + selfie request on first sight | `ChatViewModel.didReceiveMessage` | Inside `festyInterceptTripControlMessage` (non-control public mesh messages). Now skips blocked senders and drops their control packets. |
| `festyInterceptTripControlMessage` protocol requirement | — | Added to `ChatTransportEventContext`, with a default `false` implementation, so upstream's mock contexts keep compiling. |
| Trip-channel notifications (`notifyForTripChannelIfNeeded`) | end of `ChatViewModel.handlePublicMessage` | `ChatViewModel+Trip.swift`: subscribes to `ConversationStore.changes` `.appended(.mesh/.geohash)`, so it sees only messages upstream actually accepted. Skips archived echoes and meal seeds. |
| `sendMessage` hashtag auto-append | `ChatViewModel.sendMessage` | `ChatViewModel.sendMessage` → `festyScopedOutgoingContent(_:)`, one line. **Now skipped for private chats and commands.** Pre-merge it also appended the tag to DMs, which was a bug. |
| `MeshTimelinePersistence.scheduleSave` after send/receive | `ChatViewModel` (2 sites) | Covered by the `ConversationStore.changes` observer, with no core hook. |
| `clearCurrentPublicTimeline` also wipes the persisted file | `ChatViewModel.clearCurrentPublicTimeline` | Observer sees `.cleared(.mesh)` and calls `MeshTimelinePersistence.clear()`, with no core hook. |
| Panic wipe | festy removed panic | Upstream's panic (reachable from Advanced mesh settings) → `// festy:` line in `ChatViewModel.panicClearAllData` → `TripTimelinePersistenceController.wipe()` deletes the on-disk timeline and DM files. |
| `MediaRetention.pruneNow()` no-op (indefinite media) | `ChatViewModel.init` + `PublicTimelineStore.swift` | Upstream now expires media older than 7 days at launch, so a `// festy:` guard in `AppRuntime.performMediaMaintenance` skips `expireAgedMedia()` while `MediaRetention.keepMediaIndefinitely` is set. |
| `confirmNickname`, `hasChosenNickname`, `hashtagFilter` | stored `@Published` on ChatViewModel | Forwarding members in `ChatViewModel+Trip.swift`, backed by the `TripChatState.shared` singleton. They send `objectWillChange` so views observing ChatViewModel still refresh. |
| `togglePeerBlock` + DM-header block button | `ChatViewModel` + `ContentView` header | Button re-homed to `ContentSheetViews.ContentPrivateChatSheetView` (`// festy:`). It is confirm-gated and uses upstream's `ConversationUIModel.block`. **Unblock** now lives in upstream's people list, not in the header. |
| `selfColor` (`MessageFormattingContext`) / user text color | `ChatViewModel` + engine | The engine hook was dead code (see the conflict table). The live render path is `ChatMessageFormatter`: own-message `baseColor` reads `UserChatColorStore.shared` and its hex is part of the format-cache variant (`// festy:`). `TextMessageView` / `MediaMessageView` observe the store so rows refresh. |
| `isLocationChannelsSheetPresented` (screenshot warning) | ChatViewModel | Re-homed as `AppChromeModel.isTripChannelSheetPresented` (`// festy:`), set by TripChatHost and OR-ed into `AppRuntime.handleScreenshotCaptured`. TripChatHost presents the alert itself because ContentHeaderView (upstream's alert host) is hidden in trip mode. |
| Marker filter + hashtag/#main/#car filter on the timeline | `ContentView.messagesView` ~372 | `MessageListView.conversationMessages(for:)` → `TripTimelineFilter.visibleMessages` (`// festy:`). It observes `TripChatState`. |
| No triple-tap `/clear` on the message list | `ContentView` | `MessageListView` (`// festy:`). Upstream had added a confirm dialog there; the trigger is removed. |
| `ge136c` URL scheme (`user`, `geohash`) | `ContentView.handleOpenURL` ~733 | `MessageListView.handleOpenURL` accepts `bitchat` and `ge136c`. `OpenURLAction` now handles in-app `bitchat://` links itself; pre-merge these went to the OS, where nothing is registered for them in Meshy. `ge136c://join` is handled in `MeshyApp.onOpenURL`, and `ge136c://share` in `AppRuntime.handleOpenURL`. |
| Header: `GE136C/`, no triple-tap panic, `#channels` badge | `ContentView.mainHeaderView` ~1300 | `ContentHeaderView` (3 `// festy:` edits). festy's live UI hides this header anyway (`TripChatHost` sets `hidesChatHeader`), so the clear-chat button and notes-icon removal were not re-applied there. TripChatHost already has its own trash button. |
| Composer text `.primary`/`.secondary`, camera on tap, library on long press | `ContentView` | `ContentComposerView` (`// festy:`). |
| Terminal-green → `TripTheme.uiTint` in ~10 views | per view | Single hook in `Utils/Theme.swift` (`ThemePalette.matrix`). |
| `PrivacyScreen` app-switcher label | — (new upstream) | "Meshy" (`// festy:`). |
| Trip channel list + car sub-channels | `LocationChannelsSheet` | Same file: 2 hooks plus a trailing festy extension. |
| TripChatHost channel sheet | `FestivalContentView` | Injects `LocationChannelsModel` and `PeerListModel` explicitly (upstream sheet requirement, #1558). |
| festy settings page | `Views/AppInfoView.swift` | `Features/festival/TripAppInfoView.swift` |
| Friend-location replay safety | — | `FriendLocationService.ingestLocationMessage` ignores fixes older than the stored one for that sender. Upstream gossip sync now replays up to 6 h of public messages. |
| `import BitFoundation` | — | Added to every `Features/festival` file. `PeerID`, `BitchatMessage`, `hexEncodedString`, etc. now live in the BitFoundation package. |

---

## PublicTimelineStore / MeshTimelinePersistence decision

Upstream deleted `PublicTimelineStore` and made `ConversationStore` the single writer of all
conversation state. Upstream also added its own history: a 6 h gossip-sync window whose
archive persists to disk and is replayed at launch as dimmed "archived echo" rows (#1372),
plus a sealed persistent outbox for undelivered DMs.

Upstream's history does not cover what the trip layer needs:
* Upstream stores only 6 h of public messages. festy keeps the mesh timeline indefinitely,
  including the seeded #meals dinner menus.
* Upstream keeps no DM history across launches. festy restores DMs.
* The #meals seeds and the channel views need a real, stable mesh timeline.

**Decision:** keep festy's minimal persistence (`MeshTimelinePersistence`,
`PrivateChatsPersistence`, same JSON files `ge136c-mesh-timeline.json` /
`ge136c-private-chats.json` in Documents, so existing users keep their history) and adapt it
to upstream's API:
* It restores into `ConversationStore` through `ChatViewModel.appendPublicMessage` /
  `appendPrivateMessage`.
* It saves from `ConversationStore.changes`.
* It does not persist geohash timelines (same as before) or upstream's `echo-` rows, and
  never persists trip control packets.
* Files are now written with `completeFileProtectionUntilFirstUserAuthentication` on iOS.
* The files are deleted on panic wipe.

Side effect: upstream's archived-echo replay only seeds an **empty** mesh timeline. With
festy history plus meal seeds, the timeline is never empty, so echoes don't show. Messages
peers carried while you were away still arrive live through gossip sync, which is the normal
receive path. Upstream's `meshTimelineCap` (1337) now caps what's restored in memory; the
oldest messages are dropped from the view. The file keeps whatever was last saved, and after
the first save that is also capped.

---

## Follow-up merge of festy main (#14, #15)

This is a second merge commit (`git merge origin/main`, no rebase). It brings in festy
`a0cf29e..2e18ac1`:
* #14 adds `TripNamespace` / `AppStorageKeys`, the `trips/` directory, `MESHY_TRIP`, and
  JSON-driven safety / infoLinks / seedMessages.
* #15 adds `SelfieShareScope`, the `NostrPubkeyFormat` npub→hex fix, and
  `SelfieSyncService.privateSender` / `connectedPeerNoiseKeys`.

It had 7 conflicts, re-homed as follows:

| festy change | Pre-merge location | Post-merge location |
|---|---|---|
| `MESHY_TRIP = trip-ge136c-spring-2026` | `Configs/Release.xcconfig` | Same file, kept alongside the upstream `APP_GROUP_ID` lines |
| `MeshyTrip` Info.plist key | `bitchat/Info.plist` | Same file, next to upstream's `LSApplicationCategoryType` |
| `appData` doc, `selfieDTag` / `tripNoteKTag` as `TripNamespace`-derived `static var`s, note d-tag prefix | `Nostr/NostrProtocol.swift` | Same file, merged into the union with upstream's new kinds |
| `SelfieSyncService.privateSender` + `connectedPeerNoiseKeys` wiring | `ChatViewModel.init` | `festyConfigureTripLayer()` in `ChatViewModel+Trip.swift`, next to the broadcaster wiring. Uses `unifiedPeerService.peers` and `meshService.sendPrivateMessage(_:to:recipientNickname:messageID:)` (verified on `Transport`). |
| Receiving a mutual-favorites selfie sent as a DM (festy's `didReceiveMessage` intercept covered private messages too) | `ChatViewModel.didReceiveMessage` | `festyInterceptTripControlMessage` gained an `isPrivate:` parameter and runs on **three** upstream paths: `handlePublicMessage(from:…)`, `handleReceivedMessage` (now public *and* private), and `handleNoisePayload(.privateMessage)`. The last is where upstream delivers decrypted Noise DMs; a consumed packet is still delivery-ACKed. Auto-favoriting stays public-only. |
| `TripData.bundled`-based `seedMealPlaceholdersIfNeeded` (versioned `seedMessages` from the trip JSON, `TripNamespace.key(...)` UserDefaults keys, remove previously seeded IDs) | `ChatViewModel` | `ChatViewModel+Trip.swift`, on `ConversationStore` (`removeMessage(withID:from: .mesh)`, `appendPublicMessage`) |
| `TripNamespace.file("mesh-timeline.json")` / `AppStorageKeys.privateChatsFile` | `ViewModels/PublicTimelineStore.swift` (modify/delete conflict) | `Features/festival/TripTimelinePersistence.swift`. `PublicTimelineStore.swift` stays deleted. For namespace `ge136c` the filenames are unchanged. |
| `@AppStorage(AppStorageKeys.colorScheme)`, `@AppStorage(SelfieShareScope.storageKey)`, the "Share selfie with" picker, header text `TripData.bundled` name + date range | `Views/AppInfoView.swift` | `Features/festival/TripAppInfoView.swift`. festy's diff was applied with the `Trip*` renames; upstream's `AppInfoView.swift` stays verbatim. |
| Header title from `TripData.bundled?.trip.displayShortName` | `Views/ContentView.swift` (header) | `Views/ContentHeaderView.swift` (`// festy:`). The `content.empty.switch_hint` English text now says "tap the trip name". |
| `Package.swift` resources `Features/festival/trips` | — | Auto-merged |

New risks from this round:
* `SelfieShareScope.mutualFavorites` relies on `BLEService.sendPrivateMessage` reaching a
  *connected* peer. If there is no Noise session yet, upstream queues it and starts a
  handshake. Test that the first selfie send after connecting arrives.
* A mutual-favorites selfie that arrives by any path other than the three hooked ones
  (for example a Nostr-routed DM through `NostrInboundPipeline`) would show up as a DM
  containing base64. festy only sends these over the mesh.
* Checklist addition: set "Share selfie with" to Mutual favorites on A, with A and B
  mutual favorites. B gets A's selfie, and no DM row appears on either phone. Set it to
  Nobody, and nothing is sent.

---

## Public-channel behavior upstream changed that festy relies on

* **Payload caps (#1719):** public `message` payloads decode up to 128 KiB. Messages larger
  than a v1 frame (65,535 B) are **not delivered**, and `BLEService.sendMessage` refuses
  content over 60,000 characters. festy's BLE selfie response is
  `"\u{1}GE136C-SELFIE\u{1}" + base64(JPEG 256 px @ q0.65)`: typically 8-20 KB of JPEG, so
  11-27 KB of base64, which is within the limits. A very noisy 256×256 image around 40 KB
  JPEG would approach the 60,000-character limit, and above it the send is dropped
  silently. Consider capping JPEG bytes in `UserSelfieStore.save`, for example by retrying
  at lower quality above 30 KB.
* **Signature requirement:** public messages must be signed by the claimed sender
  (`BLEPublicMessageHandler`). festy's broadcasts go through `meshService.sendMessage`,
  which signs them, so they pass.
* **Freshness window:** 6 h (`syncPublicMessageMaxAgeSeconds`). Location packets up to 6 h
  old are now replayed by sync, which the `FriendLocationService` monotonic guard handles.
* **UI per-sender rate limiter / NIP-13 PoW (#1382, #1451):** the rate limiter sits in the
  public-conversation coordinator, which runs *after* festy's interception, so location and
  selfie packets are never rate-limited or counted against the sender. PoW applies only to
  geohash (Nostr) posts. festy's control packets are BLE-only.
* **Gossip sync store (see risks):** every broadcast public packet is tracked for sync,
  including festy's location packets every 30 s. The message store holds 1000 packets or
  8 MB, and the archive persists for 6 h.

---

## Risks that need an Xcode build / device test

Compile risks, most likely first:
1. **`Features/festival/ChatViewModel+Trip.swift`**
   * `extension ChatTransportEventContext { func festyInterceptTripControlMessage… }` is a
     default implementation of a protocol requirement declared on a `@MainActor` protocol.
     Verify that `ChatViewModel`'s own method is chosen as the witness, and that there is no
     "ambiguous" or actor-isolation error.
   * `TripChatState` is `@MainActor`, and `static let` markers are read from `@MainActor`
     code.
2. **`TripTimelinePersistence.swift`**
   * `PrivateChatsPersistence.scheduleSave` uses `MainActor.assumeIsolated` inside a
     `DispatchWorkItem`.
   * `MeshTimelinePersistence.writeOptions` is a `static var` on a `@MainActor` class.
   * The exhaustive `switch` over `ConversationChange` will break if upstream adds a case.
3. **`TripAppInfoView.swift`** is festy's old AppInfoView with helper types renamed by
   regex. Check that the `TripSectionHeader(_ String)` / `(_ LocalizedStringKey)` overloads
   still resolve. The `AppInfoView(topologyProvider:onPanicWipe:)` call relies on upstream's
   memberwise init, which upstream's `ContentView` uses too.
4. **`LocationChannelsSheet.swift`**: festy's rows now live in an `extension` in the same
   file. They reach `private` `@State` (`$showingCarPrompt`, `$driverEntry`) and the
   `private` environment object `locationChannelsModel`. This is legal within one file, but
   check it.
5. **`MessageListView.swift`**: `handleOpenURL` is called from inside the `OpenURLAction`
   closure, and `TripTimelineFilter.visibleMessages` is `@MainActor`, called from a View
   helper. This is fine on the Xcode 16+ SDK, where `View` is `@MainActor`.
6. **`FestMestApp.swift`**: `typealias BitchatApp = MeshyApp` combined with `@main` on
   `MeshyApp`. In SwiftPM (`swift build`), the executable target is `FestMest` while tests
   `@testable import bitchat`. That was already true before the merge. Xcode is fine.
7. **`Features/festival/*`**: `import BitFoundation` was added to every file. Grep found no
   other missing module imports, but any festy use of a type that moved to BitFoundation as
   `internal` would fail.
8. **`AppRuntime.performMediaMaintenance`**: `MediaRetention.keepMediaIndefinitely` is read
   inside `Task.detached`. `MediaRetention` is a plain enum with a `static let` Bool, so
   this is Sendable-safe. Expect an "will never be executed" warning.

Runtime risks:
* **TripChatHost sheet + DM start:** fixed. `OnlinePeersSheet` now only reports the chosen
  peer and dismisses; its presenter (TripMainView / TripChatHost) calls
  `viewModel.startPrivateChat` from the sheet's `onDismiss`, so upstream's people/DM sheet is
  presented after the peer sheet is gone.
* **Screenshot privacy warning:** fixed; see the table above.
* **Location-packet churn in gossip sync:** with N sharers × 1 packet / 30 s, a 10-person
  trip fills the 1000-slot sync store in about 50 minutes. That evicts older real chat from
  what the device re-serves to peers who were out of range. This is not data loss locally,
  because festy persists its own timeline, but upstream's "6 h public history" is
  effectively shortened. The fix is to move location/selfie to a non-synced packet type or
  raise the interval. **Not done** because it's a wire-protocol decision.
* **Selfie size:** see the payload caps note above.
* **Archived echoes:** with persisted history they never show (by design). After a
  "Clear chat log", upstream's echo watermark also hides older echoes.
* **Media retention:** upstream's 7-day media expiry is disabled for Meshy.
  `BLEIncomingFileStore`'s size-based bound still applies.
* **Identity:** Info.plist `AppGroupID` = `group.com.meshed.app`, while the app and share
  extension compute `group.com.meshy.app` (the iOS bundle is `com.meshy.app` in pbxproj).
  Both entitlements have no app group, so shared content from the share extension still
  won't reach the app. **That is unchanged from before the merge.** The team, bundle-ID and
  app-group split (`com.meshy.app` + `QH3CULU8Z7` for iOS vs `com.meshed.app` +
  `9ZYQ3XT8L9` in xcconfig) was kept exactly as festy had it. Pick one identity before the
  next release.
* **macOS debug icons:** upstream added bitchat-branded `AppIconDebug` mac icons. Only
  `image-1024.png` there is Meshy.

---

## Device test checklist (2 iPhones, A and B, both on this build)

Before you start: install over the previous Meshy build on both phones, without deleting it,
so persistence migration is exercised.

1. **Launch/upgrade**
   * Old mesh history and DMs are still there.
   * #meals shows the three dinner menus, and only once.
   * The nickname prompt does not reappear.
   * The app-switcher snapshot shows "Meshy".
2. **Public chat (#main)**
   * A→B and B→A deliver and appear under #main.
   * Location/selfie control text never appears as a chat row, including after relaunch.
3. **Channel filter**
   * Pick #driving and send "hi". B sees "hi #driving" in #driving and in #main.
   * #meals posts are hidden from #main.
   * `#car-<driver>` scoping works, and the car list shows discovered drivers.
4. **Relaunch, then send immediately**
   * Force-quit A, reopen it, and send within 2 s. B receives it.
   * A's own message is not duplicated.
   * History restored before the send is intact.
5. **Trip-channel notification**
   * With A backgrounded, B posts "#gear lost my headlamp". A gets a notification titled
     "#gear".
   * With A foregrounded and filtered to #gear, no notification appears.
6. **Friend location**
   * Turn on sharing on both phones. Each sees the other's dot within about 60 s.
   * Walk apart, then back into range. The dot never jumps back to an older fix.
   * Turn sharing off, and the dot goes stale after 2 min.
7. **Selfie**
   * A takes a new selfie. B's map shows it over BLE, with airplane mode on and Bluetooth
     on.
   * With internet on, B receives it over Nostr. Check the log `🤳 Stored Nostr selfie`.
8. **Trip notes:** drop a note on A's map. It appears on B (Nostr) and survives a
   relaunch.
9. **DMs**
   * A→B DM delivers with read receipts.
   * Relaunch both phones: the DM history is still there.
   * The block button in the DM header asks for confirmation, and after blocking,
     B's public messages and location stop showing on A.
   * Unblock from the people list.
10. **Clear chat log:** the trash button in the channel bar asks for confirmation, clears the
    timeline, and after relaunch the timeline stays cleared.
11. **Advanced mesh settings:** Info → "Advanced mesh settings" opens upstream's settings:
    tor toggle, theme, relays, notification-preview toggle.
    * With previews hidden, trip-channel notifications show "open Meshy to read".
12. **Panic wipe** (from Advanced settings): everything is gone after relaunch, including
    the mesh/DM history files.
13. **Links**
    * Tap an `@mention` or user link in chat, and the action sheet opens inside Meshy (not
      in the bitchat app).
    * Open `ge136c://join` from Safari, and trip mode turns on.
14. **Tor / Nostr:** background the app for 1 minute, then return. Relays reconnect, and
    selfie/notes subscriptions resume.
