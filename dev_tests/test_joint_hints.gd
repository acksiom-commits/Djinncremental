extends "res://dev_tests/test_base.gd"
# Joint Name x Position hints: Equality Pair ("X and Y have the same colour")
# and Mutual Exclusion ("X, Y and Z all have different pitches").
#
# These clues relate two or more descriptors -- a Name, "the star that fires
# 9th", or a given "the star that plays E5" -- through a colour or pitch the
# clue never names. A NAME row and a POSITION row are different alldiff
# structures that meet only in the star both land on, so the hints propagate
# across both grids and link a row of one to a row of the other.
#
# THE LEAK THIS REPLACED. Those Forms also attach companion Name facts
# (name_group, name_group_neg, ...) whose group value is the TRUE colour or
# pitch of the star the other participant denotes. For "Alpha and the star that
# fires 9th have the same colour" the Name hints announced "Alpha must be a blue
# star" -- the 9th star's colour, which the player cannot know. Measured before
# the fix: 24 of 25 Equality/Mutex clues over 6 puzzles built a hint from a
# companion. The hints now read the clue's own participants and never the
# companions.
#
# What must hold, and why each case exists:
#  - The companion facts are NOT consumed (regression for the leak), on a fixture
#    built to carry one AND on every Equality/Mutex clue of real puzzles.
#  - With the player's own knowledge the pair does real work: a placed star
#    resolves the other participant, across the Name and Position grids.
#  - A given participant ("the star that plays E5") only counts what the player
#    has heard.
#  - SOUNDNESS against ground truth on real puzzles across constellations, on
#    both grids, with a positive control.

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


func _mine(steps: Array, axis: String, row: int) -> Array:
	return steps.filter(func(st): return str(st["axis"]) == axis and int(st["star"]) == row)


## Claims contradicting ground truth. name n's true star is n; the star that
## really fires r-th is true_star_by_rank[r].
func _count_lies(steps: Array, true_star_by_rank: Array) -> int:
	var lies: int = 0
	for st in steps:
		var truth: int = int(st["star"]) if str(st["axis"]) == "name" else int(true_star_by_rank[int(st["star"])])
		for s in st["eliminated_stars"]:
			if int(s) == truth:
				lies += 1
		if int(st["resolved_star"]) >= 0 and int(st["resolved_star"]) != truth:
			lies += 1
	return lies


func _sweep(cd, cid: int, seed: int) -> Dictionary:
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	await g._generate_clues_forms_attempt()
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._cd = cd
	host._constellation_id = cid
	host._star_count = scn
	host._star_names = g.star_names
	host._star_colors = g.star_colors
	host._star_degrees = []
	for _s in scn:
		host._star_degrees.append(0)
	host._sequence_rank_solution = g.sequence_rank_solution
	host._pitch_freqs = cd.get_note_freqs(cid)
	host._star_pitch_index = cd.get_note_assignment(cid)
	host._form_clues_cache = g.chosen_form_clues
	host._rebuild_star_distances()
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var solver = PuzzleScript.new()
	solver.star_count = scn
	var by_rank: Array = []
	by_rank.resize(scn)
	for s0 in scn:
		by_rank[int(g.sequence_rank_solution[s0])] = s0
	d._load_match_records([])
	d._clear_deduction_caches()
	var values_clues: int = 0
	var companions_read: int = 0
	var readable: int = 0
	for clue in g.chosen_form_clues:
		if d._clue_has_values_fact(clue):
			values_clues += 1
			if not d._name_constraints_for_clue(clue).is_empty():
				companions_read += 1
			if not d._joint_constraints_for_clue(clue).is_empty():
				readable += 1
	var steps: int = 0
	var cells: int = 0
	var resolved: int = 0
	var lies: int = 0
	var on_position: int = 0
	var seq_entries: int = 0
	var seq_pos_named: int = 0
	for frac in [0.0, 0.2, 0.5, 0.75]:
		var known: int = int(round(float(scn) * float(frac)))
		d._load_match_records([])
		for s in known:
			var ri: int = d._get_or_create_match_record_for_star_idx(s)
			d._match_records[ri]["name"] = str(g.star_names[s])
			d._match_records[ri]["name_states"] = {str(g.star_names[s]): 1}
			d._match_records[ri]["seq_lo"] = int(g.sequence_rank_solution[s]) + 1
			d._match_records[ri]["seq_hi"] = int(g.sequence_rank_solution[s]) + 1
			d._match_records[ri]["pitch_revealed"] = true
		d._clear_deduction_caches()
		var found: Array = d._hint_joint_steps(g.chosen_form_clues, solver)
		steps += found.size()
		for st in found:
			cells += (st["eliminated_stars"] as Array).size()
			if bool(st["resolved"]):
				resolved += 1
			if str(st["axis"]) == "position":
				on_position += 1
		lies += _count_lies(found, by_rank)
		for st2 in d.hint_next_steps(g.chosen_form_clues):
			if str(st2["axis"]) == "sequence":
				seq_entries += 1
				if str(st2["descriptor"]).begins_with("the star that fires"):
					seq_pos_named += 1
	d._load_match_records([])
	host.queue_free()
	return {"clues": g.chosen_form_clues.size(), "values_clues": values_clues, "companions_read": companions_read,
		"readable": readable, "steps": steps, "cells": cells, "resolved": resolved, "lies": lies, "on_position": on_position,
		"seq_entries": seq_entries, "seq_pos_named": seq_pos_named}


func run() -> void:
	print("=== the pure joint finder ===")
	var solver = PuzzleScript.new()
	solver.star_count = 6
	var gof: Array = [0, 0, 1, 1, 2, 2]
	# Name row 0 and rank row 2 must share a colour; the rank row is pinned to star 4.
	var name_grid: Array = _blank_grid(6)
	var rank_grid: Array = _blank_grid(6)
	for c in 6:
		rank_grid[2][c] = (c == 4)
	var pair: Dictionary = {"grid": "name", "row": 0, "same": true, "group_of": gof, "other_grid": "rank", "other_row": 2}
	var res: Dictionary = Finder.step_for_joint(solver, {"name": name_grid, "rank": rank_grid}, [pair])
	ok(bool(res["consistent"]) and [["name", 0, 5]] == (res["resolved"] as Array),
		"a name that shares a colour with a star pinned to star 4 (colour 2) can only be star 5 (got %s)" % str(res["resolved"]))
	var pair_diff: Dictionary = pair.duplicate()
	pair_diff["same"] = false
	var res_d: Dictionary = Finder.step_for_joint(solver, {"name": _blank_grid(6), "rank": rank_grid}, [pair_diff])
	ok((res_d["eliminated"] as Array) == [["name", 0, 5]], "...and 'different colour' rules out star 5 (got %s)" % str(res_d["eliminated"]))
	var wild: Array = [-1, -1, -1, -1, -1, -1]
	pair["group_of"] = wild
	var res_w: Dictionary = Finder.step_for_joint(solver, {"name": _blank_grid(6), "rank": rank_grid}, [pair])
	ok(bool(res_w["consistent"]) and (res_w["eliminated"] as Array).is_empty() and (res_w["resolved"] as Array).is_empty(),
		"an unknown group is a wildcard, so nothing is ruled out or resolved from it (got %s / %s)" % [str(res_w["eliminated"]), str(res_w["resolved"])])
	var fixed: Dictionary = {"grid": "name", "row": 0, "same": true, "group_of": gof, "other_fixed": [4]}
	var res_f: Dictionary = Finder.step_for_joint(solver, {"name": _blank_grid(6), "rank": _blank_grid(6)}, [fixed])
	ok([["name", 0, 5]] == (res_f["resolved"] as Array), "a given participant works the same way (got %s)" % str(res_f["resolved"]))

	print("\n=== fixture: the leak, and the joint step with the player's own knowledge ===")
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
	var NAME: int = PuzzleScript.Category.NAME
	var SEQ: int = PuzzleScript.Category.SEQUENCE
	var COLOR: int = PuzzleScript.Category.COLOR
	var PITCH: int = PuzzleScript.Category.PITCH

	# "Alpha and the star that fires 3rd have the same colour." In this fixture the
	# 3rd star is star 1 (colour 0, Alpha's own colour, so the clue is TRUE). The
	# companion fact a generator attaches names that colour -- exactly what must
	# never reach the player.
	host._sequence_rank_solution = [0, 2, 1, 3, 4, 5]
	var seq_clue: Dictionary = {"text": "Alpha and the star that fires 3rd note have the same color.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": COLOR, "star_b": 2, "is_true": false}],
		"search_terms": ["N:Alpha", "S:3", "C:" + str(host.COLOR_NAME_LABELS[1])],
		"disclosures": [{"kind": "values_same", "cat": COLOR, "a": 0, "b": 1},
			{"kind": "name_group", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"chars": [{"cat": NAME, "star": 0}, {"cat": SEQ, "star": 1}, {"cat": COLOR, "star": 0}, {"cat": COLOR, "star": 1}],
		"characteristics": [], "form_id": 12}
	d._load_match_records([])
	d._clear_deduction_caches()
	ok(d.clue_indices_with_something_to_give([seq_clue]) == [0], "the Name-and-Position clue IS offered as unrecorded, so what follows is not vacuous")
	ok(d._name_constraints_for_clue(seq_clue).is_empty(),
		"LEAK REGRESSION: the companion name_group (the 3rd star's TRUE colour) is not consumed")
	var blank_steps: Array = d.hint_next_steps([seq_clue])
	ok(blank_steps.is_empty(), "blank board: nothing is ruled out, and nothing about a colour is announced (got %s)" % str(blank_steps))

	# The player has identified Beta as star 1 and placed it 3rd.
	var eos: int = d._get_or_create_match_record_for_star_idx(1)
	d._match_records[eos]["name"] = "Beta"
	d._match_records[eos]["name_states"] = {"Beta": 1}
	d._match_records[eos]["seq_lo"] = 3
	d._match_records[eos]["seq_hi"] = 3
	d._clear_deduction_caches()
	var s_pair: Array = _mine(d.hint_next_steps([seq_clue]), "name", 0)
	ok(s_pair.size() == 1 and int(s_pair[0]["resolved_star"]) == 0,
		"with Beta placed 3rd, 'Alpha shares its colour with the 3rd star' leaves Alpha only its own colour's other star, star 0 (got %s)" % str(s_pair))
	ok(not s_pair.is_empty() and str(s_pair[0]["phrase"]).contains("the star that fires 3rd note"),
		"and the sentence names the participant only as the clue does (\"%s\")" % (str(s_pair[0]["phrase"]) if not s_pair.is_empty() else ""))

	# Mutual Exclusion: Alpha and the 3rd star differ in colour. Truthful here: the
	# 3rd star is star 2 (colour 1), Alpha is colour 0. The player places Gamma there.
	d._load_match_records([])
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	var gamma: int = d._get_or_create_match_record_for_star_idx(2)
	d._match_records[gamma]["name"] = "Gamma"
	d._match_records[gamma]["name_states"] = {"Gamma": 1}
	d._match_records[gamma]["seq_lo"] = 3
	d._match_records[gamma]["seq_hi"] = 3
	d._clear_deduction_caches()
	var diff_clue: Dictionary = seq_clue.duplicate(true)
	diff_clue["text"] = "Alpha and the star that fires 3rd note all have different colors."
	diff_clue["cells"] = [{"cat_a": NAME, "star_a": 0, "cat_b": COLOR, "star_b": 4, "is_true": false}]
	diff_clue["search_terms"] = ["N:Alpha", "S:3", "C:" + str(host.COLOR_NAME_LABELS[2])]
	diff_clue["disclosures"] = [{"kind": "values_all_different", "cat": COLOR, "stars": [0, 2]},
		{"kind": "name_group_neg", "name_star": 0, "cat": COLOR, "group_key": 1}]
	diff_clue["chars"] = [{"cat": NAME, "star": 0}, {"cat": COLOR, "star": 0}, {"cat": SEQ, "star": 2}, {"cat": COLOR, "star": 2}]
	ok(d.clue_indices_with_something_to_give([diff_clue]) == [0], "the Mutual Exclusion clue IS offered as unrecorded")
	ok(d._name_constraints_for_clue(diff_clue).is_empty(), "LEAK REGRESSION: the negated companion is not consumed either")
	var s_diff: Array = _mine(d.hint_next_steps([diff_clue]), "name", 0)
	ok(s_diff.size() == 1 and (s_diff[0]["eliminated_stars"] as Array) == [3] and not bool(s_diff[0]["positive"]),
		"'differ in colour' rules Alpha out of star 3, the other star sharing the 3rd star's colour (got %s)" % str(s_diff))
	d._load_match_records([])
	d._clear_deduction_caches()

	# A given participant: "Alpha and the star that plays <star 1's note> share a colour"
	# (star 1 is colour 0, Alpha's own colour, so the clue is TRUE).
	var given_clue: Dictionary = {"text": "Alpha and the star that plays that note have the same color.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": PITCH, "star_b": 1, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(PITCH, 1)],
		"disclosures": [{"kind": "values_same", "cat": COLOR, "a": 0, "b": 1}],
		"chars": [{"cat": NAME, "star": 0}, {"cat": PITCH, "star": 1}, {"cat": COLOR, "star": 0}, {"cat": COLOR, "star": 1}],
		"characteristics": [], "form_id": 12}
	ok(d.clue_indices_with_something_to_give([given_clue]) == [0], "the given-participant clue IS offered as unrecorded")
	ok(_mine(d.hint_next_steps([given_clue]), "name", 0).is_empty(),
		"LEAK GUARD: before any star is Listened to, a pitch-named participant could be any star, so nothing is ruled out")
	for s in 6:
		var rec: int = d._get_or_create_match_record_for_star_idx(s)
		d._match_records[rec]["pitch_revealed"] = true
	d._clear_deduction_caches()
	var s_given: Array = _mine(d.hint_next_steps([given_clue]), "name", 0)
	ok(s_given.size() == 1 and int(s_given[0]["resolved_star"]) == 0,
		"...and once every pitch has been heard the participant is star 1, so Alpha can only be star 0 (got %s)" % str(s_given))
	d._load_match_records([])
	d._clear_deduction_caches()

	print("\n=== real puzzles: companions never read, and soundness on both grids ===")
	var cd = load("res://constellation_data.gd").new()
	var totals := {"values_clues": 0, "companions_read": 0, "readable": 0, "steps": 0, "cells": 0, "resolved": 0, "lies": 0, "on_position": 0, "seq_entries": 0, "seq_pos_named": 0}
	for run_def in [[0, 12], [0, 13], [2, 11], [3, 11], [4, 11], [5, 11]]:
		var sw: Dictionary = await _sweep(cd, int(run_def[0]), int(run_def[1]))
		for k in totals:
			totals[k] = int(totals[k]) + int(sw[k])
		print("    c%d s%d: %d Equality/Mutex clues, %d readable; %d steps (%d on the position grid), %d cells, %d resolutions, %d lies" % [
			int(run_def[0]), int(run_def[1]), sw["values_clues"], sw["readable"], sw["steps"], sw["on_position"], sw["cells"], sw["resolved"], sw["lies"]])
	print("    total: %s" % str(totals))
	ok(int(totals["values_clues"]) > 10, "the puzzles carry Equality/Mutex clues to judge (%d)" % int(totals["values_clues"]))
	ok(int(totals["companions_read"]) == 0, "LEAK REGRESSION on real puzzles: no Equality/Mutex clue builds a Name hint from its companion facts (%d of %d did)" % [int(totals["companions_read"]), int(totals["values_clues"])])
	ok(int(totals["steps"]) > 10 and int(totals["cells"]) > 20, "the sweep judged enough to mean something (%d steps, %d cells)" % [int(totals["steps"]), int(totals["cells"])])
	ok(int(totals["seq_entries"]) > 5, "the puzzles produce Sequence steps to judge (%d), so the next check is not vacuous" % int(totals["seq_entries"]))
	ok(int(totals["seq_pos_named"]) == 0, "no Sequence step names a star only by its own position (%d did; 17 of 28 Equality/Mutex ones used to)" % int(totals["seq_pos_named"]))
	ok(int(totals["lies"]) == 0, "no eliminated star is the truth for its row, no resolution is wrong, on either grid (%d lies)" % int(totals["lies"]))
	var fake: Array = [{"axis": "position", "star": 1, "eliminated_stars": [3], "resolved_star": 0}]
	ok(_count_lies(fake, [9, 3, 9, 9, 9, 9]) == 2, "control: the lie counter catches a true star eliminated and a wrong resolution")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
