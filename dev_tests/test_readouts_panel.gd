extends "res://dev_tests/test_base.gd"
# The Readouts panel (Sparks, Uonites, Foci, Volitions) runs itself from
# readouts_panel.gd on both pages (2026-11-04). Firmament's copy used to show
# its placeholder text, since only root_ui.gd filled the rows.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _text(page: Node, row_name: String) -> String:
	var row: Node = page.find_child(row_name, true, false)
	return row.get_node("ResourceLabel").get_parsed_text() if row else "(no row)"


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gc = root.get_node("/root/GameContext")
	# Production adds Sparks once a second while Sparks summoning has anything
	# assigned, and earlier modules in the full suite leave some assigned, with
	# its timer part-run. A tick landing in this test's few frames moved Sparks
	# off 5678 before the panel drew (full suite, 2026-11-05; reproduced by
	# forcing the tick due). Nothing but this test may change them here.
	var pm = root.get_node_or_null("/root/ProductionManager")
	var pm_was_processing: bool = pm != null and pm.is_processing()
	if pm:
		pm.set_process(false)
	var saved_sparks: BigNum = gc.sparks.copy()
	var saved_foci: int = gc.archon_foci
	gc.sparks = BigNum.from_int(1234)
	gc.archon_foci = 7

	print("=== Firmament's Readouts show the game's values ===")
	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	for i in 3:
		await process_frame
	ok(_text(firm, "RowSparksLabelInstance") == "Sparks" and _text(firm, "RowFociLabelInstance") == "Foci",
		"the name rows read Sparks and Foci")
	ok(_text(firm, "RowSparksValueInstance") == "1234", "Sparks reads 1234 (%s)" % _text(firm, "RowSparksValueInstance"))
	ok(_text(firm, "RowFociValueInstance").ends_with("/7"), "Foci reads n/7 (%s)" % _text(firm, "RowFociValueInstance"))
	gc.sparks = BigNum.from_int(5678)
	await process_frame
	ok(_text(firm, "RowSparksValueInstance") == "5678", "and keeps up as Sparks change (%s, Sparks %s)" % [
		_text(firm, "RowSparksValueInstance"), gc.sparks.to_display_string()])
	firm.queue_free()
	await process_frame

	gc.sparks = saved_sparks
	gc.archon_foci = saved_foci
	if pm:
		pm.set_process(pm_was_processing)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
