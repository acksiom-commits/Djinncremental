extends "res://dev_tests/test_base.gd"
# The melody staff shows the REPEAT SHAPE from the start, and a star's notes
# share one record.
#
# On a repeating melody (more notes than stars):
#   - a note of a star that fires once is DIM until the star's colour is known;
#   - a note of a star that repeats is the not-yet-known GREEN until its colour
#     is known, so the repeating stars stand out;
#   - once a colour is known every note of that star takes it;
#   - thin arcs join the notes of each repeating star (drawn above the numerals).
# A 1:1 melody has nothing to show, so every note keeps the original green.
#
# Clicking any note of a star opens the SAME record, so a name or colour marked
# on one note is marked on all of them -- and the record's Sequence stays
# unpinned, so nothing about WHICH star it is gets pre-filled.
#
# Fixture: 4 stars, 6 notes, note -> rank [1,2,2,3,4,1]: rank 1 fires at notes
# {1,6}, rank 2 at {2,3}, ranks 3 and 4 once (notes 4 and 5).

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
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func host_flat_row_unchanged(h) -> bool:
	h._deduction._load_match_records([{"seq_lo": 2, "seq_hi": 2}])
	var fb: Color = h._widgets.STATE_COLORS.unresolved_fallback
	var same: bool = h._widgets._seq_row_color(0, fb) == fb
	h.queue_free()
	return same


func run() -> void:
	var host = await _host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var w = host._widgets

	print("=== the colour rule on a repeating melody ===")
	var dim: Color = w.STATE_COLORS.muted
	var green: Color = host.UNKNOWN_SEQ_COLOR
	ok(w._staff_tick_color(3, -1) == dim, "a star that fires once is dim while its colour is unknown")
	ok(w._staff_tick_color(4, -1) == dim, "...and so is another")
	ok(w._staff_tick_color(1, -1) == green, "a star that repeats (rank 1) is lit green while its colour is unknown")
	ok(w._staff_tick_color(2, -1) == green, "...and so is another (rank 2)")
	ok(w._staff_tick_color(1, 2) == host.STAR_COLORS_BY_IDX[2], "a known colour replaces the green on a repeating star")
	ok(w._staff_tick_color(3, 1) == host.STAR_COLORS_BY_IDX[1], "a known colour replaces the dim on a star that fires once")
	ok(dim != green, "dim and lit are actually different colours")

	print("\n=== a 1:1 melody keeps the original green everywhere ===")
	var host_flat = await _host([1, 2, 3, 4])
	var w_flat = host_flat._widgets
	var flat_ok: bool = true
	for rank in [1, 2, 3, 4]:
		if w_flat._staff_tick_color(rank, -1) != host_flat.UNKNOWN_SEQ_COLOR:
			flat_ok = false
	ok(flat_ok, "every note of a 1:1 melody stays the not-yet-known green")
	host_flat.queue_free()
	var host_old = await _host([])
	ok(host_old._widgets._staff_tick_color(1, -1) == host_old.UNKNOWN_SEQ_COLOR, "an old cache with no melody table keeps the original green")
	host_old.queue_free()
	await process_frame

	print("\n=== a star's notes share one record, unpinned ===")
	d._load_match_records([])
	var r1: int = d._get_or_create_match_record_for_melody_tick(1)
	ok((d.record_at(r1)["melody_ticks"] as Array) == [1, 6], "clicking note 1 opens a record holding notes 1 and 6 (got %s)" % str(d.record_at(r1)["melody_ticks"]))
	ok(d._get_or_create_match_record_for_melody_tick(6) == r1, "clicking note 6 opens the SAME record")
	ok(int(d.record_at(r1)["seq_lo"]) == 0 and int(d.record_at(r1)["seq_hi"]) == 0, "and its Sequence is still unpinned (nothing pre-filled)")
	var r4: int = d._get_or_create_match_record_for_melody_tick(4)
	ok(r4 != r1 and (d.record_at(r4)["melody_ticks"] as Array) == [4], "a star that fires once gets its own record holding just its note")
	ok(d.record_count() == 2, "two clicks on one star and one on another made exactly two records (got %d)" % d.record_count())

	print("\n=== an older save's partial record is adopted, never duplicated ===")
	d._load_match_records([{"melody_ticks": [2]}])
	var before: int = d.record_count()
	var adopted: int = d._get_or_create_match_record_for_melody_tick(3)
	ok(adopted == 0 and d.record_count() == before, "note 3 finds the record that already held note 2 (record count %d -> %d)" % [before, d.record_count()])
	ok((d.record_at(0)["melody_ticks"] as Array) == [2, 3], "and that record now holds both notes (got %s)" % str(d.record_at(0)["melody_ticks"]))

	print("\n=== the Sort rows' Sequence tint follows the same rule ===")
	var fallback: Color = w.STATE_COLORS.unresolved_fallback
	d._load_match_records([{"seq_lo": 3, "seq_hi": 3}, {"seq_lo": 1, "seq_hi": 1},
		{"seq_candidates": [3, 4]}, {"seq_candidates": [1, 2]},
		{"seq_candidates": [2, 3]}, {}])
	ok(w._seq_row_color(0, fallback) == dim, "a row pinned to a star that fires once is dim while its colour is unknown")
	ok(w._seq_row_color(1, fallback) == green, "a row pinned to a repeating star is lit green")
	ok(w._seq_row_color(2, fallback) == dim, "a row whose candidates ALL fire once is dim")
	ok(w._seq_row_color(3, fallback) == green, "a row whose candidates ALL repeat is lit green")
	ok(w._seq_row_color(4, fallback) == fallback, "a row that could be either keeps the neutral tint")
	ok(w._seq_row_color(5, fallback) == fallback, "an empty row (every star possible) keeps the neutral tint")
	ok(w._seq_row_color(0, Color(0.2, 0.4, 0.9)) == Color(0.2, 0.4, 0.9), "a known colour always wins")
	ok(host_flat_row_unchanged(await _host([1, 2, 3, 4])), "a 1:1 melody leaves the row tint untouched")

	print("\n=== the staff actually draws on a repeating melody ===")
	# Real overlay, real draw callback: a drawing error or abort here fails the
	# module (the runner scores an aborted module as a failure).
	host._melody_staff_panel.size = Vector2(900, 170)
	host._melody_staff_panel.queue_redraw()
	await process_frame
	await process_frame
	ok(true, "the staff drew with repeat arcs and the arc band without aborting")

	host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
