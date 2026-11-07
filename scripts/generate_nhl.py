#!/usr/bin/env python3
"""Builds data/nhl.json and data/nhl_daily.json.

Hockey splits two ways, not five like football: every skater — centre, winger
or defenceman — is read on the same fifteen numbers, and a goaltender on an
entirely different thirteen. So the published `group` is "Skater" or "Goalie",
which is what the stat card and the guess comparison key off.

That is a coarser split than a fan would make: a centre and a defenceman are
not the same position, even though they share a stat line. Position closeness
is handled separately in the app's SportProfile, which groups forwards,
defence and goalies for that purpose alone.

Numbers here are season totals, not per-game averages like the NBA's. Career
lines come from ESPN's own published career split, cross-checked against the
sum of the season rows.
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
                         get, get_many, stat, team_groups, teams, to_float)

SPORT_PATH = "hockey/nhl"

# Position abbreviation -> the group whose stat line the player gets. Skaters
# all share one; a goaltender shares nothing with any of them.
POSITION_GROUPS = {
    "C": "Skater", "LW": "Skater", "RW": "Skater", "F": "Skater", "D": "Skater",
    "G": "Goalie",
}

# ESPN names the stat category after the position, so there is no fixed name to
# ask for. These are the ones it publishes.
CATEGORY_GROUPS = {
    "center": "Skater", "left-wing": "Skater", "right-wing": "Skater",
    "defense": "Skater", "forward": "Skater",
    "goaltender": "Goalie",
}

# Card keys per group, in display order.
GROUP_KEYS = {
    "Skater": ["GP", "G", "A", "PTS", "+/-", "PIM", "PPG", "TOI/G"],
    "Goalie": ["GP", "WINS", "L", "OTL", "GAA", "SV%", "SO", "SA"],
}

# The two stats the guess feedback comments on, per group.
PRIMARY_KEYS = {
    "Skater": ["PTS", "G"],
    "Goalie": ["WINS", "GAA"],
}

# key -> label inside the season category. Mostly identity; TOI/G and SV% are
# converted below rather than read straight.
SEASON_LABELS = {
    "GP": "GP", "G": "G", "A": "A", "PTS": "PTS", "+/-": "+/-", "PIM": "PIM",
    "PPG": "PPG", "TOI/G": "TOI/G",
    "WINS": "WINS", "L": "L", "OTL": "OTL", "GAA": "GAA",
    "SA": "SA", "SV%": "SV%", "SO": "SO",
}

# What each of those labels has to mean, checked against ESPN's own
# displayNames before a single number is read.
#
# This is not belt and braces. The skater category publishes "SOG", which is
# Shootout Goals — not shots on goal, which it does not carry at all. Read as
# shots it is wrong by three orders of magnitude and looks plausible on a card.
# Any label whose meaning drifts should stop the run, not ship.
EXPECTED_NAMES = {
    "GP": "Games Played", "G": "Goals", "A": "Assists", "PTS": "Points",
    "+/-": "Plus/Minus Rating", "PIM": "Penalty Minutes",
    "PPG": "Power Play Goals", "TOI/G": "Time On Ice Per Game",
    "WINS": "Wins", "L": "Losses", "OTL": "Overtime Losses",
    "GAA": "Goals Against Average", "SA": "Shots Against",
    "SV%": "Save Percentage", "SO": "Shutouts",
}

# key -> label inside the athlete overview's career split. The overview calls
# shots on goal "S" where the season category calls them "SOG"; everything else
# matches. TOI/G is deliberately absent — see career_line.
CAREER_LABELS = {
    "GP": "GP", "G": "G", "A": "A", "PTS": "PTS", "+/-": "+/-", "PIM": "PIM",
    "PPG": "PPG",
    "WINS": "WINS", "L": "L", "OTL": "OTL", "GAA": "GAA", "SV%": "SV%",
    "SO": "SO", "SA": "SA",
}

# Kept to one decimal; everything else is a whole number.
DECIMAL_KEYS = {"TOI/G", "SV%"}
# Kept to two. A goals-against average rounded to 2.6 throws away the
# difference between a good goalie and a great one.
PRECISE_KEYS = {"GAA"}

# Rate stats, which cannot be summed across seasons.
RATE_KEYS = {"GAA", "SV%", "TOI/G"}

# Below this a player is a call-up with a token line, and makes for an unfair
# puzzle. Measured on career games.
MIN_CAREER_GAMES = 20
# A handful of games into a new season tells you nothing, so fall back to the
# last season the player actually played. A backup goalie starts a fraction of
# his team's games, so the same bar would push every one of them onto last
# season for most of the year.
MIN_GAMES_FOR_CURRENT_SEASON = {"Skater": 10, "Goalie": 5}

# How many players land in the Notables pack — the free default pack and the
# pool the daily puzzle is drawn from.
#
# Goalies get a reserved share. Ranked against skaters on one list they would
# never appear at all, since they score no points, and the daily would then
# never once be a goalie — which is a strange way to present hockey.
NOTABLE_QUOTAS = {"Skater": 130, "Goalie": 20}


def roster_players(team_ids: list[str]) -> list[dict]:
    """Every rostered player, flattened out of ESPN's position groupings.

    Injured players included: someone on LTIR is still a player a fan knows
    and wants to guess. The career floor below removes anyone without a real
    stat line, which is the only filter that matters here.
    """
    urls = [f"{SITE_API}/{SPORT_PATH}/teams/{tid}/roster" for tid in team_ids]
    out: list[dict] = []
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


def minutes(value) -> float | None:
    """'20:10' -> 20.2. Ice time is published as mm:ss."""
    if value is None:
        return None
    text = str(value).strip()
    if ":" not in text:
        return to_float(text)
    mins, _, secs = text.partition(":")
    m, s = to_float(mins), to_float(secs)
    if m is None or s is None:
        return None
    return round(m + s / 60, 1)


def percent(value) -> float | None:
    """'.925' -> 92.5. Save percentage is published as a proportion."""
    number = to_float(value)
    return None if number is None else round(number * 100, 1)


def round_key(key: str, value: float) -> float:
    if key in PRECISE_KEYS:
        return round(value, 2)
    if key in DECIMAL_KEYS:
        return round(value, 1)
    return round(value)


def stat_category(categories: list[dict]) -> tuple[str, str] | None:
    """(category name, group) for the one category this athlete publishes."""
    for category in categories:
        group = CATEGORY_GROUPS.get(category.get("name") or "")
        if group:
            check_label_meanings(category)
            return category.get("name"), group
    return None


def check_label_meanings(category: dict) -> None:
    """Fails the run if a label we read no longer means what it used to."""
    names = dict(zip([str(l).strip() for l in category.get("labels") or []],
                     [str(n).strip() for n in category.get("displayNames") or []]))
    for label, expected in EXPECTED_NAMES.items():
        actual = names.get(label)
        if actual is not None and actual != expected:
            raise AmbiguousLabel(
                f"{label!r} is {actual!r} in the {category.get('name')!r} category, "
                f"expected {expected!r}")


def season_line(labels: list[str], values: list[str], group: str) -> dict[str, float]:
    """One season's numbers, limited to the group's card keys."""
    out: dict[str, float] = {}
    for key in GROUP_KEYS[group]:
        label = SEASON_LABELS[key]
        if key == "TOI/G":
            value = minutes(stat_text(labels, values, label))
        elif key == "SV%":
            value = percent(stat_text(labels, values, label))
        else:
            value = stat(labels, values, label)
        if value is not None:
            out[key] = round_key(key, value)
    return out


def stat_text(labels: list[str], values: list[str], label: str) -> str | None:
    """The raw display string for a label — for values `to_float` can't read."""
    found = [i for i, candidate in enumerate(labels) if candidate == label]
    if len(found) > 1:
        raise AmbiguousLabel(f"{label!r} appears {len(found)} times in {labels}")
    if not found or found[0] >= len(values):
        return None
    return values[found[0]]


def career_line(pid: int, group: str) -> dict[str, float] | None:
    """ESPN's own published career split, from the athlete overview.

    Preferred over summing the seasons so the headline numbers are ESPN's
    rather than our arithmetic — the caller sums them anyway and compares.

    Ice time is not read from here. The overview's career TOI/G is an
    accumulated figure, not an average: it reports 230:27 for a forward who
    has never played half an hour in a game. The caller computes a
    games-weighted average from the season rows instead.
    """
    doc = get(f"{WEB_API}/{SPORT_PATH}/athletes/{pid}/overview")
    stats = doc.get("statistics") or {}
    labels = [str(label).strip() for label in stats.get("labels") or []]
    for row in stats.get("splits") or []:
        if (row.get("displayName") or "").strip().lower() != "career":
            continue
        values = row.get("stats") or []
        out: dict[str, float] = {}
        for key in GROUP_KEYS[group]:
            if key == "TOI/G":
                continue
            label = CAREER_LABELS.get(key)
            if not label:
                continue
            value = percent(stat_text(labels, values, label)) if key == "SV%" \
                else stat(labels, values, label)
            if value is not None:
                out[key] = round_key(key, value)
        return out or None
    return None


def weighted_ice_time(lines: dict[int, dict[str, float]]) -> float | None:
    """Career ice time per game, weighted by the games each season covers."""
    minutes_played = games = 0.0
    for line in lines.values():
        toi, gp = line.get("TOI/G"), line.get("GP")
        if toi is None or not gp:
            continue
        minutes_played += toi * gp
        games += gp
    return round(minutes_played / games, 1) if games else None


def prominence(player: dict) -> float:
    """How recognisable a player is, used to pick the Notables pack.

    Skaters and goalies are not comparable on raw numbers — a goalie scores
    nothing — so each is scored against its own yardstick and the result is a
    fraction of a strong career in that role. Current-season production counts
    for more per unit, so a player having a big year rises.

    The benchmarks are a judgement call, not a published metric. They only have
    to order the pool, and the cut is wide enough that near-ties don't matter.
    """
    group = player["group"]
    career = player["career"]["stats"]
    season = player["season"]["stats"]
    benchmarks = {
        "Skater": [("PTS", 700), ("G", 300)],
        "Goalie": [("WINS", 250), ("SO", 30)],
    }[group]
    score = 0.0
    for key, benchmark in benchmarks:
        score += 100 * (career.get(key, 0) or 0) / benchmark
        # A season counts for about a fifth of a full career at the same rate.
        score += 100 * (season.get(key, 0) or 0) / benchmark * 5
    # Longevity on its own keeps a respected veteran in the pool.
    score += (career.get("GP", 0) or 0) / 4
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
                 published: dict[str, float] | None,
                 mismatches: list[str], partial: list[str]) -> dict | None:
    group = group_for(athlete)
    if not group:
        return None

    categories = stats_doc.get("categories") or []
    found = stat_category(categories)
    if not found:
        return None
    category, stats_group = found
    # The roster's position and the stat category should agree. When they
    # don't — a skater listed at a position ESPN files under goaltending, or
    # the reverse — the card would be built from the wrong stat set, so skip
    # rather than publish a player whose numbers don't match their badge.
    if stats_group != group:
        return None

    labels, by_year = category_rows(categories, category)
    years = sorted(by_year)
    if not years:
        return None

    lines = {year: season_line(labels, by_year[year], group) for year in years}
    career = dict(published) if published else {}

    # ESPN's per-athlete stats sometimes begin partway through a career, and
    # when they do the seasons on hand are not the whole story: the earliest is
    # not a rookie season and the totals cannot be added up. Whether a history
    # is complete is settled by evidence — sum the seasons and compare against
    # the career ESPN publishes separately — rather than by a metadata field.
    complete = bool(published)
    for key in ["GP"] + PRIMARY_KEYS[group]:
        if key in RATE_KEYS:
            continue
        figure = career.get(key)
        if figure is None:
            continue
        summed = sum((line.get(key, 0) or 0) for line in lines.values())
        if abs(summed - figure) > max(1, abs(figure) * 0.02):
            complete = False
            mismatches.append(
                f"{athlete.get('displayName')} {key}: published={figure} summed={summed}")

    if not career:
        # No published career line. Everything on the card but the rates can be
        # summed, and a player with no career line at all is not worth guessing.
        for key in GROUP_KEYS[group]:
            if key in RATE_KEYS:
                continue
            career[key] = round_key(key, sum((line.get(key, 0) or 0)
                                             for line in lines.values()))
        complete = False
    if (career.get("GP", 0) or 0) < MIN_CAREER_GAMES:
        return None

    ice_time = weighted_ice_time(lines)
    if ice_time is not None and "TOI/G" in GROUP_KEYS[group]:
        career["TOI/G"] = ice_time

    debut = min(years)
    current = max(years)
    floor = MIN_GAMES_FOR_CURRENT_SEASON[group]
    if (lines[current].get("GP", 0) or 0) < floor:
        played = [y for y in years if (lines[y].get("GP", 0) or 0) >= floor]
        if played:
            current = max(played)
    if not lines[current]:
        return None

    if not complete:
        partial.append(f"{athlete.get('displayName')} (rows from {debut})")

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
        "jersey": to_float(athlete.get("jersey")),
        "debutYear": debut,
        "headshot": (athlete.get("headshot") or {}).get("href") or None,
        "season": {"year": current, "stats": lines[current]},
        "career": {"stats": career},
        # Only a genuine debut season counts as the rookie line; with early
        # seasons missing this would be whichever year ESPN happens to start at.
        "rookie": ({"year": debut, "stats": lines[debut]} if complete
                   else {"year": None, "stats": {}}),
        "seasons": [{"year": y, "stats": lines[y]} for y in years],
    }


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    team_meta = teams(SPORT_PATH)
    if len(team_meta) < 30:
        print(f"ERROR: only {len(team_meta)} teams, refusing to publish", file=sys.stderr)
        return 1
    groups = team_groups(SPORT_PATH)
    print(f"teams: {len(team_meta)} (conference/division for {len(groups)})")

    athletes = [a for a in roster_players(list(team_meta)) if group_for(a)]
    print(f"rostered athletes: {len(athletes)}")
    if len(athletes) < 600:
        print("ERROR: roster fetch looks incomplete, refusing to publish", file=sys.stderr)
        return 1

    urls = [f"{WEB_API}/{SPORT_PATH}/athletes/{a['id']}/stats" for a in athletes]
    docs = get_many(urls, workers=16)

    with ThreadPoolExecutor(16) as ex:
        careers = list(ex.map(lambda a: career_line(int(a["id"]), group_for(a)), athletes))
    print(f"published career lines found: {sum(1 for c in careers if c)}/{len(athletes)}")

    players, season, mismatches, partial = [], 0, [], []
    for athlete, doc, published in zip(athletes, docs, careers):
        try:
            built = build_player(athlete, doc, team_meta.get(athlete["_teamID"], {}),
                                 groups, published, mismatches, partial)
        except AmbiguousLabel as error:
            print(f"ERROR: {athlete.get('displayName')}: {error}", file=sys.stderr)
            return 1
        if built:
            players.append(built)
            season = max(season, built["season"]["year"])
    mark_notable(players)
    notables = sorted((p for p in players if p["notable"]), key=lambda p: -prominence(p))
    players.sort(key=lambda p: (p["lastName"], p["firstName"]))
    goalies = sum(1 for p in players if p["group"] == "Goalie")
    print(f"players with usable stats: {len(players)} "
          f"({len(players) - goalies} skaters, {goalies} goalies; notable: {len(notables)})")

    if partial:
        print(f"note: {len(partial)} of {len(players)} players have an incomplete "
              f"season history; their rookie line is omitted")
        for line in partial[:5]:
            print(f"   {line}")
        for line in mismatches[:3]:
            print(f"   {line}")
    # A few incomplete histories are ESPN's data. Widespread disagreement means
    # the reading of it here is wrong, and nothing should be published.
    if len(partial) > len(players) * 0.15:
        print(f"ERROR: {len(partial)} incomplete histories, refusing to publish",
              file=sys.stderr)
        return 1
    if len(players) < 400:
        print("ERROR: too few players, refusing to publish", file=sys.stderr)
        return 1

    doc = {
        "generated": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "sport": "hockey",
        "league": "nhl",
        "season": season,
        "statKeys": {"byGroup": GROUP_KEYS, "primaryByGroup": PRIMARY_KEYS},
        "count": len(players),
        "players": players,
    }

    today = datetime.now(timezone.utc).astimezone(
        timezone(timedelta(hours=-5))).date()   # ET-ish; the exact offset doesn't matter
    existing = daily_schedule.load(os.path.join(repo_root, "data", "nhl_daily.json"))
    daily_doc = {
        "generated": doc["generated"],
        "season": season,
        **daily_schedule.extend(existing, [p["id"] for p in notables], today),
    }
    print(f"daily schedule: {len(daily_doc['picks'])} dates "
          f"(through {max(daily_doc['picks']) if daily_doc['picks'] else 'n/a'})")

    for base in ("", "docs"):
        path = os.path.join(repo_root, base, "data", "nhl.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
            f.write("\n")
        with open(os.path.join(repo_root, base, "data", "nhl_daily.json"), "w",
                  encoding="utf-8") as f:
            json.dump(daily_doc, f, indent=1, ensure_ascii=False)
            f.write("\n")
    size = os.path.getsize(os.path.join(repo_root, "data", "nhl.json"))
    print(f"wrote data/nhl.json — season {season}, {len(players)} players, {size/1024:.0f} KB")
    print("top 10 notables:", ", ".join(p["fullName"] for p in notables[:10]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
