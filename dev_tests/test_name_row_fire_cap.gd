extends "res://dev_tests/test_base.gd"
# A NAME'S ROW CANNOT HOLD MORE NOTES THAN THE STAR FIRES (2026-10-16).
#
# Reported from a live board (The Spark): the player confirmed "Dobraan" on the
# entries of notes 6, 9 and 14 one at a time; each joined Dobraan's row, which
# ended on five notes for a star that fires four times ("Repeats 3"), and
# nothing objected. The row's own note buttons were capped; joining entries
# went around that.
#
#  1. Prevention: once the name's row holds as many notes as it fires, the name
#     is ruled out on any other note entry (it would overfill the row) -- and
#     still open while there is room.
#  2. The Staff popup's confirm refuses it.
#  3. Safety net: a row that ends up over its count anyway is a contradiction.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
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
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	ok(d._notes_hidden(), "a repeating melody with the first notes hidden")

	# Alpha's row: marked "repeats once" (fires twice), holding note 1.
	var a: int = d._get_or_create_match_record_for_name("Alpha")
	d.record_at(a)["repeat_states"] = {1: 1}
	d._full_propagation_refresh()
	await w._on_seq_note_select(d._get_or_create_match_record_for_name("Alpha"), 1)
	a = d._get_or_create_match_record_for_name("Alpha")
	ok(d._known_fire_count_for_record(a) == 2 and d.record_at(a)["melody_ticks"] == [1], "precondition: Alpha fires twice and holds note 1")

	print("\n=== 1. ruled out on other entries only once the row is full ===")
	var e6: int = d._get_or_create_match_record_for_melody_tick(6)
	ok(d._effective_name_state(e6, "Alpha") == 0, "with room for one more note, Alpha is still open on note 6's entry")
	# Fill the row: note 2 joins it.
	await w._on_seq_note_select(d._get_or_create_match_record_for_name("Alpha"), 2)
	a = d._get_or_create_match_record_for_name("Alpha")
	ok((d.record_at(a)["melody_ticks"] as Array).size() == 2, "Alpha's row now holds two notes")
	e6 = d._get_or_create_match_record_for_melody_tick(6)
	ok(d._effective_name_state(e6, "Alpha") == 2, "with the row full, Alpha is ruled out on note 6's entry")
	ok(d._effective_name_state(e6, "Gamma") == 0, "other names stay open there")

	print("\n=== 2. the Staff popup's confirm refuses it ===")
	w._on_staff_name_check(e6, "Alpha", null)
	e6 = d._get_or_create_match_record_for_melody_tick(6)
	a = d._get_or_create_match_record_for_name("Alpha")
	ok((d.record_at(a)["melody_ticks"] as Array).size() == 2 and int(d.record_at(e6).get("name_states", {}).get("Alpha", 0)) == 0,
		"confirming Alpha on note 6 changes nothing (Alpha still on 2 notes)")

	print("\n=== 3. a row over its count anyway is a contradiction ===")
	d._detect_contradictions()
	var before: int = 0
	for c in d._contradictions:
		if str(c.get("axis", "")) == "notes":
			before += 1
	ok(before == 0, "no such contradiction while the row is within its count")
	d._propagate_name_states_confirmed_same_record(e6, "Alpha")   # joined some other way
	d._save_puzzle_notes()
	d._full_propagation_refresh()
	a = d._get_or_create_match_record_for_name("Alpha")
	d._detect_contradictions()
	var found: String = ""
	for c2 in d._contradictions:
		if str(c2.get("axis", "")) == "notes":
			found = str(c2["text"])
	ok((d.record_at(a)["melody_ticks"] as Array).size() == 3 and found == "Alpha is entered on 3 notes, but fires only 2 times.",
		"Alpha forced onto a third note is flagged: '%s'" % found)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
