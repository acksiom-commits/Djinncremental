extends "res://dev_tests/test_base.gd"
# Grain Focus milestones (author, 2026-11-05): +1 Focus at the 100th,
# 10,000th, 1,000,000th, ... Grain made, the 1/100/10,000 ladder the
# Oscillations pay on. Grains count plain (Create Grain) and Persistent
# (Kaleb) together; the 1st Grain is the First Grain milestone's, which a
# Persistent Grain now sets off too. Lifetime totals, so an Oscillation
# doesn't lower the count, and a reload re-grants nothing.

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

	print("=== the ladder: 100, 10,000, 1,000,000 ... ===")
	var gc = GC.new()
	ok(gc.claim_grain_milestone_foci() == 0, "nothing owed with no Grains made")
	gc.totals_created["persistent_grain"] = BigNum.from_int(1)
	ok(gc.claim_grain_milestone_foci() == 0, "the 1st Grain owes nothing here (First Grain pays it)")
	gc.totals_created["persistent_grain"] = BigNum.from_int(60)
	gc.totals_created["grain"] = BigNum.from_int(39)
	ok(gc.claim_grain_milestone_foci() == 0, "99 Grains owe nothing")
	gc.totals_created["grain"] = BigNum.from_int(40)
	ok(gc.claim_grain_milestone_foci() == 1, "the 100th, 60 Persistent + 40 plain, owes 1: both kinds count")
	ok(gc.claim_grain_milestone_foci() == 0, "and is not paid again")
	gc.totals_created["grain"] = BigNum.from_int(9939)
	ok(gc.claim_grain_milestone_foci() == 0, "9,999 owes nothing new")
	gc.totals_created["grain"] = BigNum.from_int(9940)
	ok(gc.claim_grain_milestone_foci() == 1, "the 10,000th owes 1")

	var old_save = GC.new()
	old_save.totals_created["grain"] = BigNum.from_int(2000000)
	ok(old_save.claim_grain_milestone_foci() == 3, "a save already past 2,000,000 catches up on 100, 10,000 and 1,000,000 at once")

	print("\n=== an Oscillation doesn't lower it; a save/load doesn't re-grant ===")
	var osc = GC.new()
	osc.totals_created["persistent_grain"] = BigNum.from_int(150)
	osc.persistent_grain = BigNum.from_int(150)
	ok(osc.claim_grain_milestone_foci() == 1, "150 Grains owe the 100th")
	osc.do_prestige_reset()
	ok(osc.grains_created_total().to_int() == 150, "the Oscillation leaves the count at 150")
	ok(osc.claim_grain_milestone_foci() == 0, "and pays nothing again")
	var reloaded = GC.new()
	reloaded.load_save_data(osc.get_save_data())
	ok(reloaded.next_grain_foci_exp == 4, "the ladder's place (next: 10^4) is saved and restored (%d)" % reloaded.next_grain_foci_exp)
	ok(reloaded.claim_grain_milestone_foci() == 0, "a reload re-grants nothing")
	var older = GC.new()
	older.load_save_data({})
	ok(older.next_grain_foci_exp == 2, "a save from before the ladder starts it at 100")

	print("\n=== the page pays it: Foci and a notice ===")
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var live = root.get_node("/root/GameContext")
	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)
	var saved_totals: Dictionary = {"grain": live.totals_created["grain"], "persistent_grain": live.totals_created["persistent_grain"]}
	var saved_exp: int = live.next_grain_foci_exp
	var saved_foci: int = live.archon_foci
	live.totals_created["grain"] = BigNum.zero()
	live.totals_created["persistent_grain"] = BigNum.from_int(100)
	live.next_grain_foci_exp = 2
	var foci_before: int = live.archon_foci
	ui._check_grain_milestone_foci()
	ok(live.archon_foci == foci_before + 1, "the 100th Grain (all Persistent) adds 1 Focus (%d -> %d)" % [foci_before, live.archon_foci])
	ok(live.next_grain_foci_exp == 4, "the next rung is 10,000")
	ui._check_grain_milestone_foci()
	ok(live.archon_foci == foci_before + 1, "and pays once")

	print("\n=== a Persistent Grain sets off First Grain ===")
	var first: Array = ui._simple_triggers.filter(func(t): return t["guard"] == "_first_grain_dialogue_triggered")
	live.totals_created["persistent_grain"] = BigNum.one()
	live.grain = BigNum.zero()
	ok(first.size() == 1 and bool(first[0]["condition"].call()), "First Grain's condition holds with 1 Persistent Grain made and no plain Grain")
	live.totals_created["persistent_grain"] = BigNum.zero()
	ok(not bool(first[0]["condition"].call()), "and not with no Grain made")

	live.totals_created["grain"] = saved_totals["grain"]
	live.totals_created["persistent_grain"] = saved_totals["persistent_grain"]
	live.next_grain_foci_exp = saved_exp
	live.archon_foci = saved_foci
	scene.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
