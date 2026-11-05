extends "res://dev_tests/test_base.gd"
# Purity locks (2026-11-04): the lock held by a PARENT Volition gets a light
# sweeping left to right across it ([sweep], lock_sweep_effect.gd), so it can
# be told on sight from the plain-gold locks held by Child Volitions. Checked
# on the Tetrad grid (a variety and a category) and on a resource row (Solid).

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
	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)

	var saved_slots = gc.volition_slots.duplicate(true)
	var saved_locks = gc.locks.duplicate(true)
	var saved_unlocked: bool = gc.purity_locks_unlocked
	gc.purity_locks_unlocked = true
	for k in gc.locks:
		gc.locks[k] = false
	# Parent on Adaemant with a Child on Aquae; Parent on Solid Monads; a Child-held
	# category lock (Medials) under a Parent on Fundaments.
	gc.volition_slots = [
		{"category": "purity_lock", "target": "adaemant",
			"children": [{"category": "purity_lock", "target": "aquae"}]},
		{"category": "purity_lock", "target": "monad_solid", "children": []},
		{"category": "purity_lock", "target": "cat_fundament",
			"children": [{"category": "purity_lock", "target": "cat_medial"}]},
	]
	for k in ["adaemant", "aquae", "monad_solid", "cat_fundament", "cat_medial"]:
		gc.locks[k] = true

	print("=== which locks a Parent holds ===")
	ok(gc.is_parent_locked("adaemant") and gc.is_parent_locked("monad_solid") and gc.is_parent_locked("cat_fundament"),
		"Adaemant, Solid and Fundaments read as Parent-locked")
	ok(not gc.is_parent_locked("aquae") and not gc.is_parent_locked("cat_medial") and not gc.is_parent_locked("aethyr"),
		"Aquae and Medials (Child-held) and Aethyr (unlocked) do not")

	print("\n=== the Tetrad grid ===")
	ui._update_tetrad_display()
	await process_frame
	var left: RichTextLabel = ui._left_tetrad_label
	var mid: RichTextLabel = ui._middle_label
	var bb: String = left.text
	ok(bb.contains("[sweep len=9][color=#ffdd77]Adaemant:[/color][/sweep]"),
		"Adaemant's name sweeps (and its len counts visible characters)")
	ok(bb.contains("[sweep len=") and bb.find("Adaemant") > bb.find("[sweep"), "Adaemant's count line sweeps too")
	ok(not bb.contains("[sweep len=6][color=#ffdd77]Aquae:"), "Aquae, held by a Child, stays plain gold")
	ok(bb.contains("[sweep len=10][color=#ffdd77][i]Fundaments[/i]"), "the Parent-locked Fundaments header sweeps")
	ok(not mid.text.contains("[sweep len=7][color=#ffdd77][i]Medials"), "the Child-locked Medials header doesn't")
	ok(left.custom_effects.size() > 0 and not left.get_parsed_text().contains("sweep"),
		"the effect is installed, so no tag shows as text")

	print("\n=== a resource row ===")
	ui._update_counters()
	await process_frame
	var solid_row = null
	for row in root.get_tree().get_nodes_in_group("resource_rows"):
		if row.resource_key == "monad_solid":
			solid_row = row
	ok(solid_row != null and String(solid_row.display_label).begins_with("[sweep len="),
		"the Parent-locked Solid row sweeps (%s)" % (solid_row.display_label if solid_row else "no row"))
	ok(solid_row != null and solid_row.label_node.custom_effects.size() > 0 \
			and not solid_row.label_node.get_parsed_text().contains("sweep"),
		"its label has the effect installed")

	gc.volition_slots = saved_slots
	gc.locks = saved_locks
	gc.purity_locks_unlocked = saved_unlocked
	scene.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
