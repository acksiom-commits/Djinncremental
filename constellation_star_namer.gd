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


## Generates `count` unique names for one constellation. Seeded by
## constellation_id only (not player_seed) so names are consistent for
## every player who unlocks that constellation — they're lore, not
## per-playthrough puzzle state.
static func generate_names(count: int, constellation_id: int, theme: Dictionary = {}) -> Array[String]:
    var active_theme: Dictionary = theme if not theme.is_empty() else DEFAULT_THEME
    var prefixes: Array = active_theme.get("prefixes", DEFAULT_THEME["prefixes"])
    var mids: Array = active_theme.get("mids", DEFAULT_THEME["mids"])
    var suffixes: Array = active_theme.get("suffixes", DEFAULT_THEME["suffixes"])

    var rng := RandomNumberGenerator.new()
    rng.seed = constellation_id * 0x2545_F491 ^ 0x1357_9BDF

    var used: Dictionary = {}
    var names: Array[String] = []
    var attempts: int = 0
    var max_attempts: int = count * 50  # safety valve against pathologically small theme pools

    while names.size() < count and attempts < max_attempts:
        attempts += 1
        var p: String = prefixes[rng.randi_range(0, prefixes.size() - 1)]
        var m: String = mids[rng.randi_range(0, mids.size() - 1)]
        var s: String = suffixes[rng.randi_range(0, suffixes.size() - 1)]
        var candidate: String = p + m + s
        if not used.has(candidate):
            used[candidate] = true
            names.append(candidate)

    # Fallback if the theme pool was too small to produce enough unique
    # combinations (shouldn't happen with default theme sizes, but guards
    # small custom/patron-submitted themes).
    var fallback_idx: int = 1
    while names.size() < count:
        names.append("Star-%d" % fallback_idx)
        fallback_idx += 1

    return names
