extends "res://dev_tests/test_base.gd"
# Star popups and the Staff bar must agree on which notes a star fires on
# (reported 2026-10-18 on The Bellows).
#
# A note placed in a star's popup goes onto the star's own map entry. Once a
# NAMED entry is tied to the star some other way, the popup reads the named
# entry instead (_find_match_record_by_star_idx), and the engine does not
# merge the two (_settle_identical_records). The note was stranded: the Staff
# bar still named it after the star, the popup showed it open. The note rows
# now read every entry for the same star (_records_sharing_star).

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
	# Alpha fires on notes 1 and 6.
	host._melody_seq_pos_sequence = [1, 2, 2, 3, 4, 1]
	host._melody_star_sequence = [0, 1, 1, 2, 3, 0]
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])

	# Note 6 placed in star 0's popup, before any name is known.
	var own: int = d._get_or_create_match_record_for_star_idx(0)
	await w._on_seq_note_select(own, 6)
	var own_uid: int = int(d.record_at(d._record_index_holding_tick(6)).get("uid", 0))

	# Then the name Alpha is tied to star 0 elsewhere (every other star ruled out).
	var named: int = d._get_or_create_match_record_for_name("Alpha")
	d.record_at(named)["star_elim"] = {1: 2, 2: 2, 3: 2}
	d._save_puzzle_notes()
	d._full_propagation_refresh()

	var popup_rec: int = d._find_match_record_by_star_idx(0)
	var holder: int = d._record_index_holding_tick(6)
	ok(int(d.record_at(holder).get("uid", 0)) == own_uid and popup_rec != holder,
		"precondition: the popup now reads a different entry from the one holding note 6 (popup %d, holder %d)" % [popup_rec, holder])
	var sp: int = d._seq_pos_for_melody_tick(6)
	var staff: String = d._known_name_for_seq_position(sp) if sp > 0 else d._known_name_for_record(d._find_match_record_by_melody_tick(6))
	ok(staff == "Alpha", "the Staff bar names note 6 Alpha (got '%s')" % staff)
	ok(d._repeat_note_state_for_record(popup_rec, 6) == 1, "star 0's popup shows note 6 as its own (got %d)" % d._repeat_note_state_for_record(popup_rec, 6))
	ok(d._repeat_note_state_for_record(d._find_match_record_by_name("Alpha"), 6) == 1, "and so does Alpha's name row")
	ok(d._repeat_note_state_for_record(d._get_or_create_match_record_for_star_idx(1), 6) != 1, "another star's popup does not")

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
