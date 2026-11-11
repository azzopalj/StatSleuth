#!/usr/bin/env python3
"""
Generates the data files the app fetches at runtime:

  data/notable.json  - the "Notable Players" pack, scored from live MLB data
  data/daily.json    - the daily puzzle schedule, fixed in advance

Run nightly by .github/workflows/update-data.yml. Standard library only.

Why this exists
---------------
The Notable pack used to be a hand-maintained list of player *names* matched
against the current rosters. It went stale on every transaction (40 of 221
names were no longer on any 40-man roster), and name matching is fragile.

The daily puzzle used to be chosen on-device by indexing the local player pool.
Because that pool varies with roster changes and cache age, different devices
could get different puzzles on the same day. Publishing the schedule here makes
it identical for everyone.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import daily_schedule  # noqa: E402

API = "https://statsapi.mlb.com/api/v1"
UA = "StatSleuth-DataBot/1.0 (+https://github.com/azzopalj/StatSleuth)"

TEAM_IDS = [141, 147, 111, 139, 110, 145, 114, 116, 118, 142,
            117, 108, 133, 136, 140, 144, 146, 121, 143, 120,
            112, 113, 115, 158, 134, 138, 109, 119, 135, 137]

# How many players end up in the Notable pack.
NOTABLE_COUNT = 220
# Award weight by kind, and how far back to look.
AWARD_WEIGHTS = {"MVP": 10, "CY": 9, "ROY": 5, "AS": 4, "SS": 3, "GG": 3}
AWARD_IDS = ["ALAS", "NLAS", "ALMVP", "NLMVP", "ALCY", "NLCY",
             "ALROY", "NLROY", "ALSS", "NLSS", "ALGG", "NLGG"]
AWARD_YEARS_BACK = 10
# Awards that alone guarantee a place in the pack, regardless of score.
MAJOR_AWARD_KINDS = {"MVP", "CY", "ROY"}


def get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if attempt == 2:
                return {}
    return {}


def current_season() -> int:
    seasons = get(f"{API}/seasons/current?sportId=1").get("seasons") or []
    if seasons:
        try:
            return int(seasons[0]["seasonId"])
        except (KeyError, ValueError):
            pass
    return datetime.now(timezone.utc).year


def fetch_rosters(season: int) -> dict[int, str]:
    out: dict[int, str] = {}
    with ThreadPoolExecutor(16) as ex:
        urls = [f"{API}/teams/{t}/roster?rosterType=40Man&season={season}" for t in TEAM_IDS]
        for d in ex.map(get, urls):
            for entry in d.get("roster", []):
                person = entry.get("person") or {}
                if person.get("id"):
                    out[person["id"]] = person.get("fullName", "")
    return out


def fetch_people(ids: list[int]) -> list[dict]:
    chunks = [ids[i:i + 100] for i in range(0, len(ids), 100)]

    def one(chunk: list[int]) -> list[dict]:
        q = urllib.parse.urlencode({
            "personIds": ",".join(map(str, chunk)),
            "hydrate": "stats(group=[hitting,pitching],type=[season,career])",
        })
        return get(f"{API}/people?{q}").get("people", [])

    people: list[dict] = []
    with ThreadPoolExecutor(12) as ex:
        for batch in ex.map(one, chunks):
            people += batch
    return people


def fetch_awards(season: int) -> tuple[dict[int, float], set[int]]:
    """Returns (weighted score by player id, set of major-award winners)."""
    years = range(season - AWARD_YEARS_BACK, season + 1)
    jobs = [(a, y) for a in AWARD_IDS for y in years]

    def one(job):
        award_id, year = job
        return award_id, year, get(f"{API}/awards/{award_id}/recipients?season={year}")

    scores: dict[int, float] = {}
    majors: set[int] = set()
    with ThreadPoolExecutor(16) as ex:
        for award_id, year, data in ex.map(one, jobs):
            kind = next(k for k in AWARD_WEIGHTS if award_id.endswith(k))
            # Recent honours say more about who is famous now.
            age = season - year
            recency = 1.0 if age <= 2 else (0.7 if age <= 5 else 0.45)
            for rec in data.get("awards", []):
                pid = (rec.get("player") or {}).get("id")
                if not pid:
                    continue
                scores[pid] = scores.get(pid, 0.0) + AWARD_WEIGHTS[kind] * recency
                if kind in MAJOR_AWARD_KINDS:
                    majors.add(pid)
    return scores, majors


def split_stat(person: dict, group: str, type_: str) -> dict:
    for block in person.get("stats", []):
        if (block.get("group", {}).get("displayName") == group
                and block.get("type", {}).get("displayName") == type_):
            splits = block.get("splits") or []
            if splits:
                return splits[0].get("stat", {}) or {}
    return {}


def num(value, default=0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def score_players(people: list[dict], award_scores: dict[int, float]) -> dict[int, dict]:
    """Career accumulation + current-season production + playing time + honours.

    Career accumulation is what keeps ageing stars (Trout, Stanton) in the pack
    once their current-season numbers fall off — a pure top-of-the-charts
    ranking would drop exactly the players fans still recognise.
    """
    rows: dict[int, dict] = {}
    for person in people:
        pid = person.get("id")
        if not pid:
            continue
        ch, cp = split_stat(person, "hitting", "career"), split_stat(person, "pitching", "career")
        sh, sp = split_stat(person, "hitting", "season"), split_stat(person, "pitching", "season")

        career = (num(ch.get("homeRuns")) / 10 + num(ch.get("hits")) / 100
                  + num(ch.get("stolenBases")) / 25 + num(cp.get("wins")) / 8
                  + num(cp.get("strikeOuts")) / 120 + num(cp.get("saves")) / 12)
        season = (num(sh.get("homeRuns")) / 3 + max(0.0, num(sh.get("ops")) - 0.700) * 25
                  + num(sp.get("strikeOuts")) / 12
                  + max(0.0, 4.50 - num(sp.get("era"), 4.50)) * 3
                  + num(sp.get("saves")) / 3)
        playing = (min(num(sh.get("gamesPlayed")) / 140, 1) * 5
                   + min(num(sp.get("inningsPitched")) / 150, 1) * 5)

        rows[pid] = {
            "name": person.get("fullName", ""),
            "score": round(award_scores.get(pid, 0.0) + career + season + playing, 3),
        }
    return rows


def pick_notable(rows: dict[int, dict], majors: set[int]) -> list[dict]:
    ranked = sorted(rows.items(), key=lambda kv: (-kv[1]["score"], kv[1]["name"]))
    chosen = {pid for pid, _ in ranked[:NOTABLE_COUNT]}
    # An MVP / Cy Young / Rookie of the Year belongs in the pack even if a down
    # year leaves them outside the cutoff.
    chosen |= {pid for pid in majors if pid in rows}
    out = [{"mlbID": pid, "name": rows[pid]["name"], "score": rows[pid]["score"]}
           for pid in chosen]
    out.sort(key=lambda p: (-p["score"], p["name"]))
    return out


def build_daily(existing: dict, notable: list[dict], today) -> dict:
    """Schedules the MLB daily from the notable pack, ordered by score."""
    return daily_schedule.extend(existing, [p["mlbID"] for p in notable], today)


def write_json(path: str, payload: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=1, ensure_ascii=False, sort_keys=False)
        f.write("\n")


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    season = current_season()
    today = datetime.now(timezone.utc).astimezone(
        timezone(timedelta(hours=-5))).date()  # ET-ish; exact offset is not critical here

    print(f"season={season} today={today}")

    roster = fetch_rosters(season)
    print(f"rostered players: {len(roster)}")
    if len(roster) < 500:
        print("ERROR: roster fetch looks incomplete, refusing to publish", file=sys.stderr)
        return 1

    people = fetch_people(list(roster))
    print(f"people fetched: {len(people)}")

    award_scores, majors = fetch_awards(season)
    print(f"award recipients: {len(award_scores)} (majors: {len(majors)})")

    rows = score_players(people, award_scores)
    notable = pick_notable(rows, majors)
    # Published daily picks must never change, so start from what is already
    # live — and keep every upcoming answer in the pack, even if this run's
    # ranking or rosters have dropped them.
    existing = daily_schedule.load(os.path.join(repo_root, "data", "daily.json"))
    previous = daily_schedule.load(os.path.join(repo_root, "data", "notable.json"))
    current = [{"mlbID": pid, "name": row["name"], "score": row["score"]}
               for pid, row in rows.items()]
    chosen = {p["mlbID"] for p in notable}
    pool = [p for p in current if p["mlbID"] in chosen] + \
           [p for p in current if p["mlbID"] not in chosen]
    for p in pool[len(chosen):]:
        p["notable"] = False
    for line in daily_schedule.keep_scheduled(
            pool, previous.get("players", []),
            daily_schedule.scheduled_ids(existing, today),
            id_key="mlbID", name_key="name"):
        print(line)
    notable = [p for p in pool if p.get("notable", True)]
    for p in notable:
        p.pop("notable", None)
        p.setdefault("score", 0.0)
    notable.sort(key=lambda p: (-p["score"], p["name"]))
    print(f"notable pack: {len(notable)}")
    if len(notable) < 100:
        print("ERROR: notable pack too small, refusing to publish", file=sys.stderr)
        return 1

    generated = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    notable_doc = {
        "generated": generated,
        "season": season,
        "count": len(notable),
        "players": [{"mlbID": p["mlbID"], "name": p["name"]} for p in notable],
    }

    daily_doc = build_daily(existing, notable, today)
    daily_doc = {"generated": generated, "season": season, **daily_doc}
    print(f"daily schedule: {len(daily_doc['picks'])} dates "
          f"(through {max(daily_doc['picks']) if daily_doc['picks'] else 'n/a'})")

    # GitHub Pages may serve from the repo root or from docs/; write both so the
    # files are reachable either way.
    for base in ("", "docs"):
        write_json(os.path.join(repo_root, base, "data", "notable.json"), notable_doc)
        write_json(os.path.join(repo_root, base, "data", "daily.json"), daily_doc)

    print("top 10:", ", ".join(p["name"] for p in notable[:10]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
