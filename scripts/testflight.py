#!/usr/bin/env python3
"""Archive the iOS app and upload it to App Store Connect (TestFlight).

    just testflight          # or: python3 scripts/testflight.py

Steps:
  1. Refuse to ship if the working tree is dirty (the build must match a commit).
  2. Validate the active trip (MESHY_TRIP) with scripts/validate_trip.py --active,
     so a trip with FILL_IN values can't go out.
  3. xcodebuild archive (Release, generic iOS device).
  4. xcodebuild -exportArchive with Configs/ExportOptions-TestFlight.plist, which
     uploads and lets App Store Connect assign the next build number.

Signing/upload use the Apple ID signed into Xcode (Settings → Accounts) via
-allowProvisioningUpdates. After upload the build shows as "Processing" in App
Store Connect → TestFlight for ~5-30 min. See docs/RELEASE_TESTFLIGHT.md.
"""
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "bitchat.xcodeproj"
SCHEME = "bitchat (iOS)"
EXPORT_OPTIONS = ROOT / "Configs" / "ExportOptions-TestFlight.plist"
TRIPS_DIR = ROOT / "bitchat" / "Features" / "festival" / "trips"
BUILD_DIR = ROOT / "build" / "testflight"


def run(cmd):
    print("$ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=ROOT, check=True)


def xcconfig_value(key):
    """Last assignment of `key` across Release.xcconfig then Local.xcconfig
    (Local is included last, so it wins — same order Xcode uses)."""
    value = None
    for name in ("Release.xcconfig", "Local.xcconfig"):
        path = ROOT / "Configs" / name
        if path.exists():
            for match in re.finditer(rf"^\s*{key}\s*=\s*(.+?)\s*$", path.read_text(), re.M):
                value = match.group(1)
    return value


def require_clean_tree():
    status = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                            capture_output=True, text=True, check=True).stdout
    if status.strip():
        sys.exit("Working tree has uncommitted changes; commit them first so the build matches a commit.\n" + status)


def validate_active_trip():
    trip = xcconfig_value("MESHY_TRIP")
    trip_file = TRIPS_DIR / f"{trip}.json"
    print(f"Active trip: {trip}")
    run([sys.executable, str(ROOT / "scripts" / "validate_trip.py"), str(trip_file), "--active"])


def archive(archive_path):
    run(["xcodebuild", "archive",
         "-project", PROJECT,
         "-scheme", SCHEME,
         "-configuration", "Release",
         "-destination", "generic/platform=iOS",
         "-archivePath", str(archive_path),
         "-allowProvisioningUpdates"])


def upload(archive_path, export_path):
    run(["xcodebuild", "-exportArchive",
         "-archivePath", str(archive_path),
         "-exportOptionsPlist", str(EXPORT_OPTIONS),
         "-exportPath", str(export_path),
         "-allowProvisioningUpdates"])


def main():
    require_clean_tree()
    validate_active_trip()
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    archive_path = BUILD_DIR / f"Meshy-{stamp}.xcarchive"
    print(f"Team {xcconfig_value('DEVELOPMENT_TEAM')}, bundle {xcconfig_value('PRODUCT_BUNDLE_IDENTIFIER')}, "
          f"version {xcconfig_value('MARKETING_VERSION')}")
    archive(archive_path)
    upload(archive_path, BUILD_DIR / f"export-{stamp}")
    print("Uploaded. App Store Connect → TestFlight: wait for processing, answer export compliance, "
          "then add the build to your tester groups.")


if __name__ == "__main__":
    main()
