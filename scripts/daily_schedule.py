"""Builds a daily-puzzle schedule that is identical on every device.

Shared by the MLB and NBA generators. The one rule that matters: a date that
has already been published must never be rewritten. Changing one would hand two
users different puzzles depending on when they last fetched the file, which is
the exact bug publishing the schedule exists to prevent.
"""

from __future__ import annotations

import json
import os
from datetime import date, timedelta

# How many days of puzzles to keep scheduled ahead of today.
LOOKAHEAD_DAYS = 21
# Don't reuse an answer within this many days.
NO_REPEAT_DAYS = 120


def extend(existing: dict, pool: list[int], today: date,
           lookahead: int = LOOKAHEAD_DAYS,
           no_repeat: int = NO_REPEAT_DAYS) -> dict:
    """Returns {"picks": {ISO date: player id}} covering today and `lookahead` days.

    `pool` is ordered by prominence, so the puzzle stays recognisable. Dates
    already in `existing` are copied through untouched.
    """
    picks: dict[str, int] = dict(existing.get("picks", {}))
    if not pool:
        return {"picks": picks}

    def recent_ids(before: date, days: int) -> set[int]:
        out = set()
        for offset in range(1, days + 1):
            key = (before - timedelta(days=offset)).isoformat()
            if key in picks:
                out.add(picks[key])
        return out

    for offset in range(lookahead + 1):
        key = (today + timedelta(days=offset)).isoformat()
        if key in picks:
            continue
        used = recent_ids(today + timedelta(days=offset), no_repeat)
        # Deterministic from the date alone, so a re-run produces the same answer.
        seed = int.from_bytes(key.encode(), "big")
        candidates = [pid for pid in pool if pid not in used] or pool
        picks[key] = candidates[seed % len(candidates)]

    # Keep the file small; dates well in the past are of no use to the app.
    cutoff = (today - timedelta(days=no_repeat + 7)).isoformat()
    picks = {k: v for k, v in picks.items() if k >= cutoff}
    return {"picks": dict(sorted(picks.items()))}


def load(path: str) -> dict:
    """Reads a published schedule, tolerating a missing or corrupt file."""
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}
