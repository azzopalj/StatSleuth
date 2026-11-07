#!/usr/bin/env python3
"""Builds data/nfl.json and data/nfl_daily.json.

Football does not have one stat line. A quarterback, a running back, a
cornerback and a kicker are judged on different numbers entirely, so each
player publishes only the keys their position group uses, and the app's
SportProfile holds the card layout and comparison rules per group. That is the
same split baseball already makes between hitters and pitchers.

Career lines come from ESPN's core API, which returns named fields
("passingYards": 37734) rather than a positional list. The web endpoints
publish career stats as values zipped to a label list that is position-shaped
and sometimes repeats a label, which cannot be read back safely. Season lines
do come from the web endpoint, read positionally — see espn_common.stat.
"""

from __future__ import annotations

import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import daily_schedule  # noqa: E402
from espn_common import (SITE_API, WEB_API, AmbiguousLabel, category_rows,  # noqa: E402
                         get, get_many, stat, team_groups, teams)

SPORT_PATH = "football/nfl"
CORE_API = "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl"

# How many players land in the Notables pack — the free default pack and the
# pool the daily puzzle is drawn from, split by role.
#
# Ranking everyone on one list would fill it with defenders, who outnumber
# everyone else three to one. They also make the thinnest puzzles: a card
# reading 21 tackles and no interceptions could be any of two hundred
# linebackers, where 1,795 passing yards narrows it to a handful. So the pack
# is weighted towards the roles a fan can actually name.
NOTABLE_QUOTAS = {
    "Quarterback": 30,
    "Receiver": 45,
    "Defense": 40,
    "Running Back": 25,
    "Kicker": 10,
}
# A couple of games into a season tells you nothing, so fall back to the last
# season the player actually played.
MIN_GAMES_FOR_CURRENT_SEASON = 4

# Position abbreviation -> the group whose stat line the player gets.
# Anything not listed (offensive line, long snappers, punters) records nothing
# the game could ask about, so those players are left out rather than shown
# with an empty card.
POSITION_GROUPS = {
    "QB": "Quarterback",
    "RB": "Running Back", "FB": "Running Back",
    "WR": "Receiver", "TE": "Receiver",
    "DE": "Defense", "DT": "Defense", "NT": "Defense", "EDGE": "Defense",
    "LB": "Defense", "ILB": "Defense", "OLB": "Defense", "MLB": "Defense",
    "CB": "Defense", "S": "Defense", "FS": "Defense", "SS": "Defense",
    "DB": "Defense",
    "K": "Kicker", "PK": "Kicker",
}

# Card keys per group, in display order. Keys are namespaced where a group
# draws on more than one category, so a running back's rushing and receiving
# yards can sit on the same card.
GROUP_KEYS = {
    "Quarterback":  ["GP", "PASS YDS", "PASS TD", "INT", "CMP%", "RTG", "RUSH YDS"],
    "Running Back": ["GP", "RUSH YDS", "RUSH TD", "CAR", "YPC", "REC", "REC YDS", "REC TD"],
    "Receiver":     ["GP", "REC", "REC YDS", "REC TD", "TGTS", "YPR", "RUSH YDS"],
    "Defense":      ["GP", "TACK", "SOLO", "SACK", "INT", "PD", "FF"],
    "Kicker":       ["GP", "FG", "FGA", "FG%", "LNG", "XPM", "PTS"],
}

# The two stats the guess feedback comments on, per group.
PRIMARY_KEYS = {
    "Quarterback":  ["PASS YDS", "PASS TD"],
    "Running Back": ["RUSH YDS", "RUSH TD"],
    "Receiver":     ["REC YDS", "REC"],
    "Defense":      ["TACK", "SACK"],
    "Kicker":       ["FG", "PTS"],
}

# Below this a player is a backup with a token stat line, and makes for an
# unfair puzzle. Keyed by group, measured on career numbers.
MIN_CAREER = {
    "Quarterback":  ("PASS YDS", 500),
    "Running Back": ("RUSH YDS", 300),
    "Receiver":     ("REC YDS", 300),
    "Defense":      ("TACK", 40),
    "Kicker":       ("FG", 20),
}

# key -> (web stat category, label within it) for season lines.
SEASON_SOURCES = {
    "GP":       ("any", "GP"),
    "PASS YDS": ("passing", "YDS"),
    "PASS TD":  ("passing", "TD"),
    "INT":      ("passing", "INT"),      # thrown; defenders override below
    "CMP%":     ("passing", "CMP%"),
    "RTG":      ("passing", "RTG"),
    "RUSH YDS": ("rushing", "YDS"),
    "RUSH TD":  ("rushing", "TD"),
    "CAR":      ("rushing", "CAR"),
    "YPC":      ("rushing", "AVG"),
    "REC":      ("receiving", "REC"),
    "REC YDS":  ("receiving", "YDS"),
    "REC TD":   ("receiving", "TD"),
    "TGTS":     ("receiving", "TGTS"),
    "YPR":      ("receiving", "AVG"),
    "TACK":     ("defensive", "TOT"),
    "SOLO":     ("defensive", "SOLO"),
    "SACK":     ("defensive", "SACK"),
    "PD":       ("defensive", "PD"),
    "FF":       ("defensive", "FF"),
    "FG":       ("kicking", "FG"),       # "22-30" — made/attempted, split below
    "FG%":      ("kicking", "FG%"),
    "LNG":      ("kicking", "LNG"),
    "XPM":      ("kicking", "XPM"),
    "PTS":      ("kicking", "PTS"),
}
# A defender's INT is caught, not thrown, so it comes from a different category.
DEFENSE_SEASON_OVERRIDES = {"INT": ("defensive", "INT")}

# key -> (core API category, field) for career lines.
CAREER_SOURCES = {
    "PASS YDS": ("passing", "passingYards"),
    "PASS TD":  ("passing", "passingTouchdowns"),
    "INT":      ("passing", "interceptions"),
    "CMP%":     ("passing", "completionPct"),
    "RTG":      ("passing", "QBRating"),
    "RUSH YDS": ("rushing", "rushingYards"),
    "RUSH TD":  ("rushing", "rushingTouchdowns"),
    "CAR":      ("rushing", "rushingAttempts"),
    "YPC":      ("rushing", "yardsPerRushAttempt"),
    "REC":      ("receiving", "receptions"),
    "REC YDS":  ("receiving", "receivingYards"),
    "REC TD":   ("receiving", "receivingTouchdowns"),
    "TGTS":     ("receiving", "receivingTargets"),
    "YPR":      ("receiving", "yardsPerReception"),
    "TACK":     ("defensive", "totalTackles"),
    "SOLO":     ("defensive", "soloTackles"),
    "SACK":     ("defensive", "sacks"),
    "PD":       ("defensive", "passesDefended"),
    "FF":       ("defensive", "fumblesForced"),
    "FG":       ("kicking", "fieldGoalsMade"),
    "FGA":      ("kicking", "fieldGoalAttempts"),
    "FG%":      ("kicking", "fieldGoalPct"),
    "LNG":      ("kicking", "longFieldGoalMade"),
    "XPM":      ("kicking", "extraPointsMade"),
    "PTS":      ("scoring", "totalPoints"),
}
DEFENSE_CAREER_OVERRIDES = {"INT": ("defensiveInterceptions", "interceptions")}

# Stats kept to one decimal; everything else is a whole number. Rates are the
# obvious ones — SACK is here because football credits half a sack when two
# players share one, so 10.5 is a real value, not a rounding artefact.
DECIMAL_KEYS = {"CMP%", "RTG", "YPC", "YPR", "FG%", "SACK"}


def roster_players(team_ids: list[str]) -> list[dict]:
    """Every rostered player, flattened out of ESPN's roster groupings.

    Injured reserve included: Micah Parsons on IR is still someone a fan knows
    and wants to be able to guess, the same reason baseball keeps players on
    the injured list searchable. Nobody is filtered on roster status — the
    career floor below already removes anyone without a real stat line.
    """
    urls = [f"{SITE_API}/{SPORT_PATH}/teams/{tid}/roster" for tid in team_ids]
    out = []
    seen: set[str] = set()
    for tid, data in zip(team_ids, get_many(urls)):
        for group in data.get("athletes") or []:
            for athlete in group.get("items") or []:
                aid = str(athlete.get("id") or "")
                if aid and aid not in seen:
                    seen.add(aid)
                    athlete["_teamID"] = tid
                    out.append(athlete)
    return out


def group_for(athlete: dict) -> str | None:
    abbrev = ((athlete.get("position") or {}).get("abbreviation") or "").upper()
    return POSITION_GROUPS.get(abbrev)


def season_line(categories: list[dict], group: str, year: int) -> dict[str, float]:
    """One season's numbers for a player, limited to their group's keys."""
    sources = dict(SEASON_SOURCES)
    if group == "Defense":
        sources.update(DEFENSE_SEASON_OVERRIDES)

    cache: dict[str, tuple[list[str], dict[int, list[str]]]] = {}

    def rows(category: str):
        if category not in cache:
            cache[category] = category_rows(categories, category)
        return cache[category]

    out: dict[str, float] = {}
    for key in GROUP_KEYS[group]:
        # GP is handled below; FGA arrives with FG, which publishes "22-30".
        if key in ("GP", "FGA"):
            continue
        category, label = sources[key]
        labels, by_year = rows(category)
        values = by_year.get(year)
        if not values:
            continue
        if key == "FG":
            # Kicking publishes field goals as "22-30"; attempts come with it.
            made, attempted = split_fg(stat_text(labels, values, label))
            if made is not None:
                out["FG"] = made
            if attempted is not None:
                out["FGA"] = attempted
            continue
        value = stat(labels, values, label)
        if value is not None:
            out[key] = round(value, 1) if key in DECIMAL_KEYS else round(value)

    # Games played is in every category; take it from whichever one the group
    # leads with, so a kicker's GP doesn't come from a stray defensive row.
    lead = SEASON_SOURCES[GROUP_KEYS[group][1]][0]
    labels, by_year = rows(lead)
    games = stat(labels, by_year.get(year) or [], "GP")
    if games is not None:
        out["GP"] = round(games)
    return out


def stat_text(labels: list[str], values: list[str], label: str) -> str | None:
    found = [i for i, candidate in enumerate(labels) if candidate == label]
    if len(found) != 1 or found[0] >= len(values):
        return None
    return values[found[0]]


def split_fg(text: str | None) -> tuple[float | None, float | None]:
    """'22-30' -> (22, 30)."""
    if not text or "-" not in text:
        return None, None
    made, _, attempted = text.partition("-")
    try:
        return float(made.replace(",", "")), float(attempted.replace(",", ""))
    except ValueError:
        return None, None


def career_line(pid: int, group: str) -> dict[str, float] | None:
    """ESPN's own published career totals, read by field name.

    Preferred over summing the season rows, so the career line is ESPN's
    number rather than our arithmetic. The caller sums the seasons anyway and
    compares, because a silent disagreement is how a wrong stat ships.

    Games played is the exception and is left to the caller. This endpoint's
    `general.gamesPlayed` is wrong for kickers — it reports 78 for a kicker
    with 266 seasons' worth of games — while every counting stat here matches
    the season rows exactly. So GP comes from those instead.
    """
    doc = get(f"{CORE_API}/athletes/{pid}/statistics")
    categories = {c.get("name"): {s.get("name"): s.get("value")
                                  for s in (c.get("stats") or [])}
                  for c in ((doc.get("splits") or {}).get("categories") or [])}
    if not categories:
        return None

    sources = dict(CAREER_SOURCES)
    if group == "Defense":
        sources.update(DEFENSE_CAREER_OVERRIDES)

    out: dict[str, float] = {}
    for key in GROUP_KEYS[group] + (["FGA"] if group == "Kicker" else []):
        if key == "GP":
            continue
        category, field = sources[key]
        value = categories.get(category, {}).get(field)
        if value is None:
            continue
        out[key] = round(float(value), 1) if key in DECIMAL_KEYS else round(float(value))
    return out or None


def prominence(player: dict) -> float:
    """How recognisable a player is, used to pick the Notables pack.

    Positions are not comparable on raw numbers — a kicker outscores every
    quarterback — so each group is scored against its own yardstick and the
    result is a fraction of a strong career in that role. Current-season
    production is added on top so a player having a big year rises.
    """
    group = player["group"]
    career = player["career"]["stats"]
    season = player["season"]["stats"]
    benchmarks = {
        "Quarterback":  [("PASS YDS", 30000), ("PASS TD", 200)],
        "Running Back": [("RUSH YDS", 8000), ("RUSH TD", 60)],
        "Receiver":     [("REC YDS", 8000), ("REC TD", 60)],
        "Defense":      [("TACK", 600), ("SACK", 60)],
        "Kicker":       [("FG", 250), ("PTS", 1200)],
    }[group]
    score = 0.0
    for key, benchmark in benchmarks:
        score += 100 * (career.get(key, 0) or 0) / benchmark
        # A season counts for about a fifth of a full career at the same rate.
        score += 100 * (season.get(key, 0) or 0) / benchmark * 2
    # Longevity on its own keeps respected veterans in the pool.
    score += (career.get("GP", 0) or 0) / 2
    return score


def mark_notable(players: list[dict]) -> None:
    """Flags the most prominent players in each role, in place."""
    notable: set[int] = set()
    for group, quota in NOTABLE_QUOTAS.items():
        ranked = sorted((p for p in players if p["group"] == group),
                        key=lambda p: (-prominence(p), p["fullName"]))
        notable |= {p["id"] for p in ranked[:quota]}
    for player in players:
        player["notable"] = player["id"] in notable


def build_player(athlete: dict, stats_doc: dict, team_meta: dict,
                 groups: dict[str, tuple[str, str]],
                 career: dict[str, float] | None,
                 mismatches: list[str], partial: list[str]) -> dict | None:
    group = group_for(athlete)
    if not group or not career:
        return None

    floor_key, floor = MIN_CAREER[group]
    if (career.get(floor_key, 0) or 0) < floor:
        return None

    categories = stats_doc.get("categories") or []
    lead = SEASON_SOURCES[GROUP_KEYS[group][1]][0]
    _, by_year = category_rows(categories, lead)
    years = sorted(by_year)
    if not years:
        return None

    lines = {year: season_line(categories, group, year) for year in years}

    # ESPN's per-athlete stats sometimes begin partway through a career — Andy
    # Dalton debuted in 2011 and his rows start in 2014 — so the earliest row
    # is not always the debut, and the seasons cannot be added up.
    #
    # Whether a history is complete is settled by evidence rather than by a
    # metadata field: the seasons are summed and compared against the career
    # ESPN publishes separately. Agreement means nothing is missing. (The
    # obvious shortcut, `experience.years`, counts something subtly different
    # in each sport — seasons since debut in the NFL, seasons actually played
    # in the NBA, which differ for anyone who spent a year out of the league.)
    complete = True
    for key in PRIMARY_KEYS[group]:
        published = career.get(key)
        if published is None:
            continue
        summed = sum((line.get(key, 0) or 0) for line in lines.values())
        if abs(summed - published) > max(1, abs(published) * 0.02):
            complete = False
            mismatches.append(
                f"{athlete.get('displayName')} {key}: published={published} summed={summed}")

    debut = min(years)
    current = max(years)
    if (lines[current].get("GP", 0) or 0) < MIN_GAMES_FOR_CURRENT_SEASON:
        played = [y for y in years
                  if (lines[y].get("GP", 0) or 0) >= MIN_GAMES_FOR_CURRENT_SEASON]
        if played:
            current = max(played)
    season = lines[current]
    if not season:
        return None

    career = dict(career)
    if complete:
        # Career games played: ESPN's own season rows, added up. See career_line
        # for why its published figure is not used. With seasons missing the sum
        # would understate it, so it is left out rather than published wrong.
        career["GP"] = round(sum((line.get("GP", 0) or 0) for line in lines.values()))
    else:
        partial.append(f"{athlete.get('displayName')} (rows from {min(years)})")
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
        "group": group,
        "age": athlete.get("age"),
        "nationality": birth.get("country") or "",
        "jersey": _to_float(athlete.get("jersey")),
        "debutYear": debut,
        "headshot": (athlete.get("headshot") or {}).get("href") or None,
        "season": {"year": current, "stats": season},
        "career": {"stats": career},
        # Only a genuine debut season counts as the rookie line; with early
        # seasons missing this would be whichever year ESPN happens to start at.
        "rookie": ({"year": debut, "stats": lines[debut]} if complete
                   else {"year": None, "stats": {}}),
        "seasons": [{"year": y, "stats": lines[y]} for y in years],
    }


def _to_float(value):
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    team_meta = teams(SPORT_PATH)
    if len(team_meta) < 30:
        print(f"ERROR: only {len(team_meta)} teams, refusing to publish", file=sys.stderr)
        return 1
    groups = team_groups(SPORT_PATH)
    print(f"teams: {len(team_meta)} (conference/division for {len(groups)})")

    athletes = [a for a in roster_players(list(team_meta)) if group_for(a)]
    print(f"rostered athletes at a scoring position: {len(athletes)}")
    if len(athletes) < 800:
        print("ERROR: roster fetch looks incomplete, refusing to publish", file=sys.stderr)
        return 1

    urls = [f"{WEB_API}/{SPORT_PATH}/athletes/{a['id']}/stats" for a in athletes]
    docs = get_many(urls, workers=16)

    with ThreadPoolExecutor(16) as ex:
        careers = list(ex.map(lambda a: career_line(int(a["id"]), group_for(a)), athletes))
    print(f"published career lines found: {sum(1 for c in careers if c)}/{len(athletes)}")

    players, season, mismatches, partial = [], 0, [], []
    for athlete, doc, career in zip(athletes, docs, careers):
        try:
            built = build_player(athlete, doc, team_meta.get(athlete["_teamID"], {}),
                                 groups, career, mismatches, partial)
        except AmbiguousLabel as error:
            print(f"ERROR: {athlete.get('displayName')}: {error}", file=sys.stderr)
            return 1
        if built:
            players.append(built)
            season = max(season, built["season"]["year"])
    mark_notable(players)
    notables = sorted((p for p in players if p["notable"]), key=lambda p: -prominence(p))
    players.sort(key=lambda p: (p["lastName"], p["firstName"]))
    print(f"players with usable stats: {len(players)} (notable: {len(notables)})")

    if partial:
        print(f"note: {len(partial)} of {len(players)} players have an incomplete season "
              f"history; their rookie line and career GP are omitted")
        for line in partial[:5]:
            print(f"   {line}")
        for line in mismatches[:3]:
            print(f"   {line}")
    # A few incomplete histories are ESPN's data. Widespread disagreement means
    # the reading of it here is wrong, and nothing should be published.
    if len(partial) > len(players) * 0.1:
        print(f"ERROR: {len(partial)} incomplete histories, refusing to publish",
              file=sys.stderr)
        return 1
    if len(players) < 500:
        print("ERROR: too few players, refusing to publish", file=sys.stderr)
        return 1

    doc = {
        "generated": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "sport": "football",
        "league": "nfl",
        "season": season,
        "statKeys": {"byGroup": GROUP_KEYS, "primaryByGroup": PRIMARY_KEYS},
        "count": len(players),
        "players": players,
    }

    today = datetime.now(timezone.utc).astimezone(
        timezone(timedelta(hours=-5))).date()   # ET-ish; the exact offset doesn't matter
    existing = daily_schedule.load(os.path.join(repo_root, "data", "nfl_daily.json"))
    daily_doc = {
        "generated": doc["generated"],
        "season": season,
        **daily_schedule.extend(existing, [p["id"] for p in notables], today),
    }
    print(f"daily schedule: {len(daily_doc['picks'])} dates "
          f"(through {max(daily_doc['picks']) if daily_doc['picks'] else 'n/a'})")

    for base in ("", "docs"):
        path = os.path.join(repo_root, base, "data", "nfl.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
            f.write("\n")
        with open(os.path.join(repo_root, base, "data", "nfl_daily.json"), "w",
                  encoding="utf-8") as f:
            json.dump(daily_doc, f, indent=1, ensure_ascii=False)
            f.write("\n")
    size = os.path.getsize(os.path.join(repo_root, "data", "nfl.json"))
    print(f"wrote data/nfl.json — season {season}, {len(players)} players, {size/1024:.0f} KB")
    print("top 10 notables:", ", ".join(p["fullName"] for p in notables[:10]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
