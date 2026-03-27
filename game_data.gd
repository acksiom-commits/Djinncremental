extends Node
# =================== GAME DATA v0.4.0 =================
# Static game data autoload. Single source of truth for
# all game content definitions.
# Add to Autoloads as "GameData" ABOVE GameContext.
#
# v0.4.0: format_number now accepts BigNum directly.
#         Legacy int overload retained for transition.


# ==================================================
# RESOURCE DEFINITIONS
# ==================================================
const RESOURCES = {
    "sparks":   {"name": "Sparks",    "icon": "res://icons/sparks.svg",   "color": "#ffffff"},
    "monad":    {"name": "Monad",     "icon": "res://icons/monad.svg",    "color": "#ee4444"},
    "tetrad":   {"name": "Tetrad",    "icon": "res://icons/tetrad.svg",   "color": "#ff9933"},
    "iota":     {"name": "Iota",      "icon": "res://icons/iota.svg",     "color": "#eecc00"},
    "mote":     {"name": "Mote",      "icon": "res://icons/mote.svg",     "color": "#55ff88"},
    "particle": {"name": "Particle",  "icon": "res://icons/particle.svg", "color": "#55aaff"},
    "grain":    {"name": "Grain",     "icon": "res://icons/grain.svg",    "color": "#9944ee"},
    "uonite":   {"name": "Uonite",    "icon": "res://icons/uonite.svg",   "color": "#ffdd55"},
}


# ==================================================
# BUTTON LABEL DEFINITIONS
# ==================================================
const BUTTON_LABELS = {
    "SummonSparkButton":      ["SUMMON",      "SPARK"],
    "MonadCompressButton":    ["Compress to", "MONAD"],
    "IotaCompressButton":     ["Compress to", "IOTA"],
    "ParticleCompressButton": ["Compress to", "PARTICLE"],
    "TetradAssembleButton":   ["Assemble",    "TETRAD"],
    "MoteAssembleButton":     ["Assemble",    "MOTE"],
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
    "monad_compress":    {"inputs": {"sparks": 5},                               "outputs": {"monad": 1}},
    "tetrad_assemble":   {"inputs": {"sparks": 1, "monad": 4},                   "outputs": {"tetrad": 1}},
    "iota_compress":     {"inputs": {"tetrad": 5},                               "outputs": {"iota": 1}},
    "mote_assemble":     {"inputs": {"sparks": 5, "monad": 16, "iota": 4},       "outputs": {"mote": 1}},
    "particle_compress": {"inputs": {"mote": 5},                                 "outputs": {"particle": 1}},
    "grain_assemble":    {"inputs": {"sparks": 25, "monad": 64, "iota": 16, "particle": 4}, "outputs": {"grain": 1}},
    "uonite_assemble":   {"inputs": {"grain": 20, "sparks": 1},                  "outputs": {"uonite": 1}},
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
