extends "res://dev_tests/test_base.gd"
# Reported live (2026-10-09): a staff note was named by mistake and the Staff
# popup's Undo buttons "did nothing". Naming a note merges its record into the
# star's named record, which unions melody_ticks, and nothing took the ticks
# back out: Undo cleared the name marks while the note stayed on the named
# record (still labelled, still deriving its position).
#
# Name Undo (selects / all) now lets the note go onto a fresh, unmarked record
# and leaves the named record, which is the Sort row's, alone.
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


func _named_with_note(d, nm: String, tick: int) -> bool:
	for i in d.record_count():
		var r: Dictionary = d.record_at(i)
		if str(r.get("name", "")) == nm and (r.get("melody_ticks", []) as Array).has(tick):
			return true
	return false


func run() -> void:
	await process_frame
	for which in ["all", "selects"]:
		print("=== name a note by mistake, then Undo %s ===" % which)
		var host = await _make_host()
		var d = host._deduction
		var w = host._widgets
		d._load_match_records([])
		var sort_row: int = d._get_or_create_match_record_for_name("Pyrios")
		d.record_at(sort_row)["seq_candidates"] = [3, 4]
		w._open_staff_popup(2, Vector2.ZERO)
		var rec: int = host._staff_popup.current_record_idx
		await w._on_staff_name_check(rec, "Pyrios", null)
		await process_frame
		ok(_named_with_note(d, "Pyrios", 2), "precondition: the note is now on the Pyrios record")
		var p = host._staff_popup
		if which == "all":
			p._name_btn_undo_all.pressed.emit()
		else:
			p._name_btn_undo_selects.pressed.emit()
		await process_frame
		ok(not _named_with_note(d, "Pyrios", 2), "Undo takes the note off the named record")
		var back: int = d._find_match_record_by_melody_tick(2)
		ok(back >= 0 and str(d.record_at(back).get("name", "")) == "", "the note answers to a fresh unnamed record")
		var row: int = d._find_match_record_by_name("Pyrios") if d.has_method("_find_match_record_by_name") else sort_row
		ok(row >= 0 and (d.record_at(row).get("seq_candidates", []) as Array) == [3, 4], "and the Sort row keeps its own entries")
		host.queue_free()
		await process_frame

	print("\n=== a note on an unnamed record is untouched ===")
	var host2 = await _make_host()
	var d2 = host2._deduction
	var w2 = host2._widgets
	d2._load_match_records([])
	var rec2: int = d2._get_or_create_match_record_for_melody_tick(2)
	w2._open_staff_popup(2, Vector2.ZERO)
	host2._staff_popup._name_btn_undo_all.pressed.emit()
	await process_frame
	var holders: int = 0
	for i2 in d2.record_count():
		if (d2.record_at(i2).get("melody_ticks", []) as Array).has(2):
			holders += 1
	ok(holders == 1 and (d2.record_at(rec2).get("melody_ticks", []) as Array).has(2),
		"the note stays on its own record and nothing else claims it (%d holders)" % holders)

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
