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
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from espn_common import (SITE_API, WEB_API, get_many, split_made_attempted,  # noqa: E402
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
    """Season year -> {label: display value} for one ESPN stat category."""
    for category in categories:
        if category.get("name") != name:
            continue
        labels = category.get("labels") or []
        rows: dict[int, dict[str, str]] = {}
        for entry in category.get("statistics") or []:
            year = (entry.get("season") or {}).get("year")
            if year:
                rows[int(year)] = dict(zip(labels, entry.get("stats") or []))
        return rows
    return {}


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
                 groups: dict[str, tuple[str, str]]) -> dict | None:
    categories = stats_doc.get("categories") or []
    averages = season_rows(categories, "averages")
    totals = season_rows(categories, "totals")
    if not averages:
        return None

    career = career_stats(totals, averages)
    if not career or career.get("GP", 0) < MIN_CAREER_GAMES:
        return None

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

    players, season = [], 0
    for athlete, doc in zip(athletes, docs):
        built = build_player(athlete, doc, team_meta.get(athlete["_teamID"], {}), groups)
        if built:
            players.append(built)
            season = max(season, built["season"]["year"])
    players.sort(key=lambda p: (p["lastName"], p["firstName"]))
    print(f"players with usable stats: {len(players)}")
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
