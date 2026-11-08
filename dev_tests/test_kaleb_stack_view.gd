extends "res://dev_tests/test_base.gd"
# Kaleb's command stack shares the Allocation Wheel's slot (SysDoc §7.3; moved
# from the Journal's Commands tab by the author, 2026-11-07, which was moved
# from the Constellation box on 2026-11-05): the page opens on the wheel, each
# carries a button to the other, nothing below moves, Firmament has neither,
# and the box's button is Study Constellation; the palette adds bars; each
# row's On/Off, number fields, menus and × change the bar; drag and drop moves
# a bar to the slot it is dropped on; Run/Pause runs Kaleb; the view fits the
# wheel's 375x450 slot.

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
	var display = scene.find_child("KalebDisplay", true, false)
	var wheel = scene.find_child("AllocationWheelControl", true, false)
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_running = false
	gc.kaleb_index = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(10))
	gc.archon_foci = gc.get_total_foci_assigned() + 10

	print("=== where it lives ===")
	ok(view != null and display != null and wheel != null and view.get_parent() == wheel.get_parent()
			and not journal.is_ancestor_of(view) and not cp.is_ancestor_of(view),
		"the stack view shares the wheel's slot, not the Journal or the Constellation box")
	ok(journal._placeholder_tab.text == "Placeholder", "the Journal's sixth tab is a Placeholder again")
	ok(btn.text == "Study Constellation" and not cp.has_method("enable_kaleb_switch"),
		"the box's button is Study Constellation again")
	ok(wheel.visible and not view.visible and not display.is_showing_stack(), "the page opens on the wheel")
	var holder: Control = wheel.get_parent()
	await process_frame
	var holder_h: float = holder.size.y
	var cp_y: float = cp.global_position.y
	var to_stack: Button = null
	for c in wheel.get_children():
		if c is Button and c.text.begins_with("Stack"):
			to_stack = c
	ok(to_stack != null, "the wheel carries a Stack button")
	to_stack.pressed.emit()
	await process_frame
	await process_frame
	ok(view.visible and not wheel.visible and display.is_showing_stack(), "which shows the stack in place of the wheel")
	ok(is_equal_approx(holder.size.y, holder_h) and is_equal_approx(cp.global_position.y, cp_y),
		"and nothing below moves (the Constellation box stays put)")
	var to_wheel: Button = null
	for c in view.find_children("*", "Button", true, false):
		if c.text == "Wheel":
			to_wheel = c
	ok(to_wheel != null, "the stack carries a Wheel button")
	to_wheel.pressed.emit()
	ok(wheel.visible and not view.visible, "which brings the wheel back")
	gc.kaleb_running = true
	await process_frame
	await process_frame
	ok(to_stack.text == "Stack ▶", "while Kaleb runs, the wheel's button says so")
	gc.kaleb_running = false
	display.show_stack(true)
	await process_frame
	await process_frame
	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	await process_frame
	var fj = firm.find_child("JournalPopout", true, false)
	ok(fj._placeholder_tab.text == "Placeholder" and firm.find_child("KalebStackView", true, false) == null
			and firm.find_child("KalebDisplay", true, false) == null,
		"Firmament has neither the stack nor the switch")
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

	print("\n=== Stack slots: each is its own stack (author, 2026-11-06) ===")
	gc.kaleb_saved_stacks = [{"bars": [], "crew": 0}, {"bars": [], "crew": 0}, {"bars": [], "crew": 0}]
	gc.kaleb_slot_stacks = [{"bars": [], "crew": 0}, {"bars": [], "crew": 0}, {"bars": [], "crew": 0}]
	gc.kaleb_live_slot = 0
	gc.archon_foci = gc.get_total_foci_assigned() + 10
	await process_frame
	var live_bars: Array = gc.kaleb_stack
	var n_live: int = live_bars.size()
	gc.kaleb_running = true
	ok(view._stack_slot == 0 and _row_count(view) == n_live, "it shows the live slot, Slot 1, at first (%d bars)" % n_live)
	view._slot_btns[1].pressed.emit()
	await process_frame
	ok(_row_count(view) == 0 and view._slot_status.text == "Slot 2 · Empty",
		"picking Slot 2 shows Slot 2's own stack, empty (%s)" % view._slot_status.text)
	ok(gc.kaleb_running and is_same(gc.kaleb_stack, live_bars) and view._run_btn.text == "Run",
		"while Slot 1 keeps running; here the button offers Run")
	var f_assigned: int = gc.get_total_foci_assigned()
	gc.archon_foci = f_assigned
	view._on_add_chosen(view.PALETTE.find("monad_compress"))
	view._on_add_chosen(view.PALETTE.find("if"))
	view._on_add_chosen(view.PALETTE.find("tetrad_assemble"))
	gc.kaleb_change_crew(1, 1)
	gc.kaleb_change_crew(1, 1)
	await process_frame
	ok(gc.kaleb_bars(1).size() == 3 and _row_count(view) == 3 and gc.get_total_foci_assigned() == f_assigned,
		"bars go into Slot 2 with no Focus free: a stack that isn't running holds nothing")
	ok(gc.kaleb_slot_crew(1) == 2 and view._crew_lbl.text == "2" and gc.kaleb_crew_size() == 3,
		"its crew is planned (2) apart from the running crew (3)")
	view._slot_btns[0].pressed.emit()
	await process_frame
	ok(_row_count(view) == n_live and view._slot_status.text == "Slot 1 · running", "back on Slot 1: its stack, running")

	print("\n=== Save / Load: a slot's base, to return to after experimenting ===")
	view._slot_btns[1].pressed.emit()
	await process_frame
	ok(view._load_btn.disabled, "Load is off while Slot 2 has no base")
	view._save_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_saved_bars(1).size() == 3 and not is_same(gc.kaleb_saved_bars(1)[0], gc.kaleb_bars(1)[0])
			and int(gc.kaleb_saved_stacks[1]["crew"]) == 2,
		"Save copies Slot 2's 3 bars and crew of 2 as its base")
	gc.kaleb_remove_bar(0, 1)
	view._load_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_bars(1).size() == 2 and view._load_btn.text == "Replace?", "Load over its bars asks first ('Replace?')")
	view._load_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_bars(1).size() == 3 and _row_count(view) == 3, "and a second press puts the 3-bar base back")
	view._save_btn.pressed.emit()
	await process_frame
	ok(view._save_btn.text == "Overwrite?", "Save over a base asks first ('Overwrite?')")
	view._slot_btns[2].pressed.emit()
	await process_frame
	ok(view._save_btn.text == "Save", "picking another slot cancels the question")

	print("\n=== Run on another slot: it runs, the old one stops ===")
	view._slot_btns[1].pressed.emit()
	await process_frame
	# What Slot 1 holds counts as freed for the switch, so ask for more than
	# that and the free pool together: a planned crew of 50, nothing free.
	gc.kaleb_slot_stacks[1]["crew"] = 50
	gc.archon_foci = gc.get_total_foci_assigned()
	gc.uonite = gc.get_total_uonites_assigned()
	view._run_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_live_slot == 0 and is_same(gc.kaleb_stack, live_bars) and String(view._footer.text).contains("Slot 2 needs 3 Foci and a crew of 50"),
		"when Slot 1's holdings and the free pool can't cover it, it is refused and Slot 1 keeps running (%s)" % view._footer.text)
	gc.kaleb_slot_stacks[1]["crew"] = 2
	gc.archon_foci = gc.get_total_foci_assigned() + 10
	var held_u0: int = gc.get_total_uonites_assigned().to_int() - gc.kaleb_uonites_held()
	view._run_btn.pressed.emit()
	await process_frame
	ok(gc.kaleb_live_slot == 1 and gc.kaleb_running and gc.kaleb_stack.size() == 3 and gc.kaleb_index == 0,
		"with enough, Slot 2 becomes the running stack, from bar 1")
	ok(gc.kaleb_bars(0).size() == n_live and is_same(gc.kaleb_bars(0), live_bars),
		"Slot 1's stack is kept as it was, no longer running")
	ok(gc.kaleb_foci_held() == 3 + gc.kaleb_crew_foci and gc.kaleb_crew_size() == 2
			and gc.get_total_uonites_assigned().to_int() - gc.kaleb_uonites_held() == held_u0,
		"only Slot 2 now holds: a Focus a bar plus its crew of 2 (%dU+%dF)" % [gc.kaleb_crew_uonites, gc.kaleb_crew_foci])
	ok(view._slot_status.text == "Slot 2 · running", "and the row says so")

	print("\n=== slots live in the game save ===")
	var data = JSON.parse_string(JSON.stringify(gc.get_save_data()))
	gc.kaleb_slot_stacks = []
	gc.kaleb_saved_stacks = []
	gc.kaleb_live_slot = 0
	gc.load_save_data(data)
	ok(gc.kaleb_live_slot == 1 and gc.kaleb_bars(0).size() == n_live and gc.kaleb_slot_crew(0) == 3
			and gc.kaleb_saved_bars(1).size() == 3 and typeof(gc.kaleb_bars(0)[0]["repeat"]) == TYPE_INT,
		"the live slot, Slot 1's stack and crew, and Slot 2's base come back from a JSON save")
	var old_slots: Dictionary = {"kaleb_stack": [], "kaleb_saved_stacks": [[{"cmd": "monad_compress", "uonites": 4, "foci_workers": 2}], [], []]}
	gc._load_kaleb_stack(old_slots)
	ok(gc.kaleb_live_slot == 0 and gc.kaleb_saved_bars(0).size() == 1 and int(gc.kaleb_saved_stacks[0]["crew"]) == 6,
		"a save from before: its stack is live in Slot 1, and a bare-list base gets a crew of its largest bar (6)")
	gc.load_save_data(data)
	gc.kaleb_running = false

	print("\n=== it fits the wheel's slot ===")
	gc.archon_foci = gc.get_total_foci_assigned() + 40
	for i in 8:
		view._on_add_chosen(view.PALETTE.find("if"))
	# Every kind of row, since the widest one sets the width.
	for cmd in view.PALETTE:
		view._on_add_chosen(view.PALETTE.find(cmd))
	await process_frame
	await process_frame
	var vr: Rect2 = view.get_global_rect()
	var need: Vector2 = view.get_combined_minimum_size()
	ok(need.x <= 375.0 and need.y <= 450.0 and vr.size.x <= 375.5 and vr.size.y <= 450.5,
		"with %d bars the view needs %s and fills %s: no more than the wheel's 375x450 slot" % [gc.kaleb_stack.size(), str(need), str(vr.size)])

	scene.queue_free()
	await process_frame
	await process_frame
	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
