extends "res://dev_tests/test_base.gd"
# SOLVE autoplays the solution only once the melody is on the Staff bar
# correctly (2026-10-19, author).
#
#  1. staff_sequence_correct(): every note settled to the star that really
#     fires it. Empty board: no. Every note placed on its true star: yes. One
#     note left open, or one note on the wrong star: no.
#  2. autoplay_solution(): plays the melody in order, lighting each star as
#     its note sounds, then completes the puzzle (the solve is recorded) as a
#     click-through would.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const EngineScript = preload("res://click_sequence_puzzle_engine.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host(melody_seq_pos: Array, melody_stars: Array, repeats: Array):
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
	host._melody_seq_pos_sequence = melody_seq_pos
	host._melody_star_sequence = melody_stars
	host._repeat_count = repeats
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func run() -> void:
	print("=== 1. the Staff bar check ===")
	# Alpha fires on notes 1 and 6, Beta on 2 and 3, Gamma on 4, Delta on 5.
	var truth: Array = [0, 1, 1, 2, 3, 0]
	var host = await _host([1, 2, 2, 3, 4, 1], truth, [1, 1, 0, 0])
	var d = host._deduction
	var w = host._widgets
	for s in 4:
		await host._on_pitch_listen_star_clicked(s)
	ok(not d.staff_sequence_correct(), "an empty board is not the melody")
	# Every note but the last on its true star, through the star's own note row.
	for t in range(1, 6):
		await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(int(truth[t - 1])), t)
	d._full_propagation_refresh()
	ok(not d.staff_sequence_correct(), "one note still open: not yet")
	await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(0), 6)
	d._full_propagation_refresh()
	ok(d.staff_sequence_correct(), "every note on the star that fires it: yes")
	# Swap notes 4 and 5 between Gamma and Delta (each fires once, so each row
	# is full: take both notes off first, then place them crossed).
	await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(2), 4)
	await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(3), 5)
	await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(2), 5)
	await w._on_seq_note_select(d._get_or_create_match_record_for_star_idx(3), 4)
	d._full_propagation_refresh()
	ok(d._record_index_holding_tick(5) == d._find_match_record_by_star_idx(2)
		and d._record_index_holding_tick(4) == d._find_match_record_by_star_idx(3),
		"precondition: notes 4 and 5 now sit on the wrong stars")
	ok(not d.staff_sequence_correct(), "two notes on the wrong stars: no")
	host.queue_free()
	await process_frame

	print("\n=== 2. autoplay plays the melody and completes ===")
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	var eng = EngineScript.new()
	eng.configure_io(null, func(): pass)
	eng.set_constellation(2, cd, gc)
	eng.note_assignment = cd.get_note_assignment(2)
	eng._build_correct_star_sequence()
	eng.state = EngineScript.State.ACTIVE
	var want: Array = eng.correct_sequence.duplicate()
	ok(want.size() >= 4, "precondition: a melody to play (%d notes)" % want.size())
	eng.autoplay_solution()
	ok(eng.replay_active and eng.autoplay_active, "autoplay started")
	eng.on_star_clicked(int(want[1]))
	ok(eng.step == 0, "clicks are ignored while it plays (step %d)" % eng.step)
	var lit: Array = []
	for _i in want.size() * 3 + 10:
		eng.tick(1.0)
		if eng.replay_lit_star >= 0 and (lit.is_empty() or lit.size() < want.size()):
			lit.append(eng.replay_lit_star)
		if not eng.autoplay_active:
			break
	ok(lit == want, "it lit every star in melody order (%d of %d)" % [lit.size(), want.size()])
	ok(int(gc.assignments.get("constellation_2_solve_count", 0)) == 1, "the puzzle is recorded solved")
	ok(not eng.autoplay_active and not eng.replay_active, "and autoplay has ended")

	print("\n=== 3. not from a puzzle that is not active ===")
	var eng2 = EngineScript.new()
	eng2.configure_io(null, func(): pass)
	eng2.set_constellation(2, cd, gc)
	eng2.autoplay_solution()
	ok(not eng2.autoplay_active, "an idle puzzle does not autoplay")

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
