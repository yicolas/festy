# Releasing to TestFlight

The app ships from Madison's App Store Connect account: team `9ZYQ3XT8L9`, bundle `com.meshed.app` (see `Configs/Release.xcconfig` and `docs/LOCAL_SIGNING.md`).

## One command

```
just testflight            # = python3 scripts/testflight.py
```

This will:

1. Stop if the working tree has uncommitted changes, so the build always matches a commit.
2. Validate the active trip (`MESHY_TRIP`) with `scripts/validate_trip.py --active`. It fails if any `FILL_IN` is left or the dates don't parse.
3. Archive the `bitchat (iOS)` scheme in Release for a generic iOS device, into `build/testflight/` (gitignored).
4. Upload with `Configs/ExportOptions-TestFlight.plist`. **`manageAppVersionAndBuildNumber` = true**, so App Store Connect assigns the next build number, the same as the "Automatically manage version and build number" checkbox in Xcode's Distribute App. `CURRENT_PROJECT_VERSION` never needs a manual bump.

Signing and upload use the Apple ID signed into **Xcode → Settings → Accounts**.

Bump `MARKETING_VERSION` (currently 1.7.1) only when you want a new version on TestFlight or the App Store.

## By hand (same result)

Scheme **bitchat (iOS)**, destination **Any iOS Device (arm64)** → Product → **Archive** → Organizer → **Distribute App** → **App Store Connect** → Upload. Leave **"Automatically manage version and build number"** checked.

## After upload (App Store Connect → Meshy → TestFlight)

1. The build shows "Processing" for about 5–30 min.
2. Answer the **export compliance** question. Info.plist has no `ITSAppUsesNonExemptEncryption` key, so App Store Connect asks on every build. The app uses Noise (Curve25519 / ChaCha20-Poly1305), Nostr secp256k1 signatures and Tor. See fest-mesh-ios `docs/ENCRYPTION_COMPLIANCE.md` (March 2026) for the answers used then.
3. Add the build to groups:
   - **Internal** (people on the App Store Connect team, up to 100): available immediately.
   - **External / public link** (students): the first build of a version needs **Beta App Review**, typically about a day. Submit well before a trip.
4. Builds expire after 90 days.
