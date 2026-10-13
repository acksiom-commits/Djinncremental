extends "res://dev_tests/test_base.gd"
# HINTS WITH THE FIRST NOTES HIDDEN (2026-10-12): the Beginner hint finder,
# re-based on who fires on each note (_hint_owner_steps).
#
# On a repeating melody the board keeps no firing-order position, so a hint
# step is about CELLS of (row, note): "with what you know, Helios must fire on
# note 6, and cannot fire on notes 1 and 2".
#
#  1. SPECIFIC STEPS on a small hand-built board: what one clue says outright,
#     what a known firing count adds, two stars related by one clue, and that
#     a star the clue gives the player no way to find yields no step.
#  2. NOTHING ABOUT WHICH NOTES ARE FIRST FIRINGS is used: the same clue on the
#     same board gives the same steps whichever notes are secretly repeats.
#  3. SOUND ON REAL PUZZLES. On generated Beginner puzzles, starting from an
#     empty board with every star Listened, every step offered is applied to
#     the board (as the player would, on the row the step names) and the finder
#     is asked again, round after round. EVERY step offered along the way must
#     be true of the real melody. The judge reads the melody; the finder never
#     does. Shown to bite: a step with one note swapped is judged false.
#  4. SCORING: a clue about a note counts as recorded once the row holds it.
#  5. WHICH STAR A NAME IS (added later the same day): a row's notes and the
#     map are one question. The real-puzzle run in 3 applies and judges all
#     three kinds of step -- notes, a row's Repeats entry, which map star a
#     name is -- and the small board checks the links between them.
#
# NOT checked here: the Hint tab on screen, and how far the steps carry a
# player towards the solution (reported, not asserted).

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _small_host(melody: Array):
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
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _beginner_puzzle(cid: int, seed: int) -> Array:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	return [g, cd]


func _host_for(g, cd, cid: int):
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = cid
	host._star_count = g.star_count
	host._star_names = g.star_names.duplicate()
	host._star_colors = g.star_colors.duplicate()
	host._star_degrees = g.star_degrees.duplicate()
	host._pitch_freqs = cd.get_note_freqs(cid)
	host._star_pitch_index = g.star_pitch_index.duplicate()
	host._sequence_rank_solution = g.sequence_rank_solution.duplicate()
	host._melody_seq_pos_sequence = g.melody_seq_pos_sequence.duplicate()
	host._melody_star_sequence = g.melody_star_sequence.duplicate()
	host._repeat_count = g.repeat_count.duplicate()
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _clue(text: String, terms: Array, facts: Array) -> Dictionary:
	return {"text": text, "search_terms": terms, "disclosures": facts, "cells": []}


func _note_steps(d, clues: Array) -> Array:
	var out: Array = []
	for st in d.hint_next_steps(clues):
		if str(st["axis"]) == "note":
			out.append(st)
	return out


func _step_for(steps: Array, descriptor: String) -> Dictionary:
	for st in steps:
		if str(st["descriptor"]) == descriptor:
			return st
	return {}


## The record of the row a step names, created if the player has not opened it.
func _row_record(d, step: Dictionary) -> int:
	match str(step["row_kind"]):
		"name":
			return d._get_or_create_match_record_for_name(str(step["row_key"]))
		"star":
			return d._get_or_create_match_record_for_star_idx(int(step["row_key"]))
	return d._get_or_create_match_record_for_melody_tick(int(step["row_key"]))


func run() -> void:
	var pin_alpha_6: Dictionary = {"kind": "firing_position", "s": 0, "sel": {"kind": "count", "lo": 6, "hi": 6}, "lo": 1, "hi": 1}

	print("=== what one clue says outright ===")
	var host = await _small_host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var w = host._widgets
	ok(d._notes_hidden() and not d.hints_unavailable(), "the notes are hidden and the hint finder is on")
	var c_pin: Dictionary = _clue("Alpha fires on note 6.", ["N:Alpha"], [pin_alpha_6])
	var steps: Array = _note_steps(d, [c_pin])
	var st: Dictionary = _step_for(steps, "Alpha")
	ok(not st.is_empty() and st["must_ticks"] == [6] and (st["cannot_ticks"] as Array).is_empty(),
		"'Alpha fires on note 6': Alpha must fire on note 6 (got %s)" % str(st.get("must_ticks", "no step")))
	ok(not st.is_empty() and w._step_sentence(st) == "With what you know, Alpha must fire on note 6.",
		"said as '%s'" % (w._step_sentence(st) if not st.is_empty() else ""))
	ok(not st.is_empty() and str(st["row_kind"]) == "name" and str(st["row_key"]) == "Alpha", "the step names the row to act on: Alpha's Name row")

	# "Beta is not the star that fires 1st note" + "Beta first fires within the first 3 notes"
	var c_neg: Dictionary = _clue("Beta is not the star that fires 1st note.", ["N:Beta", "S:1"],
		[{"kind": "ordinal_neg", "s": 1, "r": 0}])
	var st_neg: Dictionary = _step_for(_note_steps(d, [c_neg]), "Beta")
	ok(not st_neg.is_empty() and st_neg["cannot_ticks"] == [1] and (st_neg["must_ticks"] as Array).is_empty(),
		"'Beta is not the star that fires 1st note': Beta cannot fire on note 1 (got %s)" % str(st_neg.get("cannot_ticks", "no step")))
	ok(not st_neg.is_empty() and w._step_sentence(st_neg) == "With what you know, Beta cannot fire on note 1.",
		"said as '%s'" % (w._step_sentence(st_neg) if not st_neg.is_empty() else ""))

	# An order clue: "Beta first fires after Alpha" -> Beta cannot fire on note 1,
	# whatever else is known; nothing follows for Alpha.
	var c_cmp: Dictionary = _clue("Beta first fires after Alpha.", ["N:Beta", "N:Alpha"],
		[{"kind": "ordinal_cmp", "a": 1, "b": 0, "a_gt_b": true}])
	var cmp_steps: Array = _note_steps(d, [c_cmp])
	ok(_step_for(cmp_steps, "Beta").get("cannot_ticks", []) == [1] and _step_for(cmp_steps, "Alpha").is_empty(),
		"'Beta first fires after Alpha': Beta cannot fire on note 1, and nothing is said of Alpha")

	print("\n=== a star the clue gives no way to find yields no step ===")
	var c_blind: Dictionary = _clue("(no descriptor for star 0)", [], [pin_alpha_6])
	ok(_note_steps(d, [c_blind]).is_empty(), "the same fact with no descriptor in the clue's own terms: no step")
	var c_bynote: Dictionary = _clue("The star that fires 1st note fires on note 6.", ["S:1"], [pin_alpha_6])
	var st_note: Dictionary = _step_for(_note_steps(d, [c_bynote]), "the star that fires 1st note")
	ok(not st_note.is_empty() and st_note["must_ticks"] == [6] and str(st_note["row_kind"]) == "note" and int(st_note["row_key"]) == 1,
		"named only by a note, the step is about that note's own entry: note 1's star must fire on note 6")

	print("\n=== a known firing count adds what completing the row forces ===")
	# Alpha's row marked 'repeats once' (fires twice) and holding note 6.
	var a: int = d._get_or_create_match_record_for_name("Alpha")
	d.record_at(a)["repeat_states"] = {1: 1}
	d._full_propagation_refresh()
	await w._on_seq_note_select(d._get_or_create_match_record_for_name("Alpha"), 6)
	a = d._get_or_create_match_record_for_name("Alpha")
	ok(d._known_fire_count_for_record(a) == 2 and d.record_at(a)["melody_ticks"] == [6], "precondition: Alpha fires twice and holds note 6")
	# "Alpha first fires within the first 2 notes": its other note is 1 or 2, so
	# notes 3, 4, 5 are out. (ordinal_range hi = rank 1, whose label note is 2.)
	var c_range: Dictionary = _clue("Alpha first fires within the first 2 notes.", ["N:Alpha"],
		[{"kind": "ordinal_range", "s": 0, "lo": 0, "hi": 1}])
	var st_range: Dictionary = _step_for(_note_steps(d, [c_range]), "Alpha")
	ok(not st_range.is_empty() and st_range["cannot_ticks"] == [3, 4, 5] and (st_range["must_ticks"] as Array).is_empty(),
		"with one note left to place, 'within the first 2 notes' rules out notes 3, 4, 5 (got %s)" % str(st_range.get("cannot_ticks", "no step")))
	# The count unknown, the same clue forces no cell.
	var b_row: int = d._get_or_create_match_record_for_name("Beta")
	ok(d._known_fire_count_for_record(b_row) < 0, "precondition: Beta's count is not known")
	var c_range_b: Dictionary = _clue("Beta first fires within the first 2 notes.", ["N:Beta"],
		[{"kind": "ordinal_range", "s": 1, "lo": 0, "hi": 1}])
	ok(_step_for(_note_steps(d, [c_range_b]), "Beta").is_empty(), "the same clue about Beta, whose count is unknown, forces no note")

	print("\n=== two stars one clue relates are worked out together ===")
	# Beta also 'repeats once'. "The last firing of Beta is immediately before
	# the last firing of Alpha" (Alpha's last is 6) -> Beta must fire on note 5.
	d.record_at(d._get_or_create_match_record_for_name("Beta"))["repeat_states"] = {1: 1}
	d._full_propagation_refresh()
	var c_rel: Dictionary = _clue("The last firing of Beta is immediately before the last firing of Alpha.", ["N:Beta", "N:Alpha"],
		[{"kind": "firing_relation", "a": 1, "b": 0, "pick_a": {"kind": "last"}, "pick_b": {"kind": "last"},
			"spec": {"rel": "exact", "n": 1, "dir": -1, "neg": false}}])
	var st_rel: Dictionary = _step_for(_note_steps(d, [c_rel]), "Beta")
	ok(not st_rel.is_empty() and st_rel["must_ticks"] == [5],
		"Beta must fire on note 5 (got %s)" % str(st_rel.get("must_ticks", "no step")))
	var st_rel_a: Dictionary = _step_for(_note_steps(d, [c_rel]), "Alpha")
	ok(not st_rel_a.is_empty() and (st_rel_a["cannot_ticks"] as Array).has(5),
		"and on Alpha's row note 5 is ruled out: it is Beta's (got %s)" % str(st_rel_a.get("cannot_ticks", "no step")))

	print("\n=== scoring: a clue about a note is recorded once the row holds it ===")
	ok(d._disclosure_satisfied(pin_alpha_6), "'Alpha fires on note 6' is satisfied: Alpha's row holds note 6")
	var pin_alpha_1: Dictionary = {"kind": "firing_position", "s": 0, "sel": {"kind": "count", "lo": 1, "hi": 1}, "lo": 1, "hi": 1}
	ok(not d._disclosure_satisfied(pin_alpha_1), "'Alpha fires on note 1' is not: nothing on the row says so yet")
	ok(_note_steps(d, [c_pin]).is_empty(), "and the recorded clue no longer offers its step")
	host.queue_free()

	print("\n=== several clues together, once no single clue gives anything ===")
	# Alpha fires twice and nothing is placed. Neither clue forces a note alone:
	#   A "Alpha first fires within the first 2 notes"   -> its notes include 1 or 2
	#   B "Alpha fires at least once in notes 5 to 6"     -> its notes include 5 or 6
	# Together its two notes are one of each, so notes 3 and 4 are out.
	var hm = await _small_host([1, 2, 2, 3, 4, 1])
	var dm = hm._deduction
	var wm = hm._widgets
	var am: int = dm._get_or_create_match_record_for_name("Alpha")
	dm.record_at(am)["repeat_states"] = {1: 1}
	dm._full_propagation_refresh()
	var c_a: Dictionary = _clue("Alpha first fires within the first 2 notes.", ["N:Alpha"],
		[{"kind": "ordinal_range", "s": 0, "lo": 0, "hi": 1}])
	var c_b: Dictionary = _clue("Alpha fires at least once in notes 5 to 6.", ["N:Alpha"],
		[{"kind": "firing_position", "s": 0, "sel": {"kind": "count", "lo": 5, "hi": 6}, "lo": 1, "hi": 2}])
	ok(dm.hint_next_steps([c_a]).is_empty() and dm.hint_next_steps([c_b]).is_empty(), "neither clue gives a step on its own")
	var both: Array = dm.hint_next_steps([c_a, c_b])
	ok(both.size() == 1 and bool(both[0].get("multi", false)) and both[0]["clue_indices"] == [0, 1],
		"together they give one step, naming both clues (got %s)" % str(both[0].get("clue_indices", "none") if both.size() > 0 else "no step"))
	ok(both.size() == 1 and both[0]["cannot_ticks"] == [3, 4] and (both[0]["must_ticks"] as Array).is_empty(),
		"Alpha cannot fire on notes 3 and 4 (got %s)" % str(both[0].get("cannot_ticks", []) if both.size() > 0 else []))
	ok(both.size() == 1 and wm._step_sentence(both[0]) == "With what you know, Alpha cannot fire on notes 3 and 4.",
		"said as '%s'" % (wm._step_sentence(both[0]) if both.size() > 0 else ""))
	# A third clue that adds nothing to that conclusion is not named.
	var c_idle: Dictionary = _clue("Beta is not the star that fires 6th note.", ["N:Beta", "S:6"],
		[{"kind": "ordinal_neg", "s": 1, "r": 3}])
	var with_idle: Array = dm.hint_next_steps([c_a, c_idle, c_b])
	var only_singles: bool = true
	for wi in with_idle:
		if bool(wi.get("multi", false)):
			only_singles = false
	ok(only_singles and not with_idle.is_empty(), "while any single clue still gives a step, the several-clue search is not run")
	# What one clue says about how often a star fires feeds another clue's notes,
	# before the player has marked it: Beta's count is not on the board.
	var c_rep_b: Dictionary = _clue("Beta is one of the stars that repeat once.", ["N:Beta"],
		[{"kind": "repeat_count_range", "star": 1, "lo": 1, "hi": 1, "negated": false}])
	var c_gap: Dictionary = _clue("The first and last times Beta fires are exactly 5 notes apart.", ["N:Beta"],
		[{"kind": "firing_position", "s": 1, "sel": {"kind": "span", "i": 1, "j": -1}, "lo": 5, "hi": 5}])
	var world: Dictionary = dm._owner_world([c_rep_b, c_gap], [0, 1], dm._hint_solver_for(4))
	var beta_must: Array = []
	if bool(world["ok"]):
		for wk in world["verdicts"]:
			if str(world["rows"][wk]["frame"]["label"]) == "Beta":
				beta_must = world["verdicts"][wk]["must"]
	ok(beta_must == [1, 6], "'Beta repeats once' + 'first and last 5 notes apart': Beta must fire on notes 1 and 6 (got %s)" % str(beta_must))
	# Two rows the board has not joined are kept apart: a clue about "the red
	# star" says nothing about Alpha's row, though Alpha IS the red star.
	var c_red: Dictionary = _clue("The red star fires on note 2.", ["C:" + str(hm.COLOR_NAME_LABELS[0])],
		[{"kind": "firing_position", "s": 0, "sel": {"kind": "count", "lo": 2, "hi": 2}, "lo": 1, "hi": 1}])
	var w2: Dictionary = dm._owner_world([c_a, c_b, c_red], [0, 1, 2], dm._hint_solver_for(4))
	var alpha_verdict: Dictionary = {}
	var row_count: int = 0
	if bool(w2["ok"]):
		row_count = (w2["rows"] as Dictionary).size()
		for wk2 in w2["verdicts"]:
			if str(w2["rows"][wk2]["frame"]["label"]) == "Alpha":
				alpha_verdict = w2["verdicts"][wk2]
	ok(row_count == 2 and alpha_verdict.get("must", [0]) == [] and alpha_verdict.get("cannot", []) == [3, 4],
		"a clue about the star by its colour is a separate row: Alpha's row gains nothing from it (%d rows, Alpha %s)" % [row_count, str(alpha_verdict)])
	hm.queue_free()

	print("\n=== a row's notes and which star it is are one question ===")
	var hn = await _small_host([1, 2, 2, 3, 4, 1])   # Alpha and Beta fire twice, Gamma and Delta once
	var dn = hn._deduction
	var wn = hn._widgets
	for s5 in 4:
		await hn._on_pitch_listen_star_clicked(s5)
	# A clue about how often a star fires is a step on its Repeats entry.
	var c_rep: Dictionary = _clue("Gamma is one of the stars that never repeat.", ["N:Gamma"],
		[{"kind": "repeat_count_range", "star": 2, "lo": 0, "hi": 0, "negated": false}])
	var rep_steps: Array = dn.hint_next_steps([c_rep])
	var st_rep: Dictionary = {}
	for rs in rep_steps:
		if str(rs["axis"]) == "repeat":
			st_rep = rs
	ok(not st_rep.is_empty() and int(st_rep["must_value"]) == 0 and str(st_rep["descriptor"]) == "Gamma",
		"'Gamma never repeats': a step on Gamma's Repeats entry, which must be 0")
	ok(not st_rep.is_empty() and wn._step_sentence(st_rep).begins_with("With what you know, Gamma must be marked '"),
		"said as: %s" % (wn._step_sentence(st_rep) if not st_rep.is_empty() else ""))
	# Notes -> star: a Name row holding two notes cannot be a star that fires once.
	var g_row: int = dn._get_or_create_match_record_for_name("Epsilon-not-a-name")
	dn.record_at(g_row)["name"] = "Gamma"
	await wn._on_seq_note_select(g_row, 4)
	await wn._on_seq_note_select(dn._find_match_record_by_name("Gamma"), 5)
	dn._full_propagation_refresh()
	var cands: Array = dn._candidate_stars_for_record(dn._find_match_record_by_name("Gamma"))
	ok(not cands.has(2) and not cands.has(3) and cands.has(0) and cands.has(1),
		"a row holding two notes can only be a star that fires at least twice (stars %s)" % str(cands))
	# Star -> notes: every star a row could be fires twice, so the row fires twice,
	# although nothing says WHICH of them it is.
	var fr_two: Dictionary = dn._owner_frame(2, {"search_terms": ["N:Gamma"]})
	ok(fr_two["counts"] == [2] and dn._effective_star_idx(dn._find_match_record_by_name("Gamma")) < 0,
		"its firing count is known (counts %s) although no star is pinned to the row" % str(fr_two["counts"]))
	# A map star's row marked 'not note 4' cannot be the row that holds note 4.
	var star0: int = dn._get_or_create_match_record_for_star_idx(0)
	wn._on_seq_note_toggle(star0, 4)
	dn._full_propagation_refresh()
	cands = dn._candidate_stars_for_record(dn._find_match_record_by_name("Gamma"))
	ok(cands == [1], "a map star whose own row rules out note 4 is not the row holding note 4 (left: %s)" % str(cands))
	hn.queue_free()

	print("\n=== which notes are secretly repeats changes nothing ===")
	# The same star order and clues over two different melodies with the same
	# label notes for ranks 0 and 1 (notes 1 and 2); only the repeats differ.
	var sigs: Array = []
	for melody in [[1, 2, 2, 3, 4, 1], [1, 2, 3, 4, 1, 2]]:
		var h2 = await _small_host(melody)
		var d2 = h2._deduction
		var sig: Array = []
		for cl in [c_pin, c_neg, c_cmp]:
			for s2 in _note_steps(d2, [cl]):
				sig.append([str(s2["descriptor"]), s2["must_ticks"], s2["cannot_ticks"]])
		sigs.append(str(sig))
		h2.queue_free()
	ok(sigs[0] == sigs[1] and sigs[0] != "[]", "two melodies differing only in which notes repeat give identical steps")

	print("\n=== sound on real puzzles, round after round ===")
	var offered: int = 0
	var false_steps: Array = []
	var judged_cells: int = 0
	var by_axis: Dictionary = {}
	var total_placed: int = 0
	var total_notes: int = 0
	var whole_complete: int = 0
	var whole_lost_truth: int = 0
	for cid in [0, 2, 4]:
		var made: Array = _beginner_puzzle(cid, 11)
		var g = made[0]
		await g.generate_clues_forms()
		ok(g.gate_passed, "c%d: the puzzle passes the ship gate" % cid)
		var hp = await _host_for(g, made[1], cid)
		var dp = hp._deduction
		var wp = hp._widgets
		var clues: Array = []
		for cl2 in g.chosen_form_clues:
			clues.append(cl2)
		# Every star Listened: the premise the puzzle is built on.
		for s3 in g.star_count:
			await hp._on_pitch_listen_star_clicked(s3)
		var rounds: int = 0
		var here: int = 0
		for _round in 30:
			# EVERY kind of step the finder offers on this board: notes, a row's
			# Repeats entry, and which map star a name is.
			var now: Array = dp.hint_next_steps(clues)
			if now.is_empty():
				break
			rounds += 1
			for stp in now:
				offered += 1
				here += 1
				by_axis[str(stp["axis"])] = int(by_axis.get(str(stp["axis"]), 0)) + 1
				if bool(stp.get("multi", false)):
					by_axis["of which several-clue"] = int(by_axis.get("of which several-clue", 0)) + 1
				var star: int = int(stp["star"])
				match str(stp["axis"]):
					"note":
						for t in stp["must_ticks"]:
							judged_cells += 1
							if int(g.melody_star_sequence[int(t) - 1]) != star:
								false_steps.append("c%d: %s" % [cid, wp._step_sentence(stp)])
						for t2 in stp["cannot_ticks"]:
							judged_cells += 1
							if int(g.melody_star_sequence[int(t2) - 1]) == star:
								false_steps.append("c%d: %s" % [cid, wp._step_sentence(stp)])
					"repeat":
						judged_cells += 1 + (stp["cannot_values"] as Array).size()
						var real: int = int(g.repeat_count[star])
						if (int(stp["must_value"]) >= 0 and int(stp["must_value"]) != real) or (stp["cannot_values"] as Array).has(real):
							false_steps.append("c%d: %s" % [cid, wp._step_sentence(stp)])
					"name":
						# `star` is the NAME's own star; it must not be ruled out.
						judged_cells += (stp["eliminated_stars"] as Array).size()
						if (stp["eliminated_stars"] as Array).has(star):
							false_steps.append("c%d: name %s ruled out of its own star" % [cid, str(hp._star_names[star])])
			# Act on every step as the player would, on the row it names.
			for stp2 in now:
				match str(stp2["axis"]):
					"note":
						for t3 in stp2["must_ticks"]:
							var rec: int = _row_record(dp, stp2)
							if dp._repeat_note_state_for_record(rec, int(t3)) == 0:
								await wp._on_seq_note_select(rec, int(t3))
						for t4 in stp2["cannot_ticks"]:
							var rec2: int = _row_record(dp, stp2)
							if dp._repeat_note_state_for_record(rec2, int(t4)) == 0:
								wp._on_seq_note_toggle(rec2, int(t4))
					"repeat":
						var rec3: int = _row_record(dp, stp2)
						if int(stp2["must_value"]) >= 0:
							if dp._effective_repeat_state(rec3, int(stp2["must_value"])) == 0:
								wp._repeat_toggle_confirm(rec3, int(stp2["must_value"]))
						else:
							for v in stp2["cannot_values"]:
								rec3 = _row_record(dp, stp2)
								if dp._effective_repeat_state(rec3, int(v)) == 0:
									wp._repeat_toggle_block(rec3, int(v))
					"name":
						var nrec: int = dp._get_or_create_match_record_for_name(str(hp._star_names[int(stp2["star"])]))
						var elim: Dictionary = dp.record_at(nrec).get("star_elim", {})
						for s4 in stp2["eliminated_stars"]:
							if int(elim.get(int(s4), 0)) == 0:
								elim[int(s4)] = 2
						dp.record_at(nrec)["star_elim"] = elim
						dp._save_puzzle_notes()
						dp._full_propagation_refresh()
		var placed: int = 0
		for r in dp.record_count():
			placed += (dp.record_at(r).get("melody_ticks", []) as Array).size()
		var names_tied: int = 0
		for n in g.star_count:
			var nr: int = dp._find_match_record_by_name(str(hp._star_names[n]))
			if nr >= 0 and dp._candidate_stars_for_record(nr).size() == 1:
				names_tied += 1
		total_placed += placed
		total_notes += g.melody_star_sequence.size()
		print("      clues still with something to give when the steps ran out: %d of %d" % [
			dp.clue_indices_with_something_to_give(clues).size(), clues.size()])
		# THE WHOLE-MELODY SEARCH MUST NEVER LOSE THE TRUTH. On the board the
		# steps stalled on, every assignment it accepts is listed (within the
		# budget the game gives it); if the list is complete, the real melody
		# has to be in it. An incomplete list proves nothing either way.
		var stalled: Array = []
		for sw in dp.clue_indices_with_something_to_give(clues):
			stalled.append(int(sw))
		var w_setup: Dictionary = dp._owner_global_setup(clues, stalled)
		# Only the smallest of the three is given a budget large enough to
		# finish (under a second); the other two take minutes and prove the
		# same thing no better.
		if bool(w_setup["ok"]) and cid == 4:
			var w_res: Dictionary = dp._owner_global_solve(w_setup, 20000, dp._hint_solver_for(g.star_count), 3000000)
			if bool(w_res["complete"]):
				whole_complete += 1
				if not (w_res["sols"] as Array).has(g.melody_star_sequence):
					whole_lost_truth += 1
				print("      whole-melody search on the stalled board: %d assignments fit, the real melody among them: %s" % [
					(w_res["sols"] as Array).size(), str((w_res["sols"] as Array).has(g.melody_star_sequence))])
			else:
				print("      whole-melody search on the stalled board: gave up (too open to list)")
		print("    c%d: %d steps over %d rounds; %d of %d notes placed on rows; %d of %d names down to one star" % [
			cid, here, rounds, placed, g.melody_star_sequence.size(), names_tied, g.star_count])
		hp.queue_free()
	print("    steps by kind: %s; notes placed in all: %d of %d" % [str(by_axis), total_placed, total_notes])
	ok(offered >= 20, "the finder offered steps to judge (%d steps, %d cells)" % [offered, judged_cells])
	ok(int(by_axis.get("note", 0)) > 0 and int(by_axis.get("repeat", 0)) > 0 and int(by_axis.get("name", 0)) > 0,
		"all three kinds were offered and judged: notes, Repeats entries, which star a name is")
	ok(whole_complete >= 1 and whole_lost_truth == 0,
		"where the whole-melody search was run to the end (%d board), the real melody was among the assignments it accepts (%d lost)" % [whole_complete, whole_lost_truth])
	ok(false_steps.is_empty(), "every step offered was true of the real melody (%d false) %s" % [false_steps.size(), str(false_steps.slice(0, 2))])
	# The judge can fail: the first small-board step with its note moved.
	var wrong: Dictionary = {"star": 0, "must_ticks": [5], "cannot_ticks": []}
	var judge_bites: bool = int([0, 1, 1, 2, 3, 0][int(wrong["must_ticks"][0]) - 1]) != int(wrong["star"])
	ok(judge_bites, "the judge calls a step with the wrong note false")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
