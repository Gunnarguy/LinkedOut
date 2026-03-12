"""
Location intelligence for LinkedOut scoring.

Maps cities → metro areas → states → regions so the scoring engine
can assign graduated penalties instead of binary "relocation or not."

Tiers:
  0  home     – your city / metro area (no penalty)
  1  nearby   – same state or <2hr drive metros
  2  regional – neighboring states
  3  far_us   – rest of the US
  4  international
"""

from __future__ import annotations

# ── Michigan metros and common city aliases ──────────────────────────────────

_MICHIGAN_METROS: dict[str, list[str]] = {
    "Kalamazoo": [
        "kalamazoo",
        "portage",
        "mattawan",
        "paw paw",
        "richland",
        "plainwell",
        "otsego",
        "vicksburg",
        "schoolcraft",
    ],
    "Grand Rapids": [
        "grand rapids",
        "wyoming",
        "kentwood",
        "walker",
        "grandville",
        "holland",
        "zeeland",
        "byron center",
        "caledonia",
        "jenison",
        "hudsonville",
        "rockford",
        "cedar springs",
        "muskegon",
    ],
    "Detroit": [
        "detroit",
        "dearborn",
        "livonia",
        "troy",
        "southfield",
        "royal oak",
        "ann arbor",
        "ypsilanti",
        "canton",
        "novi",
        "farmington",
        "farmington hills",
        "plymouth",
        "westland",
        "sterling heights",
        "warren",
        "rochester",
        "rochester hills",
        "auburn hills",
        "pontiac",
        "bloomfield",
        "birmingham",
    ],
    "Lansing": [
        "lansing",
        "east lansing",
        "okemos",
        "haslett",
        "dewitt",
        "mason",
        "holt",
        "charlotte",
    ],
    "Traverse City": [
        "traverse city",
        "petoskey",
        "charlevoix",
        "cadillac",
    ],
    "Flint": [
        "flint",
        "burton",
        "grand blanc",
        "fenton",
        "flushing",
    ],
    "Saginaw": [
        "saginaw",
        "bay city",
        "midland",
    ],
    "Battle Creek": [
        "battle creek",
        "marshall",
        "albion",
    ],
    "Jackson": [
        "jackson",
    ],
}

# Which Michigan metros are "nearby" each other (~2hr drive)
_MI_NEARBY: dict[str, list[str]] = {
    "Kalamazoo": ["Grand Rapids", "Battle Creek", "Lansing", "Jackson"],
    "Grand Rapids": ["Kalamazoo", "Lansing", "Muskegon", "Battle Creek"],
    "Detroit": ["Lansing", "Flint", "Ann Arbor", "Jackson"],
    "Lansing": [
        "Grand Rapids",
        "Kalamazoo",
        "Detroit",
        "Flint",
        "Jackson",
        "Battle Creek",
    ],
    "Battle Creek": ["Kalamazoo", "Lansing", "Jackson", "Grand Rapids"],
    "Flint": ["Detroit", "Lansing", "Saginaw"],
    "Saginaw": ["Flint", "Traverse City"],
    "Jackson": ["Lansing", "Detroit", "Kalamazoo", "Battle Creek"],
    "Traverse City": ["Saginaw", "Cadillac"],
}

# Neighboring states to Michigan
_NEIGHBORING_STATES = {
    "michigan": {"ohio", "indiana", "wisconsin", "illinois", "minnesota"},
}

# ── US States list (for detecting domestic vs international) ────────────────

_US_STATES = {
    "alabama",
    "alaska",
    "arizona",
    "arkansas",
    "california",
    "colorado",
    "connecticut",
    "delaware",
    "florida",
    "georgia",
    "hawaii",
    "idaho",
    "illinois",
    "indiana",
    "iowa",
    "kansas",
    "kentucky",
    "louisiana",
    "maine",
    "maryland",
    "massachusetts",
    "michigan",
    "minnesota",
    "mississippi",
    "missouri",
    "montana",
    "nebraska",
    "nevada",
    "new hampshire",
    "new jersey",
    "new mexico",
    "new york",
    "north carolina",
    "north dakota",
    "ohio",
    "oklahoma",
    "oregon",
    "pennsylvania",
    "rhode island",
    "south carolina",
    "south dakota",
    "tennessee",
    "texas",
    "utah",
    "vermont",
    "virginia",
    "washington",
    "west virginia",
    "wisconsin",
    "wyoming",
    "district of columbia",
}

_STATE_ABBREV = {
    "al": "alabama",
    "ak": "alaska",
    "az": "arizona",
    "ar": "arkansas",
    "ca": "california",
    "co": "colorado",
    "ct": "connecticut",
    "de": "delaware",
    "fl": "florida",
    "ga": "georgia",
    "hi": "hawaii",
    "id": "idaho",
    "il": "illinois",
    "in": "indiana",
    "ia": "iowa",
    "ks": "kansas",
    "ky": "kentucky",
    "la": "louisiana",
    "me": "maine",
    "md": "maryland",
    "ma": "massachusetts",
    "mi": "michigan",
    "mn": "minnesota",
    "ms": "mississippi",
    "mo": "missouri",
    "mt": "montana",
    "ne": "nebraska",
    "nv": "nevada",
    "nh": "new hampshire",
    "nj": "new jersey",
    "nm": "new mexico",
    "ny": "new york",
    "nc": "north carolina",
    "nd": "north dakota",
    "oh": "ohio",
    "ok": "oklahoma",
    "or": "oregon",
    "pa": "pennsylvania",
    "ri": "rhode island",
    "sc": "south carolina",
    "sd": "south dakota",
    "tn": "tennessee",
    "tx": "texas",
    "ut": "utah",
    "vt": "vermont",
    "va": "virginia",
    "wa": "washington",
    "wv": "west virginia",
    "wi": "wisconsin",
    "wy": "wyoming",
    "dc": "district of columbia",
}

# Common international signals
_INTERNATIONAL_SIGNALS = [
    "london",
    "berlin",
    "paris",
    "amsterdam",
    "dublin",
    "toronto",
    "vancouver",
    "sydney",
    "melbourne",
    "singapore",
    "hong kong",
    "tokyo",
    "bangalore",
    "hyderabad",
    "mumbai",
    "tel aviv",
    "stockholm",
    "copenhagen",
    "zurich",
    "munich",
    "vienna",
    "barcelona",
    "madrid",
    "lisbon",
    "warsaw",
    "prague",
    "united kingdom",
    "uk",
    "germany",
    "france",
    "netherlands",
    "ireland",
    "canada",
    "australia",
    "india",
    "israel",
    "sweden",
    "denmark",
    "switzerland",
    "spain",
    "portugal",
    "poland",
    "czech republic",
    "austria",
    "japan",
    "brazil",
]

# Major US tech hubs (for the prompt to name-drop)
_US_TECH_HUBS = {
    "san francisco",
    "sf",
    "bay area",
    "palo alto",
    "mountain view",
    "san jose",
    "silicon valley",
    "cupertino",
    "menlo park",
    "sunnyvale",
    "new york",
    "nyc",
    "manhattan",
    "brooklyn",
    "seattle",
    "bellevue",
    "redmond",
    "austin",
    "denver",
    "boulder",
    "chicago",
    "boston",
    "cambridge",
    "los angeles",
    "la",
    "portland",
    "atlanta",
    "miami",
    "pittsburgh",
    "philadelphia",
    "washington dc",
    "raleigh",
    "durham",
    "salt lake city",
    "nashville",
    "phoenix",
    "san diego",
    "minneapolis",
    "columbus",
    "baltimore",
}


def _normalize(text: str) -> str:
    return text.lower().strip().replace(",", " ").replace(".", " ")


def _extract_state(location_text: str) -> str | None:
    """Try to extract a US state name from a location string."""
    norm = _normalize(location_text)
    # Check 2-letter abbreviations (e.g. "MI", "CA")
    for part in norm.split():
        if part in _STATE_ABBREV:
            return _STATE_ABBREV[part]
    # Check full state names
    for state in _US_STATES:
        if state in norm:
            return state
    return None


def _find_metro(city_text: str, home_state: str = "michigan") -> str | None:
    """Find which metro area a city belongs to within the home state."""
    norm = _normalize(city_text)
    if home_state.lower() == "michigan":
        for metro, cities in _MICHIGAN_METROS.items():
            for city in cities:
                if city in norm:
                    return metro
    return None


def classify_location(
    job_location: str,
    home_city: str = "Kalamazoo",
    home_state: str = "Michigan",
    is_remote: bool | None = None,
) -> int:
    """
    Classify a job's location into a tier relative to the user's home.

    Returns:
        0 = home (same metro)
        1 = nearby (same state, neighboring metro)
        2 = regional (neighboring state)
        3 = far_us (rest of US)
        4 = international
    """
    if is_remote is True:
        return 0

    norm = _normalize(job_location)

    if not norm or norm in (
        "remote",
        "remote-first",
        "anywhere",
        "worldwide",
        "global",
    ):
        return 0

    # Check if it's international first
    for signal in _INTERNATIONAL_SIGNALS:
        if signal in norm:
            return 4

    # Try to find the state
    job_state = _extract_state(norm)
    home_state_lower = home_state.lower()

    # Try to find the metro within home state
    home_metro = _find_metro(home_city, home_state_lower)
    job_metro = (
        _find_metro(norm, home_state_lower) if home_state_lower == "michigan" else None
    )

    # If we're in the same metro → home
    if job_metro and home_metro and job_metro == home_metro:
        return 0

    # If we're in a nearby metro within the same state → nearby
    if job_metro and home_metro:
        nearby_list = _MI_NEARBY.get(home_metro, [])
        if job_metro in nearby_list:
            return 1

    # If its in the home state (even if we didn't match a city) → nearby
    if job_state == home_state_lower:
        return 1

    # Neighboring states → regional
    neighbors = _NEIGHBORING_STATES.get(home_state_lower, set())
    if job_state and job_state in neighbors:
        return 2

    # If it's a US state we recognized → far_us
    if job_state:
        return 3

    # Check for known US tech hubs
    for hub in _US_TECH_HUBS:
        if hub in norm:
            return 3

    # If we can't tell, assume far US (don't over-penalize as international)
    return 3


# Tier labels for the scoring prompt
TIER_LABELS = {
    0: "home",
    1: "nearby",
    2: "regional",
    3: "far_us",
    4: "international",
}

TIER_DESCRIPTIONS = {
    0: "Your city / metro area — no location penalty",
    1: "Same state or neighboring metro (~1-2hr) — small penalty",
    2: "Neighboring state (OH, IN, WI, IL) — moderate penalty",
    3: "Other US location — full relocation penalty",
    4: "International — international penalty",
}
