extends "res://dev_tests/test_base.gd"
# REPEATS ARE EARNED (author ruling 2026-10-10; this file used to pin the
# opposite, "the staff shows the repeat shape and a star's notes share one
# record", and its old assertions failed 10 ways against the new code).
#
# On a repeating melody (more notes than stars) the staff gives away ONE thing
# about the shape: which notes are a star's FIRST firing. So:
#   - a first note is the not-yet-known GREEN until its colour is known;
#   - a REPEAT note (an earlier star firing again) is DIM until the board knows
#     its colour;
#   - a known colour always wins.
# A 1:1 melody has no repeat notes, so every note keeps the original green.
#
# Which star a repeat note belongs to is NOT given:
#   - every note opens its OWN record; clicking never groups notes;
#   - the board's rank for a repeat note is 0 (unknown) until the player places
#     it, and the board accepts a WRONG placement (it is not reading the answer);
#   - all the board derives for an unplaced repeat note is that its star first
#     fired before it;
#   - placing it (the Staff popup's "Same star as note" row) is what makes the
#     staff, the star's tag and the name readout follow, and Undo takes it back.
#
# Fixture: 4 stars, 6 notes, note -> rank [1,2,2,3,4,1]. First notes are 1, 2, 4
# and 5 (ranks 1..4); note 3 repeats rank 2 and note 6 repeats rank 1.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host(melody: Array):
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
	host._melody_seq_pos_sequence = melody
	# SEAM ONLY since 2026-10-12: this file pins the behaviour in which the
	# player is shown which notes are first firings. The game no longer does
	# that (first notes are hidden; see test_seq_checker_row.gd's "first notes
	# hidden" section for what it does now), so everything here runs with the
	# seam that keeps the older behaviour.
	host._deduction.notes_hidden_enabled = false
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func host_flat_row_unchanged(h) -> bool:
	h._deduction._load_match_records([{"seq_lo": 2, "seq_hi": 2}])
	var fb: Color = h._widgets.STATE_COLORS.unresolved_fallback
	var same: bool = h._widgets._seq_row_color(0, fb) == fb
	h.queue_free()
	return same


func _identity_buttons(row: Control) -> Array:
	var out: Array = []
	for c in row.get_children():
		if c is Button and (c as Button).text.is_valid_int():
			out.append(int((c as Button).text))
	return out


func run() -> void:
	var host = await _host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var w = host._widgets

	print("=== which notes are first firings is public, and nothing more ===")
	var firsts: Array = []
	for t in range(1, 7):
		if d._tick_is_first_fire(t):
			firsts.append(t)
	ok(firsts == [1, 2, 4, 5], "first notes are 1, 2, 4, 5 (got %s)" % str(firsts))
	ok(d._seq_pos_for_melody_tick(1) == 1 and d._seq_pos_for_melody_tick(2) == 2
		and d._seq_pos_for_melody_tick(4) == 3 and d._seq_pos_for_melody_tick(5) == 4,
		"a first note's position is known from the start")
	ok(d._seq_pos_for_melody_tick(3) == 0 and d._seq_pos_for_melody_tick(6) == 0,
		"a repeat note's position is NOT known (got %d and %d)" % [d._seq_pos_for_melody_tick(3), d._seq_pos_for_melody_tick(6)])
	ok(d._first_tick_for_rank(1) == 1 and d._first_tick_for_rank(2) == 2 and d._first_tick_for_rank(3) == 4 and d._first_tick_for_rank(4) == 5,
		"each position's first note is readable")
	ok(d._known_ticks_for_rank(1) == [1] and d._known_ticks_for_rank(2) == [2],
		"a position's known notes are just its first note (got %s, %s)" % [str(d._known_ticks_for_rank(1)), str(d._known_ticks_for_rank(2))])
	ok(w._ordinal_str("2") == "2", "a star's tag lists only the notes the board knows (got '%s')" % w._ordinal_str("2"))

	print("\n=== the colour rule on a repeating melody ===")
	# 2026-10-12: the bar no longer colours repeat notes differently. Every
	# note is the not-yet-known green until its star's colour is known.
	var green: Color = host.UNKNOWN_SEQ_COLOR
	var all_green: bool = true
	for t2 in range(1, 7):
		if w._staff_tick_color(t2, -1) != green:
			all_green = false
	ok(all_green, "first notes and repeat notes are the same green while their colour is unknown")
	ok(w._staff_tick_color(1, 2) == host.STAR_COLORS_BY_IDX[2], "a known colour replaces the green on a first note")
	ok(w._staff_tick_color(3, 1) == host.STAR_COLORS_BY_IDX[1], "a known colour replaces the green on a repeat note")

	print("\n=== a 1:1 melody keeps the original green everywhere ===")
	var host_flat = await _host([1, 2, 3, 4])
	var w_flat = host_flat._widgets
	var flat_ok: bool = true
	for tick in [1, 2, 3, 4]:
		if w_flat._staff_tick_color(tick, -1) != host_flat.UNKNOWN_SEQ_COLOR:
			flat_ok = false
	ok(flat_ok, "every note of a 1:1 melody stays the not-yet-known green")
	host_flat.queue_free()
	var host_old = await _host([])
	ok(host_old._widgets._staff_tick_color(1, -1) == host_old.UNKNOWN_SEQ_COLOR, "an old cache with no melody table keeps the original green")
	host_old.queue_free()
	await process_frame

	print("\n=== one note, one record: a click never groups notes ===")
	d._load_match_records([])
	var r1: int = d._get_or_create_match_record_for_melody_tick(1)
	ok((d.record_at(r1)["melody_ticks"] as Array) == [1], "clicking note 1 opens a record holding note 1 alone (got %s)" % str(d.record_at(r1)["melody_ticks"]))
	var r6: int = d._get_or_create_match_record_for_melody_tick(6)
	ok(r6 != r1 and (d.record_at(r6)["melody_ticks"] as Array) == [6], "clicking note 6 (the same star, secretly) opens a DIFFERENT record holding note 6 alone")
	ok(d._get_or_create_match_record_for_melody_tick(6) == r6, "clicking note 6 again finds that record")
	var r3: int = d._get_or_create_match_record_for_melody_tick(3)
	ok(d.record_count() == 3, "three notes clicked, three records (got %d)" % d.record_count())
	var unpinned: bool = true
	for ri in [r1, r6, r3]:
		if int(d.record_at(ri)["seq_lo"]) != 0 or int(d.record_at(ri)["seq_hi"]) != 0:
			unpinned = false
	ok(unpinned, "and none of them has a Sequence entry pre-filled")

	print("\n=== all the board derives for a repeat note: its star fired earlier ===")
	d._full_propagation_refresh()
	ok(d._effective_seq_candidates(r3) == [1, 2], "note 3 could be the star at position 1 or 2, no more (got %s)" % str(d._effective_seq_candidates(r3)))
	ok(d._effective_seq_candidates(r6) == [1, 2, 3, 4], "note 6 could be any of the four (got %s)" % str(d._effective_seq_candidates(r6)))
	ok(d._effective_seq_candidates(r1) == [1], "note 1, a first note, is position 1 (got %s)" % str(d._effective_seq_candidates(r1)))
	ok(d._seq_pos_for_melody_tick(3) == 0 and d._seq_pos_for_melody_tick(6) == 0, "and neither repeat note has been placed by the board")

	print("\n=== the Staff popup's 'Same star as note' row ===")
	var row3: Control = w._make_staff_identity_row(3, r3)
	ok(_identity_buttons(row3) == [1, 2], "note 3 offers the first notes before it: 1, 2 (got %s)" % str(_identity_buttons(row3)))
	row3.queue_free()
	var row6: Control = w._make_staff_identity_row(6, r6)
	ok(_identity_buttons(row6) == [1, 2, 4, 5], "note 6 offers 1, 2, 4, 5 (got %s)" % str(_identity_buttons(row6)))
	row6.queue_free()

	print("\n=== a mark on a star does not reach its repeat note until the note is placed ===")
	var r2: int = d._get_or_create_match_record_for_melody_tick(2)
	d._propagate_name_states_confirmed_same_record(r2, "Beta")
	d._full_propagation_refresh()
	ok(d._known_name_for_seq_position(2) == "Beta", "position 2 (note 2) is named Beta")
	ok(d._known_name_for_record(d._find_match_record_by_melody_tick(3)) == "", "note 3, the same star in truth, still shows no name")

	print("\n=== placing the note is what links it ===")
	await w._on_staff_identity_select(3, 2)
	ok(d._seq_pos_for_melody_tick(3) == 2, "after placing note 3 on the star of note 2, the board has it at position 2 (got %d)" % d._seq_pos_for_melody_tick(3))
	ok(d._known_ticks_for_rank(2) == [2, 3], "position 2's known notes are now 2 and 3 (got %s)" % str(d._known_ticks_for_rank(2)))
	ok(w._ordinal_str("2") == "2, 3", "and the star's tag reads '2, 3' (got '%s')" % w._ordinal_str("2"))
	ok(d._known_name_for_seq_position(d._seq_pos_for_melody_tick(3)) == "Beta", "note 3 now reads as Beta on the staff")
	ok(d._seq_pos_for_melody_tick(6) == 0, "note 6 is untouched")

	print("\n=== Undo lets the note go, and the star keeps what it had ===")
	w._on_staff_identity_undo(3)
	ok(d._seq_pos_for_melody_tick(3) == 0, "note 3 is unplaced again (got %d)" % d._seq_pos_for_melody_tick(3))
	ok(d._known_ticks_for_rank(2) == [2], "position 2 is back to its first note alone (got %s)" % str(d._known_ticks_for_rank(2)))
	ok(d._known_name_for_seq_position(2) == "Beta", "and position 2 is still Beta")

	print("\n=== the board is not reading the answer: a WRONG placement is accepted ===")
	await w._on_staff_identity_select(6, 4)   # truth: note 6 is position 1
	ok(d._seq_pos_for_melody_tick(6) == 4, "note 6 placed on position 4 stays there (got %d)" % d._seq_pos_for_melody_tick(6))
	await w._on_staff_identity_select(6, 1)   # moving it must move the NOTE
	ok(d._seq_pos_for_melody_tick(6) == 1, "moving note 6 to position 1 moves it (got %d)" % d._seq_pos_for_melody_tick(6))
	ok(d._known_ticks_for_rank(4) == [5], "and position 4 keeps only its own first note (got %s)" % str(d._known_ticks_for_rank(4)))

	print("\n=== the Sort rows' Sequence tint claims nothing about repeats ===")
	var fallback: Color = w.STATE_COLORS.unresolved_fallback
	d._load_match_records([{"seq_lo": 3, "seq_hi": 3}, {"seq_lo": 1, "seq_hi": 1},
		{"seq_candidates": [3, 4]}, {"seq_candidates": [1, 2]}, {}])
	var neutral: bool = true
	for ri2 in 5:
		if w._seq_row_color(ri2, fallback) != fallback:
			neutral = false
	ok(neutral, "an unresolved row keeps its neutral tint whichever stars it could be")
	ok(w._seq_row_color(0, Color(0.2, 0.4, 0.9)) == Color(0.2, 0.4, 0.9), "a known colour always wins")
	ok(host_flat_row_unchanged(await _host([1, 2, 3, 4])), "a 1:1 melody leaves the row tint untouched")

	print("\n=== the staff actually draws on a repeating melody ===")
	# Real overlay, real draw callback: a drawing error or abort here fails the
	# module (the runner scores an aborted module as a failure).
	d._load_match_records([])
	d._get_or_create_match_record_for_melody_tick(3)
	host._melody_staff_panel.size = Vector2(900, 170)
	host._melody_staff_panel.queue_redraw()
	await process_frame
	await process_frame
	ok(true, "the staff drew on a repeating melody without aborting")

	host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
