extends "res://dev_tests/test_base.gd"
# Kaleb's Create Uonite bar (author, 2026-11-07): the stack can fire the
# Expansion unattended.
#
# The bar presses the real Create Uonite handler, so a made Uonite starts the
# Oscillation. It is crewless (no crew needed, none shown on the bar), waits
# while the Oscillation's animation runs, and an If bar can count Motes
# ("mote_uonite") and Uonites to guard it.

const KC = preload("res://kaleb_commands.gd")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gc = root.get_node("/root/GameContext")
	var pm = root.get_node("/root/ProductionManager")
	var snapshot: Dictionary = gc.get_save_data()

	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)
	var kaleb: Node = ui._kaleb
	kaleb.set_process(false)   # the test steps him
	var adm = ui.archon_dialogue_manager
	for _i in 200:
		if adm.current_index < 0:
			break
		adm.advance_dialogue()

	print("=== the palette ===")
	ok(KC.COMMANDS.has("create_uonite") and KC.COMMANDS["create_uonite"]["kind"] == "press",
		"Create Uonite is a press bar")
	var view_src: String = FileAccess.get_file_as_string("res://kaleb_stack_view.gd")
	ok(view_src.contains("\"create_uonite\""), "the + Command palette lists it")

	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_running = false
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.archon_foci = gc.get_total_foci_assigned() + 5
	gc.uonite = gc.get_total_uonites_assigned()
	gc.uonites_this_cycle = 0
	gc.storage_cap = BigNum.from_int(1000000)
	var mote_cost: int = pm._recipe_cost("uonite_assemble", "mote_uonite")
	var sparks_cost: int = pm._recipe_cost("uonite_assemble", "sparks")

	print("=== an If bar counts Motes and Uonites ===")
	gc.mote_uonite = BigNum.from_int(mote_cost - 1)
	var ib: Dictionary = KC.make_bar("if")
	ib["res"] = "mote_uonite"
	ib["cmp"] = ">="
	ib["value"] = mote_cost
	ok(KC.read_count(gc, "mote_uonite") == mote_cost - 1 and not KC.test(gc, ib),
		"one Mote short of a Uonite: mote_uonite >= %d is false" % mote_cost)
	gc.mote_uonite = BigNum.from_int(mote_cost)
	ok(KC.test(gc, ib), "with a Uonite's Motes it is true")
	ok(KC.read_count(gc, "uonite") == gc.uonite.to_int(), "an If bar reads the Uonites held")

	print("=== Kaleb presses Create Uonite with no crew ===")
	gc.sparks = BigNum.from_int(sparks_cost * 3)
	gc.mote_uonite = BigNum.from_int(mote_cost)
	var held_before: int = gc.uonite.to_int()
	var cycle_before: int = gc.uonites_this_cycle
	var bar: Dictionary = KC.make_bar("create_uonite", 2)
	gc.kaleb_add_bar(bar)
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	ok(gc.kaleb_bar_workers(bar) < 1, "the stack has no crew")
	gc.kaleb_running = true
	kaleb.step()
	ok(gc.kaleb_running, "he does not pause for want of a crew")
	ok(gc.uonite.to_int() == held_before + 1 and gc.uonites_this_cycle == cycle_before + 1,
		"a Uonite was made (held %d -> %d)" % [held_before, gc.uonite.to_int()])
	ok(ui._expansion_anim_active, "and the Oscillation began")

	print("=== he waits out the Oscillation ===")
	gc.mote_uonite = BigNum.from_int(mote_cost)
	var held_mid: int = gc.uonite.to_int()
	var done_mid: int = gc.kaleb_repeat_done
	kaleb.step()
	ok(gc.uonite.to_int() == held_mid and gc.kaleb_repeat_done == done_mid and gc.kaleb_running,
		"while it plays the next press waits: nothing made, the count unchanged, no pause")

	gc.kaleb_running = false
	scene.queue_free()
	await process_frame
	await process_frame
	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
