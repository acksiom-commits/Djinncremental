extends Node
# ================== PRODUCTION MANAGER v1.4.1 ==================
# v1.4.1: Timerless continuous production via _process(delta).
#         Strict dependency-ordered production pass per frame:
#         Sparks → Monads → Tetrads → Iotas → Motes → Particles → Grains
#         Every tier's output this frame is immediately available to the next
#         tier (no timer nodes, no per-tick discrete firings).
#         gc.rates[op] now stores effective per-second production (BigNum).
#         Exponential smoothing on get_smoothed_rate() eliminates 1-frame spikes
#         (the +199 Iota flash is now permanently gone).
#         Batch logic updated to support fractional amounts for smooth continuous output.
#         get_resource_drain_per_second() no longer divides by interval.
#         Manual actions, consumption network, and get_timer_intervals() unchanged.
#
# Autoload order: GameData -> ConstellationData -> GameContext
#                 -> ProductionManager -> (scene nodes)
#
# TIMER INTERVALS (Fibonacci sequence, seconds):
#   Sparks:    1   Monad:    1   Tetrad:  2
#   Iota:      3   Mote:     5   Particle: 8
#   Grain:    13   Uonite:  21

# ===================== TIMER INTERVALS ====================
const TIMER_SPARKS:    float = 1.0
const TIMER_MONAD:     float = 1.0
const TIMER_TETRAD:    float = 2.0
const TIMER_IOTA:      float = 3.0
const TIMER_MOTE:      float = 5.0
const TIMER_PARTICLE:  float = 8.0
const TIMER_GRAIN:     float = 13.0
const TIMER_UONITE:    float = 21.0   # reserved — automated production not yet wired

# ===================== RANDOM DRAW THRESHOLD ==============
const RANDOM_DRAW_THRESHOLD: int = 1000

# ===================== DEPENDENCY ORDER ===================
const DEPENDENCY_ORDER: Array[String] = [
    "sparks_summon",
    "monad_compress",
    "tetrad_assemble",
    "iota_compress",
    "mote_assemble",
    "particle_compress",
    "grain_assemble"
]

# ===================== NODE REFERENCES ====================
var gc: Node = null
var _smoothed_rates: Dictionary = {}   # exponential smoothing for stable UI rates
var _accum: Dictionary = {}


func _ready() -> void:
    gc = get_node_or_null("/root/GameContext")
    if not gc:
        push_error("ProductionManager: GameContext autoload not found.")
        return
    # No timer nodes anymore — production is fully continuous.
    _smoothed_rates = {}

    # --- NEW: initialize accumulators ---
    _accum = {}
    for op in DEPENDENCY_ORDER:
        _accum[op] = 0.0

# ==================================================
# CONTINUOUS PRODUCTION (timerless)
# ==================================================
func _process(delta: float) -> void:
    if not gc or delta <= 0.0:
        return

    for op in DEPENDENCY_ORDER:
        var interval: float = get_timer_intervals().get(op, 1.0)
        var assigned: BigNum = gc.get_operation_total_bignum(op)

        if assigned.is_zero():
            gc.rates[op] = BigNum.zero()
            continue

        # --- ACCUMULATE TIME INTO DISCRETE ATTEMPTS ---
        _accum[op] += (1.0 / interval) * delta

        var whole: int = int(_accum[op])

        if whole <= 0:
            gc.rates[op] = BigNum.zero()
            continue

        _accum[op] -= float(whole)

        # Batch size = assignment × number of completed attempts
        var batch: BigNum = assigned.mul_int(whole)

        var actual: BigNum = BigNum.zero()

        match op:
            "sparks_summon":     actual = _produce_sparks_summon(batch)
            "monad_compress":    actual = _produce_monad_compress(batch)
            "tetrad_assemble":   actual = _produce_tetrad_assemble(batch)
            "iota_compress":     actual = _produce_iota_compress(batch)
            "mote_assemble":     actual = _produce_mote_assemble(batch)
            "particle_compress": actual = _produce_particle_compress(batch)
            "grain_assemble":    actual = _produce_grain_assemble(batch)

        # Convert to per-second rate
        gc.rates[op] = actual.mul_float(1.0 / delta)

    # === SMOOTHED RATES — eliminates 1-frame spikes (+199 Iota flash) ===
    for op in gc.rates:
        var current_f = gc.rates[op].to_float()
        if not _smoothed_rates.has(op):
            _smoothed_rates[op] = current_f
        else:
            var alpha = 0.15
            _smoothed_rates[op] = _smoothed_rates[op] * (1.0 - alpha) + current_f * alpha

# ===================== PRODUCTION HELPERS (continuous) =====================
func _produce_sparks_summon(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    gc.sparks = gc.sparks.add(requested)
    return requested

func _produce_monad_compress(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("sparks"):
        return BigNum.zero()

    var max_by_sparks = gc.sparks.mul_float(1.0 / 5.0)
    var actual = _bignum_min(requested, max_by_sparks)
    if actual.is_zero():
        return BigNum.zero()

    gc.sparks = gc.sparks.sub(actual.mul_int(5))
    _batch_roll_monads(actual)
    return actual

func _produce_tetrad_assemble(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()

    var max_by_sparks = gc.sparks.mul_float(1.0 / 1.0)
    var max_by_monads = gc.get_monad_unlocked_total().mul_float(1.0 / 4.0)
    var actual = _bignum_min(requested, _bignum_min(max_by_sparks, max_by_monads))
    if actual.is_zero():
        return BigNum.zero()

    _batch_assemble_tetrads(actual)
    return actual

func _produce_iota_compress(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()

    var max_by_tetrads = gc.get_tetrad_unlocked_total().mul_float(1.0 / 5.0)
    var actual = _bignum_min(requested, max_by_tetrads)
    if actual.is_zero():
        return BigNum.zero()

    _batch_spend_tetrads(actual.mul_int(5), actual)
    gc.iota = gc.iota.add(actual)
    return actual

func _produce_mote_assemble(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("sparks") or gc.is_locked("iota"):
        return BigNum.zero()

    var max_by_sparks = gc.sparks.mul_float(1.0 / 5.0)
    var max_by_monads = gc.get_monad_unlocked_total().mul_float(1.0 / 16.0)
    var max_by_iota = gc.iota.mul_float(1.0 / 4.0)
    var actual = _bignum_min(requested,
                       _bignum_min(max_by_sparks,
                       _bignum_min(max_by_monads, max_by_iota)))
    if actual.is_zero():
        return BigNum.zero()

    gc.sparks = gc.sparks.sub(actual.mul_int(5))
    _batch_spend_monads(actual.mul_int(16))
    gc.iota = gc.iota.sub(actual.mul_int(4))
    gc.mote = gc.mote.add(actual)
    return actual

func _produce_particle_compress(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("mote"):
        return BigNum.zero()

    var max_by_mote = gc.mote.mul_float(1.0 / 5.0)
    var actual = _bignum_min(requested, max_by_mote)
    if actual.is_zero():
        return BigNum.zero()

    gc.mote = gc.mote.sub(actual.mul_int(5))
    gc.particle = gc.particle.add(actual)
    return actual

func _produce_grain_assemble(requested: BigNum) -> BigNum:
    if requested.is_zero():
        return BigNum.zero()
    if gc.is_locked("sparks") or gc.is_locked("iota") or gc.is_locked("particle"):
        return BigNum.zero()

    var max_by_sparks = gc.sparks.mul_float(1.0 / 25.0)
    var max_by_monads = gc.get_monad_unlocked_total().mul_float(1.0 / 64.0)
    var max_by_iota = gc.iota.mul_float(1.0 / 16.0)
    var max_by_particle = gc.particle.mul_float(1.0 / 4.0)
    var actual = _bignum_min(requested,
                         _bignum_min(max_by_sparks,
                         _bignum_min(max_by_monads,
                         _bignum_min(max_by_iota, max_by_particle))))
    if actual.is_zero():
        return BigNum.zero()

    gc.sparks = gc.sparks.sub(actual.mul_int(25))
    _batch_spend_monads(actual.mul_int(64))
    gc.iota = gc.iota.sub(actual.mul_int(16))
    gc.particle = gc.particle.sub(actual.mul_int(4))
    gc.grain = gc.grain.add(actual)
    return actual

# ==================================================
# BATCH FUNCTIONS — TWO-STAGE MODEL (continuous + fractional support)
# ==================================================
func _batch_roll_monads(amount: BigNum) -> void:
    var unlocked = []
    for k in ["solid", "liquid", "gas"]:
        if not gc.is_locked("monad_" + k):
            unlocked.append(k)
    if unlocked.is_empty():
        return
    if unlocked.size() == 1:
        gc.monad[unlocked[0]] = gc.monad[unlocked[0]].add(amount)
        return

    var amt_f = amount.to_float()
    if amt_f <= float(RANDOM_DRAW_THRESHOLD) and amt_f >= 1.0:
        _roll_monads_true_random(amount.to_int(), unlocked)
    else:
        _roll_monads_simplex(amount, unlocked)

func _batch_assemble_tetrads(amount: BigNum) -> void:
    var s_avail = BigNum.zero() if gc.is_locked("monad_solid") else gc.monad["solid"]
    var l_avail = BigNum.zero() if gc.is_locked("monad_liquid") else gc.monad["liquid"]
    var g_avail = BigNum.zero() if gc.is_locked("monad_gas") else gc.monad["gas"]
    var total_monad = s_avail.add(l_avail).add(g_avail)
    var monad_cost = amount.mul_int(4)
    if total_monad.is_less_than(monad_cost):
        return
    var available_types = []
    if not s_avail.is_zero(): available_types.append("solid")
    if not l_avail.is_zero(): available_types.append("liquid")
    if not g_avail.is_zero(): available_types.append("gas")

    var amt_f = amount.to_float()
    if amt_f <= float(RANDOM_DRAW_THRESHOLD) and amt_f >= 1.0:
        _assemble_tetrads_true_random(amount.to_int(), available_types)
    else:
        _assemble_tetrads_simplex(amount, available_types, monad_cost)

func _batch_spend_tetrads(tetrad_cost: BigNum, iota_amount: BigNum) -> void:
    var available = []
    for k in gc.tetrad:
        if not gc.is_locked(k) and not gc.tetrad[k].is_zero():
            available.append(k)
    if available.is_empty():
        return

    var amt_f = iota_amount.to_float()
    if amt_f <= float(RANDOM_DRAW_THRESHOLD) and amt_f >= 1.0:
        _spend_tetrads_true_random(tetrad_cost.to_int(), available)
    else:
        _spend_tetrads_simplex(tetrad_cost, available)

# ==================== (unchanged batch sub-functions from v1.3.0) ====================
func _roll_monads_true_random(count: int, unlocked: Array) -> void:
    var totals = {}
    for k in unlocked: totals[k] = 0
    for i in count:
        var key = unlocked[gc.rng.randi_range(0, unlocked.size() - 1)]
        totals[key] += 1
    for k in unlocked:
        if totals[k] > 0:
            gc.monad[k] = gc.monad[k].add(BigNum.from_int(totals[k]))

func _roll_monads_simplex(amount: BigNum, unlocked: Array) -> void:
    match unlocked.size():
        2:
            var cut = gc.rng.randf()
            var a_amt = amount.mul_float(cut)
            var b_amt = amount.sub(a_amt)
            gc.monad[unlocked[0]] = gc.monad[unlocked[0]].add(a_amt)
            gc.monad[unlocked[1]] = gc.monad[unlocked[1]].add(b_amt)
        3:
            var split = _random_simplex_split()
            var s_amt = amount.mul_float(split.x)
            var l_amt = amount.mul_float(split.y)
            var g_amt = amount.sub(s_amt).sub(l_amt)
            gc.monad["solid"] = gc.monad["solid"].add(s_amt)
            gc.monad["liquid"] = gc.monad["liquid"].add(l_amt)
            gc.monad["gas"] = gc.monad["gas"].add(g_amt)

func _assemble_tetrads_true_random(count: int, available_types: Array) -> void:
    for i in count:
        var drawn = []
        for j in 4:
            drawn.append(available_types[gc.rng.randi_range(0, available_types.size() - 1)])
        var s = drawn.count("solid")
        var l = drawn.count("liquid")
        var g = drawn.count("gas")
        if gc.monad["solid"].is_less_than(BigNum.from_int(s)) or \
           gc.monad["liquid"].is_less_than(BigNum.from_int(l)) or \
           gc.monad["gas"].is_less_than(BigNum.from_int(g)):
            break
        if not gc.spend_sparks(1): break
        gc.spend_monad(s, l, g)
        var result = _resolve_tetrad(s, l, g)
        if result != "":
            gc.tetrad[result] = gc.tetrad[result].add(BigNum.from_int(1))

func _assemble_tetrads_simplex(amount: BigNum, available_types: Array, monad_cost: BigNum) -> void:
    var sr: float = 0.0; var lr: float = 0.0; var gr: float = 0.0
    match available_types.size():
        1:
            sr = 1.0 if available_types[0] == "solid" else 0.0
            lr = 1.0 if available_types[0] == "liquid" else 0.0
            gr = 1.0 if available_types[0] == "gas" else 0.0
        2:
            var cut = gc.rng.randf()
            var a = cut; var b = 1.0 - cut
            sr = a if available_types[0] == "solid" else (b if available_types[1] == "solid" else 0.0)
            lr = a if available_types[0] == "liquid" else (b if available_types[1] == "liquid" else 0.0)
            gr = a if available_types[0] == "gas" else (b if available_types[1] == "gas" else 0.0)
        3:
            var split = _random_simplex_split()
            sr = split.x; lr = split.y; gr = split.z
    gc.sparks = gc.sparks.sub(amount)
    gc.monad["solid"] = gc.monad["solid"].sub(_clamped_sub(gc.monad["solid"], monad_cost.mul_float(sr)))
    gc.monad["liquid"] = gc.monad["liquid"].sub(_clamped_sub(gc.monad["liquid"], monad_cost.mul_float(lr)))
    gc.monad["gas"] = gc.monad["gas"].sub(_clamped_sub(gc.monad["gas"], monad_cost.mul_float(gr)))
    _batch_distribute_tetrads(amount, sr, lr, gr)

func _batch_distribute_tetrads(amount: BigNum, sr: float, lr: float, gr: float) -> void:
    var dist = {
        "adaemant": sr*sr*sr*sr, "aquae": lr*lr*lr*lr, "aethyr": gr*gr*gr*gr,
        "earth": 6.0*sr*sr*lr*gr, "water": 6.0*lr*lr*sr*gr, "air": 6.0*gr*gr*sr*lr,
        "mud": 6.0*sr*sr*lr*lr, "dust": 6.0*sr*sr*gr*gr, "cloud": 6.0*lr*lr*gr*gr,
        "dirt": 4.0*sr*sr*sr*lr, "sand": 4.0*sr*sr*sr*gr,
        "haze": 4.0*gr*gr*gr*sr, "mist": 4.0*gr*gr*gr*lr,
        "ooze": 4.0*lr*lr*lr*sr, "foam": 4.0*lr*lr*lr*gr,
    }
    var total_prob = 0.0
    for k in dist: total_prob += dist[k]
    if total_prob <= 0.0: return
    for k in dist:
        var frac = dist[k] / total_prob
        if frac <= 0.0: continue
        var gained = amount.mul_float(frac)
        if not gained.is_zero():
            gc.tetrad[k] = gc.tetrad[k].add(gained)

func _spend_tetrads_true_random(count: int, available: Array) -> void:
    for i in count:
        var pool = []
        for k in available:
            if not gc.tetrad[k].is_zero(): pool.append(k)
        if pool.is_empty(): break
        var key = pool[gc.rng.randi_range(0, pool.size() - 1)]
        gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(1))

func _spend_tetrads_simplex(tetrad_cost: BigNum, available: Array) -> void:
    var weights = _random_weights(available.size())
    var pool_total = gc.get_tetrad_unlocked_total()
    var tf = pool_total.to_float()
    for i in available.size():
        var k = available[i]
        var ratio = weights[i]
        var max_ratio = gc.tetrad[k].to_float() / tf if tf > 0.0 else 0.0
        var spend_ratio = min(ratio, max_ratio)
        if spend_ratio <= 0.0: continue
        gc.tetrad[k] = gc.tetrad[k].sub(_clamped_sub(gc.tetrad[k], tetrad_cost.mul_float(spend_ratio)))

func _batch_spend_monads(amount: BigNum) -> void:
    var s = BigNum.zero() if gc.is_locked("monad_solid") else gc.monad["solid"]
    var l = BigNum.zero() if gc.is_locked("monad_liquid") else gc.monad["liquid"]
    var g = BigNum.zero() if gc.is_locked("monad_gas") else gc.monad["gas"]
    var total = s.add(l).add(g)
    if total.is_zero(): return
    var tf = total.to_float()
    if not gc.is_locked("monad_solid"):
        gc.monad["solid"] = gc.monad["solid"].sub(_clamped_sub(gc.monad["solid"], amount.mul_float(s.to_float() / tf)))
    if not gc.is_locked("monad_liquid"):
        gc.monad["liquid"] = gc.monad["liquid"].sub(_clamped_sub(gc.monad["liquid"], amount.mul_float(l.to_float() / tf)))
    if not gc.is_locked("monad_gas"):
        gc.monad["gas"] = gc.monad["gas"].sub(_clamped_sub(gc.monad["gas"], amount.mul_float(g.to_float() / tf)))

# ==================================================
# MANUAL ACTION ENTRY POINTS (unchanged)
# ==================================================
func manual_summon_spark() -> bool:
    gc.sparks = gc.sparks.add(BigNum.from_int(1))
    return true

func manual_monad_compress() -> bool:
    if not gc.spend_sparks(5): return false
    _roll_monad()
    return true

func manual_tetrad_assemble() -> bool:
    return _try_assemble_tetrad()

func manual_iota_compress() -> bool:
    var pool = []
    for t in gc.tetrad:
        if not gc.is_locked(t) and not gc.tetrad[t].is_zero():
            pool.append(t)
    if pool.size() < 5: return false
    var drawn = {}
    for j in 5:
        var idx = gc.rng.randi_range(0, pool.size() - 1)
        var key = pool[idx]
        drawn[key] = drawn.get(key, 0) + 1
    for key in drawn:
        if gc.tetrad[key].is_less_than(BigNum.from_int(drawn[key])): return false
    for key in drawn:
        gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(drawn[key]))
    gc.iota = gc.iota.add(BigNum.from_int(1))
    return true

func manual_particle_compress() -> bool:
    if gc.is_locked("mote"): return false
    if not gc.spend_mote(5): return false
    gc.particle = gc.particle.add(BigNum.from_int(1))
    return true

func manual_mote_assemble() -> bool:
    return _try_assemble_mote()

func manual_grain_assemble() -> bool:
    return _try_assemble_grain()

func manual_create_uonite() -> bool:
    if not gc.sparks.is_greater_or_equal(BigNum.from_int(1)): return false
    gc.sparks = gc.sparks.sub(BigNum.from_int(1))
    gc.uonite = gc.uonite.add(BigNum.from_int(100))
    gc.refinements_completed += 1
    return true

# ==================================================
# MANUAL ASSEMBLY HELPERS (unchanged)
# ==================================================
func _try_assemble_tetrad() -> bool:
    if gc.sparks.is_less_than(BigNum.from_int(1)): return false
    var pool = []
    if not gc.is_locked("monad_solid") and not gc.monad["solid"].is_zero(): pool.append("solid")
    if not gc.is_locked("monad_liquid") and not gc.monad["liquid"].is_zero(): pool.append("liquid")
    if not gc.is_locked("monad_gas") and not gc.monad["gas"].is_zero(): pool.append("gas")
    if pool.is_empty(): return false
    var drawn = []
    for i in 4:
        drawn.append(pool[gc.rng.randi_range(0, pool.size() - 1)])
    var s = drawn.count("solid")
    var l = drawn.count("liquid")
    var g = drawn.count("gas")
    if gc.monad["solid"].is_less_than(BigNum.from_int(s)) \
    or gc.monad["liquid"].is_less_than(BigNum.from_int(l)) \
    or gc.monad["gas"].is_less_than(BigNum.from_int(g)):
        return false
    var result = _resolve_tetrad(s, l, g)
    if result == "": return false
    gc.spend_sparks(1)
    gc.spend_monad(s, l, g)
    gc.tetrad[result] = gc.tetrad[result].add(BigNum.from_int(1))
    return true

func _try_assemble_mote() -> bool:
    if gc.is_locked("sparks") or gc.is_locked("iota"): return false
    if gc.sparks.is_less_than(BigNum.from_int(5)): return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(16)): return false
    if gc.iota.is_less_than(BigNum.from_int(4)): return false
    gc.spend_sparks(5)
    _draw_monads(16)
    gc.spend_iota(4)
    gc.mote = gc.mote.add(BigNum.from_int(1))
    return true

func _try_assemble_grain() -> bool:
    if gc.is_locked("sparks") or gc.is_locked("iota") or gc.is_locked("particle"): return false
    if gc.sparks.is_less_than(BigNum.from_int(25)): return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(64)): return false
    if gc.iota.is_less_than(BigNum.from_int(16)): return false
    if gc.particle.is_less_than(BigNum.from_int(4)): return false
    gc.spend_sparks(25)
    _draw_monads(64)
    gc.spend_iota(16)
    gc.spend_particle(4)
    gc.grain = gc.grain.add(BigNum.from_int(1))
    return true

func _resolve_tetrad(s: int, l: int, g: int) -> String:
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
        if not gc.is_locked("monad_" + k):
            unlocked.append(k)
    if unlocked.is_empty(): return
    var key = unlocked[gc.rng.randi_range(0, unlocked.size() - 1)]
    gc.monad[key] = gc.monad[key].add(BigNum.from_int(1))

func _draw_monads(amount: int) -> bool:
    var pool = []
    if not gc.is_locked("monad_solid") and not gc.monad["solid"].is_zero(): pool.append("solid")
    if not gc.is_locked("monad_liquid") and not gc.monad["liquid"].is_zero(): pool.append("liquid")
    if not gc.is_locked("monad_gas") and not gc.monad["gas"].is_zero(): pool.append("gas")
    if pool.is_empty(): return false
    var drawn = {}
    for i in amount:
        var key = pool[gc.rng.randi_range(0, pool.size() - 1)]
        drawn[key] = drawn.get(key, 0) + 1
    for key in drawn:
        if gc.monad[key].is_less_than(BigNum.from_int(drawn[key])): return false
    for key in drawn:
        gc.monad[key] = gc.monad[key].sub(BigNum.from_int(drawn[key]))
    return true

# ==================================================
# RANDOM WEIGHT HELPERS (unchanged)
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

# ==================================================
# UTILITY HELPERS (unchanged)
# ==================================================
func _bignum_min(a: BigNum, b: BigNum) -> BigNum:
    return a if a.is_less_or_equal(b) else b

func _clamped_sub(available: BigNum, amount: BigNum) -> BigNum:
    if amount.is_greater_than(available): return available
    return amount

# ==================================================
# TIMER INTERVAL QUERY (unchanged — for CooldownBar)
# ==================================================
func get_timer_intervals() -> Dictionary:
    return {
        "sparks_summon":     TIMER_SPARKS,
        "monad_compress":    TIMER_MONAD,
        "tetrad_assemble":   TIMER_TETRAD,
        "iota_compress":     TIMER_IOTA,
        "mote_assemble":     TIMER_MOTE,
        "particle_compress": TIMER_PARTICLE,
        "grain_assemble":    TIMER_GRAIN,
        "uonite_create":     TIMER_UONITE,
    }

# ==================================================
# CONSUMPTION NETWORK + DRAIN (updated — no interval division)
# ==================================================
func get_consumption_network() -> Dictionary:
    return {
        "sparks": [{"op": "monad_compress", "cost": 5}, {"op": "tetrad_assemble", "cost": 1},
                   {"op": "mote_assemble", "cost": 5}, {"op": "grain_assemble", "cost": 25}],
        "monad": [{"op": "tetrad_assemble", "cost": 4}, {"op": "mote_assemble", "cost": 16},
                  {"op": "grain_assemble", "cost": 64}],
        "tetrad": [{"op": "iota_compress", "cost": 5}],
        "iota": [{"op": "mote_assemble", "cost": 4}, {"op": "grain_assemble", "cost": 16}],
        "mote": [{"op": "particle_compress", "cost": 5}],
        "particle": [{"op": "grain_assemble", "cost": 4}],
        "grain": [{"op": "uonite_create", "cost": 20}],
        "uonite": [],
    }

func get_resource_drain_per_second(resource_key: String) -> float:
    var network = get_consumption_network()
    if not network.has(resource_key): return 0.0
    var total_drain: float = 0.0
    for entry in network[resource_key]:
        var op: String = entry["op"]
        var cost: float = float(entry["cost"])
        if not gc.rates.has(op): continue
        var rate: float = gc.rates[op].to_float()
        if rate <= 0.0: continue
        total_drain += rate * cost
    return total_drain

# ==================================================
# ASSIGNMENT MANAGEMENT (unchanged)
# ==================================================
func update_assignment(resource_key: String, value) -> void:
    if gc: gc.assignments[resource_key] = value

func get_assignment(resource_key: String):
    if gc: return gc.assignments.get(resource_key, 0)
    return 0

# ==================================================
# AVAILABILITY QUERIES (unchanged)
# ==================================================
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

# ==================================================
# SMOOTHED RATE ACCESS (for RootUI) — v1.4.1
# ==================================================
func get_smoothed_rate(op: String) -> BigNum:
    if _smoothed_rates.has(op):
        return BigNum.from_float(_smoothed_rates[op])
    if gc and gc.rates.has(op):
        return gc.rates[op]
    return BigNum.zero()
