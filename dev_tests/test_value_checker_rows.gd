extends "res://dev_tests/test_base.gd"
# Pitch and Repeats checker rows on the Sort tabs (2026-10-08): one on/off
# button per value, the same idea as the Sequence checker, behind the same
# Entry: Classic/Checks switch. ON = still possible, OFF = ruled out, written
# as the player's own hard marks; narrowing to one value confirms it.

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


func _strip(row: Control) -> Array:
	for c in row.get_children():
		if c is ScrollContainer:
			return c.get_child(0).get_children()
	return []


func _row_buttons(row: Control) -> Array:
	var out: Array = []
	for c in row.get_children():
		if c is Button:
			out.append(c)
	return out


func run() -> void:
	await process_frame
	var host = await _make_host()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	w._seq_checker_loaded = true
	w._seq_checker_mode = false
	var rec: int = d._get_or_create_match_record_for_name("Pyrios")

	print("=== the switch: classic rows are unchanged, checks swap them ===")
	var classic: Control = w._make_pitch_checklist_row_for_record(rec)
	ok(_strip(classic).is_empty() and classic.get_child(0) is Button and (classic.get_child(0) as Button).text == "Select Pitch", "classic Pitch row is still the trigger button")
	classic.free()
	w._seq_checker_mode = true

	print("\n=== Pitch checks ===")
	var notes: Array = w._distinct_note_names()
	var prow: Control = w._make_pitch_checklist_row_for_record(rec)
	host.add_child(prow)
	var pbtns: Array = _strip(prow)
	ok(pbtns.size() == notes.size(), "one button per distinct note (%d of %d)" % [pbtns.size(), notes.size()])
	ok((pbtns[0] as Button).text == str(notes[0]), "labelled with the note name")
	w._on_pitch_checker_toggle(rec, str(notes[0]))
	ok(d._effective_pitch_state(rec, str(notes[0])) == 2, "turning a note off rules it out")
	ok(bool((d.record_at(rec).get("manual_pitch_blocks", {}) as Dictionary).get(str(notes[0]), false)), "as a manual block (Undo blocks can see it)")
	w._on_pitch_checker_toggle(rec, str(notes[1]))
	ok(d._effective_pitch_state(rec, str(notes[2])) == 1, "leaving one note confirms it")
	w._on_pitch_checker_toggle(rec, str(notes[2]))
	ok(d._effective_pitch_state(rec, str(notes[2])) == 1, "ruling out the last note is refused")
	w._on_pitch_checker_toggle(rec, str(notes[0]))
	ok(d._effective_pitch_state(rec, str(notes[0])) == 0 and d._effective_pitch_state(rec, str(notes[2])) == 0, "turning one back on reopens the confirmed one")
	w._on_pitch_checklist_undo_all_no_popup(rec)
	var all_open: bool = true
	for n in notes:
		if d._effective_pitch_state(rec, str(n)) != 0:
			all_open = false
	ok(all_open, "Undo puts every note back")
	# locked rows
	d.record_at(rec)["pitch_revealed"] = true
	var lrow: Control = w._make_pitch_checklist_row_for_record(rec)
	host.add_child(lrow)
	var any_enabled: bool = false
	for b in _strip(lrow):
		if not (b as Button).disabled:
			any_enabled = true
	ok(not any_enabled, "a Listened row is shown but not editable")
	w._on_pitch_checker_toggle(rec, str(notes[0]))
	ok(not w._any_state(rec, "pitch_states", 1) and w._own_off_set(rec, "pitch_states").is_empty(), "and the handler refuses to write to it")
	d.record_at(rec)["pitch_revealed"] = false

	print("\n=== Repeats checks ===")
	var buckets: Array = d._get_repeat_bucket_values()
	var rrow: Control = w._make_repeat_checklist_row_for_record(rec)
	host.add_child(rrow)
	var rbtns: Array = _strip(rrow)
	ok(rbtns.size() == buckets.size(), "one button per repeat bucket (%d of %d)" % [rbtns.size(), buckets.size()])
	w._on_repeat_checker_toggle(rec, int(buckets[0]))
	ok(d._effective_repeat_state(rec, int(buckets[0])) == 2, "turning a bucket off rules it out")
	w._on_repeat_checker_toggle(rec, int(buckets[1]))
	ok(d._effective_repeat_state(rec, int(buckets[2])) == 1, "leaving one bucket confirms it")
	var undo_btn: Button = _row_buttons(rrow)[_row_buttons(rrow).size() - 1]
	ok(undo_btn.text == "↶", "the row ends with an UNDO button")
	w._repeat_undo(rec, true, true)
	ok(d._effective_repeat_state(rec, int(buckets[2])) == 0 and d._effective_repeat_state(rec, int(buckets[0])) == 0, "Undo releases every mark")
	# a bucket-slot record is locked
	var slot_rec: int = d._get_or_create_match_record_for_repeat_slot(0, 0)
	var srow: Control = w._make_repeat_checklist_row_for_record(slot_rec)
	host.add_child(srow)
	var slot_enabled: bool = false
	for b2 in _strip(srow):
		if not (b2 as Button).disabled:
			slot_enabled = true
	ok(not slot_enabled, "a Repeats bucket-slot record is shown but not editable")
	w._on_repeat_checker_toggle(slot_rec, 1)
	ok(d._effective_repeat_state(slot_rec, 0) == 1, "and its slot confirmation is untouched")

	print("\n=== ruled-out values are hidden; the return button brings them back ===")
	d.record_at(rec)["pitch_states"] = {}
	d.record_at(rec)["manual_pitch_blocks"] = {}
	d._full_propagation_refresh()
	var row_a: Control = w._make_pitch_checklist_row_for_record(rec)
	host.add_child(row_a)
	var ret_a: Button = null
	for cb in row_a.get_children():
		if cb is Button and (cb as Button).text == "→":
			ret_a = cb
	ok(ret_a != null, "the row has a straight right-arrow return button (not the curved undo)")
	ok(ret_a != null and ret_a.disabled, "greyed out while nothing is ruled out")
	var all_shown: bool = true
	for sb in _strip(row_a):
		if not (sb as Button).visible:
			all_shown = false
	ok(all_shown, "with nothing ruled out every value is shown")
	w._on_pitch_checker_toggle(rec, str(notes[0]))
	row_a.free()
	row_a = w._make_pitch_checklist_row_for_record(rec)
	host.add_child(row_a)
	var strip_a: Array = _strip(row_a)
	ok(not (strip_a[0] as Button).visible and (strip_a[1] as Button).visible and (strip_a[2] as Button).visible,
		"a note ruled out disappears and the others stay")
	for cb2 in row_a.get_children():
		if cb2 is Button and (cb2 as Button).text == "→":
			ret_a = cb2
	ok(not ret_a.disabled, "the return button is available once something is ruled out")
	ret_a.pressed.emit()
	await process_frame
	var row_b: Control = w._make_pitch_checklist_row_for_record(rec)
	host.add_child(row_b)
	ok((_strip(row_b)[0] as Button).visible, "pressing it shows the ruled-out note again")
	var strip_b: Array = _strip(row_b)
	strip_b[0].pressed.emit()
	await process_frame
	ok(d._effective_pitch_state(rec, str(notes[0])) == 0, "and clicking it restores the value")
	# the reveal state survives the rebuild every click causes, then hides again
	for cb3 in row_b.get_children():
		if cb3 is Button and (cb3 as Button).text == "→":
			cb3.pressed.emit()
	await process_frame
	var row_c: Control = w._make_pitch_checklist_row_for_record(rec)
	host.add_child(row_c)
	ok(not w._checker_show_off.get("off:p%d" % rec, true), "pressing return again hides them (state kept per row)")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
