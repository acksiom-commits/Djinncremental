extends Node
# ================== PRODUCTION MANAGER v1.7.0 ==================
# v1.7.0: More bug stomping
# v1.6.0: Storage cap enforcement. All _produce_* functions now
#         check _get_storage_headroom() before spending any inputs.
#         particle_assemble, iota_assemble_uonite, mote_assemble_uonite, and
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
    "particle_assemble",
    "iota_assemble_uonite",
    "mote_assemble_uonite",
    "iota_assemble_grains",
    "mote_assemble_grains",
	"grain_assemble"
]

# Tier order for Stoctagon overflow — rank 0 fires first (highest tier).
# "net storage" = storage-counted inputs consumed minus 1 output produced
# (Sparks are never storage-counted — see GameContext.get_storage_total()).
# Recomputed against the current recipe shapes; the old figures here (-4/-19
# for particle_assemble/iota_assemble_uonite/mote_assemble_uonite) were left
# over from the pre-branch-split recipes and had gone stale.
const OVERFLOW_PRIORITY: Array[String] = [
    "grain_assemble",       # rank 0 — net storage: -83
    "mote_assemble_grains", # rank 1 — net storage: -59
    "mote_assemble_uonite", # rank 2 — net storage: -3
    "iota_assemble_grains", # rank 3 — net storage: -11
    "iota_assemble_uonite", # rank 4 — net storage: -3
    "particle_assemble",    # rank 5 — net storage: -3
    "tetrad_assemble",      # rank 6 — net storage: -3
]
# monad_compress is excluded: it's net +1 (creates stored resource from
# non-stored sparks) and would inflate storage above cap indefinitely.
# Monad only fires in normal mode when consolidation frees real headroom.


# ===================== GENERIC OPERATION TABLE ============
# Drives _produce_generic() for the data-driven operations. particle_assemble,
# iota_assemble_grains, and mote_assemble_grains are NOT here -- all three
# became bespoke (see _produce_particle_assemble/_produce_iota_assemble_grains/
# _produce_mote_assemble_grains) once their Tetrad draws needed weld-
# compatibility awareness, same reason monad_compress/tetrad_assemble were
# already bespoke. Inputs and output key for what's left come from
# game_data.RECIPES (single source of truth) — this table holds only the
# one thing RECIPES doesn't: which locked resources should abort production
# entirely. Deliberately NOT merged with OP_LOCK_KEYS below despite the
# similar shape — the two tables serve different call sites (_produce_generic
# vs. _op_has_inputs) and intentionally disagree for
# iota_assemble_uonite/grain_assemble; see the comment above OP_LOCK_KEYS.
const GENERIC_OPS_LOCK_KEYS = {
    "iota_assemble_uonite": ["particle"],
    "mote_assemble_uonite": ["iota_uonite"],
    "grain_assemble":       ["particle", "mote_grains"],
}

# Lock keys checked by _op_has_inputs() for every op it's ever called with,
# including the two (monad_compress, tetrad_assemble) that aren't in
# GENERIC_OPS_LOCK_KEYS at all since they use their own bespoke production
# functions. Deliberately preserves the existing inconsistency where most
# ops check no locks — this mirrors exactly what _op_has_inputs hardcoded
# before it became RECIPES-driven, not a design choice made here.
const OP_LOCK_KEYS = {
    "monad_compress":       ["sparks"],
    "tetrad_assemble":      [],
    "particle_assemble":    [],
    "iota_assemble_uonite": [],
    "mote_assemble_uonite": ["iota_uonite"],
    "iota_assemble_grains": [],
    "mote_assemble_grains": ["iota_grains"],
    "grain_assemble":       [],
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
                "sparks_summon":        _produce_sparks_summon(batch)
                "monad_compress":       _produce_monad_compress(batch)
                "tetrad_assemble":      _produce_tetrad_assemble(batch)
                "particle_assemble":    _produce_particle_assemble(batch)
                "iota_assemble_grains": _produce_iota_assemble_grains(batch)
                "mote_assemble_grains": _produce_mote_assemble_grains(batch)
                _:                      _produce_generic(op, batch)
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
        "particle":    gc.particle.copy(),
        "iota_uonite": gc.iota_uonite.copy(),
        "mote_uonite": gc.mote_uonite.copy(),
        "iota_grains": gc.iota_grains.copy(),
        "mote_grains": gc.mote_grains.copy(),
        "grain":       gc.grain.copy(),
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
            "monad_compress":       actual = _produce_monad_compress(batch)
            "tetrad_assemble":      actual = _produce_tetrad_assemble(batch)
            "particle_assemble":    actual = _produce_particle_assemble(batch)
            "iota_assemble_grains": actual = _produce_iota_assemble_grains(batch)
            "mote_assemble_grains": actual = _produce_mote_assemble_grains(batch)
            _:                      actual = _produce_generic(op, batch)
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
            "monad_compress":       actual = _produce_monad_compress(batch)
            "tetrad_assemble":      actual = _produce_tetrad_assemble(batch)
            "particle_assemble":    actual = _produce_particle_assemble(batch)
            "iota_assemble_grains": actual = _produce_iota_assemble_grains(batch)
            "mote_assemble_grains": actual = _produce_mote_assemble_grains(batch)
            _:                      actual = _produce_generic(op, batch)

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
# PRODUCE — PARTICLE (bespoke: weld-compatible Tetrad draw)
# ==================================================
## Below RANDOM_DRAW_THRESHOLD outputs: same rule as manual_particle_assemble
## -- every Particle's 4 corner Tetrads have to be pairwise weld-compatible,
## drawn via _draw_compatible_tetrads() so this is exactly the same
## constraint, not a separate approximation of it. Depletes gc.tetrad/
## gc.sparks live across the loop so later Particles in the batch see
## earlier ones' consumption. Stops early (produces fewer than `count`) if
## a compatible foursome can't be found or Sparks run out -- same
## "silently short a batch rather than partially-spend" behavior the
## existing monad/tetrad batch assemblers already have.
func _assemble_particles_true_random(count: int, tetrad_cost: int, sparks_cost: int) -> void:
    for _i in count:
        if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)):
            break
        var drawn: Dictionary = _draw_compatible_tetrads(tetrad_cost)
        if drawn.is_empty() and tetrad_cost > 0:
            break
        for key in drawn:
            gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(drawn[key]))
        gc.sparks = gc.sparks.sub(BigNum.from_int(sparks_cost))
        gc.particle = gc.particle.add(BigNum.one())
        gc.add_to_total("particle", BigNum.one())


## At/above RANDOM_DRAW_THRESHOLD outputs: same statistically-proportional
## approximation the rest of this file already accepts at scale (no
## per-unit compatibility awareness) -- reuses the existing generic
## _batch_spend_tetrads() rather than a second implementation of it.
func _assemble_particles_simplex(amount: BigNum, tetrad_cost: int, sparks_cost: int) -> void:
    gc.sparks = gc.sparks.sub(amount.mul_int(sparks_cost))
    _batch_spend_tetrads(amount.mul_int(tetrad_cost), amount)
    gc.particle = gc.particle.add(amount)
    gc.add_to_total("particle", amount)


func _produce_particle_assemble(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("sparks"):
        return BigNum.zero()
    var headroom: BigNum = _get_storage_headroom()
    if headroom.is_zero():
        return BigNum.zero()
    var tetrad_cost: int = _recipe_cost("particle_assemble", "tetrad")
    var sparks_cost: int = _recipe_cost("particle_assemble", "sparks")
    var max_by_sparks: BigNum = gc.sparks.div_int_floor(sparks_cost)
    var max_by_tetrad: BigNum = gc.get_tetrad_unlocked_total().div_int_floor(tetrad_cost)
    var actual: BigNum = _bignum_min(requested,
                _bignum_min(headroom,
                _bignum_min(max_by_sparks, max_by_tetrad)))
    if actual.is_zero():
        return BigNum.zero()

    if _should_use_true_random(actual.to_float()):
        _assemble_particles_true_random(actual.to_int(), tetrad_cost, sparks_cost)
    else:
        _assemble_particles_simplex(actual, tetrad_cost, sparks_cost)
    return actual


# ==================================================
# PRODUCE — GRAIN-BRANCH IOTA/MOTE (bespoke: weld-compatible Tetrad draw)
# ==================================================
## Same weld-compatibility rule as Particle -- every one of the batch's
## Tetrads has to pairwise match wherever real welds/overlaps occur, so
## the Grain-branch's own direct Tetrad draws (cavity-fill packing, not
## corner welds, but the same "every Monad overlap matches Type" principle)
## get the same treatment as particle_assemble rather than staying an
## unconstrained draw just because the geometry differs.
func _assemble_iota_grains_true_random(count: int, particle_cost: int, tetrad_cost: int, sparks_cost: int) -> void:
    for _i in count:
        if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)):
            break
        if gc.particle.is_less_than(BigNum.from_int(particle_cost)):
            break
        # Iota's cavity is 1 group of 8 -- see _draw_compatible_cavity_groups.
        @warning_ignore("integer_division") # tetrad_cost is always an exact multiple of 8
        var drawn: Dictionary = _draw_compatible_cavity_groups(tetrad_cost / 8)
        if drawn.is_empty():
            break
        gc.spend_particle(particle_cost)
        gc.spend_sparks(sparks_cost)
        gc.iota_grains = gc.iota_grains.add(BigNum.one())
        gc.add_to_total("iota_grains", BigNum.one())


func _assemble_iota_grains_simplex(amount: BigNum, particle_cost: int, tetrad_cost: int, sparks_cost: int) -> void:
    # Direct field subtraction, not spend_particle(int) -- that helper only
    # takes a plain int and would truncate/overflow for a late-game BigNum
    # batch this large (this is exactly the ≥1000-output tier).
    gc.particle = gc.particle.sub(amount.mul_int(particle_cost))
    gc.sparks = gc.sparks.sub(amount.mul_int(sparks_cost))
    _batch_spend_tetrads(amount.mul_int(tetrad_cost), amount)
    gc.iota_grains = gc.iota_grains.add(amount)
    gc.add_to_total("iota_grains", amount)


func _produce_iota_assemble_grains(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("particle") or gc.is_locked("sparks"):
        return BigNum.zero()
    var headroom: BigNum = _get_storage_headroom()
    if headroom.is_zero():
        return BigNum.zero()
    var particle_cost: int = _recipe_cost("iota_assemble_grains", "particle")
    var tetrad_cost:   int = _recipe_cost("iota_assemble_grains", "tetrad")
    var sparks_cost:   int = _recipe_cost("iota_assemble_grains", "sparks")
    var max_by_particle: BigNum = gc.particle.div_int_floor(particle_cost)
    var max_by_sparks:   BigNum = gc.sparks.div_int_floor(sparks_cost)
    var max_by_tetrad:   BigNum = gc.get_tetrad_unlocked_total().div_int_floor(tetrad_cost)
    var actual: BigNum = _bignum_min(requested,
                _bignum_min(headroom,
                _bignum_min(max_by_particle,
                _bignum_min(max_by_sparks, max_by_tetrad))))
    if actual.is_zero():
        return BigNum.zero()

    if _should_use_true_random(actual.to_float()):
        _assemble_iota_grains_true_random(actual.to_int(), particle_cost, tetrad_cost, sparks_cost)
    else:
        _assemble_iota_grains_simplex(actual, particle_cost, tetrad_cost, sparks_cost)
    return actual


func _assemble_mote_grains_true_random(count: int, iota_cost: int, particle_cost: int, tetrad_cost: int, sparks_cost: int) -> void:
    for _i in count:
        if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)):
            break
        if gc.particle.is_less_than(BigNum.from_int(particle_cost)):
            break
        if gc.iota_grains.is_less_than(BigNum.from_int(iota_cost)):
            break
        # Mote's cavity is 6 independent groups of 8 -- see
        # _draw_compatible_cavity_groups.
        @warning_ignore("integer_division") # tetrad_cost is always an exact multiple of 8
        var drawn: Dictionary = _draw_compatible_cavity_groups(tetrad_cost / 8)
        if drawn.is_empty():
            break
        gc.spend_iota_grains(iota_cost)
        gc.spend_particle(particle_cost)
        gc.spend_sparks(sparks_cost)
        gc.mote_grains = gc.mote_grains.add(BigNum.one())
        gc.add_to_total("mote_grains", BigNum.one())


func _assemble_mote_grains_simplex(amount: BigNum, iota_cost: int, particle_cost: int, tetrad_cost: int, sparks_cost: int) -> void:
    # Direct field subtraction, not the spend_X(int) helpers -- those only
    # take a plain int and would truncate/overflow for a late-game BigNum
    # batch this large (this is exactly the ≥1000-output tier).
    gc.iota_grains = gc.iota_grains.sub(amount.mul_int(iota_cost))
    gc.particle = gc.particle.sub(amount.mul_int(particle_cost))
    gc.sparks = gc.sparks.sub(amount.mul_int(sparks_cost))
    _batch_spend_tetrads(amount.mul_int(tetrad_cost), amount)
    gc.mote_grains = gc.mote_grains.add(amount)
    gc.add_to_total("mote_grains", amount)


func _produce_mote_assemble_grains(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("iota_grains") or gc.is_locked("particle") or gc.is_locked("sparks"):
        return BigNum.zero()
    var headroom: BigNum = _get_storage_headroom()
    if headroom.is_zero():
        return BigNum.zero()
    var iota_cost:     int = _recipe_cost("mote_assemble_grains", "iota_grains")
    var particle_cost: int = _recipe_cost("mote_assemble_grains", "particle")
    var tetrad_cost:   int = _recipe_cost("mote_assemble_grains", "tetrad")
    var sparks_cost:   int = _recipe_cost("mote_assemble_grains", "sparks")
    var max_by_iota:     BigNum = gc.iota_grains.div_int_floor(iota_cost)
    var max_by_particle: BigNum = gc.particle.div_int_floor(particle_cost)
    var max_by_sparks:   BigNum = gc.sparks.div_int_floor(sparks_cost)
    var max_by_tetrad:   BigNum = gc.get_tetrad_unlocked_total().div_int_floor(tetrad_cost)
    var actual: BigNum = _bignum_min(requested,
                _bignum_min(headroom,
                _bignum_min(max_by_iota,
                _bignum_min(max_by_particle,
                _bignum_min(max_by_sparks, max_by_tetrad)))))
    if actual.is_zero():
        return BigNum.zero()

    if _should_use_true_random(actual.to_float()):
        _assemble_mote_grains_true_random(actual.to_int(), iota_cost, particle_cost, tetrad_cost, sparks_cost)
    else:
        _assemble_mote_grains_simplex(actual, iota_cost, particle_cost, tetrad_cost, sparks_cost)
    return actual


# ==================================================
# PRODUCE — GENERIC (data-driven: iota_uonite, mote_uonite,
# iota_grains, mote_grains, grain)
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
        "particle":    gc.particle    = gc.particle.sub(amount)
        "iota_uonite": gc.iota_uonite = gc.iota_uonite.sub(amount)
        "mote_uonite": gc.mote_uonite = gc.mote_uonite.sub(amount)
        "iota_grains": gc.iota_grains = gc.iota_grains.sub(amount)
        "mote_grains": gc.mote_grains = gc.mote_grains.sub(amount)
        "grain":       gc.grain       = gc.grain.sub(amount)
        _: push_warning("ProductionManager: unknown key in _spend_resource: " + key)


func _add_resource(key: String, amount: BigNum) -> void:
    match key:
        "particle":    gc.particle    = gc.particle.add(amount)
        "iota_uonite": gc.iota_uonite = gc.iota_uonite.add(amount)
        "iota_grains": gc.iota_grains = gc.iota_grains.add(amount)
        "mote_grains": gc.mote_grains = gc.mote_grains.add(amount)
        "mote_uonite":
            gc.mote_uonite = gc.mote_uonite.add(amount)
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


# ==================================================
# TUTORIAL VARIETY BACKSTOP
# ==================================================
# The 2nd Volition is SUPPOSED to be introduced by enqueue_first_particle()
# ("Two Volitions!"), which root_ui gates on all_tetrads_done AND a Particle
# existing. But _check_volition_grant() hands out Volitions purely on
# archon_foci crossing 5 / 25 / 125, with no reference to that chain — so if
# Foci reach 25 through unrelated milestones first, Volition #2 arrives
# silently, before the dialogue that explains it.
#
# The realistic way that happens: the "All Monads — 100 of each type
# created: +1 Focus" award (root_ui's monad_all totals milestone) lands
# while the Tetrad randomiser still has not rolled all 15 varieties, since
# the rare compositions (4-of-a-kind, and the 3+1 medials) can go a long
# time unseen on pure chance.
#
# Same bug class as the Uonite reveal fixed earlier — a raw Foci threshold
# racing a dialogue chain — but fixed from the other end: rather than
# re-gating the Volition, guarantee the varieties finish first, which is
# what the intended ordering assumed all along.
#
# SELF-LIMITING TO THE TUTORIAL: it only ever acts while some variety has
# never been created. Once all 15 exist, _missing_tetrad_varieties() is
# empty forever and this is dead weight costing one dictionary scan.

## Exact monad composition (solid, liquid, gas) for each variety — the
## inverse of _resolve_tetrad's partition table, and it must be kept in step
## with it. Every partition of 4 into 3 parts appears exactly once, so this
## can force ANY variety, not just the common ones.
const TETRAD_COMPOSITIONS := {
    "adaemant": [4, 0, 0], "aquae": [0, 4, 0], "aethyr": [0, 0, 4],
    "earth":    [2, 1, 1], "water": [1, 2, 1], "air":    [1, 1, 2],
    "mud":      [2, 2, 0], "dust":  [2, 0, 2], "cloud":  [0, 2, 2],
    "dirt":     [3, 1, 0], "sand":  [3, 0, 1], "haze":   [1, 0, 3],
    "mist":     [0, 1, 3], "ooze":  [1, 3, 0], "foam":   [0, 3, 1],
}

## Window, measured the same way root_ui measures the award this races:
## the MINIMUM of the three monad totals-ever-created. Using the same metric
## is what guarantees ordering — min crosses 90 strictly before it crosses
## the 100 that triggers the Focus.
const TUTORIAL_FORCE_MIN_MONADS: int = 90
## Above this, stop trickling and force everything still missing. A big
## production batch can jump the whole window in one tick, so the trickle
## alone is not a guarantee; this is the deadline that makes it one.
const TUTORIAL_FORCE_DEADLINE_MONADS: int = 95


func _missing_tetrad_varieties() -> Array:
    var missing: Array = []
    for key in TETRAD_COMPOSITIONS:
        if gc.totals_created.get(key, BigNum.zero()).is_zero():
            missing.append(key)
    return missing


## Lowest of the three monad totals-ever-created, as an int (these are in
## the low hundreds during the tutorial, so int is safe here).
func _min_monad_total() -> int:
    var lowest: BigNum = null
    for k in ["monad_solid", "monad_liquid", "monad_gas"]:
        var v: BigNum = gc.totals_created.get(k, BigNum.zero())
        if lowest == null or v.is_less_than(lowest):
            lowest = v
    return 0 if lowest == null else lowest.to_int()


## Forces one (or, past the deadline, every) still-unseen variety, paying
## the normal recipe cost so this cannot be used as free resources. Returns
## how many it actually made.
##
## Trickles ONE per batch inside the window rather than dumping all fifteen
## at once, so the tail of the set fills in looking like ordinary luck
## instead of a visible glitch.
func _force_missing_tetrad_varieties() -> int:
    var missing: Array = _missing_tetrad_varieties()
    if missing.is_empty():
        return 0
    var monads: int = _min_monad_total()
    if monads < TUTORIAL_FORCE_MIN_MONADS:
        return 0
    var budget: int = missing.size() if monads >= TUTORIAL_FORCE_DEADLINE_MONADS else 1

    var made: int = 0
    for key in missing:
        if made >= budget:
            break
        var comp: Array = TETRAD_COMPOSITIONS[key]
        var s: int = int(comp[0])
        var l: int = int(comp[1])
        var g: int = int(comp[2])
        # Affordability, checked against the SAME guards a normal assembly
        # uses — a locked monad type or missing Sparks must block a forced
        # variety exactly as it blocks a rolled one.
        if gc.monad["solid"].is_less_than(BigNum.from_int(s)) \
                or gc.monad["liquid"].is_less_than(BigNum.from_int(l)) \
                or gc.monad["gas"].is_less_than(BigNum.from_int(g)):
            continue
        if not gc.spend_sparks(1):
            break   # out of Sparks entirely; nothing further will succeed
        if not gc.spend_monad(s, l, g):
            continue   # locked type — refunding the Spark is not worth the coupling
        gc.tetrad[key] = gc.tetrad[key].add(BigNum.one())
        gc.add_to_total(key, BigNum.one())
        made += 1
    return made


func _batch_assemble_tetrads(amount: BigNum) -> void:
    # Runs BEFORE the random assembly below, and independently of whether
    # that assembly can afford anything — the backstop's whole job is to
    # complete the set on a schedule, not to piggyback on a successful roll.
    _force_missing_tetrad_varieties()

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


## The 6 K4 edges among a Particle's 4 corners (see _build_tier in
## archai_lattice.gd: corner ci's 3 non-tip Monads each weld to a DIFFERENT
## one of the other 3 corners at a dedicated shared-Monad point -- 4
## corners, C(4,2)=6 weld points total, not one shared point for all).
const _K4_EDGES := [Vector2i(0,1), Vector2i(0,2), Vector2i(0,3), Vector2i(1,2), Vector2i(1,3), Vector2i(2,3)]
const _COMPATIBLE_DRAW_ATTEMPTS: int = 20

## Whether `variety`'s own composition has ENOUGH of each type to cover
## `needs` (type -> how many of that type are simultaneously demanded) --
## not just "has at least one", since one Tetrad's finite 4 Monads can be
## drawn on by multiple weld partners at once (e.g. a 1-Solid variety asked
## to supply Solid to two different neighbors can't -- it only has the one
## Solid Monad to give).
func _tetrad_covers_needs(variety: String, needs: Dictionary) -> bool:
    var comp: Dictionary = game_data.TETRADS[variety]
    for t in needs:
        if int(comp[t]) < int(needs[t]):
            return false
    return true

## Pre-choice availability pass: which Monad types are craftable AT ALL
## right now from live/unlocked Tetrad stock -- BINARY presence (1.0 if
## some unlocked variety in stock supplies that type, 0.0 if none do), NOT
## weighted by HOW MUCH of each type is stocked. Production stays random
## among whatever's actually available -- a type that happens to be more
## abundant must not get picked more often, or the algorithm would
## reinforce whatever's already overstocked instead of treating every
## craftable option equally. Feeds _weighted_type_pick(), which with only
## 0/1 weights reduces to a uniform roll among the available types.
## Without this pre-pass at all (the bug this fixes), grinding a single
## Monad type (e.g. all-Solid, so the only stock is Adaemant) starves
## pure-Fundament Particle output almost completely: a corner needs ALL 3
## of its incident edges to land on the ONE type Adaemant supplies, which a
## uniform roll over ALL 3 types (including the two with zero stock) only
## manages 1-in-27 per corner, ~1-in-729 for all 4 corners to align in the
## same attempt -- exactly the "not passing nearly as many pure Fundament
## particles as it should" gap.
func _monad_type_supply() -> Dictionary:
    var supply := {"s": 0.0, "l": 0.0, "g": 0.0}
    for t in gc.tetrad:
        if gc.is_locked(t):
            continue
        if not gc.tetrad[t].is_greater_than(BigNum.zero()):
            continue
        var comp: Dictionary = game_data.TETRADS[t]
        for type in _MONAD_TYPES:
            if int(comp[type]) > 0:
                supply[type] = 1.0
    return supply


## Picks among _MONAD_TYPES using `weights` (type -> 0.0/not-available or
## 1.0/available, from _monad_type_supply()) -- with binary weights this IS
## a uniform roll among whichever types are actually available, not biased
## by stock quantity. Falls back to a uniform 1-in-3 roll over ALL 3 types
## if every weight is ~0 (no relevant stock at all) -- the draw this feeds
## will fail regardless in that case, so the fallback only avoids a
## divide-by-zero, it doesn't paper over anything.
func _weighted_type_pick(weights: Dictionary) -> String:
    var total: float = 0.0
    for t in _MONAD_TYPES:
        total += maxf(float(weights.get(t, 0.0)), 0.0)
    if total <= 0.0:
        return _MONAD_TYPES[gc.rng.randi_range(0, 2)]
    var roll: float = gc.rng.randf() * total
    var acc: float = 0.0
    for t in _MONAD_TYPES:
        acc += maxf(float(weights.get(t, 0.0)), 0.0)
        if roll < acc:
            return t
    return _MONAD_TYPES[_MONAD_TYPES.size() - 1]  # float-rounding fallback


## Draws 4 Tetrads for one Particle's 4 corners, respecting the REAL K4
## weld structure verified in archai_lattice.gd's _build_tier -- each
## corner has 3 SEPARATE weld points (one per other corner) + 1 free "tip"
## slot (unconstrained at this assembly step, since nothing welds to it
## yet), consuming all 4 of that corner's own Monads. A pairwise-only check
## ("does A share >=1 type with B, independently of A's other neighbors")
## can pass a combination that's actually infeasible, since it never checks
## whether one corner's finite supply is enough to cover ALL its
## simultaneous weld demands at once -- see the worked example in the
## conversation that led to this fix.
##
## Assigns an S/L/G type to each of K4's 6 edges (the weld type between
## corners i and j) via _monad_type_supply() + _weighted_type_pick() --
## uniformly random among whichever types are actually craftable right now,
## NOT a blind roll over all 3 types regardless of stock (that starves
## pure-Fundament output whenever stock is concentrated in one type -- see
## _monad_type_supply()'s own doc) and NOT weighted by how MUCH of each
## available type is stocked either (that would keep skewing further
## toward whatever's already overstocked instead of treating every
## craftable option equally, which is the whole point of "random within
## the available resources"). Sums each corner's own 3 incident-edge types
## into a required-count dict, then draws one Tetrad per corner whose own
## composition covers its own requirement via _tetrad_covers_needs()
## (leftover Monads, if any, are free for the tip). Retries with a fresh
## edge-typing up to _COMPATIBLE_DRAW_ATTEMPTS times before giving up,
## since even an availability-correct roll can still dead-end a
## combination that a different one would satisfy. Returns the drawn
## composition (variety -> count) on success, or an empty dict on failure.
##
## `count` must be 4 -- this function IS the K4 structure, not a general
## "draw N compatible tetrads" primitive; any other count is a caller bug.
func _draw_compatible_tetrads(count: int) -> Dictionary:
    if count != 4:
        push_warning("_draw_compatible_tetrads: called with count=%d, only 4 (Particle's corners) is a valid K4 draw" % count)
        return {}

    var type_weights: Dictionary = _monad_type_supply()

    for _attempt in _COMPATIBLE_DRAW_ATTEMPTS:
        var edge_type := {}
        for e in _K4_EDGES:
            edge_type[e] = _weighted_type_pick(type_weights)

        var corner_needs: Array = [{}, {}, {}, {}]
        for e in _K4_EDGES:
            var t: String = edge_type[e]
            var vi: Vector2i = e
            corner_needs[vi.x][t] = int(corner_needs[vi.x].get(t, 0)) + 1
            corner_needs[vi.y][t] = int(corner_needs[vi.y].get(t, 0)) + 1

        var drawn := {}
        var ok := true
        for ci in range(4):
            var needs: Dictionary = corner_needs[ci]
            var pool := []
            for t in gc.tetrad:
                if gc.is_locked(t):
                    continue
                var already_drawn: int = drawn.get(t, 0)
                if not gc.tetrad[t].is_greater_than(BigNum.from_int(already_drawn)):
                    continue
                if _tetrad_covers_needs(t, needs):
                    pool.append(t)
            if pool.is_empty():
                ok = false
                break
            var key = pool[gc.rng.randi_range(0, pool.size() - 1)]
            drawn[key] = drawn.get(key, 0) + 1
        if ok:
            return drawn
    return {}


# ==================================================
# CAVITY-TETRAHEDRA WELD CONSTRAINT (Iota/Mote Grain-branch Tetrad draw)
# ==================================================
# _draw_compatible_tetrads above solves the K4 structure among a Particle's
# 4 corners (6 weld points, one per pair). Iota/Mote's cavity-fill Tetrads
# have a DIFFERENT real structure (archai_lattice.gd's build_cavity_fill
# "tetrahedra" key, verified in dev_tests' _check_cavity_tetrahedra): a
# group of 8 sharing ONE common centre point ALL AT ONCE, plus 6 boundary
# points each shared by exactly 4 of the 8 (a 3-bit-cube: pick one of 2
# values per antipodal pair, 3 pairs = 8 corners) -- not the same graph, so
# it needs its own solver, below, rather than reusing the K4 one above.

const _MONAD_TYPES := ["s", "l", "g"]

## Same count-sufficiency standard as _tetrad_covers_needs() -- `needs` here
## maps type -> how many of that type this one Tetrad's own 4 vertices
## simultaneously demand (a corner's centre and one of its own picks can
## land on the SAME type, e.g. both Solid, which needs 2 Solid Monads from
## one variety at once, not just "has >=1"). Presence-only checking passed
## combinations a variety's finite composition couldn't actually cover --
## the same bug class fixed in _draw_compatible_tetrads(), found while
## reviewing that fix.
func _tetrad_supplies(variety: String, needs: Dictionary) -> bool:
    var comp: Dictionary = game_data.TETRADS[variety]
    for t in needs:
        if int(comp[t]) < int(needs[t]):
            return false
    return true


## Draws exactly 8 Tetrads for one cavity-tetrahedra group -- respects the
## real 7-shared-point structure (1 centre shared by all 8, 6 boundary
## points shared by 4 each) rather than pairwise-only compatibility.
## Assigns a random S/L/G type to each of the 7 shared points, then draws
## one Tetrad per corner whose own composition covers the required COUNT of
## each type among that corner's own 4 points (centre + its 3 picks -- when
## two or more of those 4 coincide on the same type, that type is needed
## more than once from the SAME variety). Spends
## nothing itself -- pure planning; its only caller,
## _draw_compatible_cavity_groups(), does its own inline spending (needs to,
## for correct depletion across multiple groups -- see that function).
## Retries with a fresh random point-typing up to `attempts` times before
## giving up (a bad
## random typing, e.g. all 7 points forced to 3 different types when stock
## is thin, can dead-end a group that a different typing would satisfy).
## Returns the drawn composition (variety -> count) on success, or an
## empty dict on failure.
func _draw_compatible_cavity_group(attempts: int = 20) -> Dictionary:
    for _attempt in attempts:
        var t_centre: String = _MONAD_TYPES[gc.rng.randi_range(0, 2)]
        var t_a: Array = [_MONAD_TYPES[gc.rng.randi_range(0, 2)], _MONAD_TYPES[gc.rng.randi_range(0, 2)]]
        var t_b: Array = [_MONAD_TYPES[gc.rng.randi_range(0, 2)], _MONAD_TYPES[gc.rng.randi_range(0, 2)]]
        var t_c: Array = [_MONAD_TYPES[gc.rng.randi_range(0, 2)], _MONAD_TYPES[gc.rng.randi_range(0, 2)]]

        var drawn := {}
        var ok := true
        for a_bit in range(2):
            if not ok: break
            for b_bit in range(2):
                if not ok: break
                for c_bit in range(2):
                    var needed := {}
                    for t in [t_centre, t_a[a_bit], t_b[b_bit], t_c[c_bit]]:
                        needed[t] = int(needed.get(t, 0)) + 1
                    var pool := []
                    for t in gc.tetrad:
                        if gc.is_locked(t):
                            continue
                        var already: int = drawn.get(t, 0)
                        if not gc.tetrad[t].is_greater_than(BigNum.from_int(already)):
                            continue
                        if _tetrad_supplies(t, needed):
                            pool.append(t)
                    if pool.is_empty():
                        ok = false
                        break
                    var key = pool[gc.rng.randi_range(0, pool.size() - 1)]
                    drawn[key] = drawn.get(key, 0) + 1
        if ok:
            return drawn
    return {}


## Draws `groups` independent cavity-tetrahedra groups of 8 -- Iota needs 1
## (its single decompose level); Mote needs 6 (one per Level-1 branch; its
## own top-level 8 are Particle-scale, a different tier's material entirely,
## not drawn here). Groups don't share vertices with each other, but DO
## share the same live gc.tetrad pool, so each group's draw is spent
## immediately (unlike _draw_compatible_tetrads, which leaves spending to
## the caller) so the next group's stock check sees it depleted. If any
## group fails, everything spent by earlier groups in this same call is
## refunded and an empty dict returned -- all-or-nothing, matching every
## other assembly function's atomicity.
func _draw_compatible_cavity_groups(groups: int) -> Dictionary:
    var total := {}
    for _g in groups:
        var one_group: Dictionary = _draw_compatible_cavity_group()
        if one_group.is_empty():
            for key in total:
                gc.tetrad[key] = gc.tetrad[key].add(BigNum.from_int(int(total[key])))
            return {}
        for key in one_group:
            gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(int(one_group[key])))
            total[key] = int(total.get(key, 0)) + int(one_group[key])
    return total


func manual_particle_assemble() -> bool:
    var tetrad_cost:  int = _recipe_cost("particle_assemble", "tetrad")
    var sparks_cost:  int = _recipe_cost("particle_assemble", "sparks")
    if gc.is_locked("sparks"): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    # Cheap fast-fail before the more expensive compatible draw below --
    # necessary but not sufficient (says nothing about compatibility).
    var total_available := BigNum.zero()
    for t in gc.tetrad:
        if not gc.is_locked(t):
            total_available = total_available.add(gc.tetrad[t])
    if total_available.is_less_than(BigNum.from_int(tetrad_cost)): return false

    var drawn: Dictionary = _draw_compatible_tetrads(tetrad_cost)
    if drawn.is_empty() and tetrad_cost > 0: return false

    for key in drawn:
        gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(drawn[key]))
    gc.spend_sparks(sparks_cost)
    gc.particle = gc.particle.add(BigNum.from_int(1))
    gc.add_to_total("particle", BigNum.one())
    return true


func manual_iota_assemble_uonite() -> bool:
    return _try_assemble_iota_uonite()


func manual_mote_assemble_uonite() -> bool:
    var iota_cost:   int = _recipe_cost("mote_assemble_uonite", "iota_uonite")
    var sparks_cost: int = _recipe_cost("mote_assemble_uonite", "sparks")
    if gc.is_locked("iota_uonite") or gc.is_locked("sparks"): return false
    if gc.iota_uonite.is_less_than(BigNum.from_int(iota_cost)): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    gc.spend_iota_uonite(iota_cost)
    gc.spend_sparks(sparks_cost)
    _add_resource("mote_uonite", BigNum.one())
    return true


func manual_iota_assemble_grains() -> bool:
    return _try_assemble_iota_grains()


func manual_mote_assemble_grains() -> bool:
    return _try_assemble_mote_grains()


func manual_grain_assemble() -> bool:
    return _try_assemble_grain()


# ==================================================
# DEV TOOL — skip forward by injecting 10 Grains
# Adds the correct totals_created credit for every tier
# consumed in producing 10 Grains, then injects the
# Grains directly into live storage.
# Tetrad credits are distributed at the exact multinomial
# probability for uniform 1/3 S/L/G monad draws (denom 81),
# scaled to 7680 total tetrads consumed.
# Does NOT require any resources to be present;
# purely additive — safe to call at any game state.
# ==================================================
func dev_inject_ten_grains() -> void:
    if not gc:
        return

    # ── Tier counts consumed to produce 10 Grains ──────────────
    # grain_assemble:        25 sparks + 64 monad + 16 particle + 4 mote_grains
    # mote_assemble_grains:  4 iota_grains + 8 particle + 48 tetrad + 36 sparks  per mote_grains
    # iota_assemble_grains:  4 particle + 8 tetrad + 6 sparks                    per iota_grains
    # particle_assemble:     4 tetrad + 1 spark                                 per particle
    #
    # 10 grain → 40 mote_grains → 160 iota_grains → 1120 particle → 7680 tetrad
    const GRAINS_TO_INJECT:   int = 10
    const MOTES_PRODUCED:     int = 40
    const IOTAS_PRODUCED:     int = 160
    const PARTICLES_PRODUCED: int = 1120

    # ── Credit totals_created for grain/mote_grains/iota_grains/particle ───
    gc.add_to_total("grain",       BigNum.from_int(GRAINS_TO_INJECT))
    gc.add_to_total("mote_grains", BigNum.from_int(MOTES_PRODUCED))
    gc.add_to_total("iota_grains", BigNum.from_int(IOTAS_PRODUCED))
    gc.add_to_total("particle",    BigNum.from_int(PARTICLES_PRODUCED))
    gc.add_to_total("monad_solid",  BigNum.from_int(1280))
    gc.add_to_total("monad_liquid", BigNum.from_int(1280))
    gc.add_to_total("monad_gas",    BigNum.from_int(1280))

    # ── Tetrad credits at correct multinomial proportions ───────
    # Uniform 1/3 S/L/G monad draw, 4 draws per tetrad → denominator 81.
    # 7680 tetrads total. floori(7680 × k/81) per variety; remainder 9
    # distributed by largest fractional remainder (Hamilton's method) --
    # the 6/81 class (.888), 1/81 class (.8148), and 12/81 class (.777)
    # each have the same fraction across all their members, so each of
    # those 3 whole classes (3 members apiece) gets +1 per member, using
    # exactly 9; the 4/81 class (.259, lowest) gets nothing extra.
    #
    #  1/81 each: adaemant aquae aethyr             → 95   each (94 + 1)
    # 12/81 each: earth water air                   → 1138 each (1137 + 1)
    #  6/81 each: mud dust cloud                    → 569  each (568 + 1)
    #  4/81 each: dirt sand haze mist ooze foam     → 379  each
    gc.add_to_total("adaemant", BigNum.from_int(95))
    gc.add_to_total("aquae",    BigNum.from_int(95))
    gc.add_to_total("aethyr",   BigNum.from_int(95))
    gc.add_to_total("earth",    BigNum.from_int(1138))
    gc.add_to_total("water",    BigNum.from_int(1138))
    gc.add_to_total("air",      BigNum.from_int(1138))
    gc.add_to_total("mud",      BigNum.from_int(569))
    gc.add_to_total("dust",     BigNum.from_int(569))
    gc.add_to_total("cloud",    BigNum.from_int(569))
    gc.add_to_total("dirt",     BigNum.from_int(379))
    gc.add_to_total("sand",     BigNum.from_int(379))
    gc.add_to_total("haze",     BigNum.from_int(379))
    gc.add_to_total("mist",     BigNum.from_int(379))
    gc.add_to_total("ooze",     BigNum.from_int(379))
    gc.add_to_total("foam",     BigNum.from_int(379))

    # ── Inject Grains into live storage ────────────────────────
    gc.grain = gc.grain.add(BigNum.from_int(GRAINS_TO_INJECT))
    gc.grains_this_cycle = mini(gc.grains_this_cycle + GRAINS_TO_INJECT, 20)

    print("=== DEV: Injected %d Grains | grains_this_cycle=%d ===" % [
        GRAINS_TO_INJECT, gc.grains_this_cycle
    ])


func manual_create_uonite() -> bool:
    # Guard: need at least mote_cost mote_uonite, sparks_cost sparks, and
    # headroom in the cycle cap.
    var mote_cost:   int = _recipe_cost("uonite_assemble", "mote_uonite")
    var sparks_cost: int = _recipe_cost("uonite_assemble", "sparks")
    if gc.mote_uonite.is_less_than(BigNum.from_int(mote_cost)): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)):  return false
    var headroom: int = gc.get_uonite_cycle_cap() - gc.uonites_this_cycle
    if headroom <= 0: return false
    # Batch: create as many uonites as mote_uonite, sparks, and cap headroom allow.
    var possible_by_mote:   int = gc.mote_uonite.div_int_floor(mote_cost).to_int()
    var possible_by_sparks: int = gc.sparks.div_int_floor(sparks_cost).to_int()
    var count: int = mini(possible_by_mote, mini(possible_by_sparks, headroom))
    if count <= 0: return false
    gc.mote_uonite = gc.mote_uonite.sub(BigNum.from_int(count * mote_cost))
    gc.sparks      = gc.sparks.sub(BigNum.from_int(count * sparks_cost))
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
    # The manual path does NOT route through _batch_assemble_tetrads, so the
    # tutorial variety backstop has to be invoked here as well or a player
    # who assembles Tetrads by hand never gets it. Same manual-vs-batch
    # divergence that has bitten this file before (see manual_mote_assemble_uonite
    # skipping _add_resource's counters) — the two paths share
    # _draw_monad_composition and _resolve_tetrad but nothing else, so
    # anything added to one has to be checked against the other.
    _force_missing_tetrad_varieties()

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


func _try_assemble_iota_uonite() -> bool:
    var sparks_cost:   int = _recipe_cost("iota_assemble_uonite", "sparks")
    var particle_cost: int = _recipe_cost("iota_assemble_uonite", "particle")
    if gc.is_locked("sparks") or gc.is_locked("particle"): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    if gc.particle.is_less_than(BigNum.from_int(particle_cost)): return false
    gc.spend_sparks(sparks_cost)
    gc.spend_particle(particle_cost)
    gc.iota_uonite = gc.iota_uonite.add(BigNum.from_int(1))
    gc.add_to_total("iota_uonite", BigNum.one())
    return true


func _try_assemble_iota_grains() -> bool:
    var particle_cost: int = _recipe_cost("iota_assemble_grains", "particle")
    var tetrad_cost:   int = _recipe_cost("iota_assemble_grains", "tetrad")
    var sparks_cost:   int = _recipe_cost("iota_assemble_grains", "sparks")
    if gc.is_locked("particle") or gc.is_locked("sparks"): return false
    if gc.particle.is_less_than(BigNum.from_int(particle_cost)): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    var total_available := BigNum.zero()
    for t in gc.tetrad:
        if not gc.is_locked(t):
            total_available = total_available.add(gc.tetrad[t])
    if total_available.is_less_than(BigNum.from_int(tetrad_cost)): return false

    # Iota's cavity is 1 group of 8 (see _draw_compatible_cavity_groups) --
    # spends internally on success, nothing left to spend here.
    @warning_ignore("integer_division") # tetrad_cost is always an exact multiple of 8
    var drawn: Dictionary = _draw_compatible_cavity_groups(tetrad_cost / 8)
    if drawn.is_empty(): return false

    gc.spend_particle(particle_cost)
    gc.spend_sparks(sparks_cost)
    gc.iota_grains = gc.iota_grains.add(BigNum.from_int(1))
    gc.add_to_total("iota_grains", BigNum.one())
    return true


func _try_assemble_mote_grains() -> bool:
    var iota_cost:     int = _recipe_cost("mote_assemble_grains", "iota_grains")
    var particle_cost: int = _recipe_cost("mote_assemble_grains", "particle")
    var tetrad_cost:   int = _recipe_cost("mote_assemble_grains", "tetrad")
    var sparks_cost:   int = _recipe_cost("mote_assemble_grains", "sparks")
    if gc.is_locked("iota_grains") or gc.is_locked("particle") or gc.is_locked("sparks"): return false
    if gc.iota_grains.is_less_than(BigNum.from_int(iota_cost)): return false
    if gc.particle.is_less_than(BigNum.from_int(particle_cost)): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    var total_available := BigNum.zero()
    for t in gc.tetrad:
        if not gc.is_locked(t):
            total_available = total_available.add(gc.tetrad[t])
    if total_available.is_less_than(BigNum.from_int(tetrad_cost)): return false

    # Mote's cavity is 6 independent groups of 8 (6 Level-1 branches; its
    # own top-level 8 Particle-scale tetrahedra are the "particle" cost
    # above, not drawn here) -- spends internally on success.
    @warning_ignore("integer_division") # tetrad_cost is always an exact multiple of 8
    var drawn: Dictionary = _draw_compatible_cavity_groups(tetrad_cost / 8)
    if drawn.is_empty(): return false

    gc.spend_iota_grains(iota_cost)
    gc.spend_particle(particle_cost)
    gc.spend_sparks(sparks_cost)
    gc.mote_grains = gc.mote_grains.add(BigNum.from_int(1))
    gc.add_to_total("mote_grains", BigNum.one())
    return true


func _try_assemble_grain() -> bool:
    var sparks_cost:   int = _recipe_cost("grain_assemble", "sparks")
    var monad_cost:    int = _recipe_cost("grain_assemble", "monad")
    var particle_cost: int = _recipe_cost("grain_assemble", "particle")
    var mote_cost:     int = _recipe_cost("grain_assemble", "mote_grains")
    if gc.is_locked("sparks") or gc.is_locked("particle") or gc.is_locked("mote_grains"): return false
    if gc.sparks.is_less_than(BigNum.from_int(sparks_cost)): return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(monad_cost)): return false
    if gc.particle.is_less_than(BigNum.from_int(particle_cost)): return false
    if gc.mote_grains.is_less_than(BigNum.from_int(mote_cost)): return false
    if not _draw_monads(monad_cost): return false
    gc.spend_sparks(sparks_cost)
    gc.spend_particle(particle_cost)
    gc.spend_mote_grains(mote_cost)
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
        "sparks_summon":        TIMER_SPARKS,
        "monad_compress":       TIMER_MONAD,
        "tetrad_assemble":      TIMER_TETRAD,
        "particle_assemble":    TIMER_PARTICLE,
        "iota_assemble_uonite": TIMER_IOTA,
        "mote_assemble_uonite": TIMER_MOTE,
        "iota_assemble_grains": TIMER_IOTA,
        "mote_assemble_grains": TIMER_MOTE,
        "grain_assemble":       TIMER_GRAIN,
        "uonite_create":        TIMER_UONITE,
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
