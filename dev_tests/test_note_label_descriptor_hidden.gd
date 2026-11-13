extends "res://dev_tests/test_base.gd"
# A clue's "the star that fires Nth note" names the entry holding note N when
# first notes are hidden (reported 2026-11-13, The Archon).
#
# That board keeps no firing positions, and the engine matched a Sequence
# descriptor only by position, so no entry was ever "the star that fires 15th
# note". Clue 15's "... and every star 1 hop from Eosoon are all different
# stars" therefore never reached note 15's entry: it stayed open between
# Selaion and Kerais (Eosoon's neighbour), the board stalled with every name
# placed, and the hints had nothing to say.
#
# Here the map is a chain 0-1-2-3. Star 0 fires on notes 1 and 3, stars 1, 2, 3
# once each on notes 2, 4, 5. With star 0's and star 2's notes placed, notes 2
# and 5 are each open between stars 1 and 3. The clue: the star that fires 5th
# note is not 1 hop from the yellow star (star 0). Star 1 is.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const NAMES := ["Alpha", "Beta", "Gamma", "Delta"]
const COLOR := 2   # ConstellationLogicPuzzle.Category.COLOR
const SEQUENCE := 1

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _place(host, star: int, tick: int) -> void:
	await host._widgets._on_seq_note_select(host._deduction._get_or_create_match_record_for_star_idx(star), tick)


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = NAMES.duplicate()
	host._star_colors = [3, 1, 2, 0]
	host._star_degrees = [1, 2, 2, 1]
	host._pitch_freqs = [293.66, 440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = [1, 2, 1, 3, 4]
	host._melody_star_sequence = [0, 1, 0, 2, 3]
	host._repeat_count = [1, 0, 0, 0]
	host._star_distances = [[0, 1, 2, 3], [1, 0, 1, 2], [2, 1, 0, 1], [3, 2, 1, 0]]
	host._form_clues_cache = []
	host._widgets.clear_pitch_caches()
	var d = host._deduction

	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()
	for s2 in host._star_count:
		await host._on_pitch_listen_star_clicked(s2)
	await _place(host, 0, 1)
	await _place(host, 0, 3)
	await _place(host, 2, 4)
	var e5: int = d._get_or_create_match_record_for_melody_tick(5)
	d._full_propagation_refresh()
	e5 = d._find_match_record_by_melody_tick(5)

	print("=== without the clue ===")
	ok(d._notes_hidden(), "a board with hidden first notes")
	ok(str(d._candidate_stars_for_record(e5)) == str([1, 3]),
		"note 5's entry is open between stars 1 and 3 (got %s)" % str(d._candidate_stars_for_record(e5)))
	ok(d._record_descriptor_state(e5, SEQUENCE, 3) == 1,
		"note 5's entry IS 'the star that fires 5th note' (state %d)" % d._record_descriptor_state(e5, SEQUENCE, 3))

	print("\n=== the clue: the star that fires 5th note is not 1 hop from the yellow star ===")
	host._form_clues_cache = [{
		"text": "The star that fires 5th note is not 1 hop from the yellow star.",
		"search_terms": ["S:5"],
		"disclosures": [{"kind": "distance_hop", "negated": true, "hops": 1,
			"ref": 0, "ref_cat": COLOR, "target": 3, "target_cat": SEQUENCE}],
	}]
	d._full_propagation_refresh()
	e5 = d._find_match_record_by_melody_tick(5)
	ok(str(d._candidate_stars_for_record(e5)) == str([3]),
		"note 5's entry is star 3 (got %s)" % str(d._candidate_stars_for_record(e5)))
	var e2: int = d._find_match_record_by_melody_tick(2)
	ok(e2 >= 0 and str(d._candidate_stars_for_record(e2)) == str([1]),
		"and so note 2 is star 1's (entry %d, got %s)" % [e2, str(d._candidate_stars_for_record(e2)) if e2 >= 0 else "no entry"])
	ok(d._contradictions.is_empty(), "no contradiction (%d)" % d._contradictions.size())

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
