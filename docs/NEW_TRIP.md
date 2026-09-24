# Setting up a new trip

Each trip is one JSON file in
[`bitchat/Features/festival/trips/`](../bitchat/Features/festival/trips/), and **one build setting picks the active trip**:

```
// Configs/Release.xcconfig
MESHY_TRIP = trip-ge136c-spring-2026
```

`MESHY_TRIP` is copied into Info.plist (`MeshyTrip`), and `TripData.activeResourceName` loads `trips/<MESHY_TRIP>.json`. No Swift changes are needed.

## Switching to a new trip

1. Fill in the trip file. `trips/trip-oct-2026.json` is a placeholder: every value to replace starts with `FILL_IN`. Keys starting with `_` are notes and are ignored by the app.
2. Validate it without Xcode:
   ```
   python3 scripts/validate_trip.py bitchat/Features/festival/trips/trip-oct-2026.json --active
   ```
   `--active` also fails on any leftover `FILL_IN`, bad `yyyy-MM-dd` dates or seed times, and a malformed namespace.
3. Set `MESHY_TRIP = trip-oct-2026` in `Configs/Release.xcconfig`.
4. Build, run the tests (`TripConfigTests.activeTrip_hasNoPlaceholders` fails if `FILL_IN` remains), and ship to TestFlight.

To switch back to an old trip, point `MESHY_TRIP` at its file. Old trip files stay in `trips/` as a record.

## Checklist

1. **`trip`**: identity and display.
   - `id`: unique, e.g. `ge136a-fall-2026`.
   - `namespace`: short, lowercase slug, **new for every trip** (e.g. `ge136a26`). It scopes, per trip:
     - Nostr tags (on shared public relays): trip notes `<ns>.notes` / `<ns>.note.<uuid>`, selfies `<ns>.selfie`.
     - Local state: the public mesh timeline, trip notes, cached routes, map tiles, hidden days, car assignment, the offline-download prompt, and seeded messages.

     Reusing a namespace mixes this trip's notes and chat history with the old trip's. If you omit it, `id` is used.
   - `shortName`: chat header prefix and share/feedback text (e.g. `GE136A`). Defaults to `name`.
   - `name`, `subtitle`, `location` (also used in the "cell service drops…" prompts), `dates.start`/`end` (`yyyy-MM-dd`), `timezone` (IANA, e.g. `America/Los_Angeles`).
   - `feedbackEmail`: where the Info-tab feedback card sends mail.
2. **`days`**: schedule. Each stop's `location` (with `latitude`/`longitude`) drives map pins, and the bounding box of all stops is the offline tile download region.
3. **`channels`**, **`tabs`**, **`infoSections`**, **`mapConfig`**: same schema as before.
4. **`infoLinks`**: Info-tab link cards, e.g. waivers and forms (`"style": "mandatory"` shows them first, in red, with a MANDATORY badge), river gauges, photo upload. Other styles: `red`, `blue`, `green`, `accent`.
5. **`safety`**: the Safety & Logistics card. It is a list of `sections`, each optionally with a `title`, `rows` (`icon`/`label`/`value`: leaders, phones, sat phone, hospitals), `bullets` (hazards) and `text` (vehicle policy). Omit `safety` to hide the card.
6. **`seedMessages`**: messages pre-seeded into the public mesh timeline, e.g. `#meals` menus. `time` is `yyyy-MM-dd HH:mm` in the trip timezone. Put the channel hashtag on the first line of `text`. To change the seeds after release, bump `version`: the previous seeds are removed and the new ones seeded.
7. Run the unit tests. `TripConfigTests.bundledTrip_contentIsWellFormed` fails on unparseable dates and seed times, and on duplicate IDs.

## What is *not* per trip

- **BLE chat markers** (`\u{1}GE136C-LOC\u{1}`, `\u{1}GE136C-SELFIE…\u{1}`). These are wire protocol shared with Android. Renaming or versioning them is a cross-platform change: yicolas/festy#7.
- The **`ge136c://` URL scheme** (invite deep link, share extension). It is app plumbing and users don't see it.
- **Personal preferences** (color scheme, text color, own selfie, map tile source/detail) and private DMs. See `AppStorageKeys` in `TripNamespace.swift`.

## Cross-platform note

`fest-mesh-android` still hardcodes the `ge136c.*` Nostr tags. An Android client only sees a trip's notes and selfies if its tags match that trip's `namespace`.
