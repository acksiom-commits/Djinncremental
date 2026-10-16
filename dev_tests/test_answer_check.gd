extends "res://dev_tests/test_base.gd"
# THE ANSWER CHECK FOR A FILLED CHARACTERISTIC (author, 2026-10-16).
#
# Once every note belongs to a known star, or every map star shows a name, the
# board compares that characteristic with the answer and marks the wrong
# entries (Beginner-Easy, the author's "option 2"). Before it is filled, it
# says nothing: the board must not become guess-and-check.
#
#  1. Not filled: no verdict at all.
#  2. Filled and right: "correct", nothing marked.
#  3. Filled with two notes swapped: exactly those two notes are marked.
#  4. Names: filled and right / two names swapped.
#  5. Off unless Easy (or switched on).

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
	host._star_colors = [0, 1, 2, 3]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = [1, 2, 2, 3, 4, 1]
	host._melody_star_sequence = [0, 1, 1, 2, 3, 0]
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


## Puts each listed note on map star s's own row.
func _place(host, plan: Dictionary) -> void:
	var d = host._deduction
	var w = host._widgets
	for s in plan:
		for t in plan[s]:
			await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(int(s)), int(t))


func run() -> void:
	print("=== notes ===")
	var host = await _host()
	var d = host._deduction
	d.answer_check_mode = 1
	await _place(host, {0: [1, 6], 1: [2, 3], 2: [4]})
	d._full_propagation_refresh()
	ok(not bool(d.answer_check.get("notes", {}).get("filled", true)), "1. with note 5 still unplaced, no verdict on the notes")
	ok(host._answer_check_lines().is_empty(), "   and nothing in the banner")
	await _place(host, {3: [5]})
	d._full_propagation_refresh()
	var notes: Dictionary = d.answer_check.get("notes", {})
	ok(bool(notes.get("filled", false)) and (notes.get("wrong", ["x"]) as Array).is_empty(), "2. every note placed right: filled, nothing wrong")
	var lines: Array = host._answer_check_lines()
	ok(lines.size() == 1 and str(lines[0]).contains("All 6 notes are filled in and correct."), "   the banner says so (%s)" % str(lines))
	host.queue_free()

	host = await _host()
	d = host._deduction
	d.answer_check_mode = 1
	# Notes 4 and 5 swapped between Gamma's and Delta's stars.
	await _place(host, {0: [1, 6], 1: [2, 3], 2: [5], 3: [4]})
	d._full_propagation_refresh()
	notes = d.answer_check.get("notes", {})
	ok(bool(notes.get("filled", false)) and notes.get("wrong", []) == [4, 5], "3. notes 4 and 5 swapped: exactly those two are wrong (%s)" % str(notes.get("wrong", [])))
	ok(d.answer_check_note_wrong(4) and d.answer_check_note_wrong(5) and not d.answer_check_note_wrong(1), "   the staff marks notes 4 and 5, not note 1")
	lines = host._answer_check_lines()
	ok(lines.size() == 1 and str(lines[0]).contains("2 are wrong") and str(lines[0]).contains("notes 4, 5"), "   the banner names them (%s)" % str(lines))
	host.queue_free()

	print("\n=== names ===")
	host = await _host()
	d = host._deduction
	d.answer_check_mode = 1
	for s in 4:
		d._get_or_create_match_record_for_star_idx(s)
	for s2 in 3:
		d.record_at(d._find_match_record_by_star_idx(s2))["name"] = str(host._star_names[s2])
	d._full_propagation_refresh()
	ok(not bool(d.answer_check.get("names", {}).get("filled", true)), "4. with one star unnamed, no verdict on the names")
	d.record_at(d._find_match_record_by_star_idx(3))["name"] = "Delta"
	d._full_propagation_refresh()
	var names: Dictionary = d.answer_check.get("names", {})
	ok(bool(names.get("filled", false)) and (names.get("wrong", ["x"]) as Array).is_empty(), "   every star named right: filled, nothing wrong")
	d.record_at(d._find_match_record_by_star_idx(2))["name"] = "Delta"
	d.record_at(d._find_match_record_by_star_idx(3))["name"] = "Gamma"
	d._full_propagation_refresh()
	names = d.answer_check.get("names", {})
	ok(names.get("wrong", []) == [2, 3] and d.answer_check_name_wrong(2) and not d.answer_check_name_wrong(0),
		"   Gamma and Delta swapped: exactly those two map stars are marked (%s)" % str(names.get("wrong", [])))

	print("\n=== off unless Easy ===")
	d.answer_check_mode = -1   # by difficulty, as in the game
	var gc = load("res://game_context.gd").new()
	host._gc = gc
	gc.constellation_difficulty[0] = "hard"
	d._full_propagation_refresh()
	ok(d.answer_check.is_empty() and host._answer_check_lines().is_empty(), "5. on Hard, no answer check at all")
	gc.constellation_difficulty[0] = "easy"
	d._full_propagation_refresh()
	ok(d.answer_check_name_wrong(2), "   on Easy, it runs")
	host.queue_free()

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
