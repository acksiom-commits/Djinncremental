extends Node
# =================== GAME CONTEXT v1.2.0 =================
# v1.2.0: Added ui_unlocks dictionary for progressive UI reveal.
#         Eight bool flags track which panels have been revealed.
#         Saved/loaded alongside all other game state.
# v1.1.0: Added constellation spark allocation state.
# v1.0.0: Production logic removed. Pure state node.



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
var particle: BigNum = BigNum.zero()
var iota:     BigNum = BigNum.zero()
var mote:     BigNum = BigNum.zero()
var grain:    BigNum = BigNum.zero()
var uonite:   BigNum = BigNum.zero()

var uonite_name: String = ""

# ===================== FIRMAMENT STOCKS =======================
var solid_stocks: Dictionary = {
    "clay":       BigNum.zero(),
    "stone":      BigNum.zero(),
    "ore_iron":   BigNum.zero(),
    "ore_copper": BigNum.zero(),
    "ore_silver": BigNum.zero(),
}
var liquid_stocks: Dictionary = {
    "oil":      BigNum.zero(),
    "infusion": BigNum.zero(),
    "elixir":   BigNum.zero(),
}
var gas_stocks: Dictionary = {
    "steam":  BigNum.zero(),
    "smoke":  BigNum.zero(),
    "spirit": BigNum.zero(),
}

# ===================== TRANSMUTATION ==========================
var phlogiston:   BigNum = BigNum.zero()
var quintessence: BigNum = BigNum.zero()


# ===================== GRAIN PURITY PROFILE ==================
# EMA of Tetrad category fractions at the moment each Manifold tick fires.
# Drives output-tier selection in _manifold_output_key().
# All four values sum to ≈ 1.0 once any Tetrads exist.
var grain_purity_profile: Dictionary = {
    "fundament": 0.0,
    "element":   0.0,
    "symmetric": 0.0,
    "medial":    0.0,
}

# ===================== MANIFOLD STATE ========================
# How many Grain-flow units each station receives per TIMER_MANIFOLD tick.
# Each flow unit consumes 1 Grain → yields material + Phlogiston waste.
var manifold_allocations: Dictionary = {
    "calcination": 0,
    "sublimation": 0,
    "dissolution": 0,
}
# Total budget. Grows with Atelier upgrades. Starts at 0 (manifold dormant).
var manifold_total_flows: int = 0

# Which operation currently receives the Hourglass bonus. "" = idle/dormant.
var hourglass_target_ops: Array[String] = []



# ===================== STORAGE CAP =======================
var storage_cap: BigNum = BigNum.from_int(987)
var storage_cap_at_prestige_start: BigNum = BigNum.from_int(987)

var _archon_foci_value: int = 0
var archon_foci: int:
    get:
        return _archon_foci_value
    set(value):
        _archon_foci_value = value
        emit_signal("archon_foci_changed", value)

var volitions:             int = 0
var refinements_completed: int = 0
var expansions:            int = 0
var archon_foci_spent:     int = 0
var volitions_spent:       int = 0
var _last_bonus_volition_grant: int = 0
var grains_this_cycle:     int = 0
var motes_this_cycle:      int = 0   # TEST: mirrors grains_this_cycle, drives Uonite gauge for grains-out experiment
var uonites_this_cycle:    int = 0
var archon_reward_flags:   Dictionary = {}

# ===================== VOLITION SLOTS ====================
# Source of truth for all Volition assignments (Parent + Bonus Children).
# Each slot = one Normal (Parent) Volition. Children = Bonus Volitions
# granted by the Archon constellation tier. Count = get_bonus_volitions_per_slot().
# _rebuild_volition_assignments() syncs the flat assignments dict from this.
const AUTO_FOLLOW_CATEGORIES: Array[String] = ["stoctagon", "volumitions"]
var volition_slots: Array = []
var _batch_volition_update: bool = false


# ===================== ARCHON POKE STATE ==================
var archon_poke_count:          int   = 0
var archon_lockdown_level:      int   = 0
var archon_lockdown_end_time:   float = 0.0
var archon_warning_window_end:  float = 0.0
var archon_reentry_threshold:   int   = 0


# ===================== HIGH WATERMARKS ====================
var watermarks: Dictionary = {
    "sparks":       BigNum.zero(),
    "monad":        BigNum.zero(),
    "monad_solid":  BigNum.zero(),
    "monad_liquid": BigNum.zero(),
    "monad_gas":    BigNum.zero(),
    "tetrad":       BigNum.zero(),
    "particle":     BigNum.zero(),
    "iota":         BigNum.zero(),
    "mote":         BigNum.zero(),
    "grain":        BigNum.zero(),
    "uonite":       BigNum.zero(),
}

# 
var next_expansion_foci_exp: int = 0   # next power: 10^0=1, 10^2=100, 10^4=10000...

# Geometric milestone tracking — next threshold index per resource type
# Index 1 = 5th, 2 = 25th, 3 = 125th, etc. First creation handled separately.
var tetrad_milestones: Dictionary = {}  # variety_key -> next_power_index
var monad_milestones:  Dictionary = {}  # type_key    -> next_power_index

# Lifetime totals — never reset on prestige
var totals_created: Dictionary = {
    "monad_solid": BigNum.zero(), "monad_liquid": BigNum.zero(), "monad_gas": BigNum.zero(),
    "adaemant": BigNum.zero(), "aquae":    BigNum.zero(), "aethyr": BigNum.zero(),
    "earth":    BigNum.zero(), "water":    BigNum.zero(), "air":    BigNum.zero(),
    "mud":      BigNum.zero(), "dust":     BigNum.zero(), "cloud":  BigNum.zero(),
    "dirt":     BigNum.zero(), "sand":     BigNum.zero(), "haze":   BigNum.zero(),
    "mist":     BigNum.zero(), "ooze":     BigNum.zero(), "foam":   BigNum.zero(),
    "particle": BigNum.zero(), "iota":     BigNum.zero(), "mote":   BigNum.zero(),
    "grain":    BigNum.zero(), "uonite":   BigNum.zero(),
    "sparks_summoned": BigNum.zero(),
}

# Next power-of-1000 exponent index to check per key (1 = 1K, 2 = 1M, 3 = 1B...)
var totals_milestones: Dictionary = {}


# ===================== PER-TICK RATES =====================
var rates: Dictionary = {
    "sparks_summon":     BigNum.zero(),
    "monad_compress":    BigNum.zero(),
    "tetrad_assemble":   BigNum.zero(),
    "particle_compress": BigNum.zero(),
    "iota_assemble":     BigNum.zero(),
    "mote_compress":     BigNum.zero(),
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
    "particle_compress_uonites":   BigNum.zero(),
    "particle_compress_foci":      0,
    "particle_compress_volitions": 0,
    "iota_assemble_uonites":       BigNum.zero(),
    "iota_assemble_foci":          0,
    "iota_assemble_volitions":     0,
    "mote_compress_uonites":       BigNum.zero(),
    "mote_compress_foci":          0,
    "mote_compress_volitions":     0,
    "grain_assemble_uonites":      BigNum.zero(),
    "grain_assemble_foci":         0,
    "grain_assemble_volitions":    0,
    # Constellation Foci/Volitions
    "constellation_2_foci":        0,
    "constellation_2_volitions":   0,
    # Constellation Solution Tracking
    "constellation_2_solve_count": 0,
    "constellation_2_feed_mode":   0,   # 0=off 1=on
    # Storage Consumption Volition Toggle
    "storage_overflow_volitions":  0,
    # Click Multiplier Volitions
    "click_volitions":             0,
}


# ===================== CONSTELLATION SPARK TOTALS =========
var constellation_spark_totals: Dictionary = {
    "8": 0.0,
}


# ===================== UI UNLOCKS =========================
# Progressive UI reveal flags. Set true when panel is first shown.
# Saved/loaded so UI state persists across sessions.
var ui_unlocks: Dictionary = {
    "monad_panel":      false,  # CompressPanelContainer
    "direct_readouts":  false,  # DirectReadoutsPanelContainer
    "allocation_wheel": false,  # AllocationWheelControl
    "wheel_full_access": false, # All wheel slots usable (post all-monads)
    "tetrad_panel":     false,  # AssembleTetradVBox
    "resource_bars":    false,  # BarsVBox gen bars
    "genbars":          false,  # GenBarsVBox (alias revealed with first particle)
    "particle":         false,  # ParticleIotaMoteGrainVBox
    "stoctagon":        false,  # Storage display
    "volumition":       false,  # ClickVolAssistVBox
    "uonite_creation":  false,  # CreateUoniteButton + icosahedron
    "uonite_button":    false,
    "uonite_cooldown":  false,
    "constellation":    false,  # ConstellationPanel — post-prestige
    # Firmament age panels
    "manifold":         false,
    "atelier_carousel": false,
    "firmament_viewer": false,
}


# ===================== TRIGGER COUNTERS =========================
var sparks_since_first_prestige: float = 0.0
var hint_bias_enabled: bool = false


# ===================== PURITY LOCKS =======================
var purity_locks_unlocked: bool = false

var locks: Dictionary = {
    "monad_solid":   false, "monad_liquid":  false, "monad_gas":     false,
    # Tetrad varieties (individual locks — 1 Volition each)
    "adaemant":      false, "aquae":         false, "aethyr":        false,
    "earth":        false, "water":         false, "air":           false,
    "mud":          false, "dust":          false, "cloud":         false,
    "dirt":         false, "sand":          false, "haze":          false,
    "mist":         false, "ooze":          false, "foam":          false,
    # Tetrad category locks (1 Volition each, covers all varieties in that category)
    "cat_fundament": false, "cat_element":   false,
    "cat_symmetric": false, "cat_medial":    false,
    # Chain resources (1 Volition each)
    "particle":      false,
    "iota":          false,
    "mote":          false,
    "grain":         false,
    "uonite":        false,
}

const TETRAD_CATEGORIES = {
    "cat_fundament": ["adaemant", "aquae", "aethyr"],
    "cat_element":   ["earth", "water", "air"],
    "cat_symmetric": ["mud", "dust", "cloud"],
    "cat_medial":    ["dirt", "sand", "haze", "mist", "ooze", "foam"],
}


# ===================== UTILITY ============================
var rng := RandomNumberGenerator.new()

signal archon_foci_changed(new_value: int)
signal lock_state_changed(key: String, locked: bool)
signal volition_slots_changed()


# ===================== CREATION ORDER TRACKING ===========
# Records the order in which Monad types and Tetrad varieties
# were first created. Counter increments globally across both.
# e.g. creation_order = {"solid": 1, "earth": 2, "liquid": 3, ...}
var creation_counter: int = 0
var creation_order: Dictionary = {}

func record_first_creation(key: String) -> void:
    if creation_order.has(key):
        return
    creation_counter += 1
    creation_order[key] = creation_counter


func add_to_total(key: String, amount: BigNum) -> void:
    if totals_created.has(key):
        totals_created[key] = totals_created[key].add(amount)


# ===================== LOCK HELPERS =======================
func is_locked(key: String) -> bool:
    if locks.get(key, false):
        return true
    # Tetrad variety: protected if its parent category is locked
    for cat_key in TETRAD_CATEGORIES:
        if key in TETRAD_CATEGORIES[cat_key]:
            if locks.get(cat_key, false):
                return true
    return false


func toggle_lock(key: String) -> void:
    if not purity_locks_unlocked:
        return
    if locks.get(key, false):
        # Unlock: child first, then parent (unassign clears locks dict via cascade)
        if not unassign_last_child_with_target("purity_lock", key):
            var idx = get_first_parent_index_with_target("purity_lock", key)
            if idx >= 0:
                unassign_parent_volition(idx)
            else:
                # Orphaned lock from old save — clear directly
                locks[key] = false
                emit_signal("lock_state_changed", key, false)
    else:
        # Lock: parent first, then child
        var idx = get_first_free_parent_index()
        if idx >= 0:
            assign_parent_volition(idx, "purity_lock", key)
        elif assign_next_child_in_category("purity_lock", key):
            pass
        else:
            return  # No volitions available
        locks[key] = true
        emit_signal("lock_state_changed", key, true)


func toggle_category_lock(category_key: String) -> void:
    if not purity_locks_unlocked:
        return
    if locks.get(category_key, false):
        # Unlock category: child first, then parent (cascade clears locks dict)
        if not unassign_last_child_with_target("purity_lock", category_key):
            var idx = get_first_parent_index_with_target("purity_lock", category_key)
            if idx >= 0:
                unassign_parent_volition(idx)
            else:
                # Orphaned lock from old save — clear directly
                locks[category_key] = false
                emit_signal("lock_state_changed", category_key, false)
    else:
        # Clear individual variety locks first — refunds their volitions
        var cat_keys = TETRAD_CATEGORIES.get(category_key, [])
        for k in cat_keys:
            if locks.get(k, false):
                toggle_lock(k)
        # Now assign the category lock
        var idx = get_first_free_parent_index()
        if idx >= 0:
            assign_parent_volition(idx, "purity_lock", category_key)
        elif assign_next_child_in_category("purity_lock", category_key):
            pass
        else:
            return  # No volitions available
        locks[category_key] = true
        emit_signal("lock_state_changed", category_key, true)


func is_category_locked(category_key: String) -> bool:
    return locks.get(category_key, false)


# Count of active lock entries — each consumes 1 Volition from the pool.
# Category locks and variety locks are each their own entry; double-protection
# can't occur in normal play because toggle_category_lock clears variety locks.
func get_locks_volition_cost() -> int:
    var count := 0
    for key in locks:
        if locks[key]:
            count += 1
    return count


# Volitions not committed to assignments. Purity locks now consume slots
# like any other category, so no separate lock cost subtraction.
func get_volitions_free() -> int:
    return volitions - get_total_volitions_assigned()


# True when at least one Volition (parent or child) is available for a new lock.
func can_lock_one_more() -> bool:
    if get_volitions_free() > 0:
        return true
    return get_total_free_children_in_category("purity_lock") > 0


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


# ===================== STORAGE HELPERS ===================
func get_storage_total() -> BigNum:
    var total = BigNum.zero()
    total = total.add(get_monad_total())
    total = total.add(get_tetrad_total())
    total = total.add(particle)
    total = total.add(iota)
    total = total.add(mote)
    total = total.add(grain)
    total = total.add(uonite)
    return total


func get_storage_fill_fraction() -> float:
    var cap = get_effective_storage_cap()
    if cap.is_zero():
        return 0.0
    var total = get_storage_total()
    return clamp(total.to_float() / cap.to_float(), 0.0, 1.0)


func get_resource_storage_fraction(resource_key: String) -> float:
    var total = get_storage_total()
    if total.is_zero():
        return 0.0
    var resource_val: BigNum
    match resource_key:
        "monad":    resource_val = get_monad_total()
        "tetrad":   resource_val = get_tetrad_total()
        "particle": resource_val = particle
        "iota":     resource_val = iota
        "mote":     resource_val = mote
        "grain":    resource_val = grain
        "uonite":   resource_val = uonite
        _:          return 0.0
    return clamp(resource_val.to_float() / total.to_float(), 0.0, 1.0)


func get_resource(key: String) -> BigNum:
    # Generic string-keyed resource read, added to let recipe-cost checking
    # (see ProductionManager._op_has_inputs) read off GameData.RECIPES
    # instead of re-hardcoding amounts. "monad"/"tetrad" return the
    # UNLOCKED aggregate total — matches exactly what _op_has_inputs already
    # checked via get_monad_unlocked_total()/get_tetrad_unlocked_total()
    # before this existed; there's no single scalar for a multi-subtype
    # pool otherwise.
    match key:
        "sparks":       return sparks
        "particle":     return particle
        "iota":         return iota
        "mote":         return mote
        "grain":        return grain
        "uonite":       return uonite
        "phlogiston":   return phlogiston
        "quintessence": return quintessence
        "monad":        return get_monad_unlocked_total()
        "tetrad":       return get_tetrad_unlocked_total()
        _:
            if solid_stocks.has(key):
                return solid_stocks[key]
            if liquid_stocks.has(key):
                return liquid_stocks[key]
            if gas_stocks.has(key):
                return gas_stocks[key]
            push_warning("GameContext.get_resource: unknown key " + key)
            return BigNum.zero()


func set_resource(key: String, value: BigNum) -> void:
    # Mirror of get_resource(), used only by load_save_data()'s generic
    # flat-resource restore loop. Deliberately does NOT support "monad"/
    # "tetrad" (multi-subtype, no single value to restore into) — those
    # keep their existing per-subtype load code untouched.
    match key:
        "sparks":       sparks = value
        "particle":     particle = value
        "iota":         iota = value
        "mote":         mote = value
        "grain":        grain = value
        "uonite":       uonite = value
        "phlogiston":   phlogiston = value
        "quintessence": quintessence = value
        _:
            if solid_stocks.has(key):
                solid_stocks[key] = value
            elif liquid_stocks.has(key):
                liquid_stocks[key] = value
            elif gas_stocks.has(key):
                gas_stocks[key] = value
            else:
                push_warning("GameContext.set_resource: unknown key " + key)


func expand_storage_cap(remaining_sparks: BigNum) -> BigNum:
    var l: float     = remaining_sparks.to_float()
    var s: float     = storage_cap_at_prestige_start.to_float()
    if s <= 0.0:
        return BigNum.zero()
    var l_eff: float = l / (1.0 + l / s)
    var ceiling: float = 0.05
    if has_storage_enhancer():
        ceiling = 0.15
    var b: float     = ceiling * (1.0 - exp(-5.0 * l_eff / s))
    var old_cap      := storage_cap.copy()
    storage_cap      = BigNum.from_int(storage_cap.mul_float(1.0 + b).to_int())
    return storage_cap.sub(old_cap)


func has_storage_enhancer() -> bool:
    # Satchel constellation (id 3), Tier 3 (full Spark investment) only.
    # Trinary gate: solved AND volition-assigned AND visual_state == "art".
    # Raises expand_storage_cap's asymptotic ceiling from 5% to 15%.
    const SATCHEL_ID: int = 3
    var cd = get_node_or_null("/root/ConstellationData")
    if not cd:
        return false
    var solve_key: String = "constellation_%d_solve_count" % SATCHEL_ID
    if assignments.get(solve_key, 0) < 1:
        return false
    if not has_volition_for_constellation(SATCHEL_ID):
        return false
    if cd.has_method("get_visual_state"):
        return cd.get_visual_state(SATCHEL_ID) == "art"
    return false


func get_effective_storage_cap() -> BigNum:
    # Applies the Satchel's storage_multiplier bonus (live, tier-reversible)
    # on top of the stored base storage_cap. This is the value all gameplay
    # logic (overflow gating, headroom, display) should read — never read
    # storage_cap directly except inside expand_storage_cap() itself, which
    # intentionally operates on the permanent base value.
    var cd = get_node_or_null("/root/ConstellationData")
    var mult: float = 1.0
    if cd and cd.has_method("get_active_level_bonus"):
        mult = cd.get_active_level_bonus("storage_multiplier")
    var raw: BigNum = storage_cap.mul_float(mult)
    return BigNum.from_int(raw.to_int())


# ===================== ASSIGNMENT TOTALS ==================
func get_total_uonites_assigned() -> BigNum:
    var total := BigNum.zero()
    for key in assignments:
        if key.ends_with("_uonites"):
            var val = assignments[key]
            if val is BigNum:
                total = total.add(val)
    return total

    
func get_uonite_cycle_cap() -> int:
    var a := 1
    var b := 2
    for i in expansions:
        var c := a + b
        a = b
        b = c
    return a


func get_total_foci_assigned() -> int:
    var total := 0
    for key in assignments:
        if key.ends_with("_foci"):
            total += assignments[key]
    return total


func get_total_volitions_assigned() -> int:
    var total := 0
    for slot in volition_slots:
        if slot["category"] != "":
            total += 1
    return total


func is_storage_overflow_active() -> bool:
    return assignments.get("storage_overflow_volitions", 0) > 0


func get_operation_total(operation: String) -> int:
    var u = assignments.get(operation + "_uonites", BigNum.zero())
    var u_int = u.to_int() if u is BigNum else int(u)
    return (u_int
        + assignments.get(operation + "_foci",            0)
        + assignments.get(operation + "_volitions",       0)
        + assignments.get(operation + "_bonus_volitions", 0))


func get_operation_uonites(operation: String) -> BigNum:
    var val = assignments.get(operation + "_uonites", BigNum.zero())
    if val is BigNum:
        return val
    return BigNum.from_int(int(val))


func get_operation_total_bignum(operation: String) -> BigNum:
    var u = get_operation_uonites(operation)
    var f  = BigNum.from_int(assignments.get(operation + "_foci",            0))
    var v  = BigNum.from_int(assignments.get(operation + "_volitions",       0))
    var bv = BigNum.from_int(assignments.get(operation + "_bonus_volitions", 0))
    return u.add(f).add(v).add(bv)


func get_total_assigned_bignum() -> BigNum:
    var total := BigNum.zero()
    for key in assignments:
        var val = assignments[key]
        if val is BigNum:
            total = total.add(val)
        else:
            total = total.add(BigNum.from_int(int(val)))
    return total


# ===================== CONSTELLATION HELPERS ==============
func get_constellation_points(constellation_id: int) -> int:
    var id_str = str(constellation_id)
    return assignments.get("constellation_" + id_str + "_foci",            0) \
         + assignments.get("constellation_" + id_str + "_volitions",       0) \
         + assignments.get("constellation_" + id_str + "_bonus_volitions", 0)


func get_total_constellation_points() -> int:
    var total := 0
    for key in constellation_spark_totals:
        total += get_constellation_points(int(key))
    return total


# ===================== VOLITION SLOTS API ====================
# volition_slots is the source of truth for all Volition assignments.
# _rebuild_volition_assignments() syncs the flat assignments dict keys
# (_volitions / _bonus_volitions) so existing readers work unchanged.
# Categories: "constellation", "allocation_wheel", "volumitions",
#             "purity_lock", "stoctagon"


func _make_empty_slot() -> Dictionary:
    return { "category": "", "target": "", "children": [] }


func _make_empty_child() -> Dictionary:
    return { "category": "", "target": "" }


func _ensure_slot_count(count: int) -> void:
    while volition_slots.size() < count:
        volition_slots.append(_make_empty_slot())
    while volition_slots.size() > count:
        # Trim from the end; unassign first to keep flat keys clean
        var idx = volition_slots.size() - 1
        if volition_slots[idx]["category"] != "":
            unassign_parent_volition(idx)
        volition_slots.pop_back()
    sync_bonus_children_count()


func sync_bonus_children_count() -> void:
    if _batch_volition_update:
        return
    var per_slot: int = get_bonus_volitions_per_slot()
    for slot in volition_slots:
        var children: Array = slot["children"]
        # Shrink: unassign from the end
        while children.size() > per_slot:
            children.pop_back()
        # Grow: add empty children
        while children.size() < per_slot:
            # Auto-follow: new children inherit parent for stoctagon/volumitions
            if slot["category"] in AUTO_FOLLOW_CATEGORIES:
                children.append({"category": slot["category"], "target": slot["target"]})
            else:
                children.append(_make_empty_child())
    _rebuild_volition_assignments()


func begin_batch_volition_update() -> void:
    _batch_volition_update = true


func end_batch_volition_update() -> void:
    _batch_volition_update = false
    sync_bonus_children_count()
    emit_signal("volition_slots_changed")


func assign_parent_volition(slot_index: int, category: String, target) -> void:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return
    var slot: Dictionary = volition_slots[slot_index]
    # Unassign first if already assigned elsewhere
    if slot["category"] != "":
        unassign_parent_volition(slot_index)
    slot["category"] = category
    slot["target"] = target
    # Auto-follow categories: all children get same assignment
    if category in AUTO_FOLLOW_CATEGORIES:
        for child in slot["children"]:
            child["category"] = category
            child["target"] = target
    if not _batch_volition_update:
        sync_bonus_children_count()
    emit_signal("volition_slots_changed")


func unassign_parent_volition(slot_index: int) -> void:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return
    var slot: Dictionary = volition_slots[slot_index]
    # Purity lock cascade: clear lock entries for parent and all children
    if slot["category"] == "purity_lock":
        if slot["target"] != "":
            locks[slot["target"]] = false
            emit_signal("lock_state_changed", str(slot["target"]), false)
        for child in slot["children"]:
            if child["category"] == "purity_lock" and child["target"] != "":
                locks[child["target"]] = false
                emit_signal("lock_state_changed", str(child["target"]), false)
    slot["category"] = ""
    slot["target"] = ""
    for child in slot["children"]:
        child["category"] = ""
        child["target"] = ""
    if not _batch_volition_update:
        sync_bonus_children_count()
    emit_signal("volition_slots_changed")



func assign_child_volition(slot_index: int, child_index: int, target) -> void:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return
    var slot: Dictionary = volition_slots[slot_index]
    # Can't independently assign children for unassigned or auto-follow parents
    if slot["category"] == "" or slot["category"] in AUTO_FOLLOW_CATEGORIES:
        return
    var children: Array = slot["children"]
    if child_index < 0 or child_index >= children.size():
        return
    children[child_index]["category"] = slot["category"]
    children[child_index]["target"] = target
    _rebuild_volition_assignments()
    emit_signal("volition_slots_changed")


func unassign_child_volition(slot_index: int, child_index: int) -> void:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return
    var slot: Dictionary = volition_slots[slot_index]
    if slot["category"] in AUTO_FOLLOW_CATEGORIES:
        return  # Can't independently unassign auto-follow children
    var children: Array = slot["children"]
    if child_index < 0 or child_index >= children.size():
        return
    # Purity lock: clear the lock entry for this child's target
    var child: Dictionary = children[child_index]
    if child["category"] == "purity_lock" and child["target"] != "":
        locks[child["target"]] = false
        emit_signal("lock_state_changed", str(child["target"]), false)
    child["category"] = ""
    child["target"] = ""
    _rebuild_volition_assignments()
    emit_signal("volition_slots_changed")


# --- Convenience: assign next available child in a category (left-to-right) ---

func assign_next_child_in_category(category: String, target) -> bool:
    # Finds the first slot in the given category with a free child,
    # assigns that child. Returns true if successful.
    for i in volition_slots.size():
        var slot: Dictionary = volition_slots[i]
        if slot["category"] != category:
            continue
        for ci in slot["children"].size():
            if slot["children"][ci]["category"] == "":
                assign_child_volition(i, ci, target)
                return true
    return false


func unassign_last_child_with_target(category: String, target) -> bool:
    # Finds the last child assigned to the given category+target
    # (right-to-left, last slot first) and unassigns it.
    # Returns true if successful.
    for i in range(volition_slots.size() - 1, -1, -1):
        var slot: Dictionary = volition_slots[i]
        if slot["category"] != category:
            continue
        for ci in range(slot["children"].size() - 1, -1, -1):
            var child: Dictionary = slot["children"][ci]
            if child["category"] == category and child["target"] == target:
                unassign_child_volition(i, ci)
                return true
    return false


# --- Rebuild flat assignment keys from slots ---

func _rebuild_volition_assignments() -> void:
    # Zero all existing _volitions and _bonus_volitions keys
    for key in assignments:
        if key.ends_with("_volitions"):
            assignments[key] = 0
    # Rebuild from slots
    for slot in volition_slots:
        var cat: String = slot["category"]
        if cat == "":
            continue
        var parent_key: String = _volition_assignment_key(cat, slot["target"])
        if parent_key != "":
            assignments[parent_key] = assignments.get(parent_key, 0) + 1
        for child in slot["children"]:
            if child["category"] == "":
                continue
            var child_key: String = _bonus_volition_assignment_key(
                child["category"], child["target"])
            if child_key != "":
                assignments[child_key] = assignments.get(child_key, 0) + 1


func _volition_assignment_key(category: String, target) -> String:
    match category:
        "constellation":    return "constellation_%d_volitions" % int(target)
        "allocation_wheel": return str(target) + "_volitions"
        "volumitions":      return "click_volitions"
        "stoctagon":        return "storage_overflow_volitions"
        "purity_lock":      return ""  # not yet migrated to slots
    return ""


func _bonus_volition_assignment_key(category: String, target) -> String:
    match category:
        "constellation":    return "constellation_%d_bonus_volitions" % int(target)
        "allocation_wheel": return str(target) + "_bonus_volitions"
        "volumitions":      return "click_bonus_volitions"
        "stoctagon":        return "storage_overflow_bonus_volitions"
        "purity_lock":      return ""
    return ""


# --- Slot query helpers ---

func get_parent_volition_free_count() -> int:
    var count := 0
    for slot in volition_slots:
        if slot["category"] == "":
            count += 1
    return count


func get_total_children_count() -> int:
    var total := 0
    for slot in volition_slots:
        total += slot["children"].size()
    return total


func get_free_children_count() -> int:
    var total := 0
    for slot in volition_slots:
        for child in slot["children"]:
            if child["category"] == "":
                total += 1
    return total


func get_first_free_parent_index() -> int:
    for i in volition_slots.size():
        if volition_slots[i]["category"] == "":
            return i
    return -1


func get_first_parent_index_with_target(category: String, target) -> int:
    for i in volition_slots.size():
        var slot: Dictionary = volition_slots[i]
        if slot["category"] == category:
            if category in ["stoctagon", "volumitions"] or slot["target"] == target:
                return i
    return -1


func find_slot_with_free_child(category: String) -> int:
    for i in volition_slots.size():
        var slot: Dictionary = volition_slots[i]
        if slot["category"] != category:
            continue
        for child in slot["children"]:
            if child["category"] == "":
                return i
    return -1


func get_first_free_child_index(slot_index: int) -> int:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return -1
    for i in volition_slots[slot_index]["children"].size():
        if volition_slots[slot_index]["children"][i]["category"] == "":
            return i
    return -1


func get_total_free_children_in_category(category: String) -> int:
    var count := 0
    for slot in volition_slots:
        if slot["category"] != category:
            continue
        for child in slot["children"]:
            if child["category"] == "":
                count += 1
    return count


func get_total_children_in_slot(slot_index: int) -> int:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return 0
    return volition_slots[slot_index]["children"].size()


func get_free_children_in_slot(slot_index: int) -> int:
    if slot_index < 0 or slot_index >= volition_slots.size():
        return 0
    var count := 0
    for child in volition_slots[slot_index]["children"]:
        if child["category"] == "":
            count += 1
    return count


func has_parent_volition_for_constellation(constellation_id: int) -> bool:
    for slot in volition_slots:
        if slot["category"] == "constellation" and slot["target"] == constellation_id:
            return true
    return false


func has_volition_for_constellation(constellation_id: int) -> bool:
    var key = "constellation_%d_volitions" % constellation_id
    var bonus_key = "constellation_%d_bonus_volitions" % constellation_id
    return assignments.get(key, 0) > 0 or assignments.get(bonus_key, 0) > 0


func get_constellation_sub_targets(constellation_id: int) -> Array:
    # Returns which sub_targets have active Hourglass targeting assigned.
    # Reads directly from hourglass_target_ops (multi-target Array).
    if constellation_id == 2:
        return hourglass_target_ops.duplicate()
    return []


func get_bonus_volitions_per_slot() -> int:
    # Returns 0/1/2/3 based on Archon constellation tier.
    var cd = get_node_or_null("/root/ConstellationData")
    if cd and cd.has_method("get_bonus_volition_grant"):
        return cd.get_bonus_volition_grant()
    return 0


func get_constellation_spark_fraction(constellation_id: int, threshold: float) -> float:
    if threshold <= 0.0:
        return 0.0
    var total = constellation_spark_totals.get(str(constellation_id), 0.0)
    return clamp(total / threshold, 0.0, 1.0)


func accumulate_constellation_sparks() -> void:
    var cd: Node = get_node_or_null("/root/ConstellationData")
    for key in constellation_spark_totals:
        var id := int(key)
        var points := get_constellation_points(id)
        if points <= 0:
            continue
        var mode_raw = assignments.get("constellation_%d_feed_mode" % id)
        var mode: int = mode_raw as int if mode_raw != null else 0
        if mode == 0:
            continue
        if sparks.is_zero():
            continue
        # Stop draining once the constellation is full
        if cd:
            var cap: float = cd.get_spark_cap(id)
            var current: float = constellation_spark_totals.get(key, 0.0)
            if current >= cap:
                continue
            # Clamp so we don't overshoot
            var room: float = cap - current
            var deduct: BigNum = BigNum.from_int(points)
            if deduct.to_float() > room:
                deduct = BigNum.from_float(room)
            if sparks.is_less_than(deduct):
                deduct = sparks.copy()
            sparks = sparks.sub(deduct)
            constellation_spark_totals[key] = current + deduct.to_float()
        else:
            var deduct: BigNum = BigNum.from_int(points)
            if sparks.is_less_than(deduct):
                deduct = sparks.copy()
            sparks = sparks.sub(deduct)
            constellation_spark_totals[key] = constellation_spark_totals.get(key, 0.0) + deduct.to_float()
    # Re-sync bonus children if the Archon's visual state has crossed a tier.
    # get_bonus_volition_grant() reads the live state so we only rebuild when
    # the grant value actually changes — not on every spark tick.
    if cd and cd.has_method("get_bonus_volition_grant"):
        var current_grant: int = cd.get_bonus_volition_grant()
        if current_grant != _last_bonus_volition_grant:
            _last_bonus_volition_grant = current_grant
            sync_bonus_children_count()


func reset_constellation_sparks() -> void:
    for key in constellation_spark_totals:
        constellation_spark_totals[key] = 0.0


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


func spend_particle(amount: int) -> bool:
    var cost = BigNum.from_int(amount)
    if is_locked("particle") or particle.is_less_than(cost):
        return false
    particle = particle.sub(cost)
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
    var sc  = BigNum.from_int(solid_amt)
    var lc  = BigNum.from_int(liquid_amt)
    var gcc = BigNum.from_int(gas_amt)
    if monad["solid"].is_less_than(sc) or monad["liquid"].is_less_than(lc) or monad["gas"].is_less_than(gcc):
        return false
    monad["solid"]  = monad["solid"].sub(sc)
    monad["liquid"] = monad["liquid"].sub(lc)
    monad["gas"]    = monad["gas"].sub(gcc)
    return true


# ===================== WATERMARKS =========================
func update_watermarks() -> void:
    var monad_total  = get_monad_total()
    var tetrad_total = get_tetrad_total()
    if sparks.is_greater_than(watermarks["sparks"]):
        watermarks["sparks"] = sparks.copy()
    if monad_total.is_greater_than(watermarks["monad"]):
        watermarks["monad"] = monad_total.copy()
    if monad["solid"].is_greater_than(watermarks["monad_solid"]):
        watermarks["monad_solid"] = monad["solid"].copy()
    if monad["liquid"].is_greater_than(watermarks["monad_liquid"]):
        watermarks["monad_liquid"] = monad["liquid"].copy()
    if monad["gas"].is_greater_than(watermarks["monad_gas"]):
        watermarks["monad_gas"] = monad["gas"].copy()
    if tetrad_total.is_greater_than(watermarks["tetrad"]):
        watermarks["tetrad"] = tetrad_total.copy()
    if particle.is_greater_than(watermarks["particle"]):
        watermarks["particle"] = particle.copy()
    if iota.is_greater_than(watermarks["iota"]):
        watermarks["iota"] = iota.copy()
    if mote.is_greater_than(watermarks["mote"]):
        watermarks["mote"] = mote.copy()
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
    data["creation_counter"] = creation_counter
    data["creation_order"]   = creation_order.duplicate()
    for k in tetrad:
        data["tetrad_" + k] = tetrad[k].to_save_string()
    for key in ["particle", "iota", "mote", "grain", "uonite"]:
        data[key] = get_resource(key).to_save_string()
    data["archon_foci"]           = archon_foci
    data["volitions"]             = volitions
    data["refinements_completed"] = refinements_completed
    data["expansions"]            = expansions
    data["next_expansion_foci_exp"] = next_expansion_foci_exp
    data["purity_locks_unlocked"] = purity_locks_unlocked
    data["grains_this_cycle"]     = grains_this_cycle
    data["uonites_this_cycle"]    = uonites_this_cycle
    var saved_assignments = {}
    for key in assignments:
        var val = assignments[key]
        if val is BigNum:
            saved_assignments[key] = "BN:" + val.to_save_string()
        else:
            saved_assignments[key] = val
    data["assignments"]                = saved_assignments
    data["volition_slots"]             = _serialize_volition_slots()
    data["locks"]                      = locks.duplicate()
    data["constellation_spark_totals"] = constellation_spark_totals.duplicate()
    data["storage_cap"]                = storage_cap.to_save_string()
    data["watermark_monad_solid"]      = watermarks["monad_solid"].to_save_string()
    data["watermark_monad_liquid"]     = watermarks["monad_liquid"].to_save_string()
    data["watermark_monad_gas"]        = watermarks["monad_gas"].to_save_string()
    data["ui_unlocks"]                 = ui_unlocks.duplicate()
    data["tetrad_milestones"]          = tetrad_milestones.duplicate()
    data["monad_milestones"]           = monad_milestones.duplicate()
    var saved_totals = {}
    for key in totals_created:
        saved_totals[key] = totals_created[key].to_save_string()
    data["totals_created"]    = saved_totals
    data["totals_milestones"] = totals_milestones.duplicate()
    # === FIRMAMENT STOCKS ===
    for k in solid_stocks:
        data["solid_stock_" + k]  = solid_stocks[k].to_save_string()
    for k in liquid_stocks:
        data["liquid_stock_" + k] = liquid_stocks[k].to_save_string()
    for k in gas_stocks:
        data["gas_stock_" + k]    = gas_stocks[k].to_save_string()
    data["phlogiston"]                  = phlogiston.to_save_string()
    data["quintessence"]                = quintessence.to_save_string()
    data["grain_purity_profile"]        = grain_purity_profile.duplicate()
    data["manifold_allocations"]        = manifold_allocations.duplicate()
    data["manifold_total_flows"]        = manifold_total_flows
    data["hourglass_target_ops"]        = hourglass_target_ops.duplicate()
    data["archon_poke_count"]           = archon_poke_count
    data["archon_lockdown_level"]       = archon_lockdown_level
    data["archon_lockdown_end_time"]    = archon_lockdown_end_time
    data["archon_warning_window_end"]   = archon_warning_window_end
    data["archon_reentry_threshold"]    = archon_reentry_threshold
    data["uonite_name"]                 = uonite_name
    data["hint_bias_enabled"]           = hint_bias_enabled
    data["sparks_since_first_prestige"] = sparks_since_first_prestige
    return data


func _serialize_volition_slots() -> Array:
    var result: Array = []
    for slot in volition_slots:
        var saved_children: Array = []
        for child in slot["children"]:
            saved_children.append({
                "category": child["category"],
                "target": child["target"],
            })
        result.append({
            "category": slot["category"],
            "target": slot["target"],
            "children": saved_children,
        })
    return result


func _deserialize_volition_slots(saved: Array) -> void:
    volition_slots.clear()
    for s in saved:
        var slot = _make_empty_slot()
        slot["category"] = s.get("category", "")
        var raw_target = s.get("target", "")
        # JSON round-trips integer constellation IDs as floats — cast back.
        if slot["category"] == "constellation" and raw_target is float:
            slot["target"] = int(raw_target)
        else:
            slot["target"] = raw_target
        for c in s.get("children", []):
            var child_cat: String = c.get("category", "")
            var child_raw = c.get("target", "")
            var child_target
            if child_cat == "constellation" and child_raw is float:
                child_target = int(child_raw)
            else:
                child_target = child_raw
            slot["children"].append({
                "category": child_cat,
                "target":   child_target,
            })
        volition_slots.append(slot)
    # Grow/shrink parent slot count to match volitions, but do NOT call
    # sync_bonus_children_count() here — children were just deserialized
    # and must not be overwritten. The next accumulate_constellation_sparks()
    # tick will sync if the Archon tier has changed.
    while volition_slots.size() < volitions:
        volition_slots.append(_make_empty_slot())
    while volition_slots.size() > volitions:
        var idx = volition_slots.size() - 1
        if volition_slots[idx]["category"] != "":
            unassign_parent_volition(idx)
        volition_slots.pop_back()
    _rebuild_volition_assignments()


func _migrate_flat_volitions_to_slots() -> void:
    # Old save without volition_slots: reconstruct from flat _volitions keys.
    volition_slots.clear()
    _ensure_slot_count(volitions)
    var slot_cursor := 0
    for key in assignments:
        if not key.ends_with("_volitions") or "bonus" in key:
            continue
        var count: int = assignments.get(key, 0)
        for i in count:
            if slot_cursor >= volition_slots.size():
                break
            var cat_target = _key_to_category_target(key)
            volition_slots[slot_cursor]["category"] = cat_target[0]
            volition_slots[slot_cursor]["target"] = cat_target[1]
            # Auto-follow for stoctagon/volumitions
            if cat_target[0] in AUTO_FOLLOW_CATEGORIES:
                for child in volition_slots[slot_cursor]["children"]:
                    child["category"] = cat_target[0]
                    child["target"] = cat_target[1]
            slot_cursor += 1


func _key_to_category_target(key: String) -> Array:
    if key == "click_volitions":
        return ["volumitions", ""]
    if key == "storage_overflow_volitions":
        return ["stoctagon", ""]
    if key.begins_with("constellation_") and key.ends_with("_volitions"):
        var id_str = key.trim_prefix("constellation_").trim_suffix("_volitions")
        return ["constellation", int(id_str)]
    if key.ends_with("_volitions"):
        var op = key.trim_suffix("_volitions")
        return ["allocation_wheel", op]
    return ["", ""]


func load_save_data(data: Dictionary) -> void:
    sparks          = BigNum.from_string(data.get("sparks",        "0:0"))
    monad["solid"]  = BigNum.from_string(data.get("monad_solid",   "0:0"))
    monad["liquid"] = BigNum.from_string(data.get("monad_liquid",  "0:0"))
    monad["gas"]    = BigNum.from_string(data.get("monad_gas",     "0:0"))
    # Scrub fractional monad remnants
    for k in ["solid", "liquid", "gas"]:
        monad[k] = BigNum.from_int(monad[k].to_int())

    var _cc = data.get("creation_counter"); creation_counter = _cc as int        if _cc != null else 0
    var _co = data.get("creation_order");   creation_order   = _co as Dictionary if _co != null else {}

    for k in tetrad:
        tetrad[k] = BigNum.from_string(data.get("tetrad_" + k, "0:0"))
    for key in ["particle", "iota", "mote", "grain", "uonite"]:
        set_resource(key, BigNum.from_string(data.get(key, "0:0")))

    # Scrub fractional remnants from all stored resource types
    for k in monad:
        monad[k] = BigNum.from_int(monad[k].to_int())
    for k in tetrad:
        tetrad[k] = BigNum.from_int(tetrad[k].to_int())
    for key in ["particle", "iota", "mote", "grain", "uonite"]:
        set_resource(key, BigNum.from_int(get_resource(key).to_int()))

    var _af   = data.get("archon_foci");           archon_foci               = _af as int  if _af != null else 1
    var _vo   = data.get("volitions");             volitions                 = _vo as int  if _vo != null else 0
    var _rc   = data.get("refinements_completed"); refinements_completed     = _rc as int  if _rc != null else 0
    var _as   = data.get("expansions");            expansions                = _as as int if _as != null else 0
    var _nefe = data.get("next_expansion_foci_exp"); next_expansion_foci_exp = _nefe as int if _nefe != null else 0
    var _pl   = data.get("purity_locks_unlocked"); purity_locks_unlocked     = _pl as bool if _pl != null else false
    var _gc   = data.get("grains_this_cycle");     grains_this_cycle         = _gc as int  if _gc != null else 0
    var _utc  = data.get("uonites_this_cycle");    uonites_this_cycle        = _utc as int if _utc != null else 0

    if data.has("assignments"):
        for key in data["assignments"]:
            var val = data["assignments"][key]
            if typeof(val) == TYPE_STRING and val.begins_with("BN:"):
                assignments[key] = BigNum.from_string(val.substr(3))
            else:
                assignments[key] = int(val)
    if data.has("locks"):
        for key in data["locks"]:
            if locks.has(key):
                locks[key] = data["locks"][key]
    # --- Volition Slots ---
    if data.has("volition_slots"):
        _deserialize_volition_slots(data["volition_slots"])
    else:
        _migrate_flat_volitions_to_slots()
    _rebuild_volition_assignments()
    if data.has("constellation_spark_totals"):
        for key in data["constellation_spark_totals"]:
            constellation_spark_totals[key] = float(data["constellation_spark_totals"][key])
    
    storage_cap              = BigNum.from_string(data.get("storage_cap",            "987:0"))
    watermarks["monad_solid"]  = BigNum.from_string(data.get("watermark_monad_solid",  "0:0"))
    watermarks["monad_liquid"] = BigNum.from_string(data.get("watermark_monad_liquid", "0:0"))
    watermarks["monad_gas"]    = BigNum.from_string(data.get("watermark_monad_gas",    "0:0"))

    if data.has("ui_unlocks"):
        for key in data["ui_unlocks"]:
            if ui_unlocks.has(key):
                ui_unlocks[key] = data["ui_unlocks"][key]
    if data.has("tetrad_milestones"):
        for key in data["tetrad_milestones"]:
            tetrad_milestones[key] = data["tetrad_milestones"][key]
    if data.has("monad_milestones"):
        for key in data["monad_milestones"]:
            monad_milestones[key] = data["monad_milestones"][key]
    if data.has("totals_created"):
        for key in data["totals_created"]:
            if totals_created.has(key):
                totals_created[key] = BigNum.from_string(data["totals_created"][key])
    if data.has("totals_milestones"):
        for key in data["totals_milestones"]:
            totals_milestones[key] = data["totals_milestones"][key]

    # === FIRMAMENT STOCKS ===
    for k in solid_stocks:
        solid_stocks[k]  = BigNum.from_string(data.get("solid_stock_"  + k, "0:0"))
    for k in liquid_stocks:
        liquid_stocks[k] = BigNum.from_string(data.get("liquid_stock_" + k, "0:0"))
    for k in gas_stocks:
        gas_stocks[k]    = BigNum.from_string(data.get("gas_stock_"    + k, "0:0"))
    phlogiston   = BigNum.from_string(data.get("phlogiston",   "0:0"))
    quintessence = BigNum.from_string(data.get("quintessence", "0:0"))

    if data.has("grain_purity_profile"):
        for k in data["grain_purity_profile"]:
            if grain_purity_profile.has(k):
                grain_purity_profile[k] = float(data["grain_purity_profile"][k])
    if data.has("manifold_allocations"):
        for k in data["manifold_allocations"]:
            if manifold_allocations.has(k):
                manifold_allocations[k] = int(data["manifold_allocations"][k])

    var _mf = data.get("manifold_total_flows"); manifold_total_flows = _mf as int    if _mf != null else 0
    var _ht = data.get("hourglass_target_ops")
    if _ht is Array:
        hourglass_target_ops = Array(_ht, TYPE_STRING, "", null)
    else:
        hourglass_target_ops = []
    var _apc  = data.get("archon_poke_count");         archon_poke_count         = _apc  as int   if _apc  != null else 0
    var _all  = data.get("archon_lockdown_level");     archon_lockdown_level     = _all  as int   if _all  != null else 0
    var _alet = data.get("archon_lockdown_end_time");  archon_lockdown_end_time  = _alet as float if _alet != null else 0.0
    var _aww  = data.get("archon_warning_window_end"); archon_warning_window_end = _aww  as float if _aww  != null else 0.0
    var _art  = data.get("archon_reentry_threshold");  archon_reentry_threshold  = _art  as int   if _art  != null else 0
    uonite_name = data.get("uonite_name", "")
    sparks_since_first_prestige = data.get("sparks_since_first_prestige", 0.0)
    hint_bias_enabled = data.get("hint_bias_enabled", false)
    _last_bonus_volition_grant = 0  # Forces re-sync on first accumulate tick after load


func do_prestige_reset() -> BigNum:
    var cap_delta := expand_storage_cap(sparks)
    storage_cap_at_prestige_start = storage_cap.copy()
    expansions        += 1
    volitions          = 0
    volitions_spent    = 0
    # Preserve all parent Volition assignments across Expansions, including purity
    # lock slots — players running automated fast cycles need production filters and
    # wheel assignments intact from the start of each new cycle. Purity lock state
    # (the locks dict and purity_locks_unlocked flag) also survives for the same reason.
    # Only Bonus Volition children clear: Archon Constellation resets to Tier 0 each
    # Expansion, so no bonus grants exist at cycle start.
    # NOTE: The flat assignments dict (_volitions keys) is wiped by the assignments
    # loop below. It is correctly rebuilt when _check_volition_grant() fires in
    # root_ui.gd after this function returns, via _ensure_slot_count() →
    # sync_bonus_children_count() → _rebuild_volition_assignments().
    for slot in volition_slots:
        slot["children"].clear()
    sparks = BigNum.zero()
    for k in monad:  monad[k]  = BigNum.zero()
    for k in tetrad: tetrad[k] = BigNum.zero()
    particle = BigNum.zero()
    iota     = BigNum.zero()
    mote     = BigNum.zero()
    grain    = BigNum.zero()
    grains_this_cycle = 0
    uonites_this_cycle = 0
    # Firmament stocks reset fully until survival mechanics are unlocked.
    for k in solid_stocks:  solid_stocks[k]  = BigNum.zero()
    for k in liquid_stocks: liquid_stocks[k] = BigNum.zero()
    for k in gas_stocks:    gas_stocks[k]    = BigNum.zero()
    phlogiston   = BigNum.zero()
    quintessence = BigNum.zero()
    grain_purity_profile = {"fundament": 0.0, "element": 0.0, "symmetric": 0.0, "medial": 0.0}
    for k in manifold_allocations: manifold_allocations[k] = 0
    manifold_total_flows = 0
    hourglass_target_ops = []
    for k in rates:  rates[k] = BigNum.zero()
    # Snapshot keys that survive Expansions before wiping.
    # Foci distribution, feed mode, and solve counts are persistent automation
    # state — players set these up once and expect them to persist across cycles.
    # Volition keys are intentionally excluded here: they get rebuilt by
    # _rebuild_volition_assignments() after _check_volition_grant() fires.
    var _prestige_preserve: Array[String] = []
    for k in assignments:
        if k.ends_with("_foci") \
                or k.ends_with("_feed_mode") \
                or k.ends_with("_solve_count"):
            _prestige_preserve.append(k)
    var _prestige_saved: Dictionary = {}
    for k in _prestige_preserve:
        _prestige_saved[k] = assignments[k]
    for k in assignments:
        if assignments[k] is BigNum:
            assignments[k] = BigNum.zero()
        else:
            assignments[k] = 0
    for k in _prestige_saved:
        assignments[k] = _prestige_saved[k]
    for k in constellation_spark_totals:
        constellation_spark_totals[k] = 0.0
    return cap_delta
        
        
