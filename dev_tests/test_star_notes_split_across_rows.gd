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
# The Star Map tag had the same shape: it listed one entry's notes.
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


func _fresh(d, host) -> void:
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()


## Rule out every other star on a record: bound by deduction, so no merge folds
## other entries into it.
func _bind_by_elimination(d, host, rec: int, star: int) -> void:
	var elim: Dictionary = {}
	for s in host._star_count:
		if s != star:
			elim[s] = 2
	d.record_at(rec)["star_elim"] = elim
	d._save_puzzle_notes()
	d._full_propagation_refresh()


func _note_reports(d) -> Array:
	var out: Array = []
	for c in d._contradictions:
		if str((c as Dictionary).get("axis", "")) == "notes":
			out.append(str((c as Dictionary).get("text", "")))
	return out


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

	# 4. The Star Map tag says what the popup says (reported 2026-10-31: Eosyos
	# read "?" on the map with both its notes on the popup). Here the row holds
	# two notes and a Staff entry the third; the tag read one entry only.
	ok(w._held_notes_str_for_star(0) == "1, 3, 5", "the tag lists all three notes ('%s')" % w._held_notes_str_for_star(0))

	print("\n=== a named star whose notes all sit on Staff entries ===")
	d._load_match_records([])
	for s4 in host._star_count:
		d._get_or_create_match_record_for_star_idx(s4)
	d._full_propagation_refresh()
	for s5 in host._star_count:
		await host._on_pitch_listen_star_clicked(s5)
	# Bound by deduction, as Eosyos was: every other star ruled out on the row,
	# so the row is on star 0 without any merge folding the entries into it. A
	# raw name check on the star merges them, and hides this.
	var alpha2: int = d._get_or_create_match_record_for_name("Alpha")
	d.record_at(alpha2)["star_elim"] = {1: 2, 2: 2, 3: 2}
	d._save_puzzle_notes()
	d._full_propagation_refresh()
	alpha2 = d._find_match_record_by_name("Alpha")
	ok(d._effective_star_idx(alpha2) == 0, "setup: Alpha's row is bound to star 0 by deduction (%d)" % d._effective_star_idx(alpha2))
	ok(w._held_notes_str_for_star(0) == "?", "no note placed yet: the tag reads ? ('%s')" % w._held_notes_str_for_star(0))
	for t2 in ALPHA_NOTES:
		var entry: int = d._get_or_create_match_record_for_melody_tick(int(t2))
		d._propagate_pitch_confirmed_same_record(entry, w._note_name_for_star(0))
		d._save_puzzle_notes()
		d._full_propagation_refresh()
	alpha2 = d._find_match_record_by_name("Alpha")
	ok((d.record_at(alpha2).get("melody_ticks", []) as Array).is_empty(),
		"setup: the row itself holds none of them (%s)" % str(d.record_at(alpha2).get("melody_ticks", [])))
	var popup_rec: int = d._get_or_create_match_record_for_star_idx(0)
	var popup: Array = []
	for t3 in range(1, d._melody_tick_count() + 1):
		if d._repeat_note_state_for_record(popup_rec, t3) == 1:
			popup.append(t3)
	ok(popup == ALPHA_NOTES, "setup: the popup has the star on all three notes (%s)" % str(popup))
	ok(w._held_notes_str_for_star(0) == "1, 3, 5", "and so does the tag, not '?' ('%s')" % w._held_notes_str_for_star(0))
	ok(w._held_notes_str_for_star(1) == "?", "another star stays ? ('%s')" % w._held_notes_str_for_star(1))

	# The notes on one star, split across entries, counted against what it fires.
	print("\n=== a star's firing count is checked against ALL its notes ===")
	var e5: int = d._find_match_record_by_melody_tick(5)
	var e2: int = d._get_or_create_match_record_for_melody_tick(2)
	d._full_propagation_refresh()
	alpha2 = d._find_match_record_by_name("Alpha")
	e5 = d._find_match_record_by_melody_tick(5)
	e2 = d._find_match_record_by_melody_tick(2)
	ok(d._name_row_too_full_for(e2, "Alpha"), "Alpha's star has all three notes placed, so note 2 cannot join it")
	ok(d._effective_name_state(e2, "Alpha", false) == 2, "and note 2's popup rules Alpha out (reads %d)" % d._effective_name_state(e2, "Alpha", false))
	ok(not d._name_row_too_full_for(e5, "Alpha") and d._effective_name_state(e5, "Alpha", false) != 2,
		"note 5, one of those three, is not ruled out (reads %d)" % d._effective_name_state(e5, "Alpha", false))
	ok(not d._name_row_too_full_for(e2, "Beta"), "a star with room is not called full")

	# One note too many, spread so that no single entry is over: both notes go on
	# before the count is known, one on Beta's row and one on a Staff entry bound
	# to the star. Marking the count last is the only order that reaches this;
	# once a count is known the row's own buttons, or the candidate check, stop it.
	print("\n=== too many notes on a star, split across entries ===")
	_fresh(d, host)
	var beta2: int = d._get_or_create_match_record_for_name("Beta")
	_bind_by_elimination(d, host, beta2, 1)
	await w._on_seq_note_select(d._find_match_record_by_name("Beta"), 2)
	_bind_by_elimination(d, host, d._get_or_create_match_record_for_melody_tick(4), 1)
	var b_rec: int = d._find_match_record_by_name("Beta")
	ok(d._notes_on_star_of(b_rec) == [2, 4], "setup: the star holds two notes (%s)" % str(d._notes_on_star_of(b_rec)))
	ok((d.record_at(b_rec).get("melody_ticks", []) as Array).size() == 1, "setup: no single entry is over")
	w._repeat_toggle_confirm(b_rec, 0)
	var over: Array = []
	for c2 in d._contradictions:
		over.append(str((c2 as Dictionary).get("text", "")))
	ok(not over.is_empty(), "the board is flagged as impossible (%s)" % str(over))

	# The same with nothing named: the banner must not hand over the star's name.
	print("\n=== the same on a star nobody has named ===")
	_fresh(d, host)
	for s7 in host._star_count:
		await host._on_pitch_listen_star_clicked(s7)
	for t4 in [2, 4]:
		var en: int = d._get_or_create_match_record_for_melody_tick(int(t4))
		d._propagate_pitch_confirmed_same_record(en, w._note_name_for_star(1))
		d._save_puzzle_notes()
		d._full_propagation_refresh()
	var anon: Array = _note_reports(d)
	ok(anon.size() == 1, "flagged once (%s)" % str(anon))
	var leaked: Array = []
	for n2 in NAMES:
		if anon.size() > 0 and str(anon[0]).contains(str(n2)):
			leaked.append(str(n2))
	ok(leaked.is_empty(), "and the true name is not in it (%s, leaked %s)" % [str(anon), str(leaked)])

	# Notes split across entries bound the count, for a star not Listened to.
	print("\n=== notes split across entries bound the Repeats count ===")
	_fresh(d, host)
	var alpha3: int = d._get_or_create_match_record_for_name("Alpha")
	_bind_by_elimination(d, host, alpha3, 0)
	for t5 in [1, 3]:
		var en2: int = d._get_or_create_match_record_for_melody_tick(int(t5))
		_bind_by_elimination(d, host, en2, 0)
	alpha3 = d._find_match_record_by_name("Alpha")
	ok(d._effective_star_idx(alpha3) == 0 and (d.record_at(alpha3).get("melody_ticks", []) as Array).is_empty(),
		"setup: Alpha's row is on star 0, holding no note itself")
	ok(d._effective_repeat_state(alpha3, 0) == 2, "two notes on its star: 'never repeats' is out (reads %d)" % d._effective_repeat_state(alpha3, 0))
	ok(d._effective_repeat_state(alpha3, 2) != 2, "and 'repeats twice' stays open (reads %d)" % d._effective_repeat_state(alpha3, 2))

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
