extends Node
# =================== GAME CONTEXT v1.0.0 =================
# v1.0.0: Production logic removed — all timer callbacks and
#         batch functions now live in ProductionManager.
#         GameContext is pure state: resources, assignments,
#         locks, watermarks, rates (written by ProductionManager),
#         and save/load. No production logic here.

# ===================== CORE RESOURCES =====================
var sparks:   BigNum = BigNum.zero()
var monad:    Dictionary = {"solid": BigNum.zero(), "liquid": BigNum.zero(), "gas": BigNum.zero()}
var tetrad:   Dictionary = {
    "adaemant": BigNum.zero(), "aquae": BigNum.zero(), "aethyr": BigNum.zero(),
    "earth":    BigNum.zero(), "water": BigNum.zero(), "air":    BigNum.zero(),
    "mud":      BigNum.zero(), "dust":  BigNum.zero(), "cloud":  BigNum.zero(),
    "dirt":     BigNum.zero(), "sand":  BigNum.zero(), "haze":   BigNum.zero(),
    "mist":     BigNum.zero(), "ooze":  BigNum.zero(), "foam":   BigNum.zero(),
}
var iota:     BigNum = BigNum.zero()
var mote:     BigNum = BigNum.zero()
var particle: BigNum = BigNum.zero()
var grain:    BigNum = BigNum.zero()
var uonite:   BigNum = BigNum.zero()

var archon_foci:           int = 1
var volitions:             int = 0
var refinements_completed: int = 0
var ascensions:            int = 0
var archon_foci_spent:     int = 0
var volitions_spent:       int = 0
var archon_reward_flags:   Dictionary = {}


# ===================== HIGH WATERMARKS ====================
var watermarks: Dictionary = {
    "sparks":   BigNum.zero(),
    "monad":    BigNum.zero(),
    "tetrad":   BigNum.zero(),
    "iota":     BigNum.zero(),
    "mote":     BigNum.zero(),
    "particle": BigNum.zero(),
    "grain":    BigNum.zero(),
    "uonite":   BigNum.zero(),
}


# ===================== PER-TICK RATES =====================
# Written by ProductionManager each timer tick.
# Read by RootUI for bar display.
var rates: Dictionary = {
    "sparks_summon":     BigNum.zero(),
    "monad_compress":    BigNum.zero(),
    "tetrad_assemble":   BigNum.zero(),
    "iota_compress":     BigNum.zero(),
    "mote_assemble":     BigNum.zero(),
    "particle_compress": BigNum.zero(),
    "grain_assemble":    BigNum.zero(),
}


# ===================== ASSIGNMENTS DICT ===================
var assignments: Dictionary = {
    "sparks_summon_uonites":       BigNum.zero(),
    "sparks_summon_foci":          0,
    "sparks_summon_volitions":     0,
    "monad_compress_uonites":      BigNum.zero(),
    "monad_compress_foci":         0,
    "monad_compress_volitions":    0,
    "tetrad_assemble_uonites":     BigNum.zero(),
    "tetrad_assemble_foci":        0,
    "tetrad_assemble_volitions":   0,
    "iota_compress_uonites":       BigNum.zero(),
    "iota_compress_foci":          0,
    "iota_compress_volitions":     0,
    "mote_assemble_uonites":       BigNum.zero(),
    "mote_assemble_foci":          0,
    "mote_assemble_volitions":     0,
    "particle_compress_uonites":   BigNum.zero(),
    "particle_compress_foci":      0,
    "particle_compress_volitions": 0,
    "grain_assemble_uonites":      BigNum.zero(),
    "grain_assemble_foci":         0,
    "grain_assemble_volitions":    0,
}


# ===================== PURITY LOCKS =======================
var purity_locks_unlocked: bool = true

var locks: Dictionary = {
    "sparks":       false,
    "monad_solid":  false, "monad_liquid": false, "monad_gas": false,
    "adaemant":     false, "aquae":        false, "aethyr":    false,
    "earth":        false, "water":        false, "air":       false,
    "mud":          false, "dust":         false, "cloud":     false,
    "dirt":         false, "sand":         false, "haze":      false,
    "mist":         false, "ooze":         false, "foam":      false,
    "iota":         false,
    "mote":         false,
    "particle":     false,
    "grain":        false,
}

const TETRAD_CATEGORIES = {
    "cat_fundament": ["adaemant", "aquae", "aethyr"],
    "cat_element":   ["earth", "water", "air"],
    "cat_symmetric": ["mud", "dust", "cloud"],
    "cat_medial":    ["dirt", "sand", "haze", "mist", "ooze", "foam"],
}


# ===================== UTILITY ============================
var rng := RandomNumberGenerator.new()


# ===================== LOCK HELPERS =======================
func is_locked(key: String) -> bool:
    return locks.get(key, false)


func toggle_lock(key: String) -> void:
    if not purity_locks_unlocked:
        return
    locks[key] = not locks.get(key, false)


func toggle_category_lock(category_key: String) -> void:
    if not purity_locks_unlocked:
        return
    var keys = TETRAD_CATEGORIES.get(category_key, [])
    if keys.is_empty():
        return
    var all_locked = is_category_locked(category_key)
    for k in keys:
        locks[k] = not all_locked


func is_category_locked(category_key: String) -> bool:
    var keys = TETRAD_CATEGORIES.get(category_key, [])
    if keys.is_empty():
        return false
    for k in keys:
        if not locks.get(k, false):
            return false
    return true


# ===================== RESOURCE TOTALS ====================
func get_monad_total() -> BigNum:
    return monad["solid"].add(monad["liquid"]).add(monad["gas"])


func get_monad_unlocked_total() -> BigNum:
    var total = BigNum.zero()
    for k in ["solid", "liquid", "gas"]:
        if not is_locked("monad_" + k):
            total = total.add(monad[k])
    return total


func get_tetrad_total() -> BigNum:
    var total = BigNum.zero()
    for v in tetrad.values():
        total = total.add(v)
    return total


func get_tetrad_unlocked_total() -> BigNum:
    var total = BigNum.zero()
    for k in tetrad.keys():
        if not is_locked(k):
            total = total.add(tetrad[k])
    return total


# ===================== ASSIGNMENT TOTALS ==================
func get_total_uonites_assigned() -> BigNum:
    var total := BigNum.zero()
    for key in assignments:
        if key.ends_with("_uonites"):
            var val = assignments[key]
            if val is BigNum:
                total = total.add(val)
    return total


func get_total_foci_assigned() -> int:
    var total := 0
    for key in assignments:
        if key.ends_with("_foci"):
            total += assignments[key]
    return total


func get_total_volitions_assigned() -> int:
    var total := 0
    for key in assignments:
        if key.ends_with("_volitions"):
            total += assignments[key]
    return total


func get_operation_total(operation: String) -> int:
    var u = assignments.get(operation + "_uonites", BigNum.zero())
    var u_int = u.to_int() if u is BigNum else int(u)
    return (u_int
        + assignments.get(operation + "_foci",      0)
        + assignments.get(operation + "_volitions", 0))


func get_operation_uonites(operation: String) -> BigNum:
    var val = assignments.get(operation + "_uonites", BigNum.zero())
    if val is BigNum:
        return val
    return BigNum.from_int(int(val))


func get_operation_total_bignum(operation: String) -> BigNum:
    var u = get_operation_uonites(operation)
    var f = BigNum.from_int(assignments.get(operation + "_foci",      0))
    var v = BigNum.from_int(assignments.get(operation + "_volitions", 0))
    return u.add(f).add(v)


func get_total_assigned_bignum() -> BigNum:
    var total := BigNum.zero()
    for key in assignments:
        var val = assignments[key]
        if val is BigNum:
            total = total.add(val)
        else:
            total = total.add(BigNum.from_int(int(val)))
    return total


# ===================== SAFE SPEND HELPERS =================
func spend_sparks(amount: int) -> bool:
    var cost = BigNum.from_int(amount)
    if is_locked("sparks") or sparks.is_less_than(cost):
        return false
    sparks = sparks.sub(cost)
    return true


func spend_sparks_big(amount: BigNum) -> bool:
    if is_locked("sparks") or sparks.is_less_than(amount):
        return false
    sparks = sparks.sub(amount)
    return true


func spend_iota(amount: int) -> bool:
    var cost = BigNum.from_int(amount)
    if is_locked("iota") or iota.is_less_than(cost):
        return false
    iota = iota.sub(cost)
    return true


func spend_mote(amount: int) -> bool:
    var cost = BigNum.from_int(amount)
    if is_locked("mote") or mote.is_less_than(cost):
        return false
    mote = mote.sub(cost)
    return true


func spend_particle(amount: int) -> bool:
    var cost = BigNum.from_int(amount)
    if is_locked("particle") or particle.is_less_than(cost):
        return false
    particle = particle.sub(cost)
    return true


func spend_grain(amount: int) -> bool:
    var cost = BigNum.from_int(amount)
    if is_locked("grain") or grain.is_less_than(cost):
        return false
    grain = grain.sub(cost)
    return true


func spend_monad(solid_amt: int, liquid_amt: int, gas_amt: int) -> bool:
    var s_locked = is_locked("monad_solid")  and solid_amt  > 0
    var l_locked = is_locked("monad_liquid") and liquid_amt > 0
    var g_locked = is_locked("monad_gas")    and gas_amt    > 0
    if s_locked or l_locked or g_locked:
        return false
    var sc = BigNum.from_int(solid_amt)
    var lc = BigNum.from_int(liquid_amt)
    var gc = BigNum.from_int(gas_amt)
    if monad["solid"].is_less_than(sc) or monad["liquid"].is_less_than(lc) or monad["gas"].is_less_than(gc):
        return false
    monad["solid"]  = monad["solid"].sub(sc)
    monad["liquid"] = monad["liquid"].sub(lc)
    monad["gas"]    = monad["gas"].sub(gc)
    return true


# ===================== WATERMARKS =========================
func update_watermarks() -> void:
    var monad_total  = get_monad_total()
    var tetrad_total = get_tetrad_total()
    if sparks.is_greater_than(watermarks["sparks"]):
        watermarks["sparks"] = sparks.copy()
    if monad_total.is_greater_than(watermarks["monad"]):
        watermarks["monad"] = monad_total.copy()
    if tetrad_total.is_greater_than(watermarks["tetrad"]):
        watermarks["tetrad"] = tetrad_total.copy()
    if iota.is_greater_than(watermarks["iota"]):
        watermarks["iota"] = iota.copy()
    if mote.is_greater_than(watermarks["mote"]):
        watermarks["mote"] = mote.copy()
    if particle.is_greater_than(watermarks["particle"]):
        watermarks["particle"] = particle.copy()
    if grain.is_greater_than(watermarks["grain"]):
        watermarks["grain"] = grain.copy()
    if uonite.is_greater_than(watermarks["uonite"]):
        watermarks["uonite"] = uonite.copy()


# ===================== SAVE / LOAD ========================
func get_save_data() -> Dictionary:
    var data = {}
    data["sparks"]       = sparks.to_save_string()
    data["monad_solid"]  = monad["solid"].to_save_string()
    data["monad_liquid"] = monad["liquid"].to_save_string()
    data["monad_gas"]    = monad["gas"].to_save_string()
    for k in tetrad:
        data["tetrad_" + k] = tetrad[k].to_save_string()
    data["iota"]                  = iota.to_save_string()
    data["mote"]                  = mote.to_save_string()
    data["particle"]              = particle.to_save_string()
    data["grain"]                 = grain.to_save_string()
    data["uonite"]                = uonite.to_save_string()
    data["archon_foci"]           = archon_foci
    data["volitions"]             = volitions
    data["refinements_completed"] = refinements_completed
    data["ascensions"]            = ascensions
    var saved_assignments = {}
    for key in assignments:
        var val = assignments[key]
        if val is BigNum:
            saved_assignments[key] = "BN:" + val.to_save_string()
        else:
            saved_assignments[key] = val
    data["assignments"] = saved_assignments
    data["locks"]       = locks.duplicate()
    return data


func load_save_data(data: Dictionary) -> void:
    sparks          = BigNum.from_string(data.get("sparks",        "0:0"))
    monad["solid"]  = BigNum.from_string(data.get("monad_solid",   "0:0"))
    monad["liquid"] = BigNum.from_string(data.get("monad_liquid",  "0:0"))
    monad["gas"]    = BigNum.from_string(data.get("monad_gas",     "0:0"))
    for k in tetrad:
        tetrad[k] = BigNum.from_string(data.get("tetrad_" + k, "0:0"))
    iota     = BigNum.from_string(data.get("iota",     "0:0"))
    mote     = BigNum.from_string(data.get("mote",     "0:0"))
    particle = BigNum.from_string(data.get("particle", "0:0"))
    grain    = BigNum.from_string(data.get("grain",    "0:0"))
    uonite   = BigNum.from_string(data.get("uonite",   "0:0"))
    archon_foci           = data.get("archon_foci",           1)
    volitions             = data.get("volitions",             0)
    refinements_completed = data.get("refinements_completed", 0)
    ascensions            = data.get("ascensions",            0)
    if data.has("assignments"):
        for key in data["assignments"]:
            if assignments.has(key):
                var val = data["assignments"][key]
                if typeof(val) == TYPE_STRING and val.begins_with("BN:"):
                    assignments[key] = BigNum.from_string(val.substr(3))
                else:
                    assignments[key] = int(val)
    if data.has("locks"):
        for key in data["locks"]:
            if locks.has(key):
                locks[key] = data["locks"][key]
