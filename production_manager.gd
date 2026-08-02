extends Node
# ================== PRODUCTION MANAGER v1.7.0 ==================
# v1.7.0: More bug stomping
# v1.6.0: Storage cap enforcement. All _produce_* functions now
#         check _get_storage_headroom() before spending any inputs.
#         particle_compress, iota_assemble, mote_compress, and
#         grain_assemble consolidated into _produce_generic() since
#         they are purely data-driven. monad_compress and
#         tetrad_assemble remain bespoke due to random subtype
#         distribution logic that will evolve into the mid-game
#         statistical enrichment system.
# v1.5.0: Renamed timer constants to match canonical chain order.
# v1.4.1: Timerless continuous production via _process(delta).

signal manifold_ticked

# ===================== TIMER INTERVALS ====================
const TIMER_SPARKS:    float = 1.0
const TIMER_MONAD:     float = 1.0
const TIMER_TETRAD:    float = 2.0
const TIMER_PARTICLE:  float = 3.0
const TIMER_IOTA:      float = 5.0
const TIMER_MOTE:      float = 8.0
const TIMER_GRAIN:     float = 13.0
const TIMER_UONITE:    float = 21.0
const TIMER_MANIFOLD: float = 8.0   # Transform tick — slower than Grain assembly

# ===================== RANDOM DRAW THRESHOLD ==============
const RANDOM_DRAW_THRESHOLD: int = 1000

# Below threshold: draw each unit one-at-a-time from a live pool (true
# random, exact but O(n)). Above threshold: use the simplex/proportional
# split instead (statistically equivalent at scale, O(1)). Shared by the
# monad-roll/tetrad-assemble/tetrad-spend batch dispatchers below — was
# the same condition copy-pasted 3 times.
func _should_use_true_random(amt_f: float) -> bool:
    return amt_f <= float(RANDOM_DRAW_THRESHOLD) and amt_f >= 1.0

# ===================== DEPENDENCY ORDER ===================
const DEPENDENCY_ORDER: Array[String] = [
    "sparks_summon",
    "monad_compress",
    "tetrad_assemble",
    "particle_compress",
    "iota_assemble",
    "mote_compress",
	"grain_assemble"
]

# Tier order for Stoctagon overflow — rank 0 fires first (highest tier).
const OVERFLOW_PRIORITY: Array[String] = [
    "grain_assemble",    # rank 0 — net storage: -83
    "mote_compress",     # rank 1 — net storage: -4
    "iota_assemble",     # rank 2 — net storage: -19
    "particle_compress", # rank 3 — net storage: -4
    "tetrad_assemble",   # rank 4 — net storage: -3
]
# monad_compress is excluded: it's net +1 (creates stored resource from
# non-stored sparks) and would inflate storage above cap indefinitely.
# Monad only fires in normal mode when consolidation frees real headroom.


# ===================== GENERIC OPERATION TABLE ============
# Drives _produce_generic() for the four data-driven operations. Inputs and
# output key come from game_data.RECIPES (single source of truth) — this
# table holds only the one thing RECIPES doesn't: which locked resources
# should abort production entirely. Deliberately NOT merged with
# OP_LOCK_KEYS below despite the similar shape — the two tables serve
# different call sites (_produce_generic vs. _op_has_inputs) and
# intentionally disagree for iota_assemble/grain_assemble; see the comment
# above OP_LOCK_KEYS.
const GENERIC_OPS_LOCK_KEYS = {
    "particle_compress": [],
    "iota_assemble":     ["particle"],
    "mote_compress":     ["iota"],
    "grain_assemble":    ["particle", "mote"],
}

# Lock keys checked by _op_has_inputs() for every op it's ever called with,
# including the two (monad_compress, tetrad_assemble) that aren't in
# GENERIC_OPS_LOCK_KEYS at all since they use their own bespoke production
# functions. Deliberately preserves the existing inconsistency where most
# ops check no locks — this mirrors exactly what _op_has_inputs hardcoded
# before it became RECIPES-driven, not a design choice made here.
const OP_LOCK_KEYS = {
    "monad_compress":    ["sparks"],
    "tetrad_assemble":   [],
    "particle_compress": [],
    "iota_assemble":     [],
    "mote_compress":     ["iota"],
    "grain_assemble":    [],
}

# Single source of truth for a recipe's per-input cost, used by the manual
# single-unit assembly functions below instead of hand-typed BigNum literals
# (those literals had drifted from game_data.RECIPES once already — see §0
# of the architecture doc's Uonite Grain/Mote note).
func _recipe_cost(op: String, resource_key: String) -> int:
    return game_data.RECIPES[op]["inputs"].get(resource_key, 0)

# ===================== NODE REFERENCES ====================
var gc:        Node = null
var game_data: Node = null
var _frame_count: int = 0
var _smoothed_rates: Dictionary = {}
var _accum: Dictionary = {}
var _overflow_budget: int = -1   # -1 = normal mode; >= 0 = overflow mode (remaining volitions this frame)


func _ready() -> void:
    gc        = get_node_or_null("/root/GameContext")
    game_data = get_node_or_null("/root/GameData")
    if not gc:
        push_error("ProductionManager: GameContext autoload not found.")
        return
    _smoothed_rates = {}
    _accum = {}
    for op in DEPENDENCY_ORDER:
        _accum[op] = 1.0
    _accum["manifold"] = 0.0
    _accum["constellation"] = 0.0
    
        
func reset_for_prestige() -> void:
    for op in _accum:
        _accum[op] = 0.0
    for op in _smoothed_rates:
        _smoothed_rates[op] = 0.0
        
        
func apply_offline_progress(elapsed_seconds: float) -> Dictionary:
    const CHUNK_SIZE  := 30.0
    const MAX_OFFLINE := 8.0 * 3600.0
    var secs: float = min(elapsed_seconds, MAX_OFFLINE)
    var chunks := int(secs / CHUNK_SIZE)
    if chunks <= 0:
        return {}
    var before     := _snapshot_resources()
    var local_accum: Dictionary = {}
    var intervals  := get_timer_intervals()
    for op in DEPENDENCY_ORDER:
        local_accum[op] = 0.0
    for _chunk in range(chunks):
        for op in DEPENDENCY_ORDER:
            var interval: float = intervals.get(op, 1.0)
            var assigned: BigNum = gc.get_operation_total_bignum(op)
            if assigned.is_zero():
                local_accum[op] = 0.0
                continue
            local_accum[op] += CHUNK_SIZE / interval
            var whole: int = int(local_accum[op])
            if whole <= 0:
                continue
            local_accum[op] -= float(whole)
            var batch: BigNum = assigned.mul_int(whole)
            match op:
                "sparks_summon":   _produce_sparks_summon(batch)
                "monad_compress":  _produce_monad_compress(batch)
                "tetrad_assemble": _produce_tetrad_assemble(batch)
                _:                 _produce_generic(op, batch)
        # Constellation endowment: 30 ticks per 30-second chunk (1/sec rate)
        for _ct in int(CHUNK_SIZE):
            gc.accumulate_constellation_sparks()
    var after := _snapshot_resources()
    return _diff_offline(before, after, chunks)


func _snapshot_resources() -> Dictionary:
    return {
        "sparks":   gc.sparks.copy(),
        "monad":    gc.get_monad_total().copy(),
        "tetrad":   gc.get_tetrad_total().copy(),
        "particle": gc.particle.copy(),
        "iota":     gc.iota.copy(),
        "mote":     gc.mote.copy(),
        "grain":    gc.grain.copy(),
        "uonite":   gc.uonite.copy(),
    }


func _diff_offline(before: Dictionary, after: Dictionary, chunks: int) -> Dictionary:
    var diff := { "time_simulated": chunks * 30 }
    for key in before:
        var delta: BigNum = after[key].sub(before[key])
        if not delta.is_zero():
            diff[key] = delta.to_display_string()
    return diff


func _process(delta: float) -> void:
    if not gc or delta <= 0.0:
        return
    _frame_count += 1

    # Push last frame's smoothed rates into gc.rates for UI display
    for op in DEPENDENCY_ORDER:
        gc.rates[op] = BigNum.from_float(_smoothed_rates.get(op, 0.0))

    # ── Phase 1: Accumulate time, build ready-batch table ──
    var ready_batches: Dictionary = {}
    # Hoisted out of the loop below — matches apply_offline_progress()'s
    # existing pattern (line ~140). Nothing inside the loop body changes
    # get_timer_intervals()'s inputs, so calling it fresh per-op here just
    # rebuilt the same 8-entry Dictionary (plus an autoload lookup) up to
    # 7x every frame for no benefit.
    var intervals: Dictionary = get_timer_intervals()
    for op in DEPENDENCY_ORDER:
        var interval: float = intervals.get(op, 1.0)
        var assigned: BigNum = gc.get_operation_total_bignum(op)
        if assigned.is_zero():
            _accum[op] = 0.0
            _smoothed_rates[op] = 0.0
            continue
        _accum[op] += (1.0 / interval) * delta
        var whole: int = int(_accum[op])
        if whole <= 0:
            continue
        _accum[op] -= float(whole)
        ready_batches[op] = assigned.mul_int(whole)

    # ── Phase 2: Sparks always fire (uncapped) ──
    if ready_batches.has("sparks_summon"):
        var actual: BigNum = _produce_sparks_summon(ready_batches["sparks_summon"])
        _update_smoothed_rate("sparks_summon", actual)

    # ── Phase 3: Material production — route by storage state ──
    var at_cap: bool = gc.get_storage_total().is_greater_or_equal(gc.get_effective_storage_cap())
    if at_cap:
        _run_overflow_production(ready_batches)
    else:
        _run_normal_production(ready_batches)

    # ── Phase 4: Manifold pass ──
    var _mflows = gc.get("manifold_total_flows")
    if _mflows != null and (_mflows as int) > 0:
        _accum["manifold"] += delta / TIMER_MANIFOLD
        var m_ticks: int = int(_accum["manifold"])
        if m_ticks > 0:
            _accum["manifold"] -= float(m_ticks)
            _sample_grain_purity()
            for _t in m_ticks:
                _produce_manifold()
            emit_signal("manifold_ticked")

    # ── Phase 5: Constellation spark investment (fixed 1 s rate) ──
    _accum["constellation"] += delta / 1.0
    var c_ticks: int = int(_accum["constellation"])
    if c_ticks > 0:
        _accum["constellation"] -= float(c_ticks)
        for _t in c_ticks:
            gc.accumulate_constellation_sparks()
            
            
func _update_smoothed_rate(op: String, actual: BigNum) -> void:
    var interval: float = get_timer_intervals().get(op, 1.0)
    var raw_per_sec: float = actual.to_float() / interval
    if not _smoothed_rates.has(op):
        _smoothed_rates[op] = raw_per_sec
    else:
        _smoothed_rates[op] = lerp(_smoothed_rates[op], raw_per_sec, 0.15)


func _run_normal_production(ready_batches: Dictionary) -> void:
    _overflow_budget = -1
    #if _frame_count % 60 == 0:
        #print("NORMAL_PROD | storage=", gc.get_storage_total().to_int(),
              #"/", gc.get_effective_storage_cap().to_int(),
              #" monad_s=", gc.monad["solid"].to_int(),
              #" monad_l=", gc.monad["liquid"].to_int(),
              #" monad_g=", gc.monad["gas"].to_int(),
              #" batches=", ready_batches.keys())
    for op in DEPENDENCY_ORDER:
        if op == "sparks_summon":
            continue
        if not ready_batches.has(op):
            continue
        var batch: BigNum = ready_batches[op]
        var actual: BigNum = BigNum.zero()
        match op:
            "monad_compress":  actual = _produce_monad_compress(batch)
            "tetrad_assemble": actual = _produce_tetrad_assemble(batch)
            _:                 actual = _produce_generic(op, batch)
        _update_smoothed_rate(op, actual)


func _run_overflow_production(ready_batches: Dictionary) -> void:
    var total_slots: int = gc._assignment_int("storage_overflow_volitions", 0) \
                         + gc._assignment_int("storage_overflow_bonus_volitions", 0)
    if total_slots <= 0:
        for op in OVERFLOW_PRIORITY:
            if op != "sparks_summon":
                _smoothed_rates[op] = lerp(_smoothed_rates.get(op, 0.0), 0.0, 0.15)
        _overflow_budget = -1
        return

    _overflow_budget = total_slots
    var fired: Dictionary = {}

    for op in OVERFLOW_PRIORITY:
        if _overflow_budget <= 0:
            break
        if not ready_batches.has(op):
            continue
        if not _op_has_inputs(op):
            continue

        var batch: BigNum = _bignum_min(ready_batches[op], BigNum.from_int(_overflow_budget))

        var actual: BigNum = BigNum.zero()
        match op:
            "monad_compress":  actual = _produce_monad_compress(batch)
            "tetrad_assemble": actual = _produce_tetrad_assemble(batch)
            _:                 actual = _produce_generic(op, batch)

        if not actual.is_zero():
            fired[op] = true
            _update_smoothed_rate(op, actual)
            _overflow_budget -= actual.to_int()
            _overflow_budget = max(0, _overflow_budget)

    for op in OVERFLOW_PRIORITY:
        if not fired.has(op):
            _smoothed_rates[op] = lerp(_smoothed_rates.get(op, 0.0), 0.0, 0.15)

    _overflow_budget = -1


# ==================================================
# PRODUCE — SPARKS (uncapped, no storage limit)
# ==================================================
func _produce_sparks_summon(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    var mult: float = get_sparks_multiplier()
    var actual: BigNum = requested
    if mult > 1.0:
        actual = BigNum.from_int(_safe_int(requested.to_float() * mult))
    gc.sparks = gc.sparks.add(actual)
    gc.add_to_total("sparks_summoned", actual)
    if gc.expansions > 0:
        gc.sparks_since_first_prestige += actual.to_float()
    return actual
    
    
# ==================================================
# MANIFOLD — PURITY SAMPLING
# Reads current Tetrad pool balance and EMA-updates gc.grain_purity_profile.
# Called once per manifold tick so purity reflects what's actually in storage.
# ==================================================
func _sample_grain_purity() -> void:
    if not gc or not game_data: return
    var category_totals := {"fundament": 0.0, "element": 0.0, "symmetric": 0.0, "medial": 0.0}
    var grand_total := 0.0
    for variety_key in game_data.TETRADS:
        var cat: String = game_data.TETRADS[variety_key]["category"]
        if not gc.tetrad.has(variety_key): continue
        var amt: float = gc.tetrad[variety_key].to_float()
        category_totals[cat] += amt
        grand_total += amt
    # grand_total sums BigNum.to_float() results, which overflow to
    # +Infinity for late-game values beyond float64 range — a `<= 0.0`
    # check alone doesn't catch that (Infinity is > 0.0). If it slips
    # through, category_totals[k] / grand_total can be Infinity/Infinity
    # = NaN, and lerpf() propagates a NaN target forever afterward (every
    # subsequent lerpf(NaN, x, t) is still NaN) — permanently and silently
    # poisoning grain_purity_profile instead of just capping the ratio.
    if grand_total <= 0.0 or is_inf(grand_total):
        return
    const EMA_ALPHA := 0.10
    for k in gc.grain_purity_profile:
        var sample: float = category_totals[k] / grand_total
        if is_nan(sample):
            continue
        gc.grain_purity_profile[k] = lerpf(gc.grain_purity_profile[k], sample, EMA_ALPHA)


# ==================================================
# MANIFOLD — OUTPUT TIER SELECTION
# fundament_ratio: 0.0–1.0 from gc.grain_purity_profile["fundament"]
# Thresholds are intentional design levers — adjust here only.
# ==================================================
func _manifold_output_key(station: String, fundament_ratio: float) -> String:
    match station:
        "calcination":
            if fundament_ratio >= 0.60: return "ore_iron"
            if fundament_ratio >= 0.35: return "stone"
            return "clay"
        "sublimation":
            if fundament_ratio >= 0.60: return "spirit"
            if fundament_ratio >= 0.35: return "smoke"
            return "steam"
        "dissolution":
            if fundament_ratio >= 0.60: return "elixir"
            if fundament_ratio >= 0.35: return "infusion"
            return "oil"
    return ""


# ==================================================
# MANIFOLD — TRANSFORM TICK
# Each allocated flow unit consumes 1 Grain.
# Material yield = floor(grain_count × fundament_ratio), min 1.
# Remainder → Phlogiston (the "waste that is never truly wasted").
# ==================================================
func _produce_manifold() -> void:
    if not gc: return
    var purity: float = gc.grain_purity_profile["fundament"]
    for station in gc.manifold_allocations:
        var flows: int = gc.manifold_allocations[station]
        if flows <= 0:
            continue
        var requested: BigNum = BigNum.from_int(flows)
        var available: BigNum = gc.grain.copy()
        if available.is_zero():
            continue
        var consumed: BigNum = requested if available.is_greater_or_equal(requested) else available
        gc.grain = gc.grain.sub(consumed)
        var grain_count: int = consumed.to_int()
        var mat_yield:   int = maxi(1, int(float(grain_count) * purity))
        var phlog_yield: int = grain_count - mat_yield
        var output_key: String = _manifold_output_key(station, purity)
        if not output_key.is_empty():
            var output_amount: BigNum = BigNum.from_int(mat_yield)
            match station:
                "calcination":
                    gc.solid_stocks[output_key]  = gc.solid_stocks[output_key].add(output_amount)
                "sublimation":
                    gc.gas_stocks[output_key]    = gc.gas_stocks[output_key].add(output_amount)
                "dissolution":
                    gc.liquid_stocks[output_key] = gc.liquid_stocks[output_key].add(output_amount)
        if phlog_yield > 0:
            gc.phlogiston = gc.phlogiston.add(BigNum.from_int(phlog_yield))


# ==================================================
# PRODUCE — MONAD (bespoke: random subtype distribution)
# ==================================================
func _produce_monad_compress(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if not _monad_production_possible():
        return BigNum.zero()
    # Design rule: monad compression at cap requires tetrad workers
    var at_cap: bool = gc.get_storage_total().is_greater_or_equal(gc.get_effective_storage_cap())
    if at_cap:
        var tetrad_workers: BigNum = gc.get_operation_total_bignum("tetrad_assemble")
        if tetrad_workers.is_zero():
            return BigNum.zero()
    var max_producible: BigNum = _get_storage_headroom()
    if max_producible.is_zero():
        return BigNum.zero()
    max_producible = _bignum_min(max_producible, requested)
    var max_by_sparks: BigNum = gc.sparks.div_int_floor(5)
    var actual: BigNum = _bignum_min(max_producible, max_by_sparks)
    if actual.is_zero():
        return BigNum.zero()
    gc.sparks = gc.sparks.sub(actual.mul_int(5))
    _batch_roll_monads(actual)
    return actual


# ==================================================
# PRODUCE — TETRAD (bespoke: random variety distribution)
# ==================================================
func _produce_tetrad_assemble(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    var headroom = _get_storage_headroom()
    if headroom.is_zero():
        return BigNum.zero()
    var max_by_sparks = gc.sparks
    var max_by_monads = gc.get_monad_unlocked_total().div_int_floor(4)
    var actual = _bignum_min(requested,
                _bignum_min(headroom,
                _bignum_min(max_by_sparks, max_by_monads)))
    if actual.is_zero():
        return BigNum.zero()
    var before: BigNum = gc.get_tetrad_total()
    _batch_assemble_tetrads(actual)
    if not gc.assignments.get("tetrad_ever_produced", false):
        if gc.get_tetrad_total().is_greater_than(before):
            gc.assignments["tetrad_ever_produced"] = true
    return actual


# ==================================================
# PRODUCE — GENERIC (data-driven: particle, iota, mote, grain)
# ==================================================
func _produce_generic(op: String, requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if not GENERIC_OPS_LOCK_KEYS.has(op) or not game_data.RECIPES.has(op):
        push_warning("ProductionManager: _produce_generic called with unknown op: " + op)
        return BigNum.zero()

    # Check locks on flagged input resources
    for lock_key in GENERIC_OPS_LOCK_KEYS[op]:
        if gc.is_locked(lock_key):
            return BigNum.zero()

    # Storage headroom caps output
    var headroom = _get_storage_headroom()
    if headroom.is_zero():
        return BigNum.zero()

    var recipe: Dictionary = game_data.RECIPES[op]
    var inputs: Dictionary = recipe["inputs"]
    var output_key: String = recipe["outputs"].keys()[0]

    # Calculate max producible from each input and headroom
    var actual = _bignum_min(requested, headroom)
    for input_key in inputs:
        var cost: int = inputs[input_key]
        actual = _bignum_min(actual, gc.get_resource(input_key).div_int_floor(cost))

    if actual.is_zero():
        return BigNum.zero()

    # Spend inputs
    for input_key in inputs:
        _spend_resource(input_key, actual.mul_int(inputs[input_key]))

    # Add output
    _add_resource(output_key, actual)
    return actual


# ==================================================
# GENERIC HELPERS — resource access by string key
# ==================================================
func _spend_resource(key: String, amount: BigNum) -> void:
    match key:
        "sparks":   gc.sparks   = gc.sparks.sub(amount)
        "monad":    _batch_spend_monads(amount)
        "tetrad":   _batch_spend_tetrads(amount, amount.div_int_floor(5))
        "particle": gc.particle = gc.particle.sub(amount)
        "iota":     gc.iota     = gc.iota.sub(amount)
        "mote":     gc.mote     = gc.mote.sub(amount)
        "grain":    gc.grain    = gc.grain.sub(amount)
        _: push_warning("ProductionManager: unknown key in _spend_resource: " + key)


func _add_resource(key: String, amount: BigNum) -> void:
    match key:
        "particle": gc.particle = gc.particle.add(amount)
        "iota":     gc.iota     = gc.iota.add(amount)
        "mote":
            gc.mote = gc.mote.add(amount)
            # Cap the BigNum to the small per-cycle headroom BEFORE calling
            # to_int() — amount itself can be storage-headroom-bounded (i.e.
            # effectively unbounded late-game), and to_int()-ing it first
            # then adding to a ≤20 counter can overflow the int addition
            # itself even with to_int()'s own clamp.
            var mote_delta: BigNum = _bignum_min(amount, BigNum.from_int(maxi(0, 20 - gc.motes_this_cycle)))
            gc.motes_this_cycle = mini(gc.motes_this_cycle + mote_delta.to_int(), 20)
        "grain":
            gc.grain = gc.grain.add(amount)
            var grain_delta: BigNum = _bignum_min(amount, BigNum.from_int(maxi(0, 20 - gc.grains_this_cycle)))
            gc.grains_this_cycle = mini(gc.grains_this_cycle + grain_delta.to_int(), 20)
        "uonite":
            var cap: int = gc.get_uonite_cycle_cap()
            var headroom: int = maxi(0, cap - gc.uonites_this_cycle)
            if headroom <= 0: return
            var capped_amount: BigNum = _bignum_min(amount, BigNum.from_int(headroom))
            gc.uonite = gc.uonite.add(capped_amount)
            gc.uonites_this_cycle += capped_amount.to_int()
            gc.add_to_total("uonite", capped_amount)
            return
        _: push_warning("ProductionManager: unknown key in _add_resource: " + key)
    gc.add_to_total(key, amount)


# ==================================================
# STORAGE CAP HELPER
# ==================================================
func _op_has_inputs(op: String) -> bool:
    if not game_data.RECIPES.has(op):
        return false
    for lock_key in OP_LOCK_KEYS.get(op, []):
        if gc.is_locked(lock_key):
            return false
    var inputs: Dictionary = game_data.RECIPES[op]["inputs"]
    for input_key in inputs:
        var cost: int = inputs[input_key]
        if gc.get_resource(input_key).is_less_than(BigNum.from_int(cost)):
            return false
    return true


func _get_storage_headroom() -> BigNum:
    var total = gc.get_storage_total()
    if total.is_less_than(gc.get_effective_storage_cap()):
        return gc.get_effective_storage_cap().sub(total)
    # At cap — check overflow budget first (set by _run_overflow_production)
    if _overflow_budget > 0:
        return BigNum.from_int(_overflow_budget)
    if _overflow_budget == 0:
        return BigNum.zero()
    # Legacy fallback (_overflow_budget == -1, not in overflow loop)
    return BigNum.zero()


# ==================================================
# BATCH HELPERS — monad and tetrad subtype distribution
# ==================================================
func _batch_roll_monads(amount: BigNum) -> void:
    # If any monad type is locked, disable the cap entirely to allow grinding
    var any_locked = gc.is_locked("monad_solid") or gc.is_locked("monad_liquid") or gc.is_locked("monad_gas")
    
    var unlocked = []
    for k in ["solid", "liquid", "gas"]:
        # Bypass cap if locked, or if not capped by the tutorial logic
        if any_locked or not _monad_type_is_capped(k):
            unlocked.append(k)
            
    if unlocked.is_empty():
        return
    if unlocked.size() == 1:
        gc.monad[unlocked[0]] = gc.monad[unlocked[0]].add(amount)
        gc.add_to_total("monad_" + unlocked[0], amount)
        return
    var amt_f = amount.to_float()
    if _should_use_true_random(amt_f):
        _roll_monads_true_random(amount.to_int(), unlocked)
    else:
        _roll_monads_simplex(amount, unlocked)


func _batch_assemble_tetrads(amount: BigNum) -> void:
    var s_avail = BigNum.zero() if gc.is_locked("monad_solid")  else gc.monad["solid"]
    var l_avail = BigNum.zero() if gc.is_locked("monad_liquid") else gc.monad["liquid"]
    var g_avail = BigNum.zero() if gc.is_locked("monad_gas")    else gc.monad["gas"]
    var total_monad = s_avail.add(l_avail).add(g_avail)
    var monad_cost  = amount.mul_int(4)
    if total_monad.is_less_than(monad_cost):
        return
    var available_types = []
    if not s_avail.is_zero(): available_types.append("solid")
    if not l_avail.is_zero(): available_types.append("liquid")
    if not g_avail.is_zero(): available_types.append("gas")
    
    # NEW: Pre-flight check - can we actually draw this from our pool?
    # Simulate drawing once per type to ensure availability
    if available_types.size() == 1:
        # Single type: need 4 of that type per tetrad
        var type = available_types[0]
        var needed = amount.mul_int(4)
        if gc.monad[type].is_less_than(needed):
            return
    
    var amt_f = amount.to_float()
    if _should_use_true_random(amt_f):
        _assemble_tetrads_true_random(amount.to_int(), available_types)
    else:
        _assemble_tetrads_simplex(amount, available_types, monad_cost)


func _batch_spend_tetrads(tetrad_cost: BigNum, output_amount: BigNum) -> void:
    var available = []
    for k in gc.tetrad:
        if not gc.is_locked(k) and not gc.tetrad[k].is_zero():
            available.append(k)
    if available.is_empty():
        return
    
    # NEW: Pre-flight check - can we actually afford this?
    var total_available = BigNum.zero()
    for k in available:
        total_available = total_available.add(gc.tetrad[k])
    if total_available.is_less_than(tetrad_cost):
        return
    
    var amt_f = output_amount.to_float()
    if _should_use_true_random(amt_f):
        _spend_tetrads_true_random(tetrad_cost.to_int(), available)
    else:
        _spend_tetrads_simplex(tetrad_cost, available)


func _roll_monads_true_random(count: int, unlocked: Array) -> void:
    var totals = {}
    for k in unlocked: totals[k] = 0
    for i in count:
        var key = unlocked[gc.rng.randi_range(0, unlocked.size() - 1)]
        totals[key] += 1
    for k in unlocked:
        if totals[k] > 0:
            gc.monad[k] = gc.monad[k].add(BigNum.from_int(totals[k]))
            gc.add_to_total("monad_" + k, BigNum.from_int(totals[k]))


func _roll_monads_simplex(amount: BigNum, unlocked: Array) -> void:
    var amt_f = amount.to_float()
    match unlocked.size():
        2:
            var cut = gc.rng.randf()
            var a_amt = BigNum.from_int(_safe_int(amt_f * cut))
            var b_amt = amount.sub(a_amt)
            gc.monad[unlocked[0]] = gc.monad[unlocked[0]].add(a_amt)
            gc.add_to_total("monad_" + unlocked[0], a_amt)
            gc.monad[unlocked[1]] = gc.monad[unlocked[1]].add(b_amt)
            gc.add_to_total("monad_" + unlocked[1], b_amt)
        3:
            var split = _random_simplex_split()
            var s_amt = BigNum.from_int(_safe_int(amt_f * split.x))
            var l_amt = BigNum.from_int(_safe_int(amt_f * split.y))
            var g_amt = amount.sub(s_amt).sub(l_amt)
            # Remainder from flooring lands in g_amt; redistribute randomly
            var remainder = g_amt.sub(BigNum.from_int(_safe_int(amt_f * split.z)))
            g_amt = BigNum.from_int(_safe_int(amt_f * split.z))
            var rem_i = remainder.to_int()
            var keys = ["solid", "liquid", "gas"]
            for i in rem_i:
                var k = keys[gc.rng.randi_range(0, 2)]
                match k:
                    "solid": s_amt = s_amt.add(BigNum.from_int(1))
                    "liquid": l_amt = l_amt.add(BigNum.from_int(1))
                    "gas": g_amt = g_amt.add(BigNum.from_int(1))
            gc.monad["solid"]  = gc.monad["solid"].add(s_amt)
            gc.add_to_total("monad_solid",  s_amt)
            gc.monad["liquid"] = gc.monad["liquid"].add(l_amt)
            gc.add_to_total("monad_liquid", l_amt)
            gc.monad["gas"]    = gc.monad["gas"].add(g_amt)
            gc.add_to_total("monad_gas",    g_amt)


func _assemble_tetrads_true_random(count: int, available_types: Array) -> void:
    # DEDUPED 2026-07-27 — the per-unit draw loop here used to be a second,
    # independently-fixed copy of _try_assemble_tetrad's rebuild-per-draw
    # logic (see that function's comment for the bug history). Both now
    # call the shared _draw_monad_composition() so there's exactly one
    # implementation of "draw N monads from a live categorized pool
    # without over-drawing" to keep correct. Locked types never appear in
    # available_types (pre-filtered by the caller, _batch_assemble_tetrads),
    # so unlike the manual path this call site needs no lock filtering
    # of its own.
    var monad_draws: int = _recipe_cost("tetrad_assemble", "monad")
    for i in count:
        var drawn = _draw_monad_composition(monad_draws, available_types)
        if drawn.is_empty():
            continue
        var s = drawn.count("solid")
        var l = drawn.count("liquid")
        var g = drawn.count("gas")
        if not gc.spend_sparks(1): break
        gc.spend_monad(s, l, g)
        var result = _resolve_tetrad(s, l, g)
        if result != "":
            gc.tetrad[result] = gc.tetrad[result].add(BigNum.from_int(1))
            gc.add_to_total(result, BigNum.one())


func _assemble_tetrads_simplex(amount: BigNum, available_types: Array, monad_cost: BigNum) -> void:
    var sr: float = 0.0; var lr: float = 0.0; var gr: float = 0.0
    match available_types.size():
        1:
            sr = 1.0 if available_types[0] == "solid"  else 0.0
            lr = 1.0 if available_types[0] == "liquid" else 0.0
            gr = 1.0 if available_types[0] == "gas"    else 0.0
        2:
            var cut = gc.rng.randf()
            var a = cut; var b = 1.0 - cut
            sr = a if available_types[0] == "solid"  else (b if available_types[1] == "solid"  else 0.0)
            lr = a if available_types[0] == "liquid" else (b if available_types[1] == "liquid" else 0.0)
            gr = a if available_types[0] == "gas"    else (b if available_types[1] == "gas"    else 0.0)
        3:
            var split = _random_simplex_split()
            sr = split.x; lr = split.y; gr = split.z
    gc.sparks = gc.sparks.sub(amount)
    var s_spend = BigNum.from_int(_safe_int(monad_cost.to_float() * sr))
    var l_spend = BigNum.from_int(_safe_int(monad_cost.to_float() * lr))
    var g_spend = monad_cost.sub(s_spend).sub(l_spend)
    gc.monad["solid"]  = gc.monad["solid"].sub(_clamped_sub(gc.monad["solid"],  s_spend))
    gc.monad["liquid"] = gc.monad["liquid"].sub(_clamped_sub(gc.monad["liquid"], l_spend))
    gc.monad["gas"]    = gc.monad["gas"].sub(_clamped_sub(gc.monad["gas"],       g_spend))
    _batch_distribute_tetrads(amount, sr, lr, gr)


func _batch_distribute_tetrads(amount: BigNum, sr: float, lr: float, gr: float) -> void:
    var dist = {
        "adaemant": sr*sr*sr*sr,      "aquae": lr*lr*lr*lr,      "aethyr": gr*gr*gr*gr,
        "earth":    6.0*sr*sr*lr*gr,  "water": 6.0*lr*lr*sr*gr,  "air":    6.0*gr*gr*sr*lr,
        "mud":      6.0*sr*sr*lr*lr,  "dust":  6.0*sr*sr*gr*gr,  "cloud":  6.0*lr*lr*gr*gr,
        "dirt":     4.0*sr*sr*sr*lr,  "sand":  4.0*sr*sr*sr*gr,
        "haze":     4.0*gr*gr*gr*sr,  "mist":  4.0*gr*gr*gr*lr,
        "ooze":     4.0*lr*lr*lr*sr,  "foam":  4.0*lr*lr*lr*gr,
    }
    var total_prob = 0.0
    for k in dist: total_prob += dist[k]
    if total_prob <= 0.0: return
    var amt_f = amount.to_float()
    var assigned = BigNum.zero()
    var largest_key = ""
    var largest_val = 0
    # Floor each variety's share to integer
    var int_shares: Dictionary = {}
    for k in dist:
        var frac = dist[k] / total_prob
        if frac <= 0.0: continue
        var count = _safe_int(amt_f * frac)
        if count <= 0: continue
        int_shares[k] = count
        assigned = assigned.add(BigNum.from_int(count))
        if count > largest_val:
            largest_val = count
            largest_key = k
    # Remainder from flooring goes to the largest variety
    var remainder = amount.sub(assigned)
    if not remainder.is_zero() and largest_key != "":
        int_shares[largest_key] = int_shares.get(largest_key, 0) + remainder.to_int()
    # Apply to pools
    for k in int_shares:
        var gained = BigNum.from_int(int_shares[k])
        gc.tetrad[k] = gc.tetrad[k].add(gained)
        gc.add_to_total(k, gained)


func _spend_tetrads_true_random(count: int, available: Array) -> void:
    for i in count:
        var pool = []
        for k in available:
            if not gc.tetrad[k].is_zero(): pool.append(k)
        if pool.is_empty(): break
        var key = pool[gc.rng.randi_range(0, pool.size() - 1)]
        gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(1))


func _spend_tetrads_simplex(tetrad_cost: BigNum, available: Array) -> void:
    var weights    = _random_weights(available.size())
    var pool_total = gc.get_tetrad_unlocked_total()
    var tf         = pool_total.to_float()
    var actually_spent = BigNum.zero()
    for i in available.size():
        var k           = available[i]
        var ratio       = weights[i]
        var max_ratio   = gc.tetrad[k].to_float() / tf if tf > 0.0 else 0.0
        var spend_ratio = min(ratio, max_ratio)
        if spend_ratio <= 0.0: continue
        var spend_target = BigNum.from_int(_safe_int(tetrad_cost.to_float() * spend_ratio))
        var spend = _clamped_sub(gc.tetrad[k], spend_target)
        gc.tetrad[k] = gc.tetrad[k].sub(spend)
        actually_spent = actually_spent.add(spend)
    # Reconcile floor rounding shortfall against largest available tetrad pool
    var remainder = tetrad_cost.sub(actually_spent)
    if remainder.is_zero(): return
    var largest_key = ""
    var largest_val = BigNum.zero()
    for k in available:
        if gc.tetrad[k].is_greater_than(largest_val):
            largest_val = gc.tetrad[k]
            largest_key = k
    if largest_key != "" and gc.tetrad[largest_key].is_greater_or_equal(remainder):
        gc.tetrad[largest_key] = gc.tetrad[largest_key].sub(remainder)

func _batch_spend_monads(amount: BigNum) -> void:
    var pool = []
    var _one = BigNum.from_int(1)
    for k in ["solid", "liquid", "gas"]:
        if not gc.is_locked("monad_" + k) and gc.monad[k].is_greater_or_equal(_one):
            pool.append(k)
    if pool.is_empty(): return

    var amt_i = amount.to_int()
    if amt_i <= 0: return

    if amt_i <= RANDOM_DRAW_THRESHOLD:
        # True random: equal 1/n chance per draw, rebuild pool when a type empties
        var totals = {}
        for k in pool: totals[k] = 0
        for i in amt_i:
            var active = []
            for k in pool:
                if gc.monad[k].is_greater_than(BigNum.from_int(totals.get(k, 0))):
                    active.append(k)
            if active.is_empty(): break
            var key = active[gc.rng.randi_range(0, active.size() - 1)]
            totals[key] += 1
        for k in totals:
            if totals[k] > 0:
                gc.monad[k] = gc.monad[k].sub(BigNum.from_int(totals[k]))
    else:
        # Large batch: equal split across available types. Any remainder from
        # a per-type shortfall goes entirely to the largest-balance pool in
        # one BigNum op — matching _spend_tetrads_simplex's pattern below —
        # instead of distributing it one unit at a time. Purity-locked play
        # routinely leaves pools lopsided by design (e.g. concentrating on
        # Solid for Sand-heavy recipes), and unit-at-a-time distribution
        # against a large shortfall could iterate an unbounded number of
        # times — effectively hanging the game on a single production tick.
        var n = pool.size()
        var per_type = amount.div_int_floor(n)
        var actually_spent = BigNum.zero()
        for k in pool:
            var spend = _clamped_sub(gc.monad[k], per_type)
            gc.monad[k] = gc.monad[k].sub(spend)
            actually_spent = actually_spent.add(spend)
        var remainder = amount.sub(actually_spent)
        if not remainder.is_zero():
            var largest_key = ""
            var largest_val = BigNum.zero()
            for k in pool:
                if gc.monad[k].is_greater_than(largest_val):
                    largest_val = gc.monad[k]
                    largest_key = k
            if largest_key != "":
                var extra_spend = _clamped_sub(gc.monad[largest_key], remainder)
                gc.monad[largest_key] = gc.monad[largest_key].sub(extra_spend)


# ==================================================
# MANUAL ACTIONS — called by RootUI button handlers
# ==================================================
func manual_summon_spark(amount: int = 1) -> bool:
    _produce_sparks_summon(BigNum.from_int(maxi(1, amount)))
    return true
    
    
func get_sparks_multiplier() -> float:
    var cd: Node = get_node_or_null("/root/ConstellationData")
    var constellation_mult: float = 1.0
    if cd and cd.has_method("get_active_level_bonus"):
        constellation_mult = cd.get_active_level_bonus("sparks_multiplier")
    var ar: Node = get_node_or_null("/root/AchievementRegistry")
    var achievement_mult: float = 1.0
    if ar and ar.has_method("get_total_multiplier"):
        achievement_mult = ar.get_total_multiplier("spark_summon_mult")
    return constellation_mult * achievement_mult


func manual_monad_compress() -> bool:
    if gc.get_storage_total().is_greater_or_equal(gc.get_effective_storage_cap()):
        return false
    if not gc.spend_sparks(_recipe_cost("monad_compress", "sparks")): return false
    _roll_monad()
    return true


func manual_tetrad_assemble() -> bool:
    return _try_assemble_tetrad()


func manual_particle_compress() -> bool:
    var tetrad_cost: int = _recipe_cost("particle_compress", "tetrad")
    # First pass: total availability check
    var total_available := BigNum.zero()
    for t in gc.tetrad:
        if not gc.is_locked(t):
            total_available = total_available.add(gc.tetrad[t])
    if total_available.is_less_than(BigNum.from_int(tetrad_cost)): return false

    # Draw tetrad_cost tetrads, rebuilding the eligible pool each step to
    # respect per-type stock as we accumulate draws — matching
    # the same pattern used by _try_assemble_tetrad for monads.
    var drawn = {}
    for j in tetrad_cost:
        var remaining_pool = []
        for t in gc.tetrad:
            if not gc.is_locked(t):
                var already_drawn: int = drawn.get(t, 0)
                if gc.tetrad[t].is_greater_than(BigNum.from_int(already_drawn)):
                    remaining_pool.append(t)
        if remaining_pool.is_empty(): return false
        var key = remaining_pool[gc.rng.randi_range(0, remaining_pool.size() - 1)]
        drawn[key] = drawn.get(key, 0) + 1

    # Spend and produce — draw is already validated by construction
    for key in drawn:
        gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(drawn[key]))
    gc.particle = gc.particle.add(BigNum.from_int(1))
    gc.add_to_total("particle", BigNum.one())
    return true


func manual_iota_assemble() -> bool:
    return _try_assemble_iota()


func manual_mote_compress() -> bool:
    if gc.is_locked("iota"): return false
    if not gc.spend_iota(_recipe_cost("mote_compress", "iota")): return false
    gc.mote = gc.mote.add(BigNum.from_int(1))
    gc.add_to_total("mote", BigNum.one())
    return true


func manual_grain_assemble() -> bool:
    return _try_assemble_grain()


# ==================================================
# DEV TOOL — skip forward by injecting 10 Grains
# Adds the correct totals_created credit for every tier
# consumed in producing 10 Grains, then injects the
# Grains directly into live storage.
# Tetrad credits are distributed at the exact multinomial
# probability for uniform 1/3 S/L/G monad draws (denom 81),
# scaled to 4800 total tetrads consumed.
# Does NOT require any resources to be present;
# purely additive — safe to call at any game state.
# ==================================================
func dev_inject_ten_grains() -> void:
    if not gc:
        return

    # ── Tier counts consumed to produce 10 Grains ──────────────
    # grain_assemble:    25 sparks + 64 monad + 16 particle + 4 mote  per grain
    # mote_compress:     5 iota                                         per mote
    # iota_assemble:     5 sparks + 16 monad + 4 particle               per iota
    # particle_compress: 5 tetrad                                        per particle
    #
    # 10 grain → 40 mote → 200 iota → 960 particle → 4800 tetrad
    const GRAINS_TO_INJECT:   int = 10
    const MOTES_PRODUCED:     int = 40
    const IOTAS_PRODUCED:     int = 200
    const PARTICLES_PRODUCED: int = 960

    # ── Credit totals_created for grain/mote/iota/particle ─────
    gc.add_to_total("grain",    BigNum.from_int(GRAINS_TO_INJECT))
    gc.add_to_total("mote",     BigNum.from_int(MOTES_PRODUCED))
    gc.add_to_total("iota",     BigNum.from_int(IOTAS_PRODUCED))
    gc.add_to_total("particle", BigNum.from_int(PARTICLES_PRODUCED))
    gc.add_to_total("monad_solid",  BigNum.from_int(1280))
    gc.add_to_total("monad_liquid", BigNum.from_int(1280))
    gc.add_to_total("monad_gas",    BigNum.from_int(1280))

    # ── Tetrad credits at correct multinomial proportions ───────
    # Uniform 1/3 S/L/G monad draw, 4 draws per tetrad → denominator 81.
    # 4800 tetrads total. floori(4800 × k/81) per variety;
    # remainder 21 distributed as +7 each to earth/water/air (highest-prob medials).
    #
    #  1/81 each: adaemant aquae aethyr             → 59  each
    # 12/81 each: earth water air                   → 715 each  (708 + 7 remainder)
    #  6/81 each: mud dust cloud                    → 354 each
    #  4/81 each: dirt sand haze mist ooze foam     → 236 each
    gc.add_to_total("adaemant", BigNum.from_int(59))
    gc.add_to_total("aquae",    BigNum.from_int(59))
    gc.add_to_total("aethyr",   BigNum.from_int(59))
    gc.add_to_total("earth",    BigNum.from_int(715))
    gc.add_to_total("water",    BigNum.from_int(715))
    gc.add_to_total("air",      BigNum.from_int(715))
    gc.add_to_total("mud",      BigNum.from_int(354))
    gc.add_to_total("dust",     BigNum.from_int(354))
    gc.add_to_total("cloud",    BigNum.from_int(354))
    gc.add_to_total("dirt",     BigNum.from_int(236))
    gc.add_to_total("sand",     BigNum.from_int(236))
    gc.add_to_total("haze",     BigNum.from_int(236))
    gc.add_to_total("mist",     BigNum.from_int(236))
    gc.add_to_total("ooze",     BigNum.from_int(236))
    gc.add_to_total("foam",     BigNum.from_int(236))

    # ── Inject Grains into live storage ────────────────────────
    gc.grain = gc.grain.add(BigNum.from_int(GRAINS_TO_INJECT))
    gc.grains_this_cycle = mini(gc.grains_this_cycle + GRAINS_TO_INJECT, 20)

    print("=== DEV: Injected %d Grains | grains_this_cycle=%d ===" % [
        GRAINS_TO_INJECT, gc.grains_this_cycle
    ])


func manual_create_uonite() -> bool:
    # Guard: need at least mote_cost mote, sparks_cost sparks, and headroom
    # in the cycle cap.
    var mote_cost:   int = _recipe_cost("uonite_assemble", "mote")
    var sparks_cost: int = _recipe_cost("uonite_assemble", "sparks")
    if gc.mote.is_less_than(BigNum.from_int(mote_cost)): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)):  return false
    var headroom: int = gc.get_uonite_cycle_cap() - gc.uonites_this_cycle
    if headroom <= 0: return false
    # Batch: create as many uonites as mote, sparks, and cap headroom allow.
    var possible_by_mote:   int = gc.mote.div_int_floor(mote_cost).to_int()
    var possible_by_sparks: int = gc.sparks.div_int_floor(sparks_cost).to_int()
    var count: int = mini(possible_by_mote, mini(possible_by_sparks, headroom))
    if count <= 0: return false
    gc.mote   = gc.mote.sub(BigNum.from_int(count * mote_cost))
    gc.sparks = gc.sparks.sub(BigNum.from_int(count * sparks_cost))
    gc.uonite = gc.uonite.add(BigNum.from_int(count))
    gc.add_to_total("uonite", BigNum.from_int(count))
    gc.uonites_this_cycle    += count
    gc.refinements_completed += count
    gc.motes_this_cycle       = 0
    return true


# ==================================================
# SINGLE-UNIT ASSEMBLY HELPERS (used by manual actions)
# ==================================================
## Draws `count` monads one at a time from `candidate_keys`, rebuilding the
## remaining-stock pool on every draw against LIVE gc.monad values so a type
## running low mid-draw can never be over-drawn. Returns the drawn
## composition (e.g. ["solid","solid","liquid","gas"]) on success, or an
## empty array if the pool runs dry before `count` draws complete.
##
## Shared 2026-07-27 by _try_assemble_tetrad and _assemble_tetrads_true_random
## — both used to hand-roll this exact loop independently, and both
## independently had (and were fixed for) the same over-draw bug when it
## used a single static pool built once instead of rebuilding per draw. Keep
## this the one place that logic lives; don't re-inline it at a new call site.
##
## `candidate_keys` must already be lock-filtered by the caller — locks can't
## change mid-call (synchronous, no yields), so callers filter once up front
## rather than re-checking gc.is_locked() on every draw.
func _draw_monad_composition(count: int, candidate_keys: Array) -> Array:
    var drawn: Array = []
    for i in count:
        var remaining_pool: Array = []
        for k in candidate_keys:
            if not gc.monad[k].is_less_than(BigNum.from_int(drawn.count(k) + 1)):
                remaining_pool.append(k)
        if remaining_pool.is_empty():
            return []
        drawn.append(remaining_pool[gc.rng.randi_range(0, remaining_pool.size() - 1)])
    return drawn


func _try_assemble_tetrad() -> bool:
    var sparks_cost: int = _recipe_cost("tetrad_assemble", "sparks")
    var monad_draws: int = _recipe_cost("tetrad_assemble", "monad")
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    var candidate_keys = []
    if not gc.is_locked("monad_solid")  and not gc.monad["solid"].is_zero():  candidate_keys.append("solid")
    if not gc.is_locked("monad_liquid") and not gc.monad["liquid"].is_zero(): candidate_keys.append("liquid")
    if not gc.is_locked("monad_gas")    and not gc.monad["gas"].is_zero():    candidate_keys.append("gas")
    if candidate_keys.is_empty(): return false
    var drawn = _draw_monad_composition(monad_draws, candidate_keys)
    if drawn.is_empty(): return false
    var s = drawn.count("solid")
    var l = drawn.count("liquid")
    var g = drawn.count("gas")
    if gc.monad["solid"].is_less_than(BigNum.from_int(s))  or \
       gc.monad["liquid"].is_less_than(BigNum.from_int(l)) or \
       gc.monad["gas"].is_less_than(BigNum.from_int(g)):
        return false
    var result = _resolve_tetrad(s, l, g)
    if result == "": return false
    gc.spend_sparks(sparks_cost)
    gc.spend_monad(s, l, g)
    gc.tetrad[result] = gc.tetrad[result].add(BigNum.from_int(1))
    gc.add_to_total(result, BigNum.one())
    if not gc.assignments.get("tetrad_ever_produced", false):
        gc.assignments["tetrad_ever_produced"] = true
    return true


func _try_assemble_iota() -> bool:
    var sparks_cost:   int = _recipe_cost("iota_assemble", "sparks")
    var monad_cost:    int = _recipe_cost("iota_assemble", "monad")
    var particle_cost: int = _recipe_cost("iota_assemble", "particle")
    if gc.is_locked("sparks") or gc.is_locked("particle"): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(monad_cost)): return false
    if gc.particle.is_less_than(BigNum.from_int(particle_cost)): return false
    if not _draw_monads(monad_cost): return false
    gc.spend_sparks(sparks_cost)
    gc.spend_particle(particle_cost)
    gc.iota = gc.iota.add(BigNum.from_int(1))
    gc.add_to_total("iota", BigNum.one())
    return true


func _try_assemble_grain() -> bool:
    var sparks_cost:   int = _recipe_cost("grain_assemble", "sparks")
    var monad_cost:    int = _recipe_cost("grain_assemble", "monad")
    var particle_cost: int = _recipe_cost("grain_assemble", "particle")
    var mote_cost:     int = _recipe_cost("grain_assemble", "mote")
    if gc.is_locked("sparks") or gc.is_locked("particle") or gc.is_locked("mote"): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(monad_cost)): return false
    if gc.particle.is_less_than(BigNum.from_int(particle_cost)): return false
    if gc.mote.is_less_than(BigNum.from_int(mote_cost)): return false
    if not _draw_monads(monad_cost): return false
    gc.spend_sparks(sparks_cost)
    gc.spend_particle(particle_cost)
    gc.spend_mote(mote_cost)
    gc.grain = gc.grain.add(BigNum.from_int(1))
    gc.add_to_total("grain", BigNum.one())
    gc.grains_this_cycle = mini(gc.grains_this_cycle + 1, 20)
    return true


func _resolve_tetrad(s: int, l: int, g: int) -> String:
    # Partition table for exactly 4 draws — tied to tetrad_assemble's
    # RECIPES monad cost (see _try_assemble_tetrad's monad_draws), not an
    # independent constant. If that recipe cost ever changes, this table
    # needs to change with it.
    if s == 4: return "adaemant"
    if l == 4: return "aquae"
    if g == 4: return "aethyr"
    if s == 2 and l == 1 and g == 1: return "earth"
    if l == 2 and s == 1 and g == 1: return "water"
    if g == 2 and s == 1 and l == 1: return "air"
    if s == 2 and l == 2: return "mud"
    if s == 2 and g == 2: return "dust"
    if g == 2 and l == 2: return "cloud"
    if s == 3 and l == 1: return "dirt"
    if s == 3 and g == 1: return "sand"
    if g == 3 and s == 1: return "haze"
    if g == 3 and l == 1: return "mist"
    if l == 3 and s == 1: return "ooze"
    if l == 3 and g == 1: return "foam"
    return ""


func _roll_monad() -> void:
    var unlocked = []
    for k in ["solid", "liquid", "gas"]:
        if not _monad_type_is_capped(k):
            unlocked.append(k)
    if unlocked.is_empty(): return
    var key = unlocked[gc.rng.randi_range(0, unlocked.size() - 1)]
    gc.monad[key] = gc.monad[key].add(BigNum.from_int(1))
    gc.add_to_total("monad_" + key, BigNum.one())


func _draw_monads(amount: int) -> bool:
    var _one = BigNum.from_int(1)
    var base_pool = []
    if not gc.is_locked("monad_solid")  and not gc.monad["solid"].is_less_than(_one):  base_pool.append("solid")
    if not gc.is_locked("monad_liquid") and not gc.monad["liquid"].is_less_than(_one): base_pool.append("liquid")
    if not gc.is_locked("monad_gas")    and not gc.monad["gas"].is_less_than(_one):    base_pool.append("gas")
    if base_pool.is_empty(): return false

    var drawn = {}
    for k in base_pool: drawn[k] = 0
    for i in amount:
        var remaining_pool = []
        for k in base_pool:
            if gc.monad[k].is_greater_than(BigNum.from_int(drawn[k])):
                remaining_pool.append(k)
        if remaining_pool.is_empty(): return false
        var key = remaining_pool[gc.rng.randi_range(0, remaining_pool.size() - 1)]
        drawn[key] += 1

    for key in drawn:
        if drawn[key] > 0:
            gc.monad[key] = gc.monad[key].sub(BigNum.from_int(drawn[key]))
    return true


# ==================================================
# MATH HELPERS
# ==================================================
func _random_simplex_split() -> Vector3:
    var a = gc.rng.randf()
    var b = gc.rng.randf()
    if a > b:
        var tmp = a; a = b; b = tmp
    return Vector3(a, b - a, 1.0 - b)


func _random_weights(n: int) -> Array:
    if n <= 0: return []
    if n == 1: return [1.0]
    var cuts: Array = []
    for i in n - 1:
        cuts.append(gc.rng.randf())
    cuts.sort()
    var weights: Array = []
    var prev = 0.0
    for c in cuts:
        weights.append(c - prev)
        prev = c
    weights.append(1.0 - prev)
    return weights


func _bignum_min(a: BigNum, b: BigNum) -> BigNum:
    return a if a.is_less_or_equal(b) else b


func _safe_int(f: float) -> int:
    # GDScript's int() cast does NOT clamp for floats past int64 range — it
    # wraps to garbage (confirmed: int(5e20) == -9223372036854775808, not a
    # saturated max). The simplex distribution paths below multiply an
    # unbounded late-game BigNum's to_float() by a fractional share, so a
    # large enough batch would otherwise produce a negative "count" that
    # BigNum.from_int()'s own n<=0 guard then silently zeroes out — losing
    # an entire monad/tetrad type's share for that tick.
    if f >= 9.0e18:
        return 9223372036854775807
    if f <= 0.0:
        return 0
    return int(f)


func _clamped_sub(available: BigNum, amount: BigNum) -> BigNum:
    if amount.is_greater_than(available): return available
    return amount


# ==================================================
# QUERY HELPERS — used by RootUI bars and AllocationWheel
# ==================================================
func get_per_worker_rate(op: String) -> float:
    var interval: float = get_timer_intervals().get(op, 1.0)
    if interval <= 0.0: return 0.0
    return 1.0 / interval


func get_workers_needed_for_resource(resource_key: String, producer_op: String) -> float:
    if not gc: return 0.0
    var drain:      float = get_resource_drain_per_second(resource_key)
    var production: float = gc.rates[producer_op].to_float() if gc.rates.has(producer_op) else 0.0
    if production >= drain: return 0.0
    var per_worker: float = get_per_worker_rate(producer_op)
    if per_worker <= 0.0: return 0.0
    return (drain - production) / per_worker


func get_timer_intervals() -> Dictionary:
    var base: Dictionary = {
        "sparks_summon":     TIMER_SPARKS,
        "monad_compress":    TIMER_MONAD,
        "tetrad_assemble":   TIMER_TETRAD,
        "particle_compress": TIMER_PARTICLE,
        "iota_assemble":     TIMER_IOTA,
        "mote_compress":     TIMER_MOTE,
        "grain_assemble":    TIMER_GRAIN,
        "uonite_create":     TIMER_UONITE,
    }
    if not gc:
        return base
    var target_ops = gc.get("hourglass_target_ops")
    if not target_ops is Array or (target_ops as Array).is_empty():
        return base
    var cd: Node = get_node_or_null("/root/ConstellationData")
    if not cd or not cd.has_method("get_active_level_bonus"):
        return base
    var mult: float = cd.get_active_level_bonus("cooldown_multiplier")
    if mult >= 1.0:
        return base
    for op in (target_ops as Array):
        if base.has(op):
            base[op] = base[op] * mult
    return base


func get_consumption_network() -> Dictionary:
    # Built by inverting game_data.RECIPES (op -> inputs) into a resource ->
    # consumers view. "uonite_assemble" is translated to "uonite_create"
    # since RECIPES uses the data/display name while gc.rates/timers use the
    # internal timer op name — same op, two names, preserved from the old
    # hand-written version of this function.
    var network: Dictionary = {}
    for key in game_data.RESOURCES:
        network[key] = []
    for op in game_data.RECIPES:
        var rate_op: String = "uonite_create" if op == "uonite_assemble" else op
        var inputs: Dictionary = game_data.RECIPES[op]["inputs"]
        for input_key in inputs:
            if not network.has(input_key):
                network[input_key] = []
            network[input_key].append({"op": rate_op, "cost": inputs[input_key]})
    return network


func get_resource_drain_per_second(resource_key: String) -> float:
    var network = get_consumption_network()
    if not network.has(resource_key): return 0.0
    var total_drain: float = 0.0
    for entry in network[resource_key]:
        var op:   String = entry["op"]
        var cost: float  = float(entry["cost"])
        if not gc.rates.has(op): continue
        var rate: float = gc.rates[op].to_float()
        if rate <= 0.0: continue
        total_drain += rate * cost
    return total_drain


func get_potential_drain_per_second(resource_key: String) -> float:
    var network = get_consumption_network()
    if not network.has(resource_key): return 0.0
    var total_drain: float = 0.0
    for entry in network[resource_key]:
        var op:   String = entry["op"]
        var cost: float  = float(entry["cost"])
        var assigned: BigNum = gc.get_operation_total_bignum(op)
        if assigned.is_zero(): continue
        var interval: float       = get_timer_intervals().get(op, 1.0)
        var potential_rate: float = assigned.to_float() / interval
        total_drain += potential_rate * cost
    return total_drain


func update_assignment(resource_key: String, value) -> void:
    if gc: gc.assignments[resource_key] = value


func get_available_uonites() -> BigNum:
    if not gc: return BigNum.zero()
    var assigned = gc.get_total_uonites_assigned()
    if assigned.is_greater_than(gc.uonite): return BigNum.zero()
    return gc.uonite.sub(assigned)


func get_available_foci() -> int:
    if not gc: return 0
    return max(0, gc.archon_foci - gc.get_total_foci_assigned())


func get_available_volitions() -> int:
    if not gc: return 0
    return max(0, gc.volitions - gc.get_total_volitions_assigned())


func get_smoothed_rate(op: String) -> BigNum:
    if _smoothed_rates.has(op):
        return BigNum.from_float(_smoothed_rates[op])
    if gc and gc.rates.has(op):
        return gc.rates[op]
    return BigNum.zero()
    
    
func _monad_type_is_capped(key: String) -> bool:
    # Until the first Tetrad is ever produced, no Monad type may exceed 2.
    # This prevents any single type saturating before all three exist,
    # which would trigger Ascendance out of sequence.
    # Permanent flag, not live inventory — must stay off even if all
    # produced Tetrads are later consumed by higher-tier production.
    if gc.expansions > 0:
        return false
    if gc.assignments.get("tetrad_ever_produced", false):
        return false
    return gc.monad[key].is_greater_or_equal(BigNum.from_int(2))


func _monad_production_possible() -> bool:
    var any_locked = gc.is_locked("monad_solid") or gc.is_locked("monad_liquid") or gc.is_locked("monad_gas")
    for k in ["solid", "liquid", "gas"]:
        if any_locked or not _monad_type_is_capped(k):
            return true
    return false
