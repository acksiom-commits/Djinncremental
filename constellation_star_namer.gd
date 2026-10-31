class_name ConstellationStarNamer
extends RefCounted
# ================= CONSTELLATION STAR NAMER v1.0.0 =================
# Procedurally generates Greek-rooted star names, seeded per constellation
# so the NAME POOL is stable across sessions for the same constellation_id
# (NOT per-player — these are flavor/lore names, the same set for every
# player). WHICH star gets WHICH name from that pool is a separate decision:
# constellation_logic_puzzle.gd's setup() shuffles the array this function
# returns with the player-seeded RNG (_shuffle_star_names_for_player())
# immediately after calling this, the same way colors are shuffled. Do not
# add player-seeding here — that shuffle step is where it belongs.
#
# Each constellation can supply its own theme (prefix/mid/suffix pools)
# via constellation_data.gd's optional "name_theme" field:
#   "name_theme": {
#       "prefixes": ["Kal", "Arch", ...],
#       "mids": ["o", "a", ...],
#       "suffixes": ["on", "eus", ...],
#   }
# If a constellation has no "name_theme" field, DEFAULT_THEME is used.
# ========================================================================


const DEFAULT_THEME := {
    "prefixes": ["Ast", "Pyr", "Hel", "Sel", "Ther", "Aether", "Chron",
                 "Eos", "Nyx", "Phos", "Ker", "Or", "Thal", "Mnem"],
    "mids":     ["o", "a", "i", "ae", "y", "e"],
    "suffixes": ["on", "os", "ion", "ai", "eus", "ara", "is", "eia", "ides"],
}

## Any two names in one puzzle differ by at least this many letters (edits).
## See generate_names: names the player can mistake for each other make wrong
## entries, not harder puzzles.
const MIN_NAME_DISTANCE := 3


## theme is a raw def field on player/patron constellations (save-derived).
## A wrong-typed "prefixes"/"mids"/"suffixes" value — or one of those
## present but empty — doesn't hang the engine (a local typed-var mismatch
## aborts just the current function, confirmed this session, unlike the
## same mismatch at a parameter or return boundary), but it DOES silently
## return an empty Array[String] to the caller, leaving star_names shorter
## than star_count with no error raised anywhere. Coerce the pool itself
## (falling back to the matching DEFAULT_THEME pool for a wrong type or an
## empty array — an empty pool would make every randi_range(0, -1) below
## resolve to index 0 on an out-of-bounds read) and every element via
## str() (always safe, matches the pattern used throughout this session).
static func _coerce_theme_pool(val, default: Array) -> Array:
    if typeof(val) != TYPE_ARRAY or val.is_empty():
        return default
    var result: Array = []
    for v in val:
        result.append(str(v))
    return result


## Levenshtein distance, case-insensitive.
static func _edit_distance(a: String, b: String) -> int:
    var la: String = a.to_lower()
    var lb: String = b.to_lower()
    var prev: Array[int] = []
    for j in lb.length() + 1:
        prev.append(j)
    for i in range(1, la.length() + 1):
        var cur: Array[int] = [i]
        for j in range(1, lb.length() + 1):
            var cost: int = 0 if la[i - 1] == lb[j - 1] else 1
            cur.append(mini(mini(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost))
        prev = cur
    return prev[lb.length()]


static func _too_close_to_any(candidate: String, names: Array[String]) -> bool:
    for n in names:
        if _edit_distance(candidate, n) < MIN_NAME_DISTANCE:
            return true
    return false


## Generates `count` unique names for one constellation. Seeded by
## constellation_id only (not player_seed) so names are consistent for
## every player who unlocks that constellation — they're lore, not
## per-playthrough puzzle state.
##
## NO TWO NAMES EASY TO MISTAKE FOR EACH OTHER (author, 2026-10-31). Reported
## on The Phial: a note was entered as Keraeara where the clue said Keryara,
## next to each other in the alphabetical popup list, and that was the board's
## only contradiction. So a candidate is taken only if:
##   - its prefix is among the least used so far. Every prefix goes round once
##     before any repeats, which only happens on boards with more stars than
##     the theme has prefixes (15-18 star Hard layouts, with 14 prefixes);
##   - it is at least MIN_NAME_DISTANCE edits from every name already taken.
## Both are needed: the distance alone passes Theraion/Theryis, the prefix
## alone passes Helios/Selion. Skipping a candidate keeps the same RNG walk, so
## a smaller board's names stay the first names of the larger board's.
##
## A theme too small to satisfy this (a patron's three-prefix pool) loses the
## rule rather than a name: `loose_left` falls back to plain uniqueness.
##
## A puzzle already cached keeps its names until it is reset; deliberately no
## CACHE_VERSION bump, which would throw away every board in progress.
static func generate_names(count: int, constellation_id: int, theme: Dictionary = {}) -> Array[String]:
    var active_theme: Dictionary = theme if not theme.is_empty() else DEFAULT_THEME
    var prefixes: Array = _coerce_theme_pool(active_theme.get("prefixes"), DEFAULT_THEME["prefixes"])
    var mids: Array = _coerce_theme_pool(active_theme.get("mids"), DEFAULT_THEME["mids"])
    var suffixes: Array = _coerce_theme_pool(active_theme.get("suffixes"), DEFAULT_THEME["suffixes"])

    var rng := RandomNumberGenerator.new()
    rng.seed = constellation_id * 0x2545_F491 ^ 0x1357_9BDF

    var used: Dictionary = {}
    var names: Array[String] = []
    var prefix_uses: Dictionary = {}
    for p0 in prefixes:
        prefix_uses[p0] = 0
    var fewest_uses: int = 0
    # Late draws are mostly rejected (one free prefix in fourteen), hence the
    # larger budget. Both are safety valves against pathologically small pools.
    var strict_left: int = count * 500
    var loose_left: int = count * 50

    while names.size() < count and (strict_left > 0 or loose_left > 0):
        var strict: bool = strict_left > 0
        if strict:
            strict_left -= 1
        else:
            loose_left -= 1
        var p: String = prefixes[rng.randi_range(0, prefixes.size() - 1)]
        var m: String = mids[rng.randi_range(0, mids.size() - 1)]
        var s: String = suffixes[rng.randi_range(0, suffixes.size() - 1)]
        var candidate: String = p + m + s
        if used.has(candidate):
            continue
        if strict and (int(prefix_uses[p]) > fewest_uses or _too_close_to_any(candidate, names)):
            continue
        used[candidate] = true
        names.append(candidate)
        prefix_uses[p] = int(prefix_uses[p]) + 1
        fewest_uses = int(prefix_uses.values().min())

    # Fallback if the theme pool was too small to produce enough unique
    # combinations (shouldn't happen with default theme sizes, but guards
    # small custom/patron-submitted themes).
    var fallback_idx: int = 1
    while names.size() < count:
        names.append("Star-%d" % fallback_idx)
        fallback_idx += 1

    return names
