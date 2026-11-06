extends "res://dev_tests/test_base.gd"
# Grains have NO cap of their own, and the batch Create-Grain action.
# (File name kept from when it tested a Grain cap: that cap, storage_cap^2
# / 16,825, was copied 2026-10-01 from the author's Uonite-only rule, never
# requested; removed 2026-11-05, the author ruling "Ordinary storage only".)
# Per the author's design, Grain also has NO per-cycle limiter at all (no
# Fibonacci cap, no Expansion trigger). grain_assemble costs FOUR inputs
# (sparks, monad, particle, mote_grains), so manual_create_grain() needs all
# four checked as independent bottlenecks, and they are its only limits.
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

	print("=== no Grain cap exists ===")
	ok(not gc.has_method("get_grain_storage_cap"), "game_context has no get_grain_storage_cap()")

	print("\n=== get_grain_progress(): Motes toward the next Grain ===")
	gc.grain = BigNum.zero()
	gc.mote_grains = BigNum.from_int(2)
	var p0: Vector2i = gc.get_grain_progress()
	ok(p0 == Vector2i(2, 4), "2 Motes banked reads 2/4 (got %d/%d)" % [p0.x, p0.y])
	gc.mote_grains = BigNum.from_int(9)
	var p1: Vector2i = gc.get_grain_progress()
	ok(p1 == Vector2i(4, 4), "9 Motes banked reads full, 4/4: Create Grain can make one (got %d/%d)" % [p1.x, p1.y])
	gc.grain = BigNum.from_int(100000)
	ok(gc.get_grain_progress() == Vector2i(4, 4), "however many Grains are held, the bar still only counts Motes")

	print("\n=== manual_create_grain() is limited only by its inputs, even at a tiny storage cap ===")
	# At storage_cap 150 the old copied cap allowed exactly 1 Grain.
	gc.storage_cap = BigNum.from_int(150)
	gc.grain       = BigNum.zero()
	gc.mote_grains = BigNum.from_int(40)        # inputs for 10 Grains
	gc.sparks      = BigNum.from_int(100000)
	gc.particle    = BigNum.from_int(100000)
	gc.monad["solid"] = BigNum.from_int(100000)
	var first: bool = pm.manual_create_grain()
	ok(first and gc.grain.to_int() == 10,
		"one click converts all 10 Grains' worth of Motes, storage cap 150 or not (got %d)" % gc.grain.to_int())
	var second: bool = pm.manual_create_grain()
	ok(not second and gc.grain.to_int() == 10, "then it stops only because the Motes ran out")

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
