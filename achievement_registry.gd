extends Node
# ================= ACHIEVEMENT REGISTRY v1.0.0 =================
# v1.0.0: Autoload singleton. Defines all achievements, tracks
#         earned state, computes bonus multipliers for production.
#         Save/load handled via SaveManager.


# ===================== ACHIEVEMENT DEFINITIONS =====================
# Each entry: { "name", "description", "bonus_type", "bonus_value", "earned" }
# bonus_type "" = no numeric bonus (unlock flag only)
# bonus_value is a multiplier factor: 1.01 = +1%, stacks multiplicatively.

const DEFINITIONS: Array = [
    {
        "key":         "persistence_is_rewarded",
        "name":        "Persistence Is Rewarded",
        "description": "You poked Kaleb until he put himself in Time Out.\n\nRepeatedly.",
        "bonus_type":  "spark_summon_mult",
        "bonus_value": 1.01,
    },
    {
        "key":         "pesteristence_is_rewarded",
        "name":        "Pesteristence Is Rewarded",
        "description": "You did it three more times.\n\nKaleb is questioning his career choices.",
        "bonus_type":  "spark_summon_mult",
        "bonus_value": 1.015,
    },
]

# Runtime earned state — key -> bool
var _earned: Dictionary = {}

func _ready() -> void:
    for def in DEFINITIONS:
        _earned[def["key"]] = false


# ===================== PUBLIC API =====================

func earn(key: String) -> void:
    if not _earned.has(key):
        push_warning("AchievementRegistry: unknown key '%s'" % key)
        return
    if _earned[key]:
        return  # Already earned, no double-grant
    _earned[key] = true


func is_earned(key: String) -> bool:
    return _earned.get(key, false)


func get_total_multiplier(bonus_type: String) -> float:
    var result: float = 1.0
    for def in DEFINITIONS:
        if def["bonus_type"] == bonus_type and _earned.get(def["key"], false):
            result *= def["bonus_value"]
    return result


func get_earned_achievements() -> Array:
    var result: Array = []
    for def in DEFINITIONS:
        if _earned.get(def["key"], false):
            result.append(def)
    return result


func get_all_achievements() -> Array:
    return DEFINITIONS.duplicate()


# ===================== SAVE / LOAD =====================

func get_save_data() -> Dictionary:
    return { "earned": _earned.duplicate() }


func _coerce_dict(val, default: Dictionary) -> Dictionary:
    if typeof(val) == TYPE_DICTIONARY:
        return val
    return default


func _coerce_bool(val, default: bool) -> bool:
    if typeof(val) == TYPE_BOOL:
        return val
    return default


func load_save_data(data: Dictionary) -> void:
    # data.has("earned") only confirms the key is present, not that the
    # value is a Dictionary — a corrupted save with a wrong-typed value
    # there would iterate fine but then hang/crash re-indexing that same
    # value with each iterated key (same class already fixed elsewhere
    # this session, e.g. game_context.gd's load_save_data()).
    var raw_earned: Dictionary = _coerce_dict(data.get("earned"), {})
    for key in raw_earned:
        if _earned.has(key):
            _earned[key] = _coerce_bool(raw_earned[key], false)
