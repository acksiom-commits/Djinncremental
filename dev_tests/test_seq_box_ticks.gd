extends "res://dev_tests/test_base.gd"
# The Sort tabs' Sequence boxes take STAFF NOTES, the numbers the clues and the
# staff use, and keep showing what the player typed.
#
# The melody's repeat shape is public, so a note maps to its star's rank through
# the staff's own table. Meanings:
#   lower box "N <"  : the star FIRST fires after note N
#   upper box "< M"  : the star FIRST fires before note M
#   both boxes equal, or "= N" : the star that fires at note N (any of its notes)
#   centre list      : notes; every note of every candidate star is shown
#
# The bug this guards against: typing 10 became 8, because the bound was shown
# back as the FIRST note of the star it landed on instead of what was typed.
# The typed value is now remembered (seq_tick_lo / seq_tick_hi, display only)
# and shown while it still describes the stored bound.
#
# Fixture: 4 stars, 6 notes, note -> rank [1,2,2,3,4,1]. So rank 1 fires at
# notes {1,6}, rank 2 at {2,3}, rank 3 at {4}, rank 4 at {5}; stars begun by
# note t: d(1)=1 d(2)=2 d(3)=2 d(4)=3 d(5)=4 d(6)=4. Note 3 is a repeat of rank
# 2, so a lower box of 3 is a case where "show the first note of the star it
# landed on" (2) differs from what was typed (3).

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _numbers_in(text: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string("\\d+").search_all(text):
		out.append(int(m.get_string()))
	return out


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


func _reset(r: Dictionary) -> void:
	r["seq_lo"] = 0
	r["seq_hi"] = 0
	r["seq_tick_lo"] = 0
	r["seq_tick_hi"] = 0
	r["seq_candidates"] = []


func run() -> void:
	var host = await _host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var w = host._widgets
	ok(d._seq_repeats(), "precondition: 6 notes over 4 stars is a repeating melody")
	var rec: int = d._get_or_create_match_record_for_name("Alpha")
	var lo := LineEdit.new()
	var mid := LineEdit.new()
	var hi := LineEdit.new()
	var r: Dictionary = d.record_at(rec)

	print("=== the table the boxes rely on ===")
	ok(d._stars_begun_by_tick(3) == 2 and d._stars_begun_by_tick(4) == 3 and d._stars_begun_by_tick(6) == 4,
		"stars begun by note 3 / 4 / 6 are 2 / 3 / 4")
	ok(d._seq_bounds_for_ticks(3, 0) == [3, 0], "lower 3 -> ranks 3.. (got %s)" % str(d._seq_bounds_for_ticks(3, 0)))
	ok(d._seq_bounds_for_ticks(0, 4) == [0, 2], "upper 4 -> ranks ..2 (got %s)" % str(d._seq_bounds_for_ticks(0, 4)))

	print("\n=== a typed lower bound is kept as typed ===")
	lo.text = "3"
	hi.text = ""
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(r["seq_lo"]) == 3 and int(r["seq_hi"]) == 0,
		"'3 <' stores 'first fires after note 3' = ranks 3.. (seq_lo %d, seq_hi %d)" % [int(r["seq_lo"]), int(r["seq_hi"])])
	ok(lo.text == "3", "and the box still reads 3 (got '%s'; showing the star's first note would read 2)" % lo.text)
	ok(int(r["seq_tick_lo"]) == 3, "the typed note is remembered (%d)" % int(r["seq_tick_lo"]))
	ok(mid.text == "4-5", "the centre box lists the notes of the stars still possible, ranks 3 and 4 (got '%s')" % mid.text)

	print("\n=== a typed upper bound ===")
	_reset(r)
	lo.text = ""
	hi.text = "4"
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(r["seq_hi"]) == 2 and int(r["seq_lo"]) == 0, "'< 4' stores 'first fires before note 4' = ranks ..2 (seq_hi %d)" % int(r["seq_hi"]))
	ok(hi.text == "4", "and the box still reads 4 (got '%s')" % hi.text)
	ok(mid.text == "1-3,6", "the centre box lists every note of ranks 1 and 2 (got '%s')" % mid.text)

	print("\n=== two bounds that leave one star read as an exact pin ===")
	_reset(r)
	lo.text = "3"
	hi.text = "5"
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(r["seq_lo"]) == 3 and int(r["seq_hi"]) == 3, "'3 < x < 5' leaves only rank 3 (seq_lo %d, seq_hi %d)" % [int(r["seq_lo"]), int(r["seq_hi"])])
	ok(mid.text == "= 4" and lo.text == "" and hi.text == "", "shown as '= 4' with both bound boxes cleared (got '%s' / '%s' / '%s')" % [lo.text, mid.text, hi.text])

	print("\n=== typing any note of a repeating star pins that star ===")
	_reset(r)
	lo.text = "3"
	hi.text = "3"
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(r["seq_lo"]) == 2 and int(r["seq_hi"]) == 2, "note 3 is a note of rank 2, so both boxes at 3 pin rank 2 (seq_lo %d)" % int(r["seq_lo"]))
	ok(mid.text == "= 2,3", "and every note of that star is shown (got '%s')" % mid.text)

	print("\n=== a candidate list is notes in, notes out ===")
	_reset(r)
	mid.text = "5,6"
	await w._commit_sequence_candidates(rec, lo, mid, hi)
	w._refresh_range_edits(rec, lo, mid, hi)
	ok((d.record_at(rec)["seq_candidates"] as Array) == [1, 4],
		"notes 5 and 6 are ranks 4 and 1 (got %s)" % str(d.record_at(rec)["seq_candidates"]))
	ok(mid.text == "1,5-6", "shown as every note of those stars (got '%s')" % mid.text)

	print("\n=== impossible entries are refused, the row snaps back ===")
	_reset(r)
	lo.text = "6"
	hi.text = ""
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(d.record_at(rec)["seq_lo"]) == 0, "'6 <' (every star has begun by note 6) stores nothing")
	lo.text = ""
	hi.text = "1"
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(d.record_at(rec)["seq_hi"]) == 0, "'< 1' (nothing fires before note 1) stores nothing")
	lo.text = "9"
	hi.text = ""
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(d.record_at(rec)["seq_lo"]) == 0, "a note past the end of the melody stores nothing")

	print("\n=== a re-typed note that maps to the same bound is remembered ===")
	_reset(r)
	lo.text = "2"
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(r["seq_lo"]) == 3 and lo.text == "2", "'2 <' stores ranks 3.. and reads 2")
	lo.text = "3"
	await w._commit_sequence_range(rec, lo, mid, hi)
	ok(int(r["seq_lo"]) == 3 and int(r["seq_tick_lo"]) == 3 and lo.text == "3",
		"'3 <' is the SAME bound; the box now reads the newer 3 (tick_lo %d, text '%s')" % [int(r["seq_tick_lo"]), lo.text])

	print("\n=== a bound with no typed note falls back to a real note ===")
	_reset(r)
	r["seq_lo"] = 3
	w._refresh_range_edits(rec, lo, mid, hi)
	ok(lo.text == "2", "ranks 3.. with nothing typed reads '2 <', the last first-note before it (got '%s')" % lo.text)

	print("\n=== the typed note survives a save round-trip and is dropped by a merge ===")
	_reset(r)
	lo.text = "3"
	await w._commit_sequence_range(rec, lo, mid, hi)
	var round_tripped = JSON.parse_string(JSON.stringify(d.record_at(rec)))
	d._load_match_records([round_tripped])
	ok(int(d.record_at(0).get("seq_tick_lo", -1)) == 3, "seq_tick_lo is written and read back (got %s)" % str(d.record_at(0).get("seq_tick_lo", "missing")))
	d._load_match_records([])
	# Two UNNAMED records: a merge of differently-named ones is refused outright.
	var a: int = d._get_or_create_match_record_for_melody_tick(4)
	var b: int = d._get_or_create_match_record_for_melody_tick(5)
	ok(a != b, "precondition: two separate records to merge")
	d.record_at(a)["seq_tick_lo"] = 3
	d.record_at(b)["seq_tick_hi"] = 5
	var merged: int = await d._merge_match_records(a, b, false)
	ok(int(d.record_at(merged).get("seq_tick_lo", -1)) == 0 and int(d.record_at(merged).get("seq_tick_hi", -1)) == 0,
		"merging two records forgets both typed notes (the bounds were intersected)")

	print("\n=== nothing shown is a number past the melody ===")
	_reset(d.record_at(0))
	var worst: int = 0
	for t in [mid.text, d._compressed_possible_positions_str(0)]:
		for n in _numbers_in(str(t)):
			worst = maxi(worst, int(n))
	ok(worst <= 6, "no box shows a number past note 6 (largest %d)" % worst)
	host.queue_free()
	await process_frame

	print("\n=== a 1:1 melody behaves exactly as before ===")
	var host2 = await _host([1, 2, 3, 4])
	var d2 = host2._deduction
	var w2 = host2._widgets
	ok(not d2._seq_repeats(), "precondition: a 1:1 melody")
	var rec2: int = d2._get_or_create_match_record_for_name("Alpha")
	var lo2 := LineEdit.new()
	var mid2 := LineEdit.new()
	var hi2 := LineEdit.new()
	lo2.text = "2"
	hi2.text = "4"
	await w2._commit_sequence_range(rec2, lo2, mid2, hi2)
	var r2: Dictionary = d2.record_at(rec2)
	ok(int(r2["seq_lo"]) == 3 and int(r2["seq_hi"]) == 3, "'2 < x < 4' is the single rank 3, as the old arithmetic gave (seq_lo %d, seq_hi %d)" % [int(r2["seq_lo"]), int(r2["seq_hi"])])
	ok(mid2.text == "= 3", "and reads '= 3' (got '%s')" % mid2.text)
	host2.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
