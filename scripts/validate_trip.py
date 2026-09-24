#!/usr/bin/env python3
"""Validate a trip JSON (bitchat/Features/festival/trips/*.json) without Xcode.

Mirrors the Codable required fields in FestivalModels.swift (TripData and
friends) plus the checks in TripConfigTests. Usage:

    python3 scripts/validate_trip.py bitchat/Features/festival/trips/trip-oct-2026.json [--active]

--active additionally fails on any FILL_IN placeholder (use for the trip named
by MESHY_TRIP in Configs/Release.xcconfig).
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

# Required (non-optional) keys per Swift struct.
REQUIRED = {
    "TripData": ["trip", "channels", "days"],
    "TripInfo": ["id", "name", "location", "dates"],
    "TripDates": ["start", "end"],
    "TripTab": ["id", "name", "icon", "type"],
    "TripDay": ["id", "title", "date", "items"],
    "TripItem": ["id", "title"],
    "TripLocation": ["id", "name"],
    "TripChannel": ["id", "name", "description"],
    "TripInfoSection": ["id", "title", "bullets"],
    "TripRouteLink": ["id", "title", "url"],
    "TripInfoLink": ["id", "title", "url"],
    "TripSafety": ["sections"],
    "TripContactRow": ["label", "value"],
    "TripSeedMessages": ["version", "messages"],
    "TripSeedMessage": ["id", "time", "text"],
}
TAB_TYPES = {"schedule", "channels", "map", "chat", "info", "friends", "groups", "custom"}


def require(obj, struct, path, errors):
    for key in REQUIRED[struct]:
        if key not in obj or obj[key] is None:
            errors.append(f"{path}: missing required '{key}' ({struct})")


def unique_ids(items, path, errors):
    ids = [item.get("id") for item in items]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        errors.append(f"{path}: duplicate ids {sorted(dupes)}")


def validate(trip, active):
    errors = []
    require(trip, "TripData", "$", errors)
    info = trip.get("trip", {})
    require(info, "TripInfo", "$.trip", errors)
    require(info.get("dates", {}), "TripDates", "$.trip.dates", errors)

    for tab in trip.get("tabs") or []:
        require(tab, "TripTab", "$.tabs[]", errors)
        if tab.get("type") not in TAB_TYPES:
            errors.append(f"$.tabs[{tab.get('id')}]: type must be one of {sorted(TAB_TYPES)}")
    for channel in trip.get("channels", []):
        require(channel, "TripChannel", "$.channels[]", errors)
    for day in trip.get("days", []):
        require(day, "TripDay", f"$.days[{day.get('id')}]", errors)
        for item in day.get("items", []):
            require(item, "TripItem", f"$.days[{day.get('id')}].items[]", errors)
            if item.get("location"):
                require(item["location"], "TripLocation", f"$.days[{day.get('id')}].items[{item.get('id')}].location", errors)
        unique_ids(day.get("items", []), f"$.days[{day.get('id')}].items", errors)
    unique_ids(trip.get("days", []), "$.days", errors)
    for section in trip.get("infoSections") or []:
        require(section, "TripInfoSection", "$.infoSections[]", errors)
    for link in (trip.get("mapConfig") or {}).get("routeLinks") or []:
        require(link, "TripRouteLink", "$.mapConfig.routeLinks[]", errors)
    for link in trip.get("infoLinks") or []:
        require(link, "TripInfoLink", "$.infoLinks[]", errors)
    unique_ids(trip.get("infoLinks") or [], "$.infoLinks", errors)
    if trip.get("safety"):
        require(trip["safety"], "TripSafety", "$.safety", errors)
        for section in trip["safety"].get("sections", []):
            for row in section.get("rows") or []:
                require(row, "TripContactRow", "$.safety.sections[].rows[]", errors)
    if trip.get("seedMessages"):
        seeds = trip["seedMessages"]
        require(seeds, "TripSeedMessages", "$.seedMessages", errors)
        for seed in seeds.get("messages", []):
            require(seed, "TripSeedMessage", "$.seedMessages.messages[]", errors)
        unique_ids(seeds.get("messages", []), "$.seedMessages.messages", errors)

    if active:
        raw = json.dumps(trip, ensure_ascii=False)
        count = raw.count("FILL_IN")
        if count:
            errors.append(f"active trip still has {count} FILL_IN value(s)")
        for key in ("start", "end"):
            value = info.get("dates", {}).get(key, "")
            try:
                datetime.strptime(value, "%Y-%m-%d")
            except ValueError:
                errors.append(f"$.trip.dates.{key}: '{value}' is not yyyy-MM-dd")
        for seed in (trip.get("seedMessages") or {}).get("messages", []):
            try:
                datetime.strptime(seed.get("time", ""), "%Y-%m-%d %H:%M")
            except ValueError:
                errors.append(f"$.seedMessages[{seed.get('id')}].time: '{seed.get('time')}' is not 'yyyy-MM-dd HH:mm'")
        namespace = info.get("namespace") or info.get("id", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", namespace):
            errors.append(f"$.trip.namespace: '{namespace}' should be lowercase letters, digits, dashes")
    return errors


def main(argv):
    paths = [a for a in argv if not a.startswith("--")]
    active = "--active" in argv
    failed = False
    for path in paths:
        errors = validate(json.loads(Path(path).read_text()), active)
        status = "OK" if not errors else f"{len(errors)} problem(s)"
        print(f"{path}: {status}")
        for error in errors:
            print(f"  - {error}")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
