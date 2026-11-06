extends "res://dev_tests/test_base.gd"
# Kaleb's command stack in the Journal's Commands tab (SysDoc §7.3; moved from
# the Constellation box by the author, 2026-11-05): Primordial's Journal has
# it in place of Placeholder, Firmament's doesn't, and the box's button is
# Study Constellation again; the palette adds bars; each row's On/Off, number
# fields, menus and × change the bar; drag and drop moves a bar to the slot
# it is dropped on; Run/Pause runs Kaleb; the view fits the Journal panel.

const KC = preload("res://kaleb_commands.gd")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _row_count(view) -> int:
	return view._rows.size()


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
	ui._kaleb.set_process(false)
	var cp = scene.find_child("ConstellationPanel", true, false)
	var btn: Button = cp._study_btn
	var journal = scene.find_child("JournalPopout", true, false)
	var view = scene.find_child("KalebStackView", true, false)
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_running = false
	gc.kaleb_index = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(10))
	gc.archon_foci = gc.get_total_foci_assigned() + 10

	print("=== where it lives ===")
	ok(view != null and journal.is_ancestor_of(view) and not cp.is_ancestor_of(view),
		"the stack view is in the Journal, not the Constellation box")
	ok(journal._placeholder_tab.text == "Commands", "the Journal's sixth tab reads Commands")
	ok(btn.text == "Study Constellation" and not cp.has_method("enable_kaleb_switch"),
		"the box's button is Study Constellation again")
	ok(not view.visible, "the stack is hidden while another tab is open")
	journal._placeholder_tab.pressed.emit()
	await process_frame
	await process_frame
	ok(view.visible and not journal._placeholder_scroll.visible, "the Commands tab shows the stack, not Coming soon")
	journal._ref_tab.pressed.emit()
	ok(not view.visible, "and another tab hides it")
	journal._placeholder_tab.pressed.emit()
	await process_frame
	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	await process_frame
	var fj = firm.find_child("JournalPopout", true, false)
	ok(fj._placeholder_tab.text == "Placeholder" and firm.find_child("KalebStackView", true, false) == null,
		"Firmament's Journal keeps its Placeholder tab")
	firm.queue_free()
	await process_frame

	print("\n=== the palette ===")
	var before_f: int = gc.get_total_foci_assigned()
	view._on_add_chosen(view.PALETTE.find("monad_compress"))
	view._on_add_chosen(view.PALETTE.find("lock"))
	view._on_add_chosen(view.PALETTE.find("if"))
	view._on_add_chosen(view.PALETTE.find("tetrad_assemble"))
	await process_frame
	ok(gc.kaleb_stack.size() == 4 and _row_count(view) == 4, "four commands added, four rows (%d)" % _row_count(view))
	ok(gc.get_total_foci_assigned() - before_f == 4, "each holds a Focus")
	ok(gc.kaleb_stack[1]["target"] == "monad_liquid" and gc.kaleb_stack[2]["res"] == "persistent_particle",
		"Lock and If start with sensible settings")
	gc.archon_foci = gc.get_total_foci_assigned()
	view._on_add_chosen(view.PALETTE.find("summon_spark"))
	await process_frame
	ok(gc.kaleb_stack.size() == 4 and view._footer.text.begins_with("No free"),
		"with no Focus free, nothing is added and the footer says why (%s)" % view._footer.text)
	gc.archon_foci += 10

	print("\n=== a row's controls change its bar ===")
	var r0: Dictionary = view._rows[0]
	var rep: LineEdit = null
	var on_btn: Button = null
	for c in (r0["panel"] as Control).get_child(0).get_children():
		if c is LineEdit: rep = c
		if c is Button and (c.text == "On" or c.text == "Off"): on_btn = c
	rep.text = "7"
	rep.text_submitted.emit("7")
	ok(gc.kaleb_stack[0]["repeat"] == 7, "the ×N field sets the repeat count (%d)" % gc.kaleb_stack[0]["repeat"])
	rep.text = "0"
	rep.text_submitted.emit("0")
	ok(gc.kaleb_stack[0]["repeat"] == 1, "and clamps it to at least 1")
	on_btn.button_pressed = false
	ok(gc.kaleb_stack[0]["on"] == false and on_btn.text == "Off", "On/Off switches the bar off")
	var if_edits: Array = []
	for c in (view._rows[2]["panel"] as Control).get_child(0).get_children():
		if c is LineEdit: if_edits.append(c)
	if_edits[1].text = "3"
	if_edits[1].text_submitted.emit("3")
	ok(gc.kaleb_stack[2]["goto"] == 2, "the If bar's go-to is shown 1-based and stored 0-based")

	print("\n=== drag and drop ===")
	var first = gc.kaleb_stack[0]
	ok(view._can_drop(Vector2.ZERO, view._drag(Vector2.ZERO, 0), 3), "a dragged bar can drop on another row")
	view._drop(Vector2.ZERO, {"kaleb_bar": 0}, 3)
	await process_frame
	ok(is_same(gc.kaleb_stack[3], first) and is_same(view._rows[3]["bar"], first),
		"dropped on row 4, the first bar takes slot 4 and the rows follow")

	print("\n=== remove, Run/Pause ===")
	var f_before: int = gc.get_total_foci_assigned()
	var del: Button = null
	for c in (view._rows[0]["panel"] as Control).get_child(0).get_children():
		if c is Button and c.text == "×": del = c
	del.pressed.emit()
	await process_frame
	ok(gc.kaleb_stack.size() == 3 and _row_count(view) == 3 and gc.get_total_foci_assigned() == f_before - 1,
		"× removes the bar and returns its Focus")
	view._run_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_running and view._run_btn.text == "Pause", "Run starts Kaleb")
	view._run_btn.pressed.emit()
	ok(not gc.kaleb_running, "Pause stops him")

	print("\n=== Restart sends him back to bar 1 ===")
	gc.kaleb_index = 2
	gc.kaleb_repeat_done = 1
	await process_frame
	ok(not view._restart_btn.disabled, "Restart is live while he's past bar 1")
	view._restart_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_index == 0 and gc.kaleb_repeat_done == 0 and not gc.kaleb_running,
		"Restart puts him on bar 1 with nothing done, still paused")
	ok(view._restart_btn.disabled, "and greys out at bar 1")
	gc.kaleb_index = 1
	gc.kaleb_running = true
	view._restart_btn.pressed.emit()
	ok(gc.kaleb_index == 0 and gc.kaleb_running, "while running, Restart keeps him running from bar 1")
	gc.kaleb_running = false

	print("\n=== the crew control in the header (author, 2026-11-06) ===")
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(2))
	gc.archon_foci = gc.get_total_foci_assigned() + 10
	var row_lbl: Label = view._rows[0]["uonites"] if view._rows[0]["uonites"] else view._rows[1]["uonites"]
	await process_frame
	ok(view._crew_lbl.text == "0U" and row_lbl.text == "0", "no crew yet: the header reads 0U, a bar uses 0")
	for n in 3:
		gc.kaleb_change_crew(1)
	await process_frame
	ok(view._crew_lbl.text == "2U+1F", "a crew of 3: two free Uonites, then a Focus (%s)" % view._crew_lbl.text)
	var wbar: Dictionary = view._rows[0]["bar"] if view._rows[0]["uonites"] else view._rows[1]["bar"]
	gc.kaleb_change_bar_workers(wbar, 1)
	gc.kaleb_change_bar_workers(wbar, 1)
	gc.kaleb_change_bar_workers(wbar, 1)
	await process_frame
	ok(row_lbl.text == "3", "a bar's + uses more of the crew, up to its 3 (%s)" % row_lbl.text)

	print("\n=== Stack slots: save the stack, load it back (author, 2026-11-06) ===")
	gc.kaleb_saved_stacks = [{"bars": [], "crew": 0}, {"bars": [], "crew": 0}, {"bars": [], "crew": 0}]
	gc.archon_foci = gc.get_total_foci_assigned() + 10
	await process_frame
	var n_bars: int = gc.kaleb_stack.size()
	ok(view._load_btn.disabled, "Load is off while the chosen slot is empty")
	view._slot_btns[1].pressed.emit()
	view._save_btn.pressed.emit()
	await process_frame
	var saved: Array = gc.kaleb_saved_bars(1)
	ok(saved.size() == n_bars and not is_same(saved[0], gc.kaleb_stack[0]) and int(gc.kaleb_saved_stacks[1]["crew"]) == 3,
		"Save copies the %d-bar stack and its crew of 3 into Slot 2 (a copy, not the live bars)" % n_bars)
	ok(view._slot_status.text == "Slot 2 · %d bars" % n_bars, "the row says so (%s)" % view._slot_status.text)
	var f_held: int = gc.kaleb_foci_held()
	var u_held: int = gc.kaleb_uonites_held()
	gc.kaleb_remove_bar(0)
	gc.kaleb_change_crew(-1)
	view._load_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_stack.size() == n_bars - 1 and view._load_btn.text == "Replace?",
		"Load over a live stack asks first ('Replace?') and changes nothing yet")
	gc.kaleb_running = true
	view._load_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_stack.size() == n_bars and gc.kaleb_crew_size() == 3 and not gc.kaleb_running and gc.kaleb_index == 0,
		"a second press loads Slot 2's %d bars and crew of 3, paused at bar 1" % n_bars)
	ok(not is_same(gc.kaleb_stack[0], gc.kaleb_saved_bars(1)[0]) and gc.kaleb_foci_held() == f_held
			and gc.kaleb_uonites_held() == u_held,
		"the live stack is its own copy, holding the same Uonites and Foci as before (%d, %d)" % [u_held, f_held])
	view._save_btn.pressed.emit()
	await process_frame
	ok(view._save_btn.text == "Overwrite?", "Save over a saved stack asks first ('Overwrite?')")
	view._slot_btns[0].pressed.emit()
	await process_frame
	ok(view._save_btn.text == "Save", "picking another slot cancels the question")

	print("\n=== loading staffs the saved crew afresh, and refuses what it can't hold ===")
	var big: Array = []
	for i in 30:
		big.append(KC.make_bar("monad_compress"))
	gc.kaleb_saved_stacks[2] = {"bars": big, "crew": 4}
	var live_before: Array = gc.kaleb_stack
	view._slot_btns[2].pressed.emit()
	view._load_btn.pressed.emit()
	view._load_btn.pressed.emit()
	await process_frame
	ok(is_same(gc.kaleb_stack, live_before) and String(view._footer.text).contains("Slot 3 needs 30 Foci and a crew of 4"),
		"a stack whose bars and crew the free pool can't cover is refused and the stack kept (%s)" % view._footer.text)
	var small: Array = [KC.make_bar("monad_compress"), KC.make_bar("tetrad_assemble")]
	small[0]["workers"] = 3
	gc.kaleb_saved_stacks[2] = {"bars": small, "crew": 5}
	var u_av: int = gc._free_uonites() + gc.kaleb_uonites_held()
	view._load_btn.pressed.emit()
	view._load_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_stack.size() == 2 and gc.kaleb_bar_workers(gc.kaleb_stack[0]) == 3
			and gc.kaleb_crew_uonites == mini(5, u_av) and gc.kaleb_crew_size() == 5,
		"it loads with a crew of 5, Uonites first (%dU+%dF, %d Uonites to hand); its bar uses 3" % [
			gc.kaleb_crew_uonites, gc.kaleb_crew_foci, u_av])

	print("\n=== saved stacks live in the game save ===")
	var data = JSON.parse_string(JSON.stringify(gc.get_save_data()))
	gc.kaleb_saved_stacks = []
	gc.load_save_data(data)
	ok(gc.kaleb_saved_bars(1).size() == n_bars and typeof(gc.kaleb_saved_bars(1)[0]["repeat"]) == TYPE_INT
			and int(gc.kaleb_saved_stacks[1]["crew"]) == 3,
		"Slot 2 comes back from a JSON save with %d bars and its crew of 3, numbers still ints" % n_bars)
	var old_slots: Dictionary = {"kaleb_stack": [], "kaleb_saved_stacks": [[{"cmd": "monad_compress", "uonites": 4, "foci_workers": 2}], [], []]}
	gc._load_kaleb_stack(old_slots)
	ok(gc.kaleb_saved_bars(0).size() == 1 and int(gc.kaleb_saved_stacks[0]["crew"]) == 6,
		"a slot saved before the crew (a bare list of bars) reads back with a crew of its largest bar (6)")
	gc.load_save_data(data)

	print("\n=== it fits the Journal ===")
	var panel: Control = journal._panel
	var panel_before: Vector2 = panel.size
	for i in 8:
		view._on_add_chosen(view.PALETTE.find("if"))
	view._on_add_chosen(view.PALETTE.find("persistent_particle"))
	view._on_add_chosen(view.PALETTE.find("lock"))
	await process_frame
	await process_frame
	var pr: Rect2 = panel.get_global_rect()
	var vr: Rect2 = view.get_global_rect()
	ok(panel.size == panel_before and pr.grow(0.5).encloses(vr),
		"with %d bars the view stays inside the %.0fx%.0f Journal panel (view %s)" % [gc.kaleb_stack.size(), pr.size.x, pr.size.y, str(vr.size)])

	scene.queue_free()
	await process_frame
	await process_frame
	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
