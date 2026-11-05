#!/usr/bin/env python3
"""Builds data/nba.json — every rostered NBA player with the stats the game needs.

The output shape is deliberately sport-agnostic: the app renders whatever stat
keys the file declares, so adding the NFL later needs no new client code.

  {
    "generated": "...", "sport": "basketball", "league": "nba", "season": 2027,
    "statKeys": {"card": [...], "primary": [...]},
    "players": [ { ...identity..., "season": {...}, "career": {...},
                   "rookie": {...}, "seasons": [...] } ]
  }

Career totals are computed here because ESPN publishes no career row.
"""

from __future__ import annotations

import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from espn_common import (SITE_API, WEB_API, get, get_many, split_made_attempted,  # noqa: E402
                         team_groups, teams, to_float)

SPORT_PATH = "basketball/nba"

# Shown on the stat card, in order. Keys are ESPN's own labels.
CARD_KEYS = ["PTS", "REB", "AST", "FG%", "3P%", "FT%", "STL", "BLK", "GP"]
# The two values the guess comparison reports on.
PRIMARY_KEYS = ["PTS", "REB"]
# A handful of games into a new season tells you nothing, so fall back.
MIN_GAMES_FOR_CURRENT_SEASON = 15
# Below this a player is deep bench or two-way, and makes for an unfair puzzle.
MIN_CAREER_GAMES = 20


def roster_players(team_ids: list[str]) -> list[dict]:
    urls = [f"{SITE_API}/{SPORT_PATH}/teams/{tid}/roster" for tid in team_ids]
    out = []
    for tid, data in zip(team_ids, get_many(urls)):
        for athlete in data.get("athletes") or []:
            if athlete.get("id"):
                athlete["_teamID"] = tid
                out.append(athlete)
    return out


def season_rows(categories: list[dict], name: str) -> dict[int, dict[str, str]]:
    """Season year -> {label: display value} for one ESPN stat category.

    A player traded mid-season gets three rows for that year: one per team plus
    a combined row whose teamSlug reads like "2024-25 Totals". Pick the combined
    row explicitly. Relying on it being last worked, but silently depended on
    ESPN's ordering — if that ever changed we would publish half a season.
    """
    for category in categories:
        if category.get("name") != name:
            continue
        labels = category.get("labels") or []
        by_year: dict[int, list[tuple[bool, dict[str, str]]]] = {}
        for entry in category.get("statistics") or []:
            year = (entry.get("season") or {}).get("year")
            if not year:
                continue
            slug = str(entry.get("teamSlug") or "")
            combined = slug.lower().endswith("totals")
            by_year.setdefault(int(year), []).append(
                (combined, dict(zip(labels, entry.get("stats") or []))))

        rows: dict[int, dict[str, str]] = {}
        for year, entries in by_year.items():
            combined = [row for is_combined, row in entries if is_combined]
            if combined:
                rows[year] = combined[0]
            elif len(entries) == 1:
                rows[year] = entries[0][1]
            else:
                # Split season with no combined row: take the longer stint rather
                # than guessing, and let the caller's cross-check catch it.
                rows[year] = max((row for _, row in entries),
                                 key=lambda r: to_float(r.get("GP"), 0) or 0)
        return rows
    return {}


def authoritative_career(pid: int) -> dict[str, float] | None:
    """ESPN's own published career line, from the athlete overview.

    Preferred over deriving one from the season rows so the numbers are not an
    inference of ours. The derived figure is still computed and compared.
    """
    doc = get(f"{WEB_API}/{SPORT_PATH}/athletes/{pid}/overview")
    stats = doc.get("statistics") or {}
    labels = stats.get("labels") or []
    for row in stats.get("splits") or []:
        if (row.get("displayName") or "").strip().lower() != "career":
            continue
        raw = dict(zip(labels, row.get("stats") or []))
        out: dict[str, float] = {}
        for key in CARD_KEYS:
            value = to_float(raw.get(key))
            if value is not None:
                out[key] = int(value) if key == "GP" else round(value, 3)
        return out or None
    return None


def per_game(row: dict[str, str]) -> dict[str, float]:
    out: dict[str, float] = {}
    for key in CARD_KEYS:
        value = to_float(row.get(key))
        if value is not None:
            out[key] = round(value, 3)
    return out


def career_stats(totals: dict[int, dict], averages: dict[int, dict]) -> dict[str, float] | None:
    """Career per-game line.

    Averaging the per-season averages would weight a 7-game season the same as
    an 82-game one, so sum the totals and divide by games actually played.
    """
    games = sum(to_float(averages.get(y, {}).get("GP"), 0) or 0 for y in totals)
    if games <= 0:
        return None

    def total(key: str) -> float:
        return sum(to_float(row.get(key), 0) or 0 for row in totals.values())

    def pct(key: str) -> float | None:
        made = attempted = 0.0
        for row in totals.values():
            m, a = split_made_attempted(row.get(key))
            made += m or 0
            attempted += a or 0
        return round(100 * made / attempted, 1) if attempted else None

    out: dict[str, float] = {
        "PTS": round(total("PTS") / games, 1),
        "REB": round(total("REB") / games, 1),
        "AST": round(total("AST") / games, 1),
        "STL": round(total("STL") / games, 1),
        "BLK": round(total("BLK") / games, 1),
        "GP": int(games),
    }
    for key, source in (("FG%", "FG"), ("3P%", "3PT"), ("FT%", "FT")):
        value = pct(source)
        if value is not None:
            out[key] = value
    return out


def build_player(athlete: dict, stats_doc: dict, team_meta: dict,
                 groups: dict[str, tuple[str, str]],
                 published_career: dict[str, float] | None,
                 mismatches: list[str]) -> dict | None:
    categories = stats_doc.get("categories") or []
    averages = season_rows(categories, "averages")
    totals = season_rows(categories, "totals")
    if not averages:
        return None

    derived = career_stats(totals, averages)
    career = published_career or derived
    if not career or career.get("GP", 0) < MIN_CAREER_GAMES:
        return None

    # Cross-check the two. They agreed on every player when this was written;
    # a disagreement means an assumption here has gone stale, so surface it
    # rather than quietly shipping a number.
    if published_career and derived:
        for key in ("GP", "PTS", "REB", "AST"):
            a, b = published_career.get(key), derived.get(key)
            if a is None or b is None:
                continue
            tolerance = 1.0 if key == "GP" else 0.15
            if abs(a - b) > tolerance:
                mismatches.append(
                    f"{athlete.get('displayName')} {key}: published={a} derived={b}")

    years = sorted(averages)
    current = max(years)
    if (to_float(averages[current].get("GP"), 0) or 0) < MIN_GAMES_FOR_CURRENT_SEASON:
        played = [y for y in years
                  if (to_float(averages[y].get("GP"), 0) or 0) >= MIN_GAMES_FOR_CURRENT_SEASON]
        if played:
            current = max(played)

    rookie_year = min(years)
    conference, division = groups.get(athlete.get("_teamID", ""), ("", ""))
    birth = athlete.get("birthPlace") or {}

    return {
        "id": int(athlete["id"]),
        "firstName": athlete.get("firstName") or "",
        "lastName": athlete.get("lastName") or "",
        "fullName": athlete.get("displayName") or "",
        "team": team_meta.get("abbrev", ""),
        "teamName": team_meta.get("name", ""),
        "conference": conference,
        "division": division,
        "position": (athlete.get("position") or {}).get("abbreviation") or "",
        "age": athlete.get("age"),
        "nationality": birth.get("country") or "",
        "jersey": to_float(athlete.get("jersey")),
        "debutYear": rookie_year,
        "season": {"year": current, "stats": per_game(averages[current])},
        "career": {"stats": career},
        "rookie": {"year": rookie_year, "stats": per_game(averages[rookie_year])},
        "seasons": [{"year": y, "stats": per_game(averages[y])} for y in years],
    }


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    team_meta = teams(SPORT_PATH)
    if len(team_meta) < 25:
        print(f"ERROR: only {len(team_meta)} teams, refusing to publish", file=sys.stderr)
        return 1
    groups = team_groups(SPORT_PATH)
    print(f"teams: {len(team_meta)} (conference/division for {len(groups)})")

    athletes = roster_players(list(team_meta))
    print(f"rostered athletes: {len(athletes)}")
    if len(athletes) < 300:
        print("ERROR: roster fetch looks incomplete, refusing to publish", file=sys.stderr)
        return 1

    urls = [f"{WEB_API}/{SPORT_PATH}/athletes/{a['id']}/stats" for a in athletes]
    docs = get_many(urls, workers=16)

    # ESPN publishes a career line of its own; prefer it over deriving one.
    with ThreadPoolExecutor(16) as ex:
        careers = list(ex.map(lambda a: authoritative_career(int(a["id"])), athletes))
    print(f"published career lines found: {sum(1 for c in careers if c)}/{len(athletes)}")

    players, season, mismatches = [], 0, []
    for athlete, doc, published in zip(athletes, docs, careers):
        built = build_player(athlete, doc, team_meta.get(athlete["_teamID"], {}),
                             groups, published, mismatches)
        if built:
            players.append(built)
            season = max(season, built["season"]["year"])
    players.sort(key=lambda p: (p["lastName"], p["firstName"]))
    print(f"players with usable stats: {len(players)}")
    if mismatches:
        print(f"WARNING: {len(mismatches)} career cross-check mismatches", file=sys.stderr)
        for line in mismatches[:10]:
            print(f"   {line}", file=sys.stderr)
        # A handful could be an ESPN data quirk; widespread disagreement means
        # the derivation is wrong and the file should not be published.
        if len(mismatches) > len(players) * 0.05:
            print("ERROR: too many mismatches, refusing to publish", file=sys.stderr)
            return 1
    if len(players) < 200:
        print("ERROR: too few players, refusing to publish", file=sys.stderr)
        return 1

    doc = {
        "generated": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "sport": "basketball",
        "league": "nba",
        "season": season,
        "statKeys": {"card": CARD_KEYS, "primary": PRIMARY_KEYS},
        "count": len(players),
        "players": players,
    }
    for base in ("", "docs"):
        path = os.path.join(repo_root, base, "data", "nba.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
            f.write("\n")
    size = os.path.getsize(os.path.join(repo_root, "data", "nba.json"))
    print(f"wrote data/nba.json — season {season}, {len(players)} players, {size/1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
