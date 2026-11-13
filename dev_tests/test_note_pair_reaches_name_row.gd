extends "res://dev_tests/test_base.gd"
# Entries of one NAME are one star, located or not (reported 2026-11-13).
#
# The player linked notes 7 and 11 on the Staff ("Same star as note") and ruled
# every other name off that entry, so the staff labelled both notes Eosoon. Yet
# Eosoon's Sort row showed both notes open, the map could not place Eosoon, and
# the hints read the row as holding nothing. Entries were tied together only by
# the MAP STAR they sat on, and neither entry's star was known yet; on the
# reported save's undo history that was 37 of 75 board states.
#
# Here: star 0 fires on notes 1 and 3. Nothing is Listened, so no entry can be
# located on the map. Alpha's Sort row holds no notes of its own and rules out
# note 5; the Staff entry for note 1 is linked to note 3 and has every other
# name ruled out.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const NAMES := ["Alpha", "Beta", "Gamma", "Delta"]

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
	host._star_names = NAMES.duplicate()
	host._star_colors = [3, 1, 2, 0]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [293.66, 440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = [1, 2, 1, 3, 4]
	host._melody_star_sequence = [0, 1, 0, 2, 3]
	host._repeat_count = [1, 0, 0, 0]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var w = host._widgets

	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()

	var alpha: int = d._get_or_create_match_record_for_name("Alpha")
	d.record_at(alpha)["seq_note_blocks"] = [5]
	d._save_puzzle_notes()
	d._full_propagation_refresh()

	var entry: int = d._get_or_create_match_record_for_melody_tick(1)
	d._full_propagation_refresh()
	await w._on_seq_note_select(entry, 3)
	entry = d._find_match_record_by_melody_tick(1)
	d.record_at(entry)["name_states"] = {"Beta": 2, "Gamma": 2, "Delta": 2}
	d._save_puzzle_notes()
	d._full_propagation_refresh()
	alpha = d._find_match_record_by_name("Alpha")

	print("=== setup ===")
	ok(d._notes_hidden(), "a board with hidden first notes")
	ok(entry >= 0 and entry != alpha, "the Staff entry and Alpha's row are two entries (%d, %d)" % [entry, alpha])
	ok(d._find_match_record_by_melody_tick(3) == entry, "note 3 is linked to note 1's entry")
	ok(d._known_name_for_record(entry) == "Alpha", "the staff labels the entry Alpha (got '%s')" % d._known_name_for_record(entry))
	ok(d._effective_star_idx(entry) < 0 and d._effective_star_idx(alpha) < 0,
		"neither entry is located on the map (%d, %d): the case that was broken" % [d._effective_star_idx(entry), d._effective_star_idx(alpha)])

	print("\n=== Alpha's Sort row sees the linked notes ===")
	ok(d._repeat_note_state_for_record(alpha, 1) == 1, "note 1 shows as Alpha's (state %d)" % d._repeat_note_state_for_record(alpha, 1))
	ok(d._repeat_note_state_for_record(alpha, 3) == 1, "note 3 shows as Alpha's (state %d)" % d._repeat_note_state_for_record(alpha, 3))
	ok(str(d._notes_on_star_of(alpha)) == str([1, 3]), "Alpha's star holds notes 1, 3 (got %s)" % str(d._notes_on_star_of(alpha)))

	print("\n=== and the entry sees the row's own marks ===")
	ok(d._repeat_note_state_for_record(entry, 5) == 3,
		"Alpha's 'not note 5' shows on the linked entry (state %d)" % d._repeat_note_state_for_record(entry, 5))

	print("\n=== the hints read the same row ===")
	var fr: Dictionary = d._owner_frame(0)
	ok(not fr.is_empty() and str(fr.get("held", [])) == str([1, 3]),
		"the hint frame for Alpha holds notes 1, 3 (got %s)" % str(fr.get("held", [])))

	print("\n=== a different name is not pulled in ===")
	var beta: int = d._get_or_create_match_record_for_name("Beta")
	d._full_propagation_refresh()
	ok(d._repeat_note_state_for_record(beta, 1) != 1, "Beta's row does not hold note 1 (state %d)" % d._repeat_note_state_for_record(beta, 1))
	ok(d._notes_on_star_of(beta).is_empty(), "Beta's star holds nothing (got %s)" % str(d._notes_on_star_of(beta)))

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
