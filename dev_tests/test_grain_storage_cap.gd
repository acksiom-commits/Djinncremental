extends "res://dev_tests/test_base.gd"
# Storage-derived Grain stockpile cap + batch Create-Grain action
# (2026-10-01) -- the Grain-branch counterpart of
# test_uonite_storage_cap.gd, but deliberately testing a DIFFERENT shape:
# per the user's own explicit design call, Grain has NO per-cycle limiter
# at all (no Fibonacci cap, no Expansion trigger) -- the storage cap
# (storage_cap^2 / GRAIN_SPARKS_COST) is the ONLY ceiling on how many can
# ever be held. grain_assemble also costs FOUR inputs (sparks, monad,
# particle, mote_grains), unlike uonite_assemble's two, so
# manual_create_grain() needs all four checked as independent bottlenecks.
#
# Uses bare .new() GameContext/ProductionManager instances (not the live
# autoloads), same pattern as test_uonite_storage_cap.gd.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _expected_cap(storage_cap: int) -> int:
	return (storage_cap * storage_cap) / 16825  # GRAIN_SPARKS_COST, integer floor division


func _fresh_gc_pm() -> Array:
	var gc = load("res://game_context.gd").new()
	var pm = load("res://production_manager.gd").new()
	pm.gc        = gc
	pm.game_data = load("res://game_data.gd").new()
	return [gc, pm]


func run() -> void:
	var setup: Array = _fresh_gc_pm()
	var gc = setup[0]
	var pm = setup[1]

	print("=== get_grain_storage_cap() formula ===")
	for sc in [987, 100, 1000, 1]:
		gc.storage_cap = BigNum.from_int(sc)
		var got: int = gc.get_grain_storage_cap()
		var want: int = _expected_cap(sc)
		ok(got == want, "storage_cap=%d -> cap=%d (want %d)" % [sc, got, want])

	print("\n=== get_grain_progress(): counted in Motes, no per-cycle component ===")
	gc.storage_cap = BigNum.from_int(987)
	var cap_grains: int = gc.get_grain_storage_cap()
	ok(cap_grains > 0, "sanity: storage cap is nonzero at storage_cap=987 (got %d)" % cap_grains)
	gc.grain = BigNum.zero()
	gc.mote_grains = BigNum.from_int(2)
	var p0: Vector2i = gc.get_grain_progress()
	ok(p0.y == cap_grains * 4, "cap in Motes is the Grain cap times GRAIN_MOTES_PER_UNIT (4) (got %d, want %d)" % [p0.y, cap_grains * 4])
	ok(p0.x == 2, "current reads the raw mote_grains stockpile directly (got %d)" % p0.x)

	gc.grain = BigNum.from_int(cap_grains)  # fully maxed out
	var p1: Vector2i = gc.get_grain_progress()
	ok(p1.y == 1 and p1.x == 0, "once the storage cap is fully reached, the bar reports maxed-out (0/1), not a dangling Mote count (got %d/%d)" % [p1.x, p1.y])

	print("\n=== manual_create_grain() enforces the storage cap independently of resource stock ===")
	gc.storage_cap = BigNum.from_int(150)   # cap = floor(22500/16825) = 1
	ok(gc.get_grain_storage_cap() == 1, "test setup: storage cap is exactly 1 (got %d)" % gc.get_grain_storage_cap())
	gc.grain       = BigNum.zero()
	gc.mote_grains = BigNum.from_int(1000)
	gc.sparks      = BigNum.from_int(100000)
	gc.particle    = BigNum.from_int(100000)
	gc.monad["solid"] = BigNum.from_int(100000)

	var first: bool = pm.manual_create_grain()
	ok(first, "first manual_create_grain() succeeds")
	ok(gc.grain.to_int() == 1, "exactly 1 Grain created, capped by storage not by resource stock (got %d)" % gc.grain.to_int())

	var second: bool = pm.manual_create_grain()
	ok(not second, "second call refused -- storage cap reached (1/1), even with ample resources left")
	ok(gc.grain.to_int() == 1, "stockpile still exactly 1 after the refused call")

	print("\n=== manual_create_grain() NEVER triggers an Expansion or touches cycle state ===")
	# Per the user's explicit design call: Grain is a separate accumulator,
	# not an alternate prestige path. Confirmed by checking the exact state
	# Create Uonite WOULD have touched (expansions, uonites_this_cycle,
	# motes_this_cycle) is completely untouched by a successful Grain create.
	var expansions_before: int        = gc.expansions
	var uonites_cycle_before: int     = gc.uonites_this_cycle
	var motes_cycle_before: int       = gc.motes_this_cycle
	gc.storage_cap = BigNum.from_int(987)
	gc.grain       = BigNum.zero()
	gc.mote_grains = BigNum.from_int(1000)
	gc.sparks      = BigNum.from_int(100000)
	gc.particle    = BigNum.from_int(100000)
	gc.monad["solid"] = BigNum.from_int(100000)
	var third: bool = pm.manual_create_grain()
	ok(third, "a normal (non-storage-capped) creation succeeds")
	ok(gc.expansions == expansions_before, "expansions untouched (got %d, was %d)" % [gc.expansions, expansions_before])
	ok(gc.uonites_this_cycle == uonites_cycle_before, "uonites_this_cycle untouched (got %d, was %d)" % [gc.uonites_this_cycle, uonites_cycle_before])
	ok(gc.motes_this_cycle == motes_cycle_before, "motes_this_cycle untouched (got %d, was %d)" % [gc.motes_this_cycle, motes_cycle_before])

	print("\n=== manual_create_grain(): each of the 4 recipe inputs is an independent bottleneck ===")
	# mote_grains=4, sparks=25, monad=64, particle=16 per Grain (game_data.gd).
	# Each sub-case gives 3 of the 4 inputs a huge surplus and the 4th
	# exactly enough for 3 Grains -- confirms `count` is bounded by
	# whichever input is actually scarce, for all four independently.
	var cases: Array = [
		{"name": "mote_grains", "key": "mote_grains", "per_unit": 4},
		{"name": "sparks",      "key": "sparks",      "per_unit": 25},
		{"name": "particle",    "key": "particle",    "per_unit": 16},
	]
	for c in cases:
		var setup2: Array = _fresh_gc_pm()
		var gc2 = setup2[0]
		var pm2 = setup2[1]
		gc2.storage_cap = BigNum.from_int(100000)  # cap far above 3, not the bottleneck
		gc2.mote_grains = BigNum.from_int(100000)
		gc2.sparks      = BigNum.from_int(100000)
		gc2.particle    = BigNum.from_int(100000)
		gc2.monad["solid"] = BigNum.from_int(100000)
		gc2.set(c["key"], BigNum.from_int(3 * int(c["per_unit"])))
		var ok_call: bool = pm2.manual_create_grain()
		ok(ok_call, "%s-bottlenecked call succeeds" % c["name"])
		ok(gc2.grain.to_int() == 3, "%s=exactly 3 units' worth bottlenecks count to 3 (got %d)" % [c["name"], gc2.grain.to_int()])
		var remaining: BigNum = gc2.get(c["key"])
		ok(remaining.to_int() == 0, "%s is exactly exhausted, not over- or under-spent (got %d)" % [c["name"], remaining.to_int()])

	# monad is checked separately -- it's not a plain BigNum field on gc,
	# it's drawn via _draw_monads() from the solid/liquid/gas sub-dict.
	var setup3: Array = _fresh_gc_pm()
	var gc3 = setup3[0]
	var pm3 = setup3[1]
	gc3.storage_cap = BigNum.from_int(100000)
	gc3.mote_grains = BigNum.from_int(100000)
	gc3.sparks      = BigNum.from_int(100000)
	gc3.particle    = BigNum.from_int(100000)
	gc3.monad["solid"] = BigNum.from_int(3 * 64)
	var ok_call3: bool = pm3.manual_create_grain()
	ok(ok_call3, "monad-bottlenecked call succeeds")
	ok(gc3.grain.to_int() == 3, "monad=exactly 3 units' worth bottlenecks count to 3 (got %d)" % gc3.grain.to_int())
	ok(gc3.monad["solid"].to_int() == 0, "monad is exactly exhausted (got %d)" % gc3.monad["solid"].to_int())

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
