extends "res://dev_tests/test_base.gd"
# Hint tiers 3 and 4, NAME axis (phase 1: group kinds + either-or).
#
# A Name clue restricts which map stars a name can be ("Alpha is a first_colour star",
# "Alpha is not the star with pitch E"). A step exists when that restriction,
# resolved against what the PLAYER knows, rules out a star the board still
# allows for that name.
#
# What must hold, and why each case exists:
#  - The pure finder closes the name x star grid (alldiff on both sides) and
#    reports only what the clue adds; a contradiction is never a hint.
#  - LEAK GUARDS, the whole reason this axis is riskier than Sequence:
#      * a Pitch group only EXCLUDES stars whose pitch the player has heard
#        (Listened); before that, a "not pitch E" clue yields no step at all;
#      * a Sequence-anchored group resolves through the player's own candidate
#        stars for that position, never the true rank->star mapping, so on a
#        blank board it yields nothing;
#      * a name is only ever reported if the clue's own text names it.
#  - SOUNDNESS against ground truth on a REAL puzzle with boards built from the
#    true assignment: nothing eliminated is ever a name's true star, and
#    anything resolved is correct. With a positive control.
#  - The Hint tab shows the right sentence for each case.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const Finder = preload("res://constellation_next_step_finder.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _blank_grid(n: int) -> Array:
	var grid: Array = []
	for s in n:
		var row: Array = []
		row.resize(n)
		for r in n:
			row[r] = true
		grid.append(row)
	return grid


func _hint_texts(host) -> Array:
	var out: Array = []
	for ch in host._markers_content.get_children():
		if ch is Label:
			out.append((ch as Label).text)
	return out


func _repaint(host, w) -> void:
	for c in host._markers_content.get_children():
		c.free()
	w._populate_hint_markers()


## Claims in a Name step list that contradict ground truth (name n's true star is n).
func _count_lies(steps: Array) -> int:
	var lies: int = 0
	for st in steps:
		if str(st["axis"]) != "name":
			continue
		for s in st["eliminated_stars"]:
			if int(s) == int(st["star"]):
				lies += 1
		if int(st["resolved_star"]) >= 0 and int(st["resolved_star"]) != int(st["star"]):
			lies += 1
	return lies


func _name_steps(steps: Array) -> Array:
	var out: Array = []
	for st in steps:
		if str(st["axis"]) == "name":
			out.append(st)
	return out


func run() -> void:
	print("=== the pure finder ===")
	var solver = PuzzleScript.new()
	solver.star_count = 6
	var pin: Dictionary = Finder.step_for_sets(solver, _blank_grid(6), [{"row": 0, "allowed": [2]}])
	ok(bool(pin["consistent"]) and pin["resolved"] == [[0, 2]], "a one-star allowed set pins the name (got %s)" % str(pin["resolved"]))
	ok((pin["eliminated"] as Array).size() == 10, "and closes the grid: 5 other stars for it, that star for 5 other names (got %d)" % (pin["eliminated"] as Array).size())
	var excl: Dictionary = Finder.step_for_sets(solver, _blank_grid(6), [{"row": 0, "excluded": [0, 1]}])
	ok((excl["eliminated"] as Array).size() == 2 and (excl["resolved"] as Array).is_empty(), "an excluded set only trims (got %s)" % str(excl["eliminated"]))
	var known: Array = _blank_grid(6)
	for c in 6:
		known[1][c] = (c == 1)
	var carried: Dictionary = Finder.step_for_sets(solver, known, [{"row": 0, "allowed": [0, 1]}])
	ok(carried["resolved"] == [[0, 0]], "with name 1 already known at star 1, 'star 0 or 1' resolves name 0 to star 0 (got %s)" % str(carried["resolved"]))
	var boxed: Array = _blank_grid(6)
	for c2 in 6:
		boxed[0][c2] = (c2 == 1)
	var bad: Dictionary = Finder.step_for_sets(solver, boxed, [{"row": 0, "allowed": [3]}])
	ok(not bool(bad["consistent"]) and (bad["eliminated"] as Array).is_empty(), "a restriction that contradicts the board is never a step")

	print("\n=== through the deduction engine: fixture puzzle, leak guards ===")
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33, 622.25]
	host._star_pitch_index = [0, 1, 2, 3, 4, 5]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	var d = host._deduction
	var w = host._widgets
	var COLOR: int = PuzzleScript.Category.COLOR
	var PITCH: int = PuzzleScript.Category.PITCH
	var SEQ: int = PuzzleScript.Category.SEQUENCE
	var first_colour: String = str(host.COLOR_NAME_LABELS[0])

	var NAME_CAT: int = PuzzleScript.Category.NAME
	var pos_clue: Dictionary = {"text": "Alpha is a %s star." % first_colour.to_lower(),
		"cells": [{"cat_a": NAME_CAT, "star_a": 0, "cat_b": COLOR, "star_b": 0, "is_true": true}],
		"search_terms": ["N:Alpha", "C:" + first_colour],
		"disclosures": [{"kind": "name_group", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 2}
	var neg_clue: Dictionary = {"text": "Alpha is not a %s star." % first_colour.to_lower(),
		"cells": [{"cat_a": NAME_CAT, "star_a": 0, "cat_b": COLOR, "star_b": 0, "is_true": false}],
		"search_terms": ["N:Alpha", "C:" + first_colour],
		"disclosures": [{"kind": "name_group_neg", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 2}
	var pitch_clue: Dictionary = {"text": "Alpha is not the star with pitch X.",
		"cells": [{"cat_a": NAME_CAT, "star_a": 0, "cat_b": PITCH, "star_b": 3, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(PITCH, 3)],
		"disclosures": [{"kind": "name_group_neg", "name_star": 0, "cat": PITCH, "group_key": 3}],
		"characteristics": [], "chars": [], "form_id": 2}
	var seq_clue: Dictionary = {"text": "Alpha is the star that fires 3rd.",
		"cells": [{"cat_a": NAME_CAT, "star_a": 0, "cat_b": SEQ, "star_b": 2, "is_true": true}],
		"search_terms": ["N:Alpha", "S:3"],
		"disclosures": [{"kind": "name_group", "name_star": 0, "cat": SEQ, "group_key": 2}],
		"characteristics": [], "chars": [], "form_id": 2}
	var unnamed_clue: Dictionary = {"text": "Somebody is a first_colour star.", "cells": [],
		"search_terms": ["C:" + first_colour],
		"disclosures": [{"kind": "name_group", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 2}

	d._load_match_records([])
	d._clear_deduction_caches()
	var s_pos: Array = _name_steps(d.hint_next_steps([pos_clue]))
	ok(s_pos.size() == 1 and s_pos[0]["descriptor"] == "Alpha" and (s_pos[0]["eliminated_stars"] as Array).size() == 4 and not bool(s_pos[0]["resolved"]),
		"blank board: 'Alpha is a <first colour> star' is a step, ruling out the 4 stars of other colours (got %s)" % str(s_pos))
	var s_neg: Array = _name_steps(d.hint_next_steps([neg_clue]))
	ok(s_neg.size() == 1 and (s_neg[0]["eliminated_stars"] as Array).size() == 2 and not bool(s_neg[0]["positive"]),
		"blank board: 'Alpha is not <first colour>' rules out the 2 stars of that colour (got %s)" % str(s_neg))

	ok(d.clue_indices_with_something_to_give([pitch_clue]) == [0],
		"the pitch clue IS offered as unrecorded, so the next check is not vacuous")
	ok(_name_steps(d.hint_next_steps([pitch_clue])).is_empty(),
		"LEAK GUARD: 'not pitch X' gives NO step before any pitch has been heard")
	var listened: int = d._get_or_create_match_record_for_star_idx(3)
	d._match_records[listened]["pitch_revealed"] = true
	d._clear_deduction_caches()
	var s_pitch: Array = _name_steps(d.hint_next_steps([pitch_clue]))
	ok(s_pitch.size() == 1 and (s_pitch[0]["eliminated_stars"] as Array) == [3],
		"...and once star 3 has been Listened to, it rules out exactly that star (got %s)" % str(s_pitch))
	d._load_match_records([])
	d._clear_deduction_caches()

	ok(d.clue_indices_with_something_to_give([seq_clue]) == [0],
		"the position-anchored clue IS offered as unrecorded, so the next check is not vacuous")
	ok(_name_steps(d.hint_next_steps([seq_clue])).is_empty(),
		"LEAK GUARD: a position-anchored group gives no step while the player does not know which star fires 3rd")
	ok(d._name_constraints_for_clue(unnamed_clue).is_empty(),
		"LEAK GUARD: a clue whose text does not name the name yields nothing about it")

	print("\n=== the remaining kinds: position predicates, group order, same/different pairs ===")
	d._load_match_records([])
	d._clear_deduction_caches()
	var all6: Array = [0, 1, 2, 3, 4, 5]
	var range_fact: Dictionary = {"kind": "name_rank_range", "name_star": 0, "lo": 0, "hi": 1}
	ok(d._stars_allowed_by_position_fact(range_fact) == all6, "LEAK GUARD: a rank range drops nothing while no position is known")
	# The player has identified Eos as star 4 and placed it 5th.
	var eos: int = d._get_or_create_match_record_for_star_idx(4)
	d._match_records[eos]["name"] = "Eos"
	d._match_records[eos]["name_states"] = {"Eos": 1}
	d._match_records[eos]["seq_lo"] = 5
	d._match_records[eos]["seq_hi"] = 5
	d._clear_deduction_caches()
	ok(d._player_positions_for_star(4) == [5], "fixture: the player knows star 4 fires 5th (got %s)" % str(d._player_positions_for_star(4)))
	ok(d._stars_allowed_by_position_fact(range_fact) == [0, 1, 2, 3, 5],
		"...so a range of positions 1-2 drops exactly star 4 (got %s)" % str(d._stars_allowed_by_position_fact(range_fact)))
	var late_fact: Dictionary = {"kind": "name_rank_range", "name_star": 0, "lo": 4, "hi": 5}
	ok(d._stars_allowed_by_position_fact(late_fact) == all6, "a range that star 4's known position satisfies drops nothing")

	# Beta is now identified as star 4 (instead of Eos), which pins Beta's row.
	d._match_records[eos]["name"] = "Beta"
	d._match_records[eos]["name_states"] = {"Beta": 1}
	d._clear_deduction_caches()
	var same_clue: Dictionary = {"text": "Alpha and Beta share a colour.",
		"cells": [{"cat_a": NAME_CAT, "star_a": 0, "cat_b": COLOR, "star_b": 2, "is_true": false}],
		"search_terms": ["N:Alpha", "N:Beta", d._descriptor_term(COLOR, 2)],
		"disclosures": [{"kind": "name_same_group", "name_star_a": 0, "name_star_b": 1, "cat": COLOR}],
		"characteristics": [], "chars": [], "form_id": 12}
	var diff_clue: Dictionary = same_clue.duplicate(true)
	diff_clue["text"] = "Alpha and Beta differ in colour."
	diff_clue["disclosures"] = [{"kind": "name_different_group", "name_star_a": 0, "name_star_b": 1, "cat": COLOR}]
	ok(d.clue_indices_with_something_to_give([same_clue]) == [0] and d.clue_indices_with_something_to_give([diff_clue]) == [0],
		"the same/different clues ARE offered as unrecorded, so what follows is not vacuous")
	var s_same: Array = _name_steps(d.hint_next_steps([same_clue])).filter(func(st): return st["star"] == 0)
	ok(s_same.size() == 1 and str(s_same[0]["resolved_desc"]).ends_with("star that is not Beta's"),
		"a resolved star is named by exclusion when the other star of its colour is claimed (\"%s\")" % (str(s_same[0]["resolved_desc"]) if not s_same.is_empty() else ""))
	ok(s_same.size() == 1 and int(s_same[0]["resolved_star"]) == 5,
		"Beta is on star 4 (colour 2), so 'Alpha shares Beta's colour' leaves Alpha only star 5 (got %s)" % str(s_same))
	var s_diff: Array = _name_steps(d.hint_next_steps([diff_clue])).filter(func(st): return st["star"] == 0)
	ok(s_diff.size() == 1 and (s_diff[0]["eliminated_stars"] as Array) == [5] and not bool(s_diff[0]["positive"]),
		"...and 'differs' rules out star 5, the only other star of that colour (got %s)" % str(s_diff))

	# Group order: a name that fires before every star of a colour cannot be one of them.
	var prec_clue: Dictionary = {"text": "Alpha fires before every star of the first colour.",
		"cells": [{"cat_a": NAME_CAT, "star_a": 0, "cat_b": COLOR, "star_b": 0, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(COLOR, 0)],
		"disclosures": [{"kind": "name_precedes_group", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 9}
	var s_prec: Array = _name_steps(d.hint_next_steps([prec_clue]))
	ok(s_prec.size() == 1 and (s_prec[0]["eliminated_stars"] as Array) == [0, 1],
		"'fires before every <colour> star' rules out that colour's own stars (got %s)" % str(s_prec))
	d._load_match_records([])
	d._clear_deduction_caches()

	print("\n=== the Hint tab ===")
	host._form_clues_cache = [pos_clue]
	w._populate_hint_markers()
	for c0 in host._markers_content.get_children():
		c0.free()
	w._on_hint_tier3_pressed()
	_repaint(host, w)
	var t3: String = " ".join(_hint_texts(host))
	ok(w._hint_state == w.HINT_DESCRIPTOR and t3.contains("Alpha") and not t3.contains("must be"),
		"tier 3 names the name and gives no conclusion (\"%s\")" % t3)
	w._on_hint_tier4_pressed()
	_repaint(host, w)
	var t4: String = " ".join(_hint_texts(host))
	ok(w._hint_state == w.HINT_STEP and t4.contains("Alpha must be a %s star" % first_colour.to_lower()) and t4.contains("rules out 4 stars"),
		"tier 4 spells out the restriction (\"%s\")" % t4)
	var sentence: String = w._step_sentence({"axis": "name", "descriptor": "Alpha", "resolved_star": 0,
		"resolved_desc": "the blue star", "eliminated_stars": [1, 2], "phrase": "a first_colour star", "positive": true})
	ok(sentence == "With what you know, only one star is left for Alpha: the blue star.", "a resolved name reads as one star left (\"%s\")" % sentence)

	print("\n=== SOUNDNESS on a real puzzle, boards built from the true assignment ===")
	var cd = load("res://constellation_data.gd").new()
	var cdef: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 31337, 0, cdef.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g._generate_clues_forms_attempt()
	var rh = OverlayScene.instantiate()
	root.add_child(rh)
	await process_frame
	rh._cd = cd
	rh._constellation_id = 0
	rh._star_count = scn
	rh._star_names = g.star_names
	rh._star_colors = g.star_colors
	rh._star_degrees = []
	for _s in scn:
		rh._star_degrees.append(0)
	rh._sequence_rank_solution = g.sequence_rank_solution
	rh._pitch_freqs = cd.get_note_freqs(0)
	rh._star_pitch_index = cd.get_note_assignment(0)
	rh._form_clues_cache = g.chosen_form_clues
	rh._rebuild_star_distances()
	rh._widgets.clear_pitch_caches()
	var rd = rh._deduction
	rd._load_match_records([])
	rd._clear_deduction_caches()
	var rsolver = PuzzleScript.new()
	rsolver.star_count = scn

	var with_constraints: int = 0
	for rc in g.chosen_form_clues:
		if not rd._name_constraints_for_clue(rc).is_empty():
			with_constraints += 1
	print("    %d of %d clues carry a Name restriction this phase can read" % [with_constraints, g.chosen_form_clues.size()])
	ok(with_constraints > 3, "the puzzle has Name restrictions to judge (%d) -- otherwise the sweep is vacuous" % with_constraints)

	var pairs: int = 0
	var steps_seen: int = 0
	var cells_seen: int = 0
	var resolutions_seen: int = 0
	var lies: int = 0
	for k in [0, 3, 7, 11]:
		var grid: Array = _blank_grid(scn)
		for n in mini(int(k), scn):
			for c3 in scn:
				grid[n][c3] = (c3 == n)
		var steps: Array = _name_steps(rd._hint_name_steps(g.chosen_form_clues, rsolver, grid))
		pairs += with_constraints
		steps_seen += steps.size()
		for st in steps:
			cells_seen += (st["eliminated_stars"] as Array).size()
			if bool(st["resolved"]):
				resolutions_seen += 1
		lies += _count_lies(steps)
		print("    board with %2d names known: %d name steps" % [int(k), steps.size()])
	print("    %d clue/board pairs judged, %d steps, %d eliminated cells and %d resolutions checked against truth" % [pairs, steps_seen, cells_seen, resolutions_seen])
	ok(steps_seen > 5 and cells_seen > 20, "the sweep judged enough to mean something (%d steps, %d cells)" % [steps_seen, cells_seen])
	ok(lies == 0, "no eliminated star is a name's true star, no resolution is wrong (%d lies)" % lies)
	print("\n=== SOUNDNESS with truthful player records: named, placed and Listened stars ===")
	# The sweep above only gave the finder a name grid. These kinds read the
	# player's POSITION and PITCH knowledge, so build records that say what a
	# correct player would have written: star s named, placed at its true
	# position, and its pitch heard.
	var new_kinds: Array = ["name_rank_range", "name_nbr_count", "name_nbr_extreme", "name_precedes_group",
		"name_follows_group", "name_extreme_in_group", "name_same_group", "name_different_group"]
	var kind_counts: Dictionary = {}
	for rc2 in g.chosen_form_clues:
		for dd in (rc2.get("disclosures", []) as Array):
			if dd is Dictionary and new_kinds.has(str((dd as Dictionary).get("kind", ""))):
				var probe: Array = rd._name_constraints_for_clue({"search_terms": rc2.get("search_terms", []), "disclosures": [dd]})
				if not probe.is_empty():
					kind_counts[str(dd["kind"])] = int(kind_counts.get(str(dd["kind"]), 0)) + 1
	print("    readable clues of the new kinds in this puzzle: %s" % str(kind_counts))
	ok(not kind_counts.is_empty(), "this puzzle carries clues of the new kinds (%d), so the sweep exercises them" % kind_counts.size())
	var lies2: int = 0
	var steps2: int = 0
	var cells2: int = 0
	var resolved2: int = 0
	for k2 in [3, 7, 11]:
		rd._load_match_records([])
		for s3 in mini(int(k2), scn):
			var ri: int = rd._get_or_create_match_record_for_star_idx(s3)
			rd._match_records[ri]["name"] = str(g.star_names[s3])
			rd._match_records[ri]["name_states"] = {str(g.star_names[s3]): 1}
			rd._match_records[ri]["seq_lo"] = int(g.sequence_rank_solution[s3]) + 1
			rd._match_records[ri]["seq_hi"] = int(g.sequence_rank_solution[s3]) + 1
			rd._match_records[ri]["pitch_revealed"] = true
		rd._clear_deduction_caches()
		var steps2_list: Array = _name_steps(rd._hint_name_steps(g.chosen_form_clues, rsolver))
		steps2 += steps2_list.size()
		for st2 in steps2_list:
			cells2 += (st2["eliminated_stars"] as Array).size()
			if bool(st2["resolved"]):
				resolved2 += 1
		lies2 += _count_lies(steps2_list)
		print("    %2d stars named, placed and heard: %d name steps" % [int(k2), steps2_list.size()])
	rd._load_match_records([])
	rd._clear_deduction_caches()
	print("    %d steps, %d eliminated cells, %d resolutions checked against truth" % [steps2, cells2, resolved2])
	ok(steps2 > 3 and cells2 > 10, "the record-driven sweep judged enough to mean something (%d steps, %d cells)" % [steps2, cells2])
	ok(lies2 == 0, "with real position and pitch knowledge, no eliminated star is a name's true star and no resolution is wrong (%d lies)" % lies2)

	var fake: Array = [{"axis": "name", "star": 2, "eliminated_stars": [2], "resolved_star": 5}]
	ok(_count_lies(fake) == 2, "control: the lie counter catches a true star eliminated and a wrong resolution")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
