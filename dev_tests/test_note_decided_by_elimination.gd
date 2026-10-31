extends "res://dev_tests/test_base.gd"
# A note only one star can still fire on (reported 2026-10-31 on The Phial).
# Every other star had all its notes placed, so notes 1, 2, 4, 11 and 12 could
# only be Keraeara's, yet their Staff popups showed A5, Keraeara, Red and
# Repeats 5 times white rather than green, and the staff itself showed "?".
#
# Two causes. A note has no entry until its popup opens, so with no record the
# conclusion had nowhere to go; and the popup makes that entry and reads it
# without the engine ever having seen it, so its X marks were display-only.
#
# Star 0 fires on notes 1, 3, 5; stars 1, 2, 3 once each, on notes 2, 4, 6.
# Stars 1 and 2 share a colour, so a note down to those two has a known colour
# and no known star.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const NAMES := ["Alpha", "Beta", "Gamma", "Delta"]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _setup_host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = NAMES.duplicate()
	host._star_colors = [3, 1, 1, 2]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [293.66, 440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = [1, 2, 1, 3, 1, 4]
	host._melody_star_sequence = [0, 1, 0, 2, 0, 3]
	host._repeat_count = [2, 0, 0, 0]
	host._widgets.clear_pitch_caches()
	return host


func _fresh(host) -> void:
	var d = host._deduction
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()
	for s2 in host._star_count:
		await host._on_pitch_listen_star_clicked(s2)


## The player puts `star`'s own note on that star's popup.
func _place(host, star: int, tick: int) -> void:
	await host._widgets._on_seq_note_select(host._deduction._get_or_create_match_record_for_star_idx(star), tick)


func run() -> void:
	var host = await _setup_host()
	var d = host._deduction
	var w = host._widgets

	print("=== nothing decided yet ===")
	await _fresh(host)
	await _place(host, 1, 2)
	await _place(host, 2, 4)
	ok(d._notes_hidden(), "setup: a board with hidden first notes")
	var open_notes: int = 0
	for t in [1, 3, 5, 6]:
		if d._find_match_record_by_melody_tick(t) < 0:
			open_notes += 1
	ok(open_notes == 4, "two stars could still take notes 1, 3, 5, 6: no entry is made for any (%d of 4 empty)" % open_notes)

	print("\n=== the last other star fills ===")
	await _place(host, 3, 6)
	var bound: int = 0
	for t2 in [1, 3, 5]:
		var rec: int = d._find_match_record_by_melody_tick(t2)
		if rec >= 0 and d._effective_star_idx(rec) == 0:
			bound += 1
	ok(bound == 3, "notes 1, 3, 5 are star 0's, with nobody having opened their popups (%d of 3)" % bound)
	ok(w._held_notes_str_for_star(0) == "1, 3, 5", "the map tag lists them ('%s')" % w._held_notes_str_for_star(0))
	var rec12: int = d._find_match_record_by_melody_tick(3)
	if rec12 >= 0:
		var note0: String = w._note_name_for_star(0)
		ok(d._effective_pitch_state(rec12, note0, false) == 1, "note 3's popup shows its pitch green (reads %d)" % d._effective_pitch_state(rec12, note0, false))
		ok(d._effective_color_state(rec12, 3, false) == 1, "and its colour (reads %d)" % d._effective_color_state(rec12, 3, false))
		ok(d._effective_repeat_state(rec12, 2, false) == 1, "and its Repeats (reads %d)" % d._effective_repeat_state(rec12, 2, false))
		ok(not (d._melody_marker_for_record(rec12) as Dictionary).is_empty() and bool(d._melody_marker_for_record(rec12)["pitch_known"]),
			"and the staff shows the pitch, not ?")
	ok(d._contradictions.is_empty(), "a true board stays clean (%s)" % str(d._contradictions))

	print("\n=== a name given afterwards ===")
	var lbl := Label.new()
	var bc := Button.new()
	var bx := Button.new()
	host.add_child(lbl)
	host.add_child(bc)
	host.add_child(bx)
	await w._on_name_check(0, "Alpha", lbl, bc, bx)
	var r3: int = d._find_match_record_by_melody_tick(3)
	ok(d._effective_name_state(r3, "Alpha", false) == 1, "note 3's popup shows Alpha green (reads %d)" % d._effective_name_state(r3, "Alpha", false))
	var alpha: int = d._find_match_record_by_name("Alpha")
	ok(d._repeat_note_state_for_record(alpha, 3) == 1, "and Alpha's Sequence row has it (reads %d)" % d._repeat_note_state_for_record(alpha, 3))

	print("\n=== it releases with its cause ===")
	await _fresh(host)
	await _place(host, 1, 2)
	await _place(host, 2, 4)
	var undo_before: int = d._board_undo.size()
	await _place(host, 3, 6)
	# Placed notes are kept through Backstep, so a placement is no step at all,
	# and the entries it decided must not become one.
	ok(d._board_undo.size() == undo_before, "the entries made for it add no Backstep step (%d -> %d)" % [undo_before, d._board_undo.size()])
	ok(d._find_match_record_by_melody_tick(1) >= 0, "setup: note 1 was decided")
	var star3: int = d._find_match_record_by_melody_tick(6)
	await w._on_seq_note_select(star3, 6)
	var r1: int = d._find_match_record_by_melody_tick(1)
	ok(r1 < 0 or d._effective_star_idx(r1) < 0, "letting note 6 go lets note 1 go too (star %d)" % (d._effective_star_idx(r1) if r1 >= 0 else -1))
	ok(w._held_notes_str_for_star(0) == "?", "and the tag is back to ? ('%s')" % w._held_notes_str_for_star(0))

	print("\n=== a star whose count is unknown is not ruled out ===")
	var d_marks: Array = []
	d._load_match_records([])
	for s3 in host._star_count:
		d._get_or_create_match_record_for_star_idx(s3)
	d._full_propagation_refresh()
	await _place(host, 1, 2)
	await _place(host, 2, 4)
	await _place(host, 3, 6)
	for t3 in [1, 3, 5]:
		if d._find_match_record_by_melody_tick(t3) >= 0:
			d_marks.append(t3)
	ok(d_marks.is_empty(), "with nothing Listened no star is known to be full: no note is decided (%s)" % str(d_marks))

	print("\n=== a popup opened on a note narrowed but not decided ===")
	await _fresh(host)
	await _place(host, 0, 1)
	await _place(host, 0, 3)
	await _place(host, 0, 5)
	await _place(host, 3, 6)
	ok(d._find_match_record_by_melody_tick(2) < 0, "setup: note 2 could be star 1 or 2, so it has no entry yet")
	w._open_staff_popup(2, Vector2(100, 100))
	var r2: int = d._find_match_record_by_melody_tick(2)
	ok(d._candidate_stars_for_record(r2) == [1, 2], "setup: its entry could be stars 1 or 2 (%s)" % str(d._candidate_stars_for_record(r2)))
	ok(d._effective_color_state(r2, 1, false) == 1, "the popup shows their shared colour green on opening (reads %d)" % d._effective_color_state(r2, 1, false))
	(host._staff_popup as Window).hide()

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
