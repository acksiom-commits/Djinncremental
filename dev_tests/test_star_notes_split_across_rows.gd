extends "res://dev_tests/test_base.gd"
# A star's notes split across rows (reported 2026-10-27 on The Spark):
# Rostoei's Sort:Name row was down to one map star, the D4 star, and held
# notes 1 and 5; the Staff entry for note 13 had been given D4 and so sat on
# that star too. Rostoei repeats twice, so all three firings were placed.
# Yet the map showed no name on the D4 star, Rostoei's Sequence entry still
# listed most notes as open, and every other note's Staff popup still
# offered the name.
#
# Two causes, both counting ROWS where the question is about the STAR:
#   - binding refused a row whose only candidate star already held ANY
#     other row, even one that is the same star seen from the Staff bar;
#   - "that star's notes are all accounted for" compared one row's notes
#     with the star's firing count, so notes split across rows never added up.
#
# Here: star 0 fires on notes 1, 3, 5. The Staff entry for note 5 is given
# star 0's pitch first; then Alpha's row is given notes 1 and 3.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const NAMES := ["Alpha", "Beta", "Gamma", "Delta"]
const ALPHA_NOTES := [1, 3, 5]

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
	host._star_colors = [3, 1, 2, 2]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [293.66, 440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	# Six notes for four stars: star 0 (rank 1) fires on notes 1, 3 and 5.
	host._melody_seq_pos_sequence = [1, 2, 1, 3, 1, 4]
	host._repeat_count = [2, 0, 0, 0]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()
	ok(d._notes_hidden(), "setup: a repeating board, first notes hidden")

	# Every star Listened, as the players are presumed to have done.
	for s in host._star_count:
		await host._on_pitch_listen_star_clicked(s)

	# The Staff entry for note 5, given star 0's pitch (the engine half of the
	# popup's pitch check).
	var note5: int = d._get_or_create_match_record_for_melody_tick(5)
	d._propagate_pitch_confirmed_same_record(note5, w._note_name_for_star(0))
	d._save_puzzle_notes()
	d._full_propagation_refresh()
	ok(d._effective_star_idx(note5) == 0, "setup: the note-5 entry sits on star 0 (%d)" % d._effective_star_idx(note5))

	# Alpha's row: notes 1 and 3. Two notes rule out every star Listen says
	# fires once, which leaves star 0 -- narrowed by deduction alone, as
	# Rostoei's row was. (A raw mark such as a unique colour would let the
	# merge path bind it and hide the refusal.)
	var alpha: int = d._get_or_create_match_record_for_name("Alpha")
	d._full_propagation_refresh()
	await w._on_seq_note_select(alpha, 1)
	alpha = d._find_match_record_by_name("Alpha")
	await w._on_seq_note_select(alpha, 3)
	alpha = d._find_match_record_by_name("Alpha")
	ok(d._candidate_stars_for_record(alpha) == [0],
		"setup: Alpha's row can only be star 0 (%s)" % str(d._candidate_stars_for_record(alpha)))

	# 1. The row is bound to that star, so the map shows its name.
	ok(d._effective_star_idx(alpha) == 0, "Alpha's row is bound to star 0 (%d)" % d._effective_star_idx(alpha))
	ok(w._confirmed_name_for_star(0) == "Alpha",
		"the Star Map names star 0 Alpha ('%s')" % w._confirmed_name_for_star(0))

	# 2. The row's Sequence entry has all three notes and nothing else open.
	var texts: Array = w._seq_notes_typed_texts(alpha)
	ok(str(texts[1]) == "=1,=3,=5", "Alpha's Sequence entry lists exactly =1,=3,=5 (%s)" % str(texts))

	# 3. Every note's Staff popup: Alpha confirmed on its own notes, ruled
	# out on every other.
	var all_names: Array[String] = []
	for n in NAMES:
		all_names.append(str(n))
	var judged: int = 0
	var wrong: Array = []
	for t in range(1, d._melody_tick_count() + 1):
		var rt: int = d._get_or_create_match_record_for_melody_tick(t)
		d._full_propagation_refresh()
		alpha = d._find_match_record_by_name("Alpha")
		var st: int = d._effective_name_state(rt, "Alpha", false)
		if (st == 0 or st == 4) and d._compute_excluded_names_for(rt).has("Alpha"):
			st = 2
		var want: int = 1 if ALPHA_NOTES.has(t) else 2
		judged += 1
		if st != want:
			wrong.append("note %d reads %d, want %d" % [t, st, want])
	ok(wrong.is_empty(), "Alpha in every note's Staff popup (%d/%d notes; wrong: %s)"
		% [judged - wrong.size(), judged, str(wrong)])

	# Soundness: names nobody has placed stay open on the notes nobody has
	# placed. Beta..Delta are truly notes 2, 4, 6, but nothing says which.
	var open_judged: int = 0
	var closed: Array = []
	for nm in ["Beta", "Gamma", "Delta"]:
		for t2 in [2, 4, 6]:
			var rt2: int = d._find_match_record_by_melody_tick(t2)
			open_judged += 1
			var st2: int = d._effective_name_state(rt2, str(nm), false)
			if (st2 == 0 or st2 == 4) and d._compute_excluded_names_for(rt2).has(str(nm)):
				st2 = 2
			if st2 != 0:
				closed.append("%s on note %d reads %d" % [nm, t2, st2])
	ok(closed.is_empty(), "unplaced names stay open on unplaced notes (%d/%d cells; wrong: %s)"
		% [open_judged - closed.size(), open_judged, str(closed)])

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
