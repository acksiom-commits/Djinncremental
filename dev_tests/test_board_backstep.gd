extends "res://dev_tests/test_base.gd"
# Backstep / Forward through the board's history (2026-10-17, author).
#
#  - Backstep undoes the player's entries one at a time, newest first; Forward
#    re-applies them; a new entry after a Backstep clears Forward.
#  - Two things are never undone: which star each placed note belongs to, and
#    Listen. A note placed between two marks stays where it was placed when
#    either mark is undone, and placing it is not a step of its own.
#  - The history is saved with the board and comes back on reload.

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
	# Alpha fires on notes 1 and 6, Beta on 2 and 3, Gamma on 4, Delta on 5.
	host._melody_seq_pos_sequence = [1, 2, 2, 3, 4, 1]
	host._melody_star_sequence = [0, 1, 1, 2, 3, 0]
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _blocked(d, star: int, nm: String) -> bool:
	var r: int = d._find_match_record_by_star_idx(star)
	return r >= 0 and (d.record_at(r).get("manual_name_blocks", {}) as Dictionary).has(nm)


func _note6_on_alpha(d) -> bool:
	var r: int = d._find_match_record_by_star_idx(0)
	return r >= 0 and (d.record_at(r).get("melody_ticks", []) as Array).has(6)


func _all_listened(d) -> bool:
	for s in 4:
		var r: int = d._find_match_record_by_star_idx(s)
		if r < 0 or not bool(d.record_at(r).get("pitch_revealed", false)):
			return false
	return true


func run() -> void:
	var host = await _host()
	var d = host._deduction
	var w = host._widgets

	print("=== Listen is not a step ===")
	for s in 4:
		await host._on_pitch_listen_star_clicked(s)
	ok(not d.can_backstep(), "after Listening to every star there is nothing to backstep")

	print("\n=== a mark, a placed note, another mark ===")
	w._on_slot_name_x(d._find_match_record_by_star_idx(0), "Beta", null)    # mark A
	await w._on_seq_note_select(d._find_match_record_by_star_idx(0), 6)     # note 6 is Alpha's
	w._on_slot_name_x(d._find_match_record_by_star_idx(1), "Gamma", null)   # mark B
	ok(_blocked(d, 0, "Beta") and _blocked(d, 1, "Gamma") and _note6_on_alpha(d),
		"precondition: both marks are on the board and note 6 is on Alpha")
	ok(d._board_undo.size() == 2, "two steps recorded, the placed note not among them (%d)" % d._board_undo.size())

	print("\n=== Backstep, newest first ===")
	ok(d.board_step(false), "Backstep changed the board")
	ok(not _blocked(d, 1, "Gamma") and _blocked(d, 0, "Beta"), "the first Backstep took back mark B only")
	ok(_note6_on_alpha(d), "note 6 is still on Alpha")
	ok(d.board_step(false), "a second Backstep changed the board")
	ok(not _blocked(d, 0, "Beta"), "the second Backstep took back mark A")
	ok(_note6_on_alpha(d), "note 6 is still on Alpha, though it was placed after mark A")
	ok(_all_listened(d), "every star is still Listened")
	ok(not d.can_backstep() and d.can_forward(), "nothing left to backstep; Forward is available")

	print("\n=== Forward ===")
	ok(d.board_step(true), "Forward changed the board")
	ok(_blocked(d, 0, "Beta") and not _blocked(d, 1, "Gamma"), "the first Forward put mark A back")
	d.board_step(true)
	ok(_blocked(d, 1, "Gamma"), "the second Forward put mark B back")
	ok(_note6_on_alpha(d) and _all_listened(d), "note 6 and every Listen survived the round trip")

	print("\n=== a new entry after a Backstep clears Forward ===")
	d.board_step(false)
	ok(d.can_forward(), "precondition: Forward is available after a Backstep")
	w._on_slot_name_x(d._find_match_record_by_star_idx(2), "Delta", null)
	ok(not d.can_forward(), "a new mark clears Forward")
	ok(d.can_backstep(), "and can itself be backstepped")

	print("\n=== the history is saved with the board ===")
	var host2 = await _host()
	var d2 = host2._deduction
	var notes: Dictionary = {}
	d._save_puzzle_notes()
	var depth: int = d._board_undo.size()
	notes = host._cd.get_player_puzzle_notes(0) if host._cd else {}
	if notes.is_empty():
		# No ConstellationData in this harness: round-trip through JSON by hand,
		# the way the save file does.
		notes = JSON.parse_string(JSON.stringify({"match_records": d._save_match_records(),
			"board_undo": d._board_undo, "board_redo": d._board_redo, "record_uid_next": d._next_record_uid}))
	d2._load_match_records(notes["match_records"])
	d2._load_board_history(notes)
	ok(d2._board_undo.size() == depth and d2.can_backstep(), "the reloaded board has the same %d steps" % depth)
	ok(d2.board_step(false), "a Backstep on the reloaded board changes it")
	ok(not _blocked(d2, 2, "Delta"), "and takes back the last mark made before the save")

	host.queue_free()
	host2.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
