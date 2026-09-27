extends "res://dev_tests/test_base.gd"
# Hint tiers 3 and 4, POSITION descriptors: Colour / Pitch / Name facts about
# "the star that fires 7th".
#
# The Name hints read clues whose subject is a NAME. A clue can just as well be
# about a Sequence descriptor -- "the star that fires 7th is not blue", "the star
# that fires 3rd is Alpha or Beta" -- and there the colour/pitch group says which
# STARS that position cannot be. The player records it by crossing that colour
# off the position's row. These are the Colour and Pitch facts a player deduces.
#
# What must hold, and why each case exists:
#  - A colour group is exact (painted on the map), so it rules out every star of
#    that colour for the position.
#  - A pitch group only rules out stars whose pitch the player has heard, the
#    same gate the Name hints use.
#  - "Alpha or Beta" narrows a position to the stars those names could be on.
#  - The subject is only ever named by the clue's own term (S:<n>), and a clue
#    that does not name the position yields nothing.
#  - SOUNDNESS against ground truth, on real puzzles across constellations with
#    truthful boards: nothing eliminated is the true star of that position, and
#    anything resolved is right. With a positive control.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _position_steps(steps: Array) -> Array:
	var out: Array = []
	for st in steps:
		if str(st["axis"]) == "position":
			out.append(st)
	return out


## Claims that contradict ground truth. `true_star[r]` is the star that really
## fires r-th (0-based).
func _count_lies(steps: Array, true_star: Array) -> int:
	var lies: int = 0
	for st in steps:
		if str(st["axis"]) != "position":
			continue
		var truth: int = int(true_star[int(st["star"])])
		for s in st["eliminated_stars"]:
			if int(s) == truth:
				lies += 1
		if int(st["resolved_star"]) >= 0 and int(st["resolved_star"]) != truth:
			lies += 1
	return lies


func _true_star_by_rank(ranks: Array) -> Array:
	var out: Array = []
	out.resize(ranks.size())
	for s in ranks.size():
		out[int(ranks[s])] = s
	return out


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
	var truth: Array = _true_star_by_rank(g.sequence_rank_solution)
	d._load_match_records([])
	d._clear_deduction_caches()
	var readable: int = 0
	var kinds: Dictionary = {}
	for clue in g.chosen_form_clues:
		var cs: Array = d._position_constraints_for_clue(clue)
		if not cs.is_empty():
			readable += 1
		for disc in (clue.get("disclosures", []) as Array):
			if disc is Dictionary and ["descriptor_not_in_group", "descriptor_either_or"].has(str((disc as Dictionary).get("kind", ""))):
				if not d._position_constraints_for_clue({"search_terms": clue.get("search_terms", []), "disclosures": [disc]}).is_empty():
					kinds[str(disc["kind"])] = int(kinds.get(str(disc["kind"]), 0)) + 1
	var steps: int = 0
	var cells: int = 0
	var resolved: int = 0
	var lies: int = 0
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
		var found: Array = _position_steps(d._hint_position_steps(g.chosen_form_clues, solver))
		steps += found.size()
		for st in found:
			cells += (st["eliminated_stars"] as Array).size()
			if bool(st["resolved"]):
				resolved += 1
		lies += _count_lies(found, truth)
	d._load_match_records([])
	host.queue_free()
	return {"clues": g.chosen_form_clues.size(), "readable": readable, "kinds": kinds, "steps": steps,
		"cells": cells, "resolved": resolved, "lies": lies}


func run() -> void:
	print("=== fixture: colour, pitch and either-or on a position ===")
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
	var SEQ: int = PuzzleScript.Category.SEQUENCE
	var COLOR: int = PuzzleScript.Category.COLOR
	var PITCH: int = PuzzleScript.Category.PITCH
	var NAME: int = PuzzleScript.Category.NAME
	var solver = PuzzleScript.new()
	solver.star_count = 6
	var colour_term: String = d._descriptor_term(COLOR, 0)

	# "The star that fires 3rd is not <colour of stars 0 and 1>."
	var colour_clue: Dictionary = {"text": "The star that fires 3rd is not that colour.",
		"cells": [], "search_terms": ["S:3", colour_term],
		"disclosures": [{"kind": "descriptor_not_in_group", "cat": SEQ, "star": 2, "group_cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 24}
	var pitch_clue: Dictionary = {"text": "The star that fires 3rd is not that pitch.",
		"cells": [], "search_terms": ["S:3"],
		"disclosures": [{"kind": "descriptor_not_in_group", "cat": SEQ, "star": 2, "group_cat": PITCH, "group_key": 4}],
		"characteristics": [], "chars": [], "form_id": 24}
	var either_clue: Dictionary = {"text": "The star that fires 3rd is Alpha or Beta.",
		"cells": [], "search_terms": ["S:3", "N:Alpha", "N:Beta"],
		"disclosures": [{"kind": "descriptor_either_or", "cat_a": SEQ, "star_a": 2, "cat_b": NAME, "s1": 0, "s2": 1}],
		"characteristics": [], "chars": [], "form_id": 15}
	var unnamed_clue: Dictionary = colour_clue.duplicate(true)
	unnamed_clue["search_terms"] = [colour_term]

	d._load_match_records([])
	d._clear_deduction_caches()
	ok(d.clue_indices_with_something_to_give([colour_clue]) == [0], "the colour clue IS offered as unrecorded, so what follows is not vacuous")
	var s_col: Array = _position_steps(d.hint_next_steps([colour_clue]))
	ok(s_col.size() == 1 and s_col[0]["descriptor"] == "the star that fires 3rd note" and (s_col[0]["eliminated_stars"] as Array) == [0, 1] \
			and not bool(s_col[0]["positive"]),
		"a colour group rules out every star of that colour for the position (got %s)" % str(s_col))

	ok(d.clue_indices_with_something_to_give([pitch_clue]) == [0], "the pitch clue IS offered as unrecorded")
	ok(_position_steps(d.hint_next_steps([pitch_clue])).is_empty(),
		"LEAK GUARD: a pitch group rules out nothing before any pitch has been heard")
	var heard: int = d._get_or_create_match_record_for_star_idx(4)
	d._match_records[heard]["pitch_revealed"] = true
	d._clear_deduction_caches()
	var s_pitch: Array = _position_steps(d.hint_next_steps([pitch_clue]))
	ok(s_pitch.size() == 1 and (s_pitch[0]["eliminated_stars"] as Array) == [4],
		"...and once star 4 has been Listened to, it rules out exactly that star (got %s)" % str(s_pitch))
	d._load_match_records([])
	d._clear_deduction_caches()

	ok(d.clue_indices_with_something_to_give([either_clue]) == [0], "the either-or clue IS offered as unrecorded")
	var alpha: int = d._get_or_create_match_record_for_star_idx(0)
	d._match_records[alpha]["name"] = "Alpha"
	d._match_records[alpha]["name_states"] = {"Alpha": 1}
	var beta: int = d._get_or_create_match_record_for_star_idx(1)
	d._match_records[beta]["name"] = "Beta"
	d._match_records[beta]["name_states"] = {"Beta": 1}
	d._clear_deduction_caches()
	var s_or: Array = _position_steps(d.hint_next_steps([either_clue]))
	ok(s_or.size() == 1 and (s_or[0]["eliminated_stars"] as Array) == [2, 3, 4, 5] and bool(s_or[0]["positive"]),
		"with Alpha and Beta placed on stars 0 and 1, 'Alpha or Beta' leaves the position only those (got %s)" % str(s_or))
	d._load_match_records([])
	d._clear_deduction_caches()

	ok(d._position_constraints_for_clue(unnamed_clue).is_empty(),
		"a clue whose text does not name the position yields nothing about it")

	var sentence: String = w._step_sentence({"axis": "position", "descriptor": "the star that fires 3rd",
		"resolved_star": -1, "eliminated_stars": [0, 1], "phrase": "a blue star", "positive": false})
	ok(sentence == "With what you know, The star that fires 3rd cannot be a blue star, which rules out 2 stars.",
		"the position sentence reads correctly (\"%s\")" % sentence)

	print("\n=== SOUNDNESS on real puzzles, truthful boards, against ground truth ===")
	var cd = load("res://constellation_data.gd").new()
	var total_steps: int = 0
	var total_cells: int = 0
	var total_lies: int = 0
	var all_kinds: Dictionary = {}
	for run_def in [[0, 12], [2, 11], [3, 11], [5, 11]]:
		var sw: Dictionary = await _sweep(cd, int(run_def[0]), int(run_def[1]))
		total_steps += int(sw["steps"])
		total_cells += int(sw["cells"])
		total_lies += int(sw["lies"])
		for kk in sw["kinds"]:
			all_kinds[kk] = int(all_kinds.get(kk, 0)) + int(sw["kinds"][kk])
		print("    c%d s%d: %d of %d clues readable %s; %d steps, %d cells, %d resolutions, %d lies" % [
			int(run_def[0]), int(run_def[1]), sw["readable"], sw["clues"], str(sw["kinds"]), sw["steps"], sw["cells"], sw["resolved"], sw["lies"]])
	print("    total: %d steps, %d eliminated cells, kinds %s" % [total_steps, total_cells, str(all_kinds)])
	ok(total_steps > 5 and total_cells > 15, "the sweep judged enough to mean something (%d steps, %d cells)" % [total_steps, total_cells])
	ok(all_kinds.has("descriptor_not_in_group"), "the puzzles carry position-subject group clues, so the group path was exercised")
	ok(total_lies == 0, "no eliminated star is the true star of its position, no resolution is wrong (%d lies)" % total_lies)
	var fake: Array = [{"axis": "position", "star": 2, "eliminated_stars": [4], "resolved_star": 5}]
	ok(_count_lies(fake, [0, 1, 4, 3, 2, 5]) == 2, "control: the lie counter catches a true star eliminated and a wrong resolution")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
