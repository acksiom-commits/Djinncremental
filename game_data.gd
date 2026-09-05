extends Node
# =================== GAME DATA v0.5.0 =================
# v0.5.0: Renamed iota->particle, mote->iota, particle->mote.
# v0.4.0: format_number now accepts BigNum directly.
# Static game data autoload. Single source of truth for
# all game content definitions.
# Add to Autoloads as "GameData" ABOVE GameContext.


# ==================================================
# RESOURCE DEFINITIONS
# ==================================================
const RESOURCES = {
    "sparks":   {"name": "Sparks",    "icon": "res://icons/sparks.svg",   "color": "#ffffff"},
    "monad":    {"name": "Monad",     "icon": "res://icons/monad.svg",    "color": "#ee4444"},
    "tetrad":   {"name": "Tetrad",    "icon": "res://icons/tetrad.svg",   "color": "#ff9933"},
    "particle": {"name": "Particle",  "icon": "res://icons/particle.svg", "color": "#eecc00"},
    "iota_uonite": {"name": "Iota",   "icon": "res://icons/iota.svg",     "color": "#55ff88"},
    "mote_uonite": {"name": "Mote",   "icon": "res://icons/mote.svg",     "color": "#55aaff"},
    # Grain-branch Iota/Mote -- material-packed (real Tetrad/Particle density
    # in the cavity), not bare-Spark colonized. Reuse the Uonite-branch icons
    # for now (no distinct asset yet, no UI to show them in either -- see
    # RECIPES comment below).
    "iota_grains": {"name": "Iota",   "icon": "res://icons/iota.svg",     "color": "#55ff88"},
    "mote_grains": {"name": "Mote",   "icon": "res://icons/mote.svg",     "color": "#55aaff"},
    "grain":    {"name": "Grain",     "icon": "res://icons/grain.svg",    "color": "#9944ee"},
    "uonite":   {"name": "Uonite",    "icon": "res://icons/uonite.svg",   "color": "#ffdd55"},
# ---- Firmament Stocks ----
    "phlogiston": {"name": "Phlogiston", "icon": "res://icons/phlogiston.svg", "color": "#ff8440"},
    "clay":       {"name": "Clay",       "icon": "res://icons/clay.svg",       "color": "#cc9966"},
    "stone":      {"name": "Stone",      "icon": "res://icons/stone.svg",      "color": "#aaaaaa"},
    "ore_iron":   {"name": "Iron Ore",   "icon": "res://icons/ore_iron.svg",   "color": "#cc8866"},
    "ore_copper": {"name": "Copper Ore", "icon": "res://icons/ore_copper.svg", "color": "#dd7733"},
    "ore_silver": {"name": "Silver Ore", "icon": "res://icons/ore_silver.svg", "color": "#ddddff"},
    "oil":        {"name": "Oil",        "icon": "res://icons/oil.svg",        "color": "#446688"},
    "infusion":   {"name": "Infusion",   "icon": "res://icons/infusion.svg",   "color": "#4488cc"},
    "elixir":     {"name": "Elixir",     "icon": "res://icons/elixir.svg",     "color": "#44ccff"},
    "steam":      {"name": "Steam",      "icon": "res://icons/steam.svg",      "color": "#9977cc"},
    "smoke":      {"name": "Smoke",      "icon": "res://icons/smoke.svg",      "color": "#886699"},
    "spirit":     {"name": "Spirit",     "icon": "res://icons/spirit.svg",     "color": "#bb88ff"},
}


# ==================================================
# PRIMORDIAL BUTTON LABEL DEFINITIONS
# ==================================================
const BUTTON_LABELS = {
    "SummonSparkButton":      ["SUMMON",      "SPARK"],
    "FuseGrainButton":        ["FUSE",        "GRAINS"],
    "MonadCompressButton":    ["Compress to", "MONAD"],
    "ParticleCompressButton": ["Assemble",    "PARTICLE"],
    "IotaAssembleButton":     ["Assemble",    "IOTA"],
    "MoteCompressButton":     ["Assemble",    "MOTE"],
    "TetradAssembleButton":   ["Assemble",    "TETRAD"],
    "GrainAssembleButton":    ["Assemble",    "GRAIN"],
    "CreateUoniteButton":     ["Create",      "UONITE"],
}


# ==================================================
# TETRAD DEFINITIONS
# ==================================================
const TETRADS = {
    "adaemant": {"category": "fundament", "s": 4, "l": 0, "g": 0, "display": "Adaemant"},
    "aquae":    {"category": "fundament", "s": 0, "l": 4, "g": 0, "display": "Aquae"},
    "aethyr":   {"category": "fundament", "s": 0, "l": 0, "g": 4, "display": "Aethyr"},
    "earth":    {"category": "element",   "s": 2, "l": 1, "g": 1, "display": "Earth"},
    "water":    {"category": "element",   "s": 1, "l": 2, "g": 1, "display": "Water"},
    "air":      {"category": "element",   "s": 1, "l": 1, "g": 2, "display": "Air"},
    "mud":      {"category": "symmetric", "s": 2, "l": 2, "g": 0, "display": "Mud"},
    "dust":     {"category": "symmetric", "s": 2, "l": 0, "g": 2, "display": "Dust"},
    "cloud":    {"category": "symmetric", "s": 0, "l": 2, "g": 2, "display": "Cloud"},
    "dirt":     {"category": "medial",    "s": 3, "l": 1, "g": 0, "display": "Dirt"},
    "sand":     {"category": "medial",    "s": 3, "l": 0, "g": 1, "display": "Sand"},
    "haze":     {"category": "medial",    "s": 1, "l": 0, "g": 3, "display": "Haze"},
    "mist":     {"category": "medial",    "s": 0, "l": 1, "g": 3, "display": "Mist"},
    "ooze":     {"category": "medial",    "s": 1, "l": 3, "g": 0, "display": "Ooze"},
    "foam":     {"category": "medial",    "s": 0, "l": 3, "g": 1, "display": "Foam"},
}

const TETRAD_CATEGORIES = ["fundament", "element", "symmetric", "medial"]

const TETRAD_CATEGORY_NAMES = {
    "fundament": "Fundaments",
    "element":   "Elements",
    "symmetric": "Symmetrics",
    "medial":    "Medials",
}

const POOL_NAMES = {
    "uonites":   "Uonites",
    "foci":      "Foci",
    "volitions": "Volitions",
}


# ==================================================
# RECIPE DEFINITIONS
# ==================================================
const RECIPES = {
    "monad_compress":    {"inputs": {"sparks": 5},                                    "outputs": {"monad": 1}},
    "tetrad_assemble":   {"inputs": {"sparks": 1, "monad": 4},                        "outputs": {"tetrad": 1}},
    # Every tier from Tetrad up is 4 corners of the previous tier + its own
    # centroid Spark (Sierpinski corner+centroid assembly) -- only Monad and
    # Uonite are still pure N-of-previous-tier compression, so everything
    # else is named "_assemble", not "_compress".
    "particle_assemble": {"inputs": {"tetrad": 4, "sparks": 1},                       "outputs": {"particle": 1}},

    # ---- Uonite branch (cheap, unfilled -- bare-Spark cavity colonization
    # only, no packed material).
    #
    # iota_assemble_uonite's 11 sparks = 5 base + 6 neurology cavity-fill
    # pockets. No "monad" input -- Uonite-track Iota doesn't pack material,
    # that's specifically what distinguishes it from the Grain branch.
    # mote_assemble_uonite's 36 sparks is the 36 verified cavity-fill
    # pockets (own centroid Spark cost not separately itemized here, unlike
    # particle_assemble's explicit 1 -- flag if that's meant to be 37, not
    # 36). Every Uonite-branch Iota/Mote is colonized with its cavity-fill
    # Sparks from assembly, no separate action.
    "iota_assemble_uonite": {"inputs": {"sparks": 11, "particle": 4},                 "outputs": {"iota_uonite": 1}},
    "mote_assemble_uonite": {"inputs": {"iota_uonite": 4, "sparks": 36},              "outputs": {"mote_uonite": 1}},

    # ---- Grain branch (expensive, filled -- real Tetrad/Particle density
    # packed into the cavity, not bare Sparks). Numbers are the verified
    # octahedral cavity-packing decomposition (see
    # planned_archai_purity_tier_taxonomy.md): Iota's cavity packs down to
    # 8 real Tetrads (its 8 tetrahedra-shaped positions) + 6 residual Spark
    # pockets; Mote's packs to 8 Particles (Level-1 pieces) + 48 Tetrads
    # (Level-2, 6 octahedra x 8 each) + 36 residual Spark pockets. No UI
    # exists for this branch yet (see BUTTON_LABELS / the pending
    # Uonite<->Grain toggle) -- recipes and production logic only.
    "iota_assemble_grains": {"inputs": {"particle": 4, "tetrad": 8, "sparks": 6},      "outputs": {"iota_grains": 1}},
    "mote_assemble_grains": {"inputs": {"iota_grains": 4, "particle": 8, "tetrad": 48, "sparks": 36}, "outputs": {"mote_grains": 1}},

    # grain_assemble now draws its Mote input from the real Grain-branch
    # Mote (mote_grains) instead of the Uonite-branch one it temporarily
    # borrowed while mote_grains didn't exist yet.
    "grain_assemble":    {"inputs": {"sparks": 25, "monad": 64, "particle": 16, "mote_grains": 4}, "outputs": {"grain": 1}},
    "uonite_assemble":   {"inputs": {"mote_uonite": 20, "sparks": 1},                 "outputs": {"uonite": 1}},
}


# ==================================================
# HELPER FUNCTIONS
# ==================================================
func get_resource_color(resource_key: String) -> String:
    return RESOURCES.get(resource_key, {}).get("color", "#ffffff")

func get_resource_icon(resource_key: String) -> String:
    return RESOURCES.get(resource_key, {}).get("icon", "")

func get_resource_name(resource_key: String) -> String:
    return RESOURCES.get(resource_key, {}).get("name", resource_key)

func get_tetrads_in_category(category: String) -> Array:
    var result = []
    for key in TETRADS:
        if TETRADS[key]["category"] == category:
            result.append(key)
    return result


# ==================================================
# NUMBER FORMATTING
# ==================================================
func format_number(value, _use_engineering: bool = false) -> String:
    # Accepts BigNum or int
    if value is BigNum:
        return value.to_display_string()
    # Legacy int path
    if value is int:
        if value < 1000:
            return str(value)
        return _format_int_scientific(value)
    return str(value)


func _format_int_scientific(value: int) -> String:
    if value == 0:
        return "0"
    var exponent := 0
    var v := float(value)
    while v >= 10.0:
        v /= 10.0
        exponent += 1
    if exponent >= 1000:
        var exp_exp := 0
        var ev := float(exponent)
        while ev >= 10.0:
            ev /= 10.0
            exp_exp += 1
        return "1e1e%d" % exp_exp
    var mantissa_str = "%.1f" % v
    mantissa_str = mantissa_str.trim_suffix("0").trim_suffix(".")
    return mantissa_str + "e" + str(exponent)
