extends "res://dev_tests/test_base.gd"
# Bonus Foci by Fibonacci count of TOTAL Uonites: +1 at 2, 3, 5, 8, 13, 21,
# 34, ... Uonites created (the first Uonite is paid by its own milestone).
# The count is a pure function of the lifetime total
# (so it never goes backwards), paid exactly once per threshold, and a save that
# predates the rule catches up in one go.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame
	var GC = load("res://game_context.gd")

	print("=== the threshold sequence ===")
	var expect: Dictionary = {0: 0, 1: 0, 2: 1, 3: 2, 4: 2, 5: 3, 7: 3, 8: 4, 12: 4, 13: 5,
		20: 5, 21: 6, 33: 6, 34: 7, 54: 7, 55: 8, 89: 9}
	var bad: int = 0
	for total in expect:
		var got: int = GC.fibonacci_foci_for_total(int(total))
		if got != int(expect[total]):
			bad += 1
			print("      total %d: got %d, want %d" % [int(total), got, int(expect[total])])
	ok(bad == 0, "+1 at 2, 3, 5, 8, 13, 21, 34, 55, 89 and nowhere between (%d wrong of %d)" % [bad, expect.size()])
	ok(GC.fibonacci_foci_for_total(1) == 0, "the first Uonite pays nothing here (its own milestone pays it)")

	print("\n=== claiming: once per threshold, catch-up in one go ===")
	var gc = GC.new()
	ok(gc.claim_uonite_fibonacci_foci() == 0, "nothing owed with no Uonites made")
	gc.totals_created["uonite"] = BigNum.from_int(1)
	ok(gc.claim_uonite_fibonacci_foci() == 0, "the first Uonite owes nothing from this ladder")
	gc.totals_created["uonite"] = BigNum.from_int(2)
	ok(gc.claim_uonite_fibonacci_foci() == 1, "the second Uonite owes 1")
	ok(gc.claim_uonite_fibonacci_foci() == 0, "and is not paid again")
	gc.totals_created["uonite"] = BigNum.from_int(4)
	ok(gc.claim_uonite_fibonacci_foci() == 1, "going from 2 to 4 crosses 3 only: owes 1")
	gc.totals_created["uonite"] = BigNum.from_int(5)
	ok(gc.claim_uonite_fibonacci_foci() == 1, "5 owes 1 more")
	gc.totals_created["uonite"] = BigNum.from_int(7)
	ok(gc.claim_uonite_fibonacci_foci() == 0, "7 owes nothing new")

	var old_save = GC.new()
	old_save.totals_created["uonite"] = BigNum.from_int(21)
	ok(old_save.claim_uonite_fibonacci_foci() == 6, "a save with 21 Uonites already made catches up on all 6 at once")
	ok(old_save.uonite_fibonacci_foci_granted == 6, "and records them as granted")

	print("\n=== it survives a save/load round trip (no double grant) ===")
	var saved: Dictionary = old_save.get_save_data()
	var reloaded = GC.new()
	reloaded.load_save_data(saved)
	ok(reloaded.uonite_fibonacci_foci_granted == 6, "the granted count is saved and restored (%d)" % reloaded.uonite_fibonacci_foci_granted)
	ok(reloaded.claim_uonite_fibonacci_foci() == 0, "a reload re-grants nothing")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
