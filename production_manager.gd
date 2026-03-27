extends Node
# ================== PRODUCTION MANAGER v1.1.0 ==================
# v1.1.0: Replaced all batch ratio math with stratified random sampling.
#         Monad rolls, Tetrad assembly, and Tetrad spending now use
#         fresh random splits each tick via uniform simplex sampling.
#         This makes purity locks meaningful and distribution organic.
#
# v1.0.0: Full rewrite. Owns all production logic, timers, batch
#         functions, manual action entry points, rate tracking.
#
# Autoload order: GameData -> ConstellationData -> GameContext
#                 -> ProductionManager -> (scene nodes)

# ===================== TIMER INTERVALS ====================
const TIMER_INTERVAL: float = 1.0

# ===================== NODE REFERENCES ====================
var gc: Node = null   # GameContext shorthand

var _timers: Dictionary = {}


func _ready() -> void:
    gc = get_node_or_null("/root/GameContext")
    if not gc:
        push_error("ProductionManager: GameContext autoload not found.")
        return
    _create_timers()


# ==================================================
# TIMER SETUP
# ==================================================
func _create_timers() -> void:
    var ops = [
        "sparks_summon",
        "monad_compress",
        "tetrad_assemble",
        "iota_compress",
        "mote_assemble",
        "particle_compress",
        "grain_assemble",
    ]
    for op in ops:
        var t = Timer.new()
        t.name      = op + "_timer"
        t.wait_time = TIMER_INTERVAL
        t.autostart = true
        t.timeout.connect(_get_timer_callback(op))
        add_child(t)
        _timers[op] = t


func _get_timer_callback(op: String) -> Callable:
    match op:
        "sparks_summon":     return _on_sparks_summon_timeout
        "monad_compress":    return _on_monad_compress_timeout
        "tetrad_assemble":   return _on_tetrad_assemble_timeout
        "iota_compress":     return _on_iota_compress_timeout
        "mote_assemble":     return _on_mote_assemble_timeout
        "particle_compress": return _on_particle_compress_timeout
        "grain_assemble":    return _on_grain_assemble_timeout
    push_error("ProductionManager: unknown op in _get_timer_callback: " + op)
    return func(): pass


# ==================================================
# TIMER TIMEOUT HANDLERS
# ==================================================
func _on_sparks_summon_timeout() -> void:
    var amount = gc.get_operation_total_bignum("sparks_summon")
    if amount.is_zero():
        gc.rates["sparks_summon"] = BigNum.zero()
        return
    gc.rates["sparks_summon"] = amount
    gc.sparks = gc.sparks.add(amount)


func _on_monad_compress_timeout() -> void:
    var amount = gc.get_operation_total_bignum("monad_compress")
    if amount.is_zero():
        gc.rates["monad_compress"] = BigNum.zero()
        return
    var spark_cost = amount.mul_int(5)
    if gc.is_locked("sparks") or gc.sparks.is_less_than(spark_cost):
        gc.rates["monad_compress"] = BigNum.zero()
        return
    gc.rates["monad_compress"] = amount
    gc.sparks = gc.sparks.sub(spark_cost)
    _batch_roll_monads(amount)


func _on_tetrad_assemble_timeout() -> void:
    var amount = gc.get_operation_total_bignum("tetrad_assemble")
    if amount.is_zero():
        gc.rates["tetrad_assemble"] = BigNum.zero()
        return
    gc.rates["tetrad_assemble"] = BigNum.zero()
    _batch_assemble_tetrads(amount)


func _on_iota_compress_timeout() -> void:
    var amount = gc.get_operation_total_bignum("iota_compress")
    if amount.is_zero():
        gc.rates["iota_compress"] = BigNum.zero()
        return
    var tetrad_cost = amount.mul_int(5)
    if gc.get_tetrad_unlocked_total().is_less_than(tetrad_cost):
        gc.rates["iota_compress"] = BigNum.zero()
        return
    gc.rates["iota_compress"] = amount
    _batch_spend_tetrads(tetrad_cost)
    gc.iota = gc.iota.add(amount)


func _on_mote_assemble_timeout() -> void:
    var amount = gc.get_operation_total_bignum("mote_assemble")
    if amount.is_zero():
        gc.rates["mote_assemble"] = BigNum.zero()
        return
    if gc.is_locked("sparks") or gc.is_locked("iota"):
        gc.rates["mote_assemble"] = BigNum.zero()
        return
    var spark_cost = amount.mul_int(5)
    var monad_cost = amount.mul_int(16)
    var iota_cost  = amount.mul_int(4)
    if gc.sparks.is_less_than(spark_cost) \
    or gc.get_monad_unlocked_total().is_less_than(monad_cost) \
    or gc.iota.is_less_than(iota_cost):
        gc.rates["mote_assemble"] = BigNum.zero()
        return
    gc.rates["mote_assemble"] = amount
    gc.sparks = gc.sparks.sub(spark_cost)
    _batch_spend_monads(monad_cost)
    gc.iota = gc.iota.sub(iota_cost)
    gc.mote = gc.mote.add(amount)


func _on_particle_compress_timeout() -> void:
    var amount = gc.get_operation_total_bignum("particle_compress")
    if amount.is_zero():
        gc.rates["particle_compress"] = BigNum.zero()
        return
    if gc.is_locked("mote"):
        gc.rates["particle_compress"] = BigNum.zero()
        return
    var mote_cost = amount.mul_int(5)
    if gc.mote.is_less_than(mote_cost):
        gc.rates["particle_compress"] = BigNum.zero()
        return
    gc.rates["particle_compress"] = amount
    gc.mote     = gc.mote.sub(mote_cost)
    gc.particle = gc.particle.add(amount)


func _on_grain_assemble_timeout() -> void:
    var amount = gc.get_operation_total_bignum("grain_assemble")
    if amount.is_zero():
        gc.rates["grain_assemble"] = BigNum.zero()
        return
    if gc.is_locked("sparks") or gc.is_locked("iota") or gc.is_locked("particle"):
        gc.rates["grain_assemble"] = BigNum.zero()
        return
    var spark_cost    = amount.mul_int(25)
    var monad_cost    = amount.mul_int(64)
    var iota_cost     = amount.mul_int(16)
    var particle_cost = amount.mul_int(4)
    if gc.sparks.is_less_than(spark_cost) \
    or gc.get_monad_unlocked_total().is_less_than(monad_cost) \
    or gc.iota.is_less_than(iota_cost) \
    or gc.particle.is_less_than(particle_cost):
        gc.rates["grain_assemble"] = BigNum.zero()
        return
    gc.rates["grain_assemble"] = amount
    gc.sparks = gc.sparks.sub(spark_cost)
    _batch_spend_monads(monad_cost)
    gc.iota     = gc.iota.sub(iota_cost)
    gc.particle = gc.particle.sub(particle_cost)
    gc.grain    = gc.grain.add(amount)


# ==================================================
# MANUAL ACTION ENTRY POINTS
# ==================================================
func manual_summon_spark() -> bool:
    gc.sparks = gc.sparks.add(BigNum.from_int(1))
    return true


func manual_monad_compress() -> bool:
    if not gc.spend_sparks(5):
        return false
    _roll_monad()
    return true


func manual_tetrad_assemble() -> bool:
    return _try_assemble_tetrad()


func manual_iota_compress() -> bool:
    # TODO: fix pool check -- should be total units >= 5, not distinct types >= 5
    var pool = []
    for t in gc.tetrad:
        if not gc.is_locked(t) and not gc.tetrad[t].is_zero():
            pool.append(t)
    if pool.size() < 5:
        return false
    var drawn = {}
    for j in 5:
        var idx = gc.rng.randi_range(0, pool.size() - 1)
        var key = pool[idx]
        drawn[key] = drawn.get(key, 0) + 1
    for key in drawn:
        if gc.tetrad[key].is_less_than(BigNum.from_int(drawn[key])):
            return false
    for key in drawn:
        gc.tetrad[key] = gc.tetrad[key].sub(BigNum.from_int(drawn[key]))
    gc.iota = gc.iota.add(BigNum.from_int(1))
    return true


func manual_particle_compress() -> bool:
    if gc.is_locked("mote"):
        return false
    if not gc.spend_mote(5):
        return false
    gc.particle = gc.particle.add(BigNum.from_int(1))
    return true


func manual_mote_assemble() -> bool:
    return _try_assemble_mote()


func manual_grain_assemble() -> bool:
    return _try_assemble_grain()


func manual_create_uonite() -> bool:
    # DEV HACK: 100 Uonites for 1 Spark -- replace with recipe cost before release
    if not gc.sparks.is_greater_or_equal(BigNum.from_int(1)):
        return false
    gc.sparks = gc.sparks.sub(BigNum.from_int(1))
    gc.uonite = gc.uonite.add(BigNum.from_int(100))
    gc.refinements_completed += 1
    return true


# ==================================================
# MANUAL ASSEMBLY HELPERS
# ==================================================
func _try_assemble_tetrad() -> bool:
    if gc.sparks.is_less_than(BigNum.from_int(1)):
        return false
    var pool = []
    if not gc.is_locked("monad_solid")   and not gc.monad["solid"].is_zero():   pool.append("solid")
    if not gc.is_locked("monad_liquid") and not gc.monad["liquid"].is_zero(): pool.append("liquid")
    if not gc.is_locked("monad_gas")    and not gc.monad["gas"].is_zero():    pool.append("gas")
    if pool.is_empty():
        return false
    var drawn = []
    for i in 4:
        drawn.append(pool[gc.rng.randi_range(0, pool.size() - 1)])
    var s = drawn.count("solid")
    var l = drawn.count("liquid")
    var g = drawn.count("gas")
    if gc.monad["solid"].is_less_than(BigNum.from_int(s))   \
    or gc.monad["liquid"].is_less_than(BigNum.from_int(l)) \
    or gc.monad["gas"].is_less_than(BigNum.from_int(g)):
        return false
    var result = _resolve_tetrad(s, l, g)
    if result == "":
        return false
    gc.spend_sparks(1)
    gc.spend_monad(s, l, g)
    gc.tetrad[result] = gc.tetrad[result].add(BigNum.from_int(1))
    return true


func _try_assemble_mote() -> bool:
    if gc.is_locked("sparks") or gc.is_locked("iota"):
        return false
    if gc.sparks.is_less_than(BigNum.from_int(5)):
        return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(16)):
        return false
    if gc.iota.is_less_than(BigNum.from_int(4)):
        return false
    gc.spend_sparks(5)
    _draw_monads(16)
    gc.spend_iota(4)
    gc.mote = gc.mote.add(BigNum.from_int(1))
    return true


func _try_assemble_grain() -> bool:
    if gc.is_locked("sparks") or gc.is_locked("iota") or gc.is_locked("particle"):
        return false
    if gc.sparks.is_less_than(BigNum.from_int(25)):
        return false
    if gc.get_monad_unlocked_total().is_less_than(BigNum.from_int(64)):
        return false
    if gc.iota.is_less_than(BigNum.from_int(16)):
        return false
    if gc.particle.is_less_than(BigNum.from_int(4)):
        return false
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


# ==================================================
# BATCH FUNCTIONS (automated timer paths)
# Production uses stratified random sampling so the
# distribution is random each tick, not determined by
# current pool ratios. Spending uses pool ratios since
# that correctly reflects what you actually have.
# ==================================================

func _batch_roll_monads(amount: BigNum) -> void:
    var unlocked = []
    for k in ["solid", "liquid", "gas"]:
        if not gc.is_locked("monad_" + k):
            unlocked.append(k)
    if unlocked.is_empty():
        return
    match unlocked.size():
        1:
            gc.monad[unlocked[0]] = gc.monad[unlocked[0]].add(amount)
        2:
            var cut   = gc.rng.randf()
            var a_amt = amount.mul_float(cut)
            var b_amt = amount.sub(a_amt)
            gc.monad[unlocked[0]] = gc.monad[unlocked[0]].add(a_amt)
            gc.monad[unlocked[1]] = gc.monad[unlocked[1]].add(b_amt)
        3:
            var split = _random_simplex_split()
            var s_amt = amount.mul_float(split.x)
            var l_amt = amount.mul_float(split.y)
            var g_amt = amount.sub(s_amt).sub(l_amt)
            gc.monad["solid"]  = gc.monad["solid"].add(s_amt)
            gc.monad["liquid"] = gc.monad["liquid"].add(l_amt)
            gc.monad["gas"]    = gc.monad["gas"].add(g_amt)


func _batch_assemble_tetrads(amount: BigNum) -> void:
    if gc.sparks.is_less_than(amount):
        return
    var s_avail = BigNum.zero() if gc.is_locked("monad_solid")   else gc.monad["solid"]
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

    # Fresh random split across available types this tick
    var sr: float = 0.0
    var lr: float = 0.0
    var gr: float = 0.0
    match available_types.size():
        1:
            sr = 1.0 if available_types[0] == "solid"   else 0.0
            lr = 1.0 if available_types[0] == "liquid" else 0.0
            gr = 1.0 if available_types[0] == "gas"    else 0.0
        2:
            var cut = gc.rng.randf()
            var a   = cut
            var b   = 1.0 - cut
            sr = a if available_types[0] == "solid"   else (b if available_types[1] == "solid"   else 0.0)
            lr = a if available_types[0] == "liquid" else (b if available_types[1] == "liquid" else 0.0)
            gr = a if available_types[0] == "gas"    else (b if available_types[1] == "gas"    else 0.0)
        3:
            var split = _random_simplex_split()
            sr = split.x
            lr = split.y
            gr = split.z

    gc.sparks = gc.sparks.sub(amount)
    gc.monad["solid"]  = gc.monad["solid"].sub(monad_cost.mul_float(sr))
    gc.monad["liquid"] = gc.monad["liquid"].sub(monad_cost.mul_float(lr))
    gc.monad["gas"]    = gc.monad["gas"].sub(monad_cost.mul_float(gr))
    gc.rates["tetrad_assemble"] = amount
    _batch_distribute_tetrads(amount, sr, lr, gr)


func _batch_distribute_tetrads(amount: BigNum, sr: float, lr: float, gr: float) -> void:
    var dist = {
        "adaemant": sr*sr*sr*sr,        "aquae":  lr*lr*lr*lr,        "aethyr": gr*gr*gr*gr,
        "earth":    6.0*sr*sr*lr*gr,    "water":  6.0*lr*lr*sr*gr,    "air":    6.0*gr*gr*sr*lr,
        "mud":      6.0*sr*sr*lr*lr,    "dust":   6.0*sr*sr*gr*gr,    "cloud":  6.0*lr*lr*gr*gr,
        "dirt":     4.0*sr*sr*sr*lr,    "sand":   4.0*sr*sr*sr*gr,    "haze":   4.0*gr*gr*gr*sr,
        "mist":     4.0*gr*gr*gr*lr,    "ooze":   4.0*lr*lr*lr*sr,    "foam":   4.0*lr*lr*lr*gr,
    }
    var total_prob = 0.0
    for k in dist:
        total_prob += dist[k]
    if total_prob <= 0.0:
        return
    for k in dist:
        var frac = dist[k] / total_prob
        if frac <= 0.0:
            continue
        var gained = amount.mul_float(frac)
        if not gained.is_zero():
            gc.tetrad[k] = gc.tetrad[k].add(gained)


func _batch_spend_tetrads(amount: BigNum) -> void:
    var pool_total = gc.get_tetrad_unlocked_total()
    if pool_total.is_zero():
        return
    var available = []
    for k in gc.tetrad:
        if not gc.is_locked(k) and not gc.tetrad[k].is_zero():
            available.append(k)
    if available.is_empty():
        return
    var weights = _random_weights(available.size())
    var tf = pool_total.to_float()
    for i in available.size():
        var k           = available[i]
        var ratio       = weights[i]
        var max_ratio   = gc.tetrad[k].to_float() / tf if tf > 0.0 else 0.0
        var spend_ratio = min(ratio, max_ratio)
        if spend_ratio <= 0.0:
            continue
        gc.tetrad[k] = gc.tetrad[k].sub(amount.mul_float(spend_ratio))


func _batch_spend_monads(amount: BigNum) -> void:
    var s = BigNum.zero() if gc.is_locked("monad_solid")   else gc.monad["solid"]
    var l = BigNum.zero() if gc.is_locked("monad_liquid") else gc.monad["liquid"]
    var g = BigNum.zero() if gc.is_locked("monad_gas")    else gc.monad["gas"]
    var total = s.add(l).add(g)
    if total.is_zero():
        return
    var tf = total.to_float()
    if not gc.is_locked("monad_solid"):
        gc.monad["solid"]  = gc.monad["solid"].sub(amount.mul_float(s.to_float() / tf))
    if not gc.is_locked("monad_liquid"):
        gc.monad["liquid"] = gc.monad["liquid"].sub(amount.mul_float(l.to_float() / tf))
    if not gc.is_locked("monad_gas"):
        gc.monad["gas"]    = gc.monad["gas"].sub(amount.mul_float(g.to_float() / tf))


func _roll_monad() -> void:
    var unlocked = []
    for k in ["solid", "liquid", "gas"]:
        if not gc.is_locked("monad_" + k):
            unlocked.append(k)
    if unlocked.is_empty():
        return
    var key = unlocked[gc.rng.randi_range(0, unlocked.size() - 1)]
    gc.monad[key] = gc.monad[key].add(BigNum.from_int(1))


func _draw_monads(amount: int) -> bool:
    var pool = []
    if not gc.is_locked("monad_solid")   and not gc.monad["solid"].is_zero():   pool.append("solid")
    if not gc.is_locked("monad_liquid") and not gc.monad["liquid"].is_zero(): pool.append("liquid")
    if not gc.is_locked("monad_gas")    and not gc.monad["gas"].is_zero():    pool.append("gas")
    if pool.is_empty():
        return false
    var drawn = {}
    for i in amount:
        var key = pool[gc.rng.randi_range(0, pool.size() - 1)]
        drawn[key] = drawn.get(key, 0) + 1
    for key in drawn:
        if gc.monad[key].is_less_than(BigNum.from_int(drawn[key])):
            return false
    for key in drawn:
        gc.monad[key] = gc.monad[key].sub(BigNum.from_int(drawn[key]))
    return true


# ==================================================
# RANDOM WEIGHT HELPERS
# ==================================================

# Uniformly distributed random split across 3 types
# via uniform simplex sampling (order statistics method).
func _random_simplex_split() -> Vector3:
    var a = gc.rng.randf()
    var b = gc.rng.randf()
    if a > b:
        var tmp = a
        a = b
        b = tmp
    return Vector3(a, b - a, 1.0 - b)


# n random weights summing to 1.0 via order statistics.
# Generalises _random_simplex_split to any number of types.
func _random_weights(n: int) -> Array:
    if n <= 0:
        return []
    if n == 1:
        return [1.0]
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
# ASSIGNMENT MANAGEMENT
# ==================================================
func update_assignment(resource_key: String, value) -> void:
    if gc:
        gc.assignments[resource_key] = value


func get_assignment(resource_key: String):
    if gc:
        return gc.assignments.get(resource_key, 0)
    return 0


# ==================================================
# AVAILABILITY QUERIES
# ==================================================
func get_available_uonites() -> BigNum:
    if not gc:
        return BigNum.zero()
    var assigned = gc.get_total_uonites_assigned()
    if assigned.is_greater_than(gc.uonite):
        return BigNum.zero()
    return gc.uonite.sub(assigned)


func get_available_foci() -> int:
    if not gc:
        return 0
    return max(0, gc.archon_foci - gc.get_total_foci_assigned())


func get_available_volitions() -> int:
    if not gc:
        return 0
    return max(0, gc.volitions - gc.get_total_volitions_assigned())
