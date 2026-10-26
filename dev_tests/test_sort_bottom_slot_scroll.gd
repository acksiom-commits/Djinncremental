extends "res://dev_tests/test_base.gd"
# Sort: tab vertical scroll across a click (reported 2026-10-25). Scrolled to
# the bottom of a Sort: tab, every right-click on a checker button in the
# bottom slot threw the Markers scroll ~30px up, so each further entry there
# meant scrolling back down first.
#
# Cause: every click ends in request_markers_rebuild(). In that frame the old
# rows are freed while the new rows' checker strips (horizontal
# ScrollContainers) have not yet shown their scrollbars, so for one layout
# pass the list is shorter than both the old and the finished one, and the
# outer ScrollContainer clamps scroll_vertical to it. Only a scroll within
# that dip of the bottom is affected, which is where the bottom slot sits.
#
# What must hold, on Sort: Name, Color and Pitch:
#  - right-clicking checker buttons in the bottom slot, several in a row with
#    no scrolling in between, leaves scroll_vertical exactly where it was
#  - a middle slot, clicked from a mid-list scroll, keeps its scroll too
#  - a left-click that really shortens the list still lands on the new
#    bottom (the clamp is right there; only the transient one was wrong)
#  - the height held through the rebuild is released a frame later
#
# A/B (2026-10-25): against the unfixed widgets file all 8 bottom-slot checks
# fail (Name 1159 -> 1099, Color 1147 -> 1087, Pitch 799 -> 739 on the first
# click, and it stays there), and so does the left-click one (1099, not the
# new bottom 1154: left-clicks dipped the same way). The middle-slot check
# passes on both -- the dip only reaches a scroll within ~60px of the bottom.
# The fix (_rebuild_markers_in_place) passes all 24.
#
# Instantiates the real ConstellationStudyOverlay scene with a fake 6-star
# board, same setup as test_repeat_count_sort_tab.gd. _cd stays null, so no
# click here writes to the real save.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

## The checker-strip fact rows a Sort slot can carry (checker entry mode).
const CHECKER_FACTS := ["Seq.", "Pitch:", "Repeats:"]
## Sort: tabs by _matches_sort_mode.
const SORT_TABS := {0: "Name", 2: "Color", 3: "Pitch"}
const CLICKS_PER_SLOT := 3

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_host(sort_mode: int):
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	# 12 stars, not test_repeat_count_sort_tab's 6: at 6 the Sort: Color and
	# Pitch slots' strips all fit without a scrollbar, so those tabs never
	# dipped and their checks passed vacuously against the unfixed code.
	host._constellation_id = 0
	host._star_count = 12
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta",
		"Auriel", "Boreas", "Castor", "Doria", "Ixion", "Lyra"]
	host._star_colors = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3]
	host._star_degrees = [2, 2, 3, 1, 2, 3, 1, 2, 2, 3, 1, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 587.33]
	host._star_pitch_index = [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
	host._repeat_count = [0, 0, 1, 1, 2, 0, 0, 1, 1, 2, 0, -1]
	host.visible = true
	# Checker entry mode, set in memory only (set_seq_checker_enabled would
	# write the player's user://study_prefs.cfg).
	host._widgets._seq_checker_loaded = true
	host._widgets._seq_checker_mode = true
	host._deduction._load_match_records([])
	host._widgets._sort_matches(sort_mode)
	await _settle()
	return host


func _settle() -> void:
	for _i in 3:
		await process_frame


func _find_fact_control(node: Node, label_text: String) -> Control:
	for c in node.get_children():
		if c is HBoxContainer and c.get_child_count() >= 2 and c.get_child(0) is Label \
				and (c.get_child(0) as Label).text == label_text:
			return c.get_child(1) as Control
		var deeper: Control = _find_fact_control(c, label_text)
		if deeper != null:
			return deeper
	return null


func _buttons_under(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(c)
		_buttons_under(c, out)


## The Sort slot row (an HBox directly under _markers_content) at `which`,
## -1 = the bottom one.
func _sort_row(host, which: int) -> Node:
	var rows: Array = []
	for c in host._markers_content.get_children():
		if c is HBoxContainer and not c.is_queued_for_deletion():
			rows.append(c)
	return rows[which] if not rows.is_empty() else null


## First value button of a checker strip that a right-click can rule out.
func _checker_button(host, which: int, fact: String) -> Button:
	var row: Node = _sort_row(host, which)
	if row == null:
		return null
	var ctrl: Control = _find_fact_control(row, fact)
	if ctrl == null:
		return null
	var btns: Array = []
	_buttons_under(ctrl, btns)
	for b in btns:
		var btn := b as Button
		if btn.is_visible_in_tree() and not btn.disabled and btn.tooltip_text.contains("right-click: rule out"):
			return btn
	return null


func _right_click(btn: Button) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	btn.gui_input.emit(ev)


func _bottom_scroll(host) -> int:
	var bar: VScrollBar = host._markers_scroll.get_v_scroll_bar()
	return int(bar.max_value - bar.page)


func run() -> void:
	await process_frame

	for mode in SORT_TABS:
		var tab: String = SORT_TABS[mode]
		print("=== Sort: %s, bottom slot, %d right-clicks per strip with no scrolling between ===" % [tab, CLICKS_PER_SLOT])
		for fact in CHECKER_FACTS:
			var host = await _make_host(int(mode))
			var sc: ScrollContainer = host._markers_scroll
			sc.scroll_vertical = 100000
			await _settle()
			var start: int = sc.scroll_vertical
			if start <= 0 or start != _bottom_scroll(host):
				# A fact row this tab's slots don't carry is skipped below; a
				# list that does not scroll at all would make every check vacuous.
				ok(false, "Sort: %s list scrolls and sits at its bottom before clicking (scroll=%d, bottom=%d)" % [tab, start, _bottom_scroll(host)])
				host.queue_free()
				continue
			if _checker_button(host, -1, fact) == null:
				print("  (no %s checker strip in a Sort: %s slot)" % [fact, tab])
				host.queue_free()
				continue
			var judged: int = 0
			var kept: int = 0
			var seen: Array = []
			for _k in CLICKS_PER_SLOT:
				var btn: Button = _checker_button(host, -1, fact)
				if btn == null:
					break
				_right_click(btn)
				await _settle()
				judged += 1
				seen.append(sc.scroll_vertical)
				if sc.scroll_vertical == start:
					kept += 1
			ok(judged == CLICKS_PER_SLOT and kept == judged,
				"Sort: %s bottom slot, %s: scroll kept on %d/%d right-clicks (start %d, after each %s)" % [tab, fact, kept, judged, start, str(seen)])
			ok(is_zero_approx(host._markers_content.custom_minimum_size.y),
				"Sort: %s %s: the held list height is released after the rebuild" % [tab, fact])
			host.queue_free()
			await process_frame

	print("\n=== a middle slot, from a mid-list scroll, keeps its scroll too ===")
	var mid_host = await _make_host(0)
	var mid_sc: ScrollContainer = mid_host._markers_scroll
	mid_sc.scroll_vertical = _bottom_scroll(mid_host) / 2
	await _settle()
	var mid_start: int = mid_sc.scroll_vertical
	var mid_btn: Button = _checker_button(mid_host, 2, "Seq.")
	ok(mid_btn != null and mid_start > 0, "precondition: a middle slot's Seq. strip, list scrolled to %d" % mid_start)
	if mid_btn != null:
		_right_click(mid_btn)
		await _settle()
		ok(mid_sc.scroll_vertical == mid_start, "middle slot right-click: scroll %d -> %d" % [mid_start, mid_sc.scroll_vertical])
	mid_host.queue_free()
	await process_frame

	print("\n=== a left-click that shortens the list still lands on the new bottom ===")
	var left_host = await _make_host(0)
	var left_sc: ScrollContainer = left_host._markers_scroll
	left_sc.scroll_vertical = 100000
	await _settle()
	var left_start: int = left_sc.scroll_vertical
	var left_btn: Button = _checker_button(left_host, -1, "Seq.")
	ok(left_btn != null, "precondition: the bottom slot's Seq. strip")
	if left_btn != null:
		left_btn.pressed.emit()
		await _settle()
		var new_bottom: int = _bottom_scroll(left_host)
		ok(new_bottom < left_start, "precondition: pinning a position really shortens the list (bottom %d -> %d)" % [left_start, new_bottom])
		ok(left_sc.scroll_vertical == mini(left_start, new_bottom),
			"left-click: scroll at %d, the new bottom (%d)" % [left_sc.scroll_vertical, new_bottom])
	left_host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
