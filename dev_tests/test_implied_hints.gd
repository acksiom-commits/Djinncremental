extends "res://dev_tests/test_base.gd"
# The "already implied" hint message (tiers 3 and 4).
#
# Measured 2026-09-26: late in a puzzle the player is often stuck on single-clue
# steps (10 of 18 boards at 85-95% known) and combining clues never helps -- the
# clues still waiting are ones whose content the board ALREADY entails, so the
# old "nothing you can act on yet" pointed the player at a deduction that does
# not exist. The player just has not noted them.
#
# What must hold, and why each case exists:
#  - "Already implied" means ENTAILED, not "adds nothing now". A clue that adds
#    nothing because the board is still too empty (a trivial restriction, an
#    unknown group) is "needs more filled in first" and must NOT be called known.
#  - Only clues with something checkable can be entailed; one with nothing
#    checkable is unknown, not known.
#  - The message says so for all-implied and for mixed cases, and keeps the plain
#    message when none is implied.
#  - It is recomputed on every repaint, so it cannot outlive a step appearing.
#  - Consistency on real puzzles: a clue judged entailed never also produces a
#    step (both cannot be true), and the check judged something (denominators).

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _texts(host) -> String:
	var out: Array = []
	for ch in host._markers_content.get_children():
		if ch is Label:
			out.append((ch as Label).text)
	return " ".join(out)


func _repaint(host, w) -> void:
	for c in host._markers_content.get_children():
		c.free()
	w._populate_hint_markers()


func _row(open: Array, n: int) -> Array:
	var row: Array = []
	row.resize(n)
	for s in n:
		row[s] = open.has(s)
	return row


func run() -> void:
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
	var NAME: int = PuzzleScript.Category.NAME
	var COLOR: int = PuzzleScript.Category.COLOR

	print("=== what counts as entailed ===")
	var trivial: Dictionary = {"allowed": [0, 1, 2, 3, 4, 5]}
	ok(not d._row_constraint_entailed(_row([0, 1, 2, 3, 4, 5], 6), trivial),
		"a trivial restriction (every star allowed) is NOT entailed: it says nothing yet")
	ok(d._row_constraint_entailed(_row([0, 1], 6), {"allowed": [0, 1]}), "a row already inside the allowed set IS entailed")
	ok(not d._row_constraint_entailed(_row([0, 1, 4], 6), {"allowed": [0, 1]}), "a row that still has a star outside it is not entailed")
	ok(d._row_constraint_entailed(_row([0, 1], 6), {"excluded": [2, 3]}), "a row with none of the excluded stars left IS entailed")
	ok(not d._row_constraint_entailed(_row([0, 1], 6), {"excluded": [1]}), "...but not while an excluded star is still open")
	ok(not d._row_constraint_entailed(_row([0, 1], 6), {"excluded": []}), "an empty exclusion says nothing, so it is not entailed")
	ok(not d._row_constraint_entailed(_row([], 6), {"allowed": [0]}), "an empty (contradictory) row is never called known")

	var gof: Array = [0, 0, 1, 1, 2, 2]
	var same_c: Dictionary = {"grid": "name", "row": 0, "same": true, "group_of": gof, "other_grid": "name", "other_row": 1}
	var diff_c: Dictionary = {"grid": "name", "row": 0, "same": false, "group_of": gof, "other_grid": "name", "other_row": 2}
	var grids: Dictionary = {"name": [_row([0, 1], 6), _row([0, 1], 6), _row([2, 3], 6), _row([0, 1, 2, 3, 4, 5], 6), _row([4], 6), _row([5], 6)], "rank": []}
	ok(d._pair_constraint_entailed(same_c, grids), "two names both confined to colour 0 DO share a colour")
	ok(d._pair_constraint_entailed(diff_c, grids), "a name in colour 0 and one in colour 1 DO differ")
	var open_same: Dictionary = same_c.duplicate()
	open_same["other_row"] = 3
	ok(not d._pair_constraint_entailed(open_same, grids), "a partner still open to every colour is not entailed")
	var unknown: Dictionary = same_c.duplicate()
	unknown["group_of"] = [-1, -1, -1, -1, -1, -1]
	ok(not d._pair_constraint_entailed(unknown, grids), "an unknown group is never entailed")

	print("\n=== the breakdown and the Hint tab ===")
	# Alpha is confined to colour 0's stars by what the player has derived.
	var entailed_clue: Dictionary = {"text": "Alpha is a first-colour star.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": COLOR, "star_b": 2, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(COLOR, 2)],
		"disclosures": [{"kind": "name_group", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 2}
	# Gamma and Delta share a colour: nothing narrows either, so it stays "needs more".
	var pair2_clue: Dictionary = {"text": "Gamma and Delta share a colour.",
		"cells": [{"cat_a": NAME, "star_a": 2, "cat_b": COLOR, "star_b": 4, "is_true": false}],
		"search_terms": ["N:Gamma", "N:Delta", d._descriptor_term(COLOR, 4)],
		"disclosures": [{"kind": "values_same", "cat": COLOR, "a": 2, "b": 3}],
		"chars": [{"cat": NAME, "star": 2}, {"cat": NAME, "star": 3}, {"cat": COLOR, "star": 2}, {"cat": COLOR, "star": 3}],
		"characteristics": [], "form_id": 12}
	# Alpha and Beta share a colour, on a board that knows nothing yet.
	var pair_clue: Dictionary = {"text": "Alpha and Beta share a colour.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": COLOR, "star_b": 2, "is_true": false}],
		"search_terms": ["N:Alpha", "N:Beta", d._descriptor_term(COLOR, 2)],
		"disclosures": [{"kind": "values_same", "cat": COLOR, "a": 0, "b": 1}],
		"chars": [{"cat": NAME, "star": 0}, {"cat": NAME, "star": 1}, {"cat": COLOR, "star": 0}, {"cat": COLOR, "star": 1}],
		"characteristics": [], "form_id": 12}

	d._load_match_records([])
	d._derived_descriptor_stars["%d:%d" % [NAME, 0]] = [0, 1]
	d._clear_deduction_caches()
	ok(d.clue_indices_with_something_to_give([entailed_clue]) == [0], "the clue IS offered as unrecorded, so what follows is not vacuous")
	ok(d.hint_next_steps([entailed_clue]).is_empty(), "with Alpha already confined to colour 0 it gives no step")
	var bd: Dictionary = d.hint_waiting_breakdown([entailed_clue])
	ok(int(bd["waiting"]) == 1 and int(bd["entailed"]) == 1, "and it is counted as already implied (got %s)" % str(bd))

	host._form_clues_cache = [entailed_clue]
	w._populate_hint_markers()
	for c0 in host._markers_content.get_children():
		c0.free()
	w._on_hint_tier3_pressed()
	_repaint(host, w)
	var all_msg: String = _texts(host)
	ok(w._hint_state == w.HINT_IMPLIED and all_msg.contains("already say only what you know") and not all_msg.contains("the rest need"),
		"tier 3 says the waiting clues already say only what the player knows (\"%s\")" % all_msg)
	w._on_hint_tier4_pressed()
	ok(w._hint_state == w.HINT_IMPLIED, "tier 4 says the same")

	# It must not outlive its cause: once the derived narrowing is gone the clue
	# gives a step again.
	d._derived_descriptor_stars.clear()
	d._clear_deduction_caches()
	_repaint(host, w)
	ok(w._hint_state == w.HINT_NONE and _texts(host).contains("Something has changed"),
		"when a step appears the message clears itself (\"%s\")" % _texts(host))

	print("\n=== the other outcomes ===")
	d._load_match_records([])
	d._clear_deduction_caches()
	ok(d.clue_indices_with_something_to_give([pair_clue]) == [0], "the pair clue IS offered as unrecorded")
	ok(d.hint_next_steps([pair_clue]).is_empty(), "on an empty board it gives no step")
	var bd_pair: Dictionary = d.hint_waiting_breakdown([pair_clue])
	ok(int(bd_pair["entailed"]) == 0, "and is NOT called implied: it needs more filled in first (got %s)" % str(bd_pair))
	host._form_clues_cache = [pair_clue]
	_repaint(host, w)
	w._on_hint_tier3_pressed()
	_repaint(host, w)
	ok(w._hint_state == w.HINT_NO_STEP and _texts(host).contains("Nothing you can act on yet"),
		"so the plain message is kept (\"%s\")" % _texts(host))

	# A mixed list: one clue implied, one waiting on more.
	d._derived_descriptor_stars["%d:%d" % [NAME, 0]] = [0, 1]
	d._clear_deduction_caches()
	var bd_mix: Dictionary = d.hint_waiting_breakdown([entailed_clue, pair2_clue])
	ok(int(bd_mix["waiting"]) == 2 and int(bd_mix["entailed"]) == 1, "in a mixed list one is implied and one is not (got %s)" % str(bd_mix))
	host._form_clues_cache = [entailed_clue, pair2_clue]
	_repaint(host, w)
	w._on_hint_tier3_pressed()
	_repaint(host, w)
	ok(w._hint_state == w.HINT_IMPLIED and _texts(host).contains("1 of the 2 clues still waiting"),
		"the mixed message says how many (\"%s\")" % _texts(host))
	d._derived_descriptor_stars.clear()
	d._clear_deduction_caches()

	print("\n=== consistency on real puzzles ===")
	var cd = load("res://constellation_data.gd").new()
	var boards: int = 0
	var stuck: int = 0
	var judged_entailed: int = 0
	var contradictions: int = 0
	for run_def in [[0, 12], [2, 11], [3, 11], [5, 11]]:
		var cid: int = int(run_def[0])
		var cdef: Dictionary = cd.get_constellation_def(cid)
		var scn: int = int(cdef["star_count"])
		var g = PuzzleScript.new()
		var sq: Array = []
		for i in range(scn):
			sq.append(i)
		g.setup(scn, cdef["line_pairs"], sq, int(run_def[1]), cid, cdef.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		await g._generate_clues_forms_attempt()
		var rh = OverlayScene.instantiate()
		root.add_child(rh)
		await process_frame
		rh._cd = cd
		rh._constellation_id = cid
		rh._star_count = scn
		rh._star_names = g.star_names
		rh._star_colors = g.star_colors
		rh._star_degrees = []
		for _s in scn:
			rh._star_degrees.append(0)
		rh._sequence_rank_solution = g.sequence_rank_solution
		rh._pitch_freqs = cd.get_note_freqs(cid)
		rh._star_pitch_index = cd.get_note_assignment(cid)
		rh._form_clues_cache = g.chosen_form_clues
		rh._rebuild_star_distances()
		rh._widgets.clear_pitch_caches()
		var rd = rh._deduction
		var clues: Array = g.chosen_form_clues
		for frac in [0.0, 0.5, 0.85, 0.95]:
			var known: int = int(round(float(scn) * float(frac)))
			rd._load_match_records([])
			for s2 in known:
				var ri: int = rd._get_or_create_match_record_for_star_idx(s2)
				rd._match_records[ri]["name"] = str(g.star_names[s2])
				rd._match_records[ri]["name_states"] = {str(g.star_names[s2]): 1}
				rd._match_records[ri]["seq_lo"] = int(g.sequence_rank_solution[s2]) + 1
				rd._match_records[ri]["seq_hi"] = int(g.sequence_rank_solution[s2]) + 1
				rd._match_records[ri]["pitch_revealed"] = true
			rd._clear_deduction_caches()
			boards += 1
			var real_grids: Dictionary = rd._closed_boards()
			var stepped: Dictionary = {}
			for st in rd.hint_next_steps(clues):
				stepped[int(st["clue_index"])] = true
			if stepped.is_empty() and not rd.clue_indices_with_something_to_give(clues).is_empty():
				stuck += 1
			for ci in rd.clue_indices_with_something_to_give(clues):
				if rd._clue_entailed(clues[ci], real_grids):
					judged_entailed += 1
					if stepped.has(int(ci)):
						contradictions += 1
		rh.queue_free()
	print("    %d boards, %d with waiting clues but no step, %d clue judgements of 'entailed'" % [boards, stuck, judged_entailed])
	ok(judged_entailed > 5, "the check judged enough clues to mean something (%d), so 'no contradiction' is not vacuous" % judged_entailed)
	ok(contradictions == 0, "no clue judged entailed also produces a step (%d contradictions)" % contradictions)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
