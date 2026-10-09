extends "res://dev_tests/test_base.gd"
# Sort:tab Sequence entry, checker version (2026-10-07): one on/off button per
# position instead of the typed lo < list < hi boxes. What must hold:
#
#  - the row has one button per position, labelled with its first staff note;
#  - turning a position OFF removes it from the record's effective candidates,
#    turning it back ON restores it, and restoring everything clears the
#    record's Sequence info entirely (no explicit all-positions list left);
#  - narrowing down to one position is an exact pin, same as typing it;
#  - the last remaining position cannot be turned off (an empty set is a
#    contradiction, not information);
#  - the checker row is NOT wider than the typed row it replaces (its scroll
#    area has a small minimum and fills whatever the row is given).
#
# Like the other overlay-scene modules, verify through the FULL suite.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 0, 1, 2]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	host._repeat_count = [0, 0, 1, 1, 2, -1]
	return host


func _strip_buttons(row: Control) -> Array:
	var out: Array = []
	for c in row.get_children():
		if c is ScrollContainer:
			for b in c.get_child(0).get_children():
				out.append(b)
	return out


func run() -> void:
	await process_frame
	var host = await _make_host()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	var rec: int = d._get_or_create_match_record_for_name("Pyrios")

	# Typed row first, for the width comparison.
	w._seq_checker_loaded = true
	w._seq_checker_mode = false
	var typed_row: Control = w._make_sequence_range_row_for_record(rec, Color.WHITE)
	var typed_w: float = typed_row.get_combined_minimum_size().x
	typed_row.free()

	w._seq_checker_mode = true
	var row: Control = w._make_sequence_range_row_for_record(rec, Color.WHITE)
	host.add_child(row)
	var btns: Array = _strip_buttons(row)

	print("=== one button per position ===")
	ok(btns.size() == 6, "six buttons for six stars (got %d)" % btns.size())
	ok(btns.size() == 6 and (btns[0] as Button).text == "1" and (btns[5] as Button).text == "6",
		"labelled with the first staff note")

	print("\n=== width does not grow ===")
	var checker_w: float = row.get_combined_minimum_size().x
	ok(checker_w <= typed_w, "checker row min width %.0f <= typed row %.0f" % [checker_w, typed_w])

	print("\n=== off / on / all-restored ===")
	var lo_e := LineEdit.new()
	var mid_e := LineEdit.new()
	var hi_e := LineEdit.new()
	host.add_child(lo_e)
	host.add_child(mid_e)
	host.add_child(hi_e)
	ok(d._effective_seq_candidates(rec).size() == 6, "precondition: all six open")
	w._on_seq_checker_toggle(rec, 3, lo_e, mid_e, hi_e)
	await process_frame
	var eff: Array = d._effective_seq_candidates(rec)
	ok(eff.size() == 5 and not eff.has(3), "turning 3 off leaves the other five (got %s)" % str(eff))
	w._on_seq_checker_toggle(rec, 3, lo_e, mid_e, hi_e)
	await process_frame
	ok(d._effective_seq_candidates(rec).size() == 6, "turning 3 back on restores all six")
	var r: Dictionary = d.record_at(rec)
	ok((r.get("seq_candidates", []) as Array).is_empty() and int(r.get("seq_lo", 0)) == 0 and int(r.get("seq_hi", 0)) == 0,
		"and leaves no explicit all-positions list behind")

	print("\n=== down to one is an exact pin ===")
	for p in [1, 2, 3, 4, 5]:
		w._on_seq_checker_toggle(rec, p, lo_e, mid_e, hi_e)
		await process_frame
	r = d.record_at(d._get_or_create_match_record_for_name("Pyrios"))
	var eff2: Array = d._effective_seq_candidates(d._get_or_create_match_record_for_name("Pyrios"))
	ok(eff2 == [6], "only position 6 is left (got %s)" % str(eff2))
	ok(int(r.get("seq_lo", 0)) == 6 and int(r.get("seq_hi", 0)) == 6, "stored as an exact pin, as if 6 had been typed")

	print("\n=== the last position cannot be turned off ===")
	var prec: int = d._get_or_create_match_record_for_name("Pyrios")
	w._on_seq_checker_toggle(prec, 6, lo_e, mid_e, hi_e)
	await process_frame
	ok(d._effective_seq_candidates(prec) == [6], "still pinned to 6")

	print("\n=== repeating melody: one button per NOTE, repeats linked ===")
	var host2 = await _make_host()
	var d2 = host2._deduction
	var w2 = host2._widgets
	host2._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]   # 8 notes, 6 stars
	d2._load_match_records([])
	var rec2: int = d2._get_or_create_match_record_for_name("Pyrios")
	w2._seq_checker_loaded = true
	w2._seq_checker_mode = true
	var row2: Control = w2._make_sequence_range_row_for_record(rec2, Color.WHITE)
	host2.add_child(row2)
	var b2: Array = _strip_buttons(row2)
	ok(b2.size() == 8, "eight buttons for eight notes, none skipped (got %d)" % b2.size())
	var labels: Array = []
	for b in b2:
		labels.append((b as Button).text)
	ok(labels == ["1", "2", "3", "4", "5", "6", "7", "8"], "labelled 1..8 (got %s)" % str(labels))
	var lo2 := LineEdit.new()
	var mid2 := LineEdit.new()
	var hi2 := LineEdit.new()
	host2.add_child(lo2)
	host2.add_child(mid2)
	host2.add_child(hi2)
	# The 4th note is the 1st star's second note -- toggling it turns that star off.
	w2._on_seq_checker_toggle(rec2, d2._seq_pos_for_melody_tick(4), lo2, mid2, hi2)
	await process_frame
	var eff3: Array = d2._effective_seq_candidates(rec2)
	ok(eff3.size() == 5 and not eff3.has(1), "toggling note 4 turns star 1 off, leaving five (got %s)" % str(eff3))
	row2.free()
	row2 = w2._make_sequence_range_row_for_record(rec2, Color.WHITE)
	host2.add_child(row2)
	b2 = _strip_buttons(row2)
	ok((b2[0] as Button).modulate == (b2[3] as Button).modulate and (b2[0] as Button).modulate != (b2[1] as Button).modulate,
		"notes 1 and 4 (same star) now share the off look; note 2 does not")

	print("\n=== the scroll position survives a rebuild ===")
	# A click rebuilds the whole row; the strip must come back where it was.
	var host3 = await _make_host()
	var d3 = host3._deduction
	var w3 = host3._widgets
	host3._star_count = 6
	d3._load_match_records([])
	var rec3: int = d3._get_or_create_match_record_for_name("Pyrios")
	w3._seq_checker_loaded = true
	w3._seq_checker_mode = true
	var holder := Control.new()
	holder.size = Vector2(300, 40)
	host3.add_child(holder)
	var rowa: Control = w3._make_sequence_range_row_for_record(rec3, Color.WHITE)
	rowa.size = Vector2(60, 30)    # narrower than its six buttons, so it scrolls
	holder.add_child(rowa)
	await process_frame
	await process_frame
	var scrolla: ScrollContainer = null
	for c in rowa.get_children():
		if c is ScrollContainer:
			scrolla = c
	scrolla.scroll_horizontal = 25
	await process_frame
	var moved: int = scrolla.scroll_horizontal
	ok(moved > 0, "precondition: the strip could be scrolled (at %d)" % moved)
	rowa.queue_free()
	await process_frame
	var rowb: Control = w3._make_sequence_range_row_for_record(rec3, Color.WHITE)
	rowb.size = Vector2(60, 30)
	holder.add_child(rowb)
	await process_frame
	await process_frame
	await process_frame
	var scrollb: ScrollContainer = null
	for c2 in rowb.get_children():
		if c2 is ScrollContainer:
			scrollb = c2
	ok(scrollb.scroll_horizontal == moved, "the rebuilt strip is back at %d (got %d)" % [moved, scrollb.scroll_horizontal])

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
