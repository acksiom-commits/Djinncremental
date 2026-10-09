extends "res://dev_tests/test_base.gd"
# The Repeats section on the Staff popup and on the Star Map star widget
# (2026-10-08). Both edit the same record axis as the Sort rows' checklist,
# through shared mutations (_repeat_toggle_confirm / _block / _protect /
# _undo), so what must hold is:
#   - each surface lists one row per repeat bucket;
#   - the check / X / right-click / Undo controls change the record exactly as
#     the Sort-row checklist does (confirm clears siblings, X is a manual block,
#     right-click protects, Undo all releases);
#   - a mutation made on one surface is what the others then read.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 0, 1, 2]
	host._sequence_rank_solution = [3, 0, 5, 1, 4, 2]
	host._repeat_count = [0, 0, 1, 1, 2, -1]
	host._widgets.clear_pitch_caches()
	return host


func _rows_under(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is StaffPopupRow:
			out.append(c)
		_rows_under(c, out)


func run() -> void:
	await process_frame
	var host = await _make_host()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	var buckets: Array = d._get_repeat_bucket_values()
	ok(buckets.size() >= 2, "precondition: there are repeat buckets to list (%d)" % buckets.size())

	print("=== Staff popup ===")
	var rec: int = d._get_or_create_match_record_for_melody_tick(2)
	w._open_staff_popup(2, Vector2.ZERO)
	var popup = host._staff_popup
	var repeat_rows: int = popup._repeat_columns[0].get_child_count() if popup._repeat_columns.size() > 0 else -1
	ok(repeat_rows == buckets.size(), "the Repeats section has one row per bucket (%d of %d)" % [repeat_rows, buckets.size()])
	ok(popup._repeat_added_count == buckets.size(), "and the popup's declared/added row counts agree")

	w._on_staff_repeat_check(rec, 1, null)
	ok(d._effective_repeat_state(rec, 1) == 1, "check confirms a value")
	ok(d._effective_repeat_state(rec, 0) == 2, "and clears its sibling, as the Sort-row checklist does")
	# Un-confirming leaves the siblings struck out (the documented "sticky"
	# behaviour, same on the Sort rows), so the value is re-derived rather than
	# going neutral; Undo is how a player releases it.
	w._on_staff_repeat_undo_all(rec)
	ok(d._effective_repeat_state(rec, 1) == 0 and d._effective_repeat_state(rec, 0) == 0, "Undo all releases a confirm and its siblings")
	w._on_staff_repeat_x(rec, 2, null)
	ok(d._effective_repeat_state(rec, 2) == 2, "X rules a value out")
	ok(bool((d.record_at(rec).get("manual_repeat_blocks", {}) as Dictionary).get(2, false)), "recorded as a manual block (Undo blocks can see it)")
	w._on_staff_repeat_undo_all(rec)
	ok(d._effective_repeat_state(rec, 2) == 0 and d._effective_repeat_state(rec, 1) == 0, "Undo all releases everything")

	print("\n=== Star Map widget ===")
	d._load_match_records([])
	host._star_screen_pos = []
	for i in host._star_count:
		host._star_screen_pos.append(Vector2(40 + i * 30, 60))
	host._selected_star = 0
	w._build_star_widgets_impl()
	await process_frame
	var widget: Node = host._star_widgets[0]
	var rows: Array = []
	_rows_under(widget, rows)
	# the Name checklist uses plain Buttons, not StaffPopupRow, so every
	# StaffPopupRow under the widget is a Repeats row
	ok(rows.size() == buckets.size(), "the star widget lists one Repeats row per bucket (%d of %d)" % [rows.size(), buckets.size()])
	var has_header: bool = false
	var stack: Array = [widget]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).text == "REPEATS":
			has_header = true
		stack.append_array(n.get_children())
	ok(has_header, "under a REPEATS header")

	var srec: int = d._get_or_create_match_record_for_star_idx(0)
	(rows[2] as StaffPopupRow).check_pressed.emit()
	ok(d._effective_repeat_state(srec, 2) == 1, "the star widget's check confirms on its own star's record")
	await process_frame
	await process_frame
	var again: Array = []
	_rows_under(host._star_widgets[0], again)
	ok(again.size() == buckets.size(), "the widget rebuilds with its Repeats rows intact after a change")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
