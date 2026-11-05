extends "res://dev_tests/test_base.gd"
# Study Constellation in the Constellation slideout (2026-11-04), above Inscribe
# Runes, on both pages: the player opens Study from the slideout instead of
# closing it for the button under the Constellation box. It shows when the
# box's button is revealed, opens Study for the constellation chosen in the
# slideout, and the slideout stays open behind the puzzle.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _left_press_at(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	return e


func _check_page(scene: String) -> void:
	print("\n=== %s ===" % scene)
	var page = load(scene).instantiate()
	root.add_child(page)
	await process_frame
	await process_frame
	var pop = page.find_child("ConstellationPopout", true, false)
	var cp = page.find_child("ConstellationPanel", true, false)
	var btn: Button = pop.find_child("StudyConstellationButton", true, false)
	var overlay = page.find_child("ConstellationStudyOverlay", true, false)
	var cd = root.get_node("/root/ConstellationData")
	if btn == null or cp == null or overlay == null:
		ok(false, "the page has the slideout's Study button, the box and the overlay")
		page.queue_free()
		return

	pop.show_tab()
	pop.show_slot_grid()
	pop._on_tab_pressed()
	await process_frame
	ok(btn.get_parent().name == "SelectorVBox" and btn.get_index() == btn.get_parent().get_child_count() - 1,
		"it is the last thing in the Constellation column")

	cp._study_btn.disabled = true
	await process_frame
	ok(not btn.visible, "hidden while the box's Study button is unrevealed")
	cp.reveal_study_button()
	await process_frame
	ok(btn.visible, "shown once it is revealed")
	# With it shown, the panel keeps its height: the column must not outgrow it
	# and push the panel's bottom edge down (it did by 5 px at 75 px tall).
	pop._selected_slot = 2
	pop._refresh_info_panel()
	await process_frame
	await process_frame
	ok(is_equal_approx(pop._panel.size.y, pop.PANEL_HEIGHT),
		"the panel stays %.0f px tall with the button shown (%.0f)" % [pop.PANEL_HEIGHT, pop._panel.size.y])
	var inscribe: Button = pop.find_child("InscribeRunesButton", true, false)
	ok(absf(btn.get_global_rect().position.y - inscribe.get_global_rect().position.y) < 0.5 \
			and absf(btn.get_global_rect().end.y - inscribe.get_global_rect().end.y) < 0.5,
		"it lines up with Inscribe Runes, top and bottom")

	var pick: int = -1
	for id in [2, 1, 0]:
		if cd.unlocked.has(id):
			pick = id
			break
	# The choice is set directly: a slot click also builds that puzzle, which
	# is slow and not what this checks. The button's own send is real, below.
	pop._selected_slot = -1
	await process_frame
	ok(btn.disabled, "disabled with no constellation chosen")
	pop._selected_slot = pick
	await process_frame
	ok(not btn.disabled, "enabled once one is chosen (%d)" % pick)

	# The box can lag behind the slideout's choice; the button sends the
	# slideout's first. That send builds the puzzle (slow), and the code is the
	# slideout's own, shared by both pages, so it is checked on the first page;
	# on the second the box already matches.
	cp._active_id = -1 if scene == "res://RootUI.tscn" else pick
	btn.pressed.emit()
	await process_frame
	ok(overlay.visible and overlay.get_current_constellation_id() == pick and cp.active_constellation() == pick,
		"it opens Study for the slideout's constellation (%d; overlay %d, box %d)"
		% [pick, overlay.get_current_constellation_id(), cp.active_constellation()])
	ok(pop._is_open, "the slideout stays open behind it")
	ok(overlay.z_index > pop.z_index and overlay.z_index > pop._panel.z_index,
		"Study draws over the slideout (z %d over %d)" % [overlay.z_index, pop.z_index])

	# A click in the puzzle, away from the slideout, must not close it.
	var far := Vector2(pop._panel.get_global_rect().end.x + 200.0, 300.0)
	pop._input(_left_press_at(far))
	ok(pop._is_open, "a click in the Study puzzle leaves the slideout open")
	overlay.visible = false
	pop._input(_left_press_at(far))
	ok(not pop._is_open, "with Study shut, a click outside closes the slideout as before")

	page.queue_free()
	await process_frame


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	await _check_page("res://RootUI.tscn")
	await _check_page("res://FirmamentUI.tscn")
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
