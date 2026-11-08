extends "res://dev_tests/test_base.gd"
# Kaleb's Assign bar (author, 2026-11-07): sets the Uonites or Foci on one
# Allocation Wheel resource, so a restarted stack can rebuild the wheel's
# setup after an Oscillation zeroes it.
#
# It writes the wheel's own assignment key, never takes more than are free (a
# big value takes all that are free), is a SET (running it twice changes
# nothing, a lower value gives units back), never touches Volitions, and
# pauses Kaleb on a wheel resource the wheel hasn't unlocked yet. The wheel's
# lock rule is one implementation, GameContext.is_wheel_resource_locked().

const KC = preload("res://kaleb_commands.gd")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _assign_bar(pool: String, target: String, value: int) -> Dictionary:
	var b: Dictionary = KC.make_bar("assign")
	b["res"] = pool
	b["target"] = target
	b["value"] = value
	return b


func _uon(gc, key: String) -> int:
	var v = gc.assignments.get(key, BigNum.zero())
	return v.to_int() if v is BigNum else -1


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gc = root.get_node("/root/GameContext")
	var snapshot: Dictionary = gc.get_save_data()

	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)
	var kaleb: Node = ui._kaleb
	kaleb.set_process(false)
	var adm = ui.archon_dialogue_manager
	for _i in 200:
		if adm.current_index < 0:
			break
		adm.advance_dialogue()

	print("=== the palette and the wheel's lock rule ===")
	ok(KC.COMMANDS.has("assign") and KC.COMMANDS["assign"]["kind"] == "assign", "Assign is in the palette")
	ok(FileAccess.get_file_as_string("res://kaleb_stack_view.gd").contains("\"assign\""), "and in the + Command menu")
	ok(not KC.ASSIGN_POOLS.has("volitions"), "it moves Uonites and Foci only, never Volitions")
	var wheel_src: String = FileAccess.get_file_as_string("res://allocation_wheel_control.gd")
	ok(wheel_src.contains("game_context.is_wheel_resource_locked(key)"), "the wheel asks the same lock rule")
	gc.ui_unlocks["wheel_full_access"] = false
	ok(not gc.is_wheel_resource_locked("sparks") and gc.is_wheel_resource_locked("monad"),
		"Sparks is always open; Monads wait for the wheel's full access")
	gc.ui_unlocks["wheel_full_access"] = true
	gc.totals_created["particle"] = BigNum.zero()
	ok(not gc.is_wheel_resource_locked("monad") and gc.is_wheel_resource_locked("particle"),
		"with full access Monads open, a Particle not yet made stays locked")

	# A clean slate with units to move.
	for k in gc.assignments.keys():
		var kk: String = String(k)
		if kk.ends_with("_uonites"):
			gc.assignments[k] = BigNum.zero()
		elif kk.ends_with("_foci"):
			gc.assignments[k] = 0
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_running = false
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(10))
	gc.archon_foci = gc.get_total_foci_assigned() + 8
	gc.kaleb_add_bar(_assign_bar("uonites", "sparks", 3))
	var foci_free: int = gc.archon_foci - gc.get_total_foci_assigned()
	var vols_before: int = gc.get_total_volitions_assigned()

	print("=== Assign sets the Uonites on a wheel resource ===")
	gc.kaleb_running = true
	kaleb.step()
	ok(_uon(gc, "sparks_summon_uonites") == 3, "3 Uonites on Sparks (%d)" % _uon(gc, "sparks_summon_uonites"))
	ok(gc.kaleb_running, "he carries on")
	ok(gc.uonite.to_int() - gc.get_total_uonites_assigned().to_int() == 7, "7 Uonites are left free")
	gc.kaleb_index = 0
	kaleb.step()
	ok(_uon(gc, "sparks_summon_uonites") == 3 and gc.uonite.to_int() - gc.get_total_uonites_assigned().to_int() == 7,
		"running it again changes nothing: it sets, it doesn't add")
	gc.kaleb_stack[0]["value"] = 1
	gc.kaleb_index = 0
	kaleb.step()
	ok(_uon(gc, "sparks_summon_uonites") == 1, "a lower value gives units back (1)")
	gc.kaleb_stack[0]["value"] = 99999
	gc.kaleb_index = 0
	kaleb.step()
	ok(_uon(gc, "sparks_summon_uonites") == 10 and gc.uonite.to_int() == gc.get_total_uonites_assigned().to_int(),
		"a huge value takes all that are free, no more (10 of 10)")

	print("=== Assign sets Foci, and only what's free ===")
	gc.kaleb_stack[0]["res"] = "foci"
	gc.kaleb_stack[0]["target"] = "monad"
	gc.kaleb_stack[0]["value"] = 2
	gc.kaleb_index = 0
	kaleb.step()
	ok(gc._assignment_int("monad_compress_foci", -1) == 2, "2 Foci on Monads")
	gc.kaleb_stack[0]["value"] = 99999
	gc.kaleb_index = 0
	kaleb.step()
	ok(gc._assignment_int("monad_compress_foci", -1) == foci_free and gc.archon_foci == gc.get_total_foci_assigned(),
		"a huge value takes every free Focus (%d), none beyond" % foci_free)
	ok(gc.get_total_volitions_assigned() == vols_before, "no Volition was touched")

	print("=== Assign pauses on a wheel resource that is still locked ===")
	gc.kaleb_stack[0]["res"] = "uonites"
	gc.kaleb_stack[0]["target"] = "particle"
	gc.kaleb_stack[0]["value"] = 1
	gc.kaleb_index = 0
	gc.kaleb_running = true
	kaleb.step()
	ok(not gc.kaleb_running and gc.kaleb_index == 0 and _uon(gc, "particle_assemble_uonites") == 0,
		"a Particle not yet made: he pauses on the bar and assigns nothing")
	gc.kaleb_stack[0]["target"] = ""
	gc.kaleb_running = true
	kaleb.step()
	ok(not gc.kaleb_running, "a bar with no resource chosen pauses him too")

	gc.kaleb_running = false
	scene.queue_free()
	await process_frame
	await process_frame
	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
