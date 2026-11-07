"""Shared helpers for the ESPN-backed sport generators (NBA, later NFL).

ESPN's bulk "statistics/byathlete" endpoint returns athlete identities but empty
stat values, so real numbers only come from one request per athlete. That is far
too much work to do on device (the NFL alone is ~1,900 players and ~55 MB), which
is why these generators run in CI and publish a compact normalized file instead.

Note on the User-Agent: ESPN rejects any agent string matching /bot/i, so this
identifies the client by name without that word. It is a plain identifier, not a
browser impersonation.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

SITE_API = "https://site.api.espn.com/apis/site/v2/sports"
WEB_API = "https://site.web.api.espn.com/apis/common/v3/sports"
HEADERS = {"User-Agent": "StatSleuth/1.0 (+https://github.com/azzopalj/StatSleuth)"}


def get(url: str, attempts: int = 3) -> dict:
    req = urllib.request.Request(url, headers=HEADERS)
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError):
            if attempt == attempts - 1:
                return {}
    return {}


def get_many(urls: list[str], workers: int = 12) -> list[dict]:
    with ThreadPoolExecutor(workers) as ex:
        return list(ex.map(get, urls))


def to_float(value, default=None):
    """ESPN gives stats as display strings: '28.1', '1,234', '506-1186', '-'."""
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace(",", "")
    if not text or text in {"-", "--"}:
        return default
    try:
        return float(text)
    except ValueError:
        return default


def split_made_attempted(value) -> tuple[float | None, float | None]:
    """'506-1186' -> (506.0, 1186.0)."""
    if not isinstance(value, str) or "-" not in value:
        return None, None
    made, _, attempted = value.partition("-")
    return to_float(made), to_float(attempted)


class AmbiguousLabel(Exception):
    """A stat label appears more than once in the category being read."""


def category_rows(categories: list[dict], name: str) -> tuple[list[str], dict[int, list[str]]]:
    """(labels, {season year: raw stat values}) for one ESPN stat category.

    A player traded mid-season gets one row per team plus a combined row whose
    teamSlug reads like "2024 Totals". The combined row is picked explicitly:
    relying on it being last would quietly depend on ESPN's ordering, and
    getting it wrong publishes half a season.

    Values stay a positional list because some categories repeat a label — NFL
    "defensive" carries YDS twice, for fumble and interception returns — so
    zipping labels to values would silently drop one. Read them with `stat`.
    """
    for category in categories:
        if category.get("name") != name:
            continue
        labels = [str(label).strip() for label in category.get("labels") or []]
        by_year: dict[int, list[tuple[bool, list[str]]]] = {}
        for entry in category.get("statistics") or []:
            year = (entry.get("season") or {}).get("year")
            if not year:
                continue
            combined = str(entry.get("teamSlug") or "").lower().endswith("totals")
            by_year.setdefault(int(year), []).append((combined, entry.get("stats") or []))

        rows: dict[int, list[str]] = {}
        for year, entries in by_year.items():
            combined = [values for is_combined, values in entries if is_combined]
            if combined:
                rows[year] = combined[0]
            elif len(entries) == 1:
                rows[year] = entries[0][1]
            else:
                # A split season with no combined row: take the longer stint
                # rather than guessing, and let the caller's cross-check catch it.
                gp = labels.index("GP") if "GP" in labels else 0
                rows[year] = max((values for _, values in entries),
                                 key=lambda v: to_float(v[gp] if gp < len(v) else None, 0) or 0)
        return labels, rows
    return [], {}


def stat(labels: list[str], values: list[str], label: str, default=None):
    """One value out of a positional stat row, by label.

    Raises rather than guessing when the label is repeated in the category —
    picking the first occurrence silently is how you end up publishing
    interception return yards as fumble return yards.
    """
    found = [i for i, candidate in enumerate(labels) if candidate == label]
    if len(found) > 1:
        raise AmbiguousLabel(f"{label!r} appears {len(found)} times in {labels}")
    if not found or found[0] >= len(values):
        return default
    return to_float(values[found[0]], default)


def teams(sport_path: str) -> dict[str, dict]:
    """Team id -> {abbrev, name}."""
    data = get(f"{SITE_API}/{sport_path}/teams")
    out: dict[str, dict] = {}
    for league in (data.get("sports") or [{}])[0].get("leagues") or []:
        for entry in league.get("teams") or []:
            t = entry.get("team") or {}
            if not t.get("id"):
                continue
            out[str(t["id"])] = {
                "abbrev": t.get("abbreviation") or "",
                "name": t.get("displayName") or "",
            }
    return out


def team_groups(sport_path: str) -> dict[str, tuple[str, str]]:
    """Team id -> (conference, division), from the /groups tree.

    The tree is conference -> division -> teams. Leagues without divisions put
    teams directly under the conference, so handle both.
    """
    data = get(f"{SITE_API}/{sport_path}/groups")
    mapping: dict[str, tuple[str, str]] = {}
    for conference in data.get("groups") or []:
        conf_name = conference.get("name") or ""
        divisions = conference.get("children") or []
        if not divisions:
            divisions = [conference]
        for division in divisions:
            div_name = division.get("name") or ""
            for team in division.get("teams") or []:
                if team.get("id"):
                    mapping[str(team["id"])] = (conf_name, div_name)
    return mapping
