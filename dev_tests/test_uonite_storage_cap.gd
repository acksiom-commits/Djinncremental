extends "res://dev_tests/test_base.gd"
# Storage-derived Uonite stockpile cap (user-specified 2026-09-20): no more
# than storage_cap^2 / UONITE_SPARKS_COST Uonites can be held at once,
# alongside (not instead of) the existing per-cycle Fibonacci creation-rate
# cap (get_uonite_cycle_cap()). One Uonite's footprint in storage units is
# UONITE_SPARKS_COST / storage_cap; as storage_cap grows 5%/Expansion via
# the ALREADY-SHIPPING has_storage_enhancer() mechanic, footprint shrinks
# AND total room grows, so the count that fits grows quadratically.
#
# Uses bare .new() GameContext/ProductionManager instances (not the live
# autoloads) with gc/game_data wired in directly, matching
# test_second_volition_gate.gd's pattern -- these don't need _ready() to
# fire since nothing here touches other collaborators.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _expected_cap(storage_cap: int) -> int:
	return (storage_cap * storage_cap) / 28801  # integer floor division


func run() -> void:
	var gc = load("res://game_context.gd").new()
	var pm = load("res://production_manager.gd").new()
	pm.gc        = gc
	pm.game_data = load("res://game_data.gd").new()

	print("=== get_uonite_storage_cap() formula ===")
	for sc in [987, 100, 1000, 1]:
		gc.storage_cap = BigNum.from_int(sc)
		var got: int = gc.get_uonite_storage_cap()
		var want: int = _expected_cap(sc)
		ok(got == want, "storage_cap=%d -> cap=%d (want %d)" % [sc, got, want])

	print("\n=== quadratic growth: a 5%% Expansion bump grows the cap by more than 5%% ===")
	gc.storage_cap = BigNum.from_int(987)
	var cap_before: int = gc.get_uonite_storage_cap()
	gc.storage_cap = gc.storage_cap.mul_float(1.05).floor_to_whole()  # what do_prestige_reset() does
	var cap_after: int = gc.get_uonite_storage_cap()
	ok(cap_after > cap_before,
		"cap grew after the storage_cap bump (%d -> %d)" % [cap_before, cap_after])
	ok(float(cap_after) / float(cap_before) > 1.05,
		"growth exceeds the storage_cap's own 5%% (footprint shrinks too): %.1f%% vs storage_cap alone"
			% (100.0 * (float(cap_after) / float(cap_before) - 1.0)))

	print("\n=== manual_create_uonite() enforces the storage cap independently of the cycle cap ===")
	gc.storage_cap = BigNum.from_int(200)   # cap = floor(40000/28801) = 1
	ok(gc.get_uonite_storage_cap() == 1, "test setup: storage cap is exactly 1 (got %d)"
		% gc.get_uonite_storage_cap())
	gc.expansions = 5                        # cycle cap is comfortably bigger than 1 here
	ok(gc.get_uonite_cycle_cap() > 1, "test setup: cycle cap (%d) is NOT the bottleneck"
		% gc.get_uonite_cycle_cap())
	gc.uonite            = BigNum.zero()
	gc.uonites_this_cycle = 0
	gc.mote_uonite       = BigNum.from_int(1000)
	gc.sparks            = BigNum.from_int(1000)

	var first: bool = pm.manual_create_uonite()
	ok(first, "first manual_create_uonite() succeeds")
	ok(gc.uonite.to_int() == 1, "exactly 1 Uonite created, capped by storage not by mote/sparks stock (got %d)"
		% gc.uonite.to_int())

	var second: bool = pm.manual_create_uonite()
	ok(not second,
		"second call refused -- storage cap reached (1/1), even with ample mote_uonite/sparks/cycle headroom left")
	ok(gc.uonite.to_int() == 1, "stockpile still exactly 1 after the refused call")

	print("\n=== automated _add_resource(\"uonite\", ...) path enforces the same storage cap ===")
	gc.storage_cap        = BigNum.from_int(200)   # cap == 1 again
	gc.uonite             = BigNum.zero()
	gc.uonites_this_cycle = 0
	pm._add_resource("uonite", BigNum.from_int(50))   # a big batch, should clamp to headroom
	ok(gc.uonite.to_int() == 1,
		"automated path clamped a 50-Uonite batch down to the storage cap (got %d)" % gc.uonite.to_int())
	pm._add_resource("uonite", BigNum.from_int(50))
	ok(gc.uonite.to_int() == 1,
		"automated path adds nothing more once the storage cap is already full (got %d)" % gc.uonite.to_int())

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
