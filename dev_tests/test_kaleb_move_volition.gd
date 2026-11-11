extends "res://dev_tests/test_base.gd"
# Kaleb's Move Volition bar (author, 2026-11-10): the Djinn's first effect.
#
# It works only while The Djinn is at Tier 1 or above (below that Kaleb
# pauses and nothing moves: the 2026-11-05 "Keep them by hand" ruling holds
# there). It moves Constellation Volitions between Free and a Constellation,
# or from one Constellation to another (a parent is re-pointed in place), up
# to its count, and pauses when none can move.

const KC = preload("res://kaleb_commands.gd")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _bar(from: String, to: String, n: int) -> Dictionary:
	var b: Dictionary = KC.make_bar("move_volition")
	b["res"] = from
	b["target"] = to
	b["value"] = n
	return b


func _on(gc, id: int) -> int:
	return gc._assignment_int("constellation_%d_volitions" % id, 0)


func _run_one(gc, kaleb) -> void:
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.kaleb_running = true
	kaleb.step()


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gc = root.get_node("/root/GameContext")
	var cd = root.get_node("/root/ConstellationData")
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

	print("=== the palette ===")
	ok(KC.COMMANDS.has("move_volition") and KC.COMMANDS["move_volition"]["kind"] == "volition", "Move Volition is in the palette")
	ok(FileAccess.get_file_as_string("res://kaleb_stack_view.gd").contains("\"move_volition\""), "and in the + Command menu")
	ok(cd.DJINN_ID == 6 and String(cd.get_constellation_def(cd.DJINN_ID).get("name", "")) == "The Djinn", "DJINN_ID names The Djinn")

	# A clean slate: three empty Volitions, the Archon dark (no children),
	# the Spark, the Archon and the Djinn unlocked.
	for id in [0, 1, cd.DJINN_ID]:
		if not cd.unlocked.has(id):
			cd.unlocked.append(id)
	for k in gc.constellation_spark_totals.keys():
		gc.constellation_spark_totals[k] = 0.0
	gc.volitions = 3
	gc._ensure_slot_count(3)
	for i in gc.volition_slots.size():
		if gc.volition_slots[i]["category"] != "":
			gc.unassign_parent_volition(i)
	gc.sync_bonus_children_count()
	gc.archon_foci = gc.get_total_foci_assigned() + 4
	gc.kaleb_stack = []
	gc.kaleb_running = false
	gc.kaleb_add_bar(_bar("free", str(cd.DJINN_ID), 1))
	# Instant bars recycle within a frame, so park Kaleb on bar 2 ("If
	# Sparks >= 0, go to bar 2") to run bar 1 exactly once a step.
	var park: Dictionary = KC.make_bar("if")
	park["res"] = "sparks"
	park["cmp"] = ">="
	park["value"] = 0
	park["goto"] = 1
	gc.kaleb_add_bar(park)
	ok(gc.get_volitions_free() == 3 and gc.get_free_children_count() == 0,
		"3 free Volitions, no children (%d, %d)" % [gc.get_volitions_free(), gc.get_free_children_count()])

	print("=== below the Djinn's Tier 1 nothing moves ===")
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running and gc.kaleb_index == 0 and _on(gc, cd.DJINN_ID) == 0,
		"the Djinn dark: he pauses on the bar and moves nothing")
	gc.constellation_spark_totals[str(cd.DJINN_ID)] = cd.SPARKS_TIER_STARS - 1.0
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running and _on(gc, cd.DJINN_ID) == 0, "one Spark short of Tier 1: still nothing")

	print("=== at the Djinn's Tier 1 ===")
	gc.constellation_spark_totals[str(cd.DJINN_ID)] = cd.SPARKS_TIER_STARS
	ok(cd.get_visual_state(cd.DJINN_ID) == "stars", "the Djinn is at Tier 1")
	_run_one(gc, kaleb)
	ok(gc.kaleb_running and _on(gc, cd.DJINN_ID) == 1 and gc.get_volitions_free() == 2,
		"Free → the Djinn: one placed, he carries on (%d on it, %d free)" % [_on(gc, cd.DJINN_ID), gc.get_volitions_free()])
	ok(gc.has_volition_for_constellation(cd.DJINN_ID), "so the Djinn can be Supplied and Endowed")

	gc.kaleb_stack[0]["res"] = str(cd.DJINN_ID)
	gc.kaleb_stack[0]["target"] = "1"
	_run_one(gc, kaleb)
	ok(_on(gc, cd.DJINN_ID) == 0 and _on(gc, 1) == 1 and gc.get_volitions_free() == 2,
		"the Djinn → the Archon: the same Volition moves, none freed or added")

	gc.kaleb_stack[0]["res"] = "free"
	gc.kaleb_stack[0]["target"] = "0"
	gc.kaleb_stack[0]["value"] = 5
	_run_one(gc, kaleb)
	ok(gc.kaleb_running and _on(gc, 0) == 2 and gc.get_volitions_free() == 0,
		"Free → the Spark ×5 with 2 free: both move, no pause")
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running and _on(gc, 0) == 2, "again with none free: he pauses")

	gc.kaleb_stack[0]["res"] = "0"
	gc.kaleb_stack[0]["target"] = "free"
	gc.kaleb_stack[0]["value"] = 1
	_run_one(gc, kaleb)
	ok(gc.kaleb_running and _on(gc, 0) == 1 and gc.get_volitions_free() == 1, "the Spark → Free: one taken off")

	gc.kaleb_stack[0]["res"] = str(cd.DJINN_ID)
	gc.kaleb_stack[0]["target"] = "0"
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running and _on(gc, 0) == 1, "from the Djinn with none on it: he pauses")
	gc.kaleb_stack[0]["res"] = "0"
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running, "from a Constellation to itself: he pauses")
	gc.kaleb_stack[0]["target"] = "free"
	gc.kaleb_stack[0]["res"] = "13"
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running, "a Constellation that isn't unlocked: he pauses")

	print("=== Constellation Foci (the Djinn's too) ===")
	ok(KC.COMMANDS.has("constellation_foci") and KC.COMMANDS["constellation_foci"]["kind"] == "cfoci", "Constellation Foci is in the palette")
	ok(FileAccess.get_file_as_string("res://kaleb_stack_view.gd").contains("\"constellation_foci\""), "and in the + Command menu")
	var fkey: String = "constellation_0_foci"
	gc.assignments[fkey] = 0
	gc.archon_foci = gc.get_total_foci_assigned() + 6
	var vols_before: int = gc.get_total_volitions_assigned()
	gc.kaleb_stack[0] = KC.make_bar("constellation_foci")
	gc.kaleb_stack[0]["target"] = "0"
	gc.kaleb_stack[0]["value"] = 4
	_run_one(gc, kaleb)
	ok(gc.kaleb_running and gc._assignment_int(fkey, -1) == 4, "4 Foci on the Spark (%d)" % gc._assignment_int(fkey, -1))
	_run_one(gc, kaleb)
	ok(gc._assignment_int(fkey, -1) == 4 and gc.archon_foci - gc.get_total_foci_assigned() == 2,
		"running it again changes nothing: it sets, it doesn't add")
	gc.kaleb_stack[0]["value"] = 1
	_run_one(gc, kaleb)
	ok(gc._assignment_int(fkey, -1) == 1 and gc.archon_foci - gc.get_total_foci_assigned() == 5, "a lower value gives Foci back")
	gc.kaleb_stack[0]["value"] = 99999
	_run_one(gc, kaleb)
	ok(gc._assignment_int(fkey, -1) == 6 and gc.archon_foci == gc.get_total_foci_assigned(),
		"a huge value takes every free Focus, none beyond (6)")
	ok(gc.get_total_volitions_assigned() == vols_before, "no Volition was touched")
	gc.kaleb_stack[0]["target"] = "13"
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running, "a Constellation that isn't unlocked: he pauses")
	gc.kaleb_stack[0]["target"] = "0"
	gc.kaleb_stack[0]["value"] = 0
	gc.constellation_spark_totals[str(cd.DJINN_ID)] = 0.0
	_run_one(gc, kaleb)
	ok(not gc.kaleb_running and gc._assignment_int(fkey, -1) == 6, "the Djinn dark: he pauses and the Foci stay")
	gc.constellation_spark_totals[str(cd.DJINN_ID)] = cd.SPARKS_TIER_STARS

	print("=== only Constellation Volitions ===")
	var cats: Array = []
	for s in gc.volition_slots:
		if s["category"] != "":
			cats.append(s["category"])
	ok(cats.size() == 2 and cats.count("constellation") == 2, "every placed Volition is on a Constellation (%s)" % str(cats))

	gc.kaleb_running = false
	scene.queue_free()
	await process_frame
	await process_frame
	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
