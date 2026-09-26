extends "res://dev_tests/test_base.gd"
# Hint tiers 3 and 4: the next-step finder (Sequence axis).
#
#   tier 3  "what does it bear on?"   which clue is actionable NOW, and the one
#                                     thing it bears on -- no conclusion
#   tier 4  "show me the step"        the conclusion, spelled out
#
# What must hold, and why each case exists:
#  - A step is only offered when the clue, ON TOP OF THE PLAYER'S OWN BOARD,
#    rules out something the board still allows -- unlike tier 2, which only
#    says a clue has unrecorded content.
#  - The same clue is a different step (or none) as the board changes: a
#    relational clue gives a small step on a blank board and a full
#    resolution once its partner star is known.
#  - SOUNDNESS against ground truth, on a REAL puzzle, with partly-solved
#    boards: nothing the finder eliminates is ever the star's true rank, and
#    anything it resolves matches the truth. This is the check that would catch
#    a hint that lies; it is the whole reason to distrust "it looked right".
#  - A contradiction between board and clue is never turned into a hint.
#  - Text only ever names a star through what the CLUE itself already says.
#  - Nothing actionable -> a plain message, not an invented step.

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


## How many claims in a finder result contradict ground truth: an eliminated
## cell that is the star's TRUE rank, or a resolution to a wrong rank.
func _count_lies(res: Dictionary, truth: Array) -> int:
	var n: int = 0
	for cell in res["eliminated"]:
		if int(truth[int(cell[0])]) == int(cell[1]):
			n += 1
	for cell2 in res["resolved"]:
		if int(truth[int(cell2[0])]) != int(cell2[1]):
			n += 1
	return n


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


func run() -> void:
	print("=== the pure finder ===")
	var solver = PuzzleScript.new()
	solver.star_count = 6
	var exact: Array = [{"kind": "ordinal_exact", "s": 0, "r": 3}]
	var blank: Dictionary = Finder.step_for_facts(solver, _blank_grid(6), exact)
	ok(bool(blank["consistent"]), "an exact-rank clue on a blank board is consistent")
	ok((blank["resolved"] as Array).size() == 1 and blank["resolved"][0] == [0, 3],
		"it pins star 0 to rank 3 (got %s)" % str(blank["resolved"]))
	# 5 other ranks for star 0, plus rank 3 for each of the 5 other stars.
	ok((blank["eliminated"] as Array).size() == 10, "and rules out 5 ranks for it and rank 3 for the other 5 stars (got %d)" % (blank["eliminated"] as Array).size())

	var cmp_fact: Array = [{"kind": "ordinal_cmp", "a": 0, "b": 1, "a_gt_b": false}]
	var cmp_blank: Dictionary = Finder.step_for_facts(solver, _blank_grid(6), cmp_fact)
	ok((cmp_blank["resolved"] as Array).is_empty() and (cmp_blank["eliminated"] as Array).size() == 2,
		"'a before b' on a blank board only trims the ends (elim %s, resolved %s)" % [str(cmp_blank["eliminated"]), str(cmp_blank["resolved"])])
	var known_a: Array = _blank_grid(6)
	for r in 6:
		known_a[0][r] = (r == 4)
	var cmp_known: Dictionary = Finder.step_for_facts(solver, known_a, cmp_fact)
	ok((cmp_known["resolved"] as Array) == [[1, 5]],
		"once star 0 is known at rank 4, the same clue resolves star 1 to rank 5 (got %s)" % str(cmp_known["resolved"]))

	var contradiction: Array = _blank_grid(6)
	for r in 6:
		contradiction[0][r] = (r == 0)
	var bad: Dictionary = Finder.step_for_facts(solver, contradiction, exact)
	ok(not bool(bad["consistent"]) and (bad["eliminated"] as Array).is_empty(),
		"a clue that contradicts the board is never turned into a step")
	var noop: Dictionary = Finder.step_for_facts(solver, _blank_grid(6), [])
	ok(not bool(noop["consistent"]) and (noop["eliminated"] as Array).is_empty(), "no Sequence facts -> no step")

	print("\n=== through the deduction engine and the Hint tab ===")
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

	var exact_clue: Dictionary = {"text": "Alpha fires 4th note.", "cells": [], "search_terms": ["N:Alpha"],
		"disclosures": exact, "characteristics": [], "chars": [], "form_id": 1}
	var cmp_clue: Dictionary = {"text": "Alpha fires before Beta.", "cells": [], "search_terms": ["N:Alpha", "N:Beta"],
		"disclosures": cmp_fact, "characteristics": [], "chars": [], "form_id": 5}
	# Names a star only through a descriptor the clue does NOT list: nothing to say.
	var mute_clue: Dictionary = {"text": "Somebody fires before somebody.", "cells": [], "search_terms": [],
		"disclosures": cmp_fact, "characteristics": [], "chars": [], "form_id": 5}

	d._load_match_records([])
	d._clear_deduction_caches()
	var steps: Array[Dictionary] = d.hint_next_steps([exact_clue])
	ok(steps.size() == 1 and steps[0]["descriptor"] == "Alpha" and steps[0]["resolved_rank"] == 3,
		"blank board: the exact clue is a step on Alpha, resolving rank 3 (got %s)" % str(steps))
	ok(d.hint_next_steps([mute_clue]).is_empty(),
		"a clue that names no star in its own text yields no step, so nothing can be named from ground truth")

	var ranked: Array[Dictionary] = d.hint_next_steps([cmp_clue, exact_clue])
	ok(ranked.size() >= 2 and ranked[0]["clue_index"] == 1,
		"the step that pins a star ranks ahead of one that only trims (first is clue %d)" % (ranked[0]["clue_index"] if not ranked.is_empty() else -1))

	host._form_clues_cache = [exact_clue]
	w._populate_hint_markers()
	for c0 in host._markers_content.get_children():
		c0.free()

	w._on_hint_tier3_pressed()
	ok(w._hint_state == w.HINT_DESCRIPTOR, "tier 3 finds an actionable step")
	_repaint(host, w)
	var t3: String = " ".join(_hint_texts(host))
	ok(t3.contains("Alpha") and not t3.contains("must fire") and not t3.contains("cannot fire"),
		"tier 3 names what it bears on and gives NO conclusion (\"%s\")" % t3)

	w._on_hint_tier4_pressed()
	_repaint(host, w)
	var t4: String = " ".join(_hint_texts(host))
	ok(w._hint_state == w.HINT_STEP and t4.contains("Alpha must fire 4th"),
		"tier 4 spells the step out (\"%s\")" % t4)

	# The player records the conclusion: the step is spent and must vanish.
	var slot: int = d._get_or_create_match_record_for_seq(4)
	d._match_records[slot]["name_states"] = {"Alpha": 1}
	d._clear_deduction_caches()
	_repaint(host, w)
	ok(w._hint_state == w.HINT_NONE and _hint_texts(host).any(func(t): return t.contains("no longer available")),
		"once the player has recorded it, the step is withdrawn rather than shown stale")
	w._on_hint_tier3_pressed()
	ok(w._hint_state == w.HINT_NO_STEP, "and with nothing actionable, tier 3 says so instead of inventing a step")
	w._on_hint_tier4_pressed()
	ok(w._hint_state == w.HINT_NO_STEP, "tier 4 likewise")

	print("\n=== SOUNDNESS on a real puzzle, partly-solved boards, against ground truth ===")
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
	var truth: Array = g.sequence_rank_solution
	var judged_clues: int = 0
	var clues_with_steps: int = 0
	var cells_checked: int = 0
	var resolved_checked: int = 0
	var lies: int = 0
	# Positive control: the lie counter must FIRE on a result that is wrong.
	var fake: Dictionary = {"eliminated": [[0, int(truth[0])]], "resolved": [[1, (int(truth[1]) + 1) % scn]]}
	ok(_count_lies(fake, truth) == 2, "control: the lie counter catches a true cell eliminated and a wrong resolution")
	var seed_known_counts: Array = [0, 3, 7, 11]
	for k in seed_known_counts:
		var grid: Array = _blank_grid(scn)
		for s in mini(int(k), scn):
			for r in scn:
				grid[s][r] = (r == int(truth[s]))
		var with_steps_here: int = 0
		for clue in g.chosen_form_clues:
			var facts: Array = []
			for f in (clue.get("disclosures", []) as Array):
				if f is Dictionary and not PuzzleScript.VALUE_FACT_KINDS.has(str((f as Dictionary).get("kind", ""))):
					facts.append(f)
			if facts.is_empty():
				continue
			judged_clues += 1
			var res: Dictionary = Finder.step_for_facts(g, grid, facts)
			if not bool(res["consistent"]):
				# A sound board plus a TRUE clue can never contradict.
				lies += 1
				continue
			if not (res["eliminated"] as Array).is_empty():
				clues_with_steps += 1
				with_steps_here += 1
			cells_checked += (res["eliminated"] as Array).size()
			resolved_checked += (res["resolved"] as Array).size()
			lies += _count_lies(res, truth)
		print("    board with %2d stars known: %d of %d Sequence-bearing clues give a step" % [int(k), with_steps_here, g.chosen_form_clues.size()])
	print("    judged %d clue/board pairs, %d gave a step, %d eliminated cells and %d resolutions checked against truth" % [judged_clues, clues_with_steps, cells_checked, resolved_checked])
	ok(judged_clues > 40 and clues_with_steps > 10 and cells_checked > 50,
		"the sweep judged enough to mean something (%d pairs, %d with a step, %d cells)" % [judged_clues, clues_with_steps, cells_checked])
	ok(lies == 0, "no eliminated cell is a true rank, no resolution is wrong, no true clue contradicts a sound board (%d lies)" % lies)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
