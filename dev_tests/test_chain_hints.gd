extends "res://dev_tests/test_base.gd"
# Hint tier 5, "walk me through every step" (2026-09-27 user report: tier 4
# alone isn't explicit enough).
#
# Tier 4 stops at the single best step. This applies hint_next_steps' best
# step to a WORKING COPY of the boards (never the real records), re-derives,
# and repeats -- automating what a player would get by pressing tier 4 over
# and over -- returning the whole reachable chain in order.
#
# What must hold, and why each case exists:
#  - The chain is STRICTLY MORE than a single tier-4 press: a fixture where
#    step 1 unlocks step 2 (step 2 is not resolvable from a single
#    hint_next_steps() call on the blank board) proves the chaining, not just
#    the underlying per-step soundness already covered elsewhere.
#  - SOUNDNESS against ground truth on real puzzles, across board-fill levels
#    -- 0 lies, with a positive control.
#  - It shares tiers 3/4's Listen interrupt and "already implied" outcomes
#    (both already exhaustively tested elsewhere; one assertion each here is
#    enough to confirm tier 5 actually routes into them, not re-derive them).
#  - PERFORMANCE: measured 2026-09-27, an early-game chain on an 18-star board
#    cost ~5s to compute once (~70 steps x ~70-90ms). The result is cached and
#    invalidated only by a real board change -- a second call must not repeat
#    that cost, checked via a computation counter rather than wall-clock time.
#  - The Hint tab shows a loading message before the (possibly slow) chain
#    computation, and every step's clue + sentence afterward.

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


## Claims contradicting ground truth, over a Sequence-only chain.
func _count_lies(chain: Array, true_star_by_rank: Array, sequence_rank_solution: Array) -> int:
	var lies: int = 0
	for st in chain:
		var truth: int
		match str(st["axis"]):
			"sequence":
				truth = int(sequence_rank_solution[int(st["star"])])
			"name":
				truth = int(st["star"])
			"position":
				truth = int(true_star_by_rank[int(st["star"])])
		var elim: Array = st["eliminated_ranks"] if st.has("eliminated_ranks") else st["eliminated_stars"]
		for e in elim:
			if int(e) == truth:
				lies += 1
		var res: int = int(st.get("resolved_rank", st.get("resolved_star", -1)))
		if res >= 0 and res != truth:
			lies += 1
	return lies


func run() -> void:
	print("=== the chain is more than one tier-4 press ===")
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

	# A pins Alpha to the 5th position; B alone only trims the ends on a blank
	# board, but once A has landed, B forces Beta to the ONE remaining rank
	# after it -- the exact math already validated in test_next_step_hints.gd's
	# "once star 0 is known at rank 4, the same clue resolves star 1 to rank 5".
	var clue_a: Dictionary = {"text": "Alpha fires 5th note.", "cells": [], "search_terms": ["N:Alpha"],
		"disclosures": [{"kind": "ordinal_exact", "s": 0, "r": 4}], "characteristics": [], "chars": [], "form_id": 1}
	var clue_b: Dictionary = {"text": "Alpha fires before Beta.", "cells": [], "search_terms": ["N:Alpha", "N:Beta"],
		"disclosures": [{"kind": "ordinal_cmp", "a": 0, "b": 1, "a_gt_b": false}], "characteristics": [], "chars": [], "form_id": 5}
	d._load_match_records([])
	d._clear_deduction_caches()

	var single: Array[Dictionary] = d.hint_next_steps([clue_a, clue_b])
	var b_alone: Array = single.filter(func(st): return int(st["clue_index"]) == 1)
	var b_resolves_anything: bool = b_alone.any(func(st): return bool(st["resolved"]))
	ok(not b_alone.is_empty() and not b_resolves_anything,
		"a single hint_next_steps() call: B only trims both ends, it does not resolve Beta yet (got %s)" % str(b_alone))

	ok(d.hint_chain_computations == 0, "no chain computed yet")
	var chain: Array[Dictionary] = d.hint_full_chain([clue_a, clue_b])
	ok(d.hint_chain_computations == 1, "one real computation")
	ok(chain.size() == 2, "the chain has exactly 2 steps (got %d)" % chain.size())
	ok(chain[0]["clue_index"] == 0 and int(chain[0]["resolved_rank"]) == 4,
		"step 1 is clue A, pinning Alpha to the 5th position (got %s)" % str(chain[0]))
	ok(chain[1]["clue_index"] == 1 and int(chain[1]["resolved_rank"]) == 5,
		"step 2 is clue B, NOW resolving Beta to the 6th -- only reachable because step 1 already landed (got %s)" % str(chain[1]))

	print("\n=== caching: a second call is served, invalidated by a real change ===")
	var chain2: Array[Dictionary] = d.hint_full_chain([clue_a, clue_b])
	ok(d.hint_chain_computations == 1, "a second call with nothing changed is served from cache, not recomputed")
	ok(chain == chain2, "and returns the identical result")
	d._clear_deduction_caches()
	d.hint_full_chain([clue_a, clue_b])
	ok(d.hint_chain_computations == 2, "clearing the deduction caches (a real board change) forces a fresh computation")

	print("\n=== the Hint tab ===")
	host._form_clues_cache = [clue_a, clue_b]
	w._populate_hint_markers()
	for c0 in host._markers_content.get_children():
		c0.free()
	await w._on_hint_tier5_pressed()
	ok(w._hint_state == w.HINT_CHAIN, "tier 5 lands on the chain state")
	_repaint(host, w)
	var t: String = _texts(host)
	ok(t.contains("Step 1:") and t.contains("Step 2:") and t.contains("Alpha") and t.contains("Beta") and t.contains("6th"),
		"every step is shown, in order, including the one tier 4 alone would have missed (\"%s\")" % t)

	print("\n=== shared outcomes with tiers 3/4 (already tested there; one check each here) ===")
	d._load_match_records([])
	d._clear_deduction_caches()
	# No pitch fact at all here: never blocked on Listening.
	ok(not d.hint_pitch_blocked([clue_a, clue_b]), "sanity: this fixture has nothing pitch-gated")
	# Reuse the fixture shape from test_listen_interrupt.gd: a pitch fact with no
	# Listened star yet is the one hint_pitch_blocked() case tested at length there.
	var NAME: int = PuzzleScript.Category.NAME
	var PITCH: int = PuzzleScript.Category.PITCH
	var pitch_clue: Dictionary = {"text": "Alpha is not that pitch.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": PITCH, "star_b": 3, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(PITCH, 3)],
		"disclosures": [{"kind": "name_group_neg", "name_star": 0, "cat": PITCH, "group_key": 3}],
		"characteristics": [], "chars": [], "form_id": 2}
	host._form_clues_cache = [pitch_clue]
	_repaint(host, w)
	await w._on_hint_tier5_pressed()
	ok(w._hint_state == w.HINT_LISTEN, "tier 5 shares tier 3/4's Listen interrupt")
	d._load_match_records([])
	d._clear_deduction_caches()

	# Alpha already confined to colour 0 via a derived narrowing, same fixture
	# shape as test_implied_hints.gd -- no step, but already implied.
	var COLOR: int = PuzzleScript.Category.COLOR
	var entailed_clue: Dictionary = {"text": "Alpha is a first-colour star.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": COLOR, "star_b": 2, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(COLOR, 2)],
		"disclosures": [{"kind": "name_group", "name_star": 0, "cat": COLOR, "group_key": 0}],
		"characteristics": [], "chars": [], "form_id": 2}
	d._derived_descriptor_stars["%d:%d" % [NAME, 0]] = [0, 1]
	d._clear_deduction_caches()
	host._form_clues_cache = [entailed_clue]
	_repaint(host, w)
	await w._on_hint_tier5_pressed()
	ok(w._hint_state == w.HINT_IMPLIED, "tier 5 shares tier 3/4's 'already implied' outcome")
	d._derived_descriptor_stars.clear()
	d._load_match_records([])
	d._clear_deduction_caches()

	print("\n=== the cost hook ===")
	ok(w._hint_cost(5) == 0, "tier 5 is free by default")

	print("\n=== SOUNDNESS on real puzzles, across board-fill levels ===")
	var cd = load("res://constellation_data.gd").new()
	var total_len: int = 0
	var total_lies: int = 0
	var boards_judged: int = 0
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
		var by_rank: Array = []
		by_rank.resize(scn)
		for s0 in scn:
			by_rank[int(g.sequence_rank_solution[s0])] = s0
		for frac in [0.0, 0.5, 0.85]:
			var known: int = int(round(float(scn) * frac))
			rd._load_match_records([])
			for s in known:
				var ri: int = rd._get_or_create_match_record_for_star_idx(s)
				rd._match_records[ri]["name"] = str(g.star_names[s])
				rd._match_records[ri]["name_states"] = {str(g.star_names[s]): 1}
				rd._match_records[ri]["seq_lo"] = int(g.sequence_rank_solution[s]) + 1
				rd._match_records[ri]["seq_hi"] = int(g.sequence_rank_solution[s]) + 1
				rd._match_records[ri]["pitch_revealed"] = true
			rd._clear_deduction_caches()
			var rchain: Array = rd.hint_full_chain(clues)
			boards_judged += 1
			total_len += rchain.size()
			total_lies += _count_lies(rchain, by_rank, g.sequence_rank_solution)
		rh.queue_free()
	print("    %d boards, %d total chain steps, %d lies" % [boards_judged, total_len, total_lies])
	ok(boards_judged == 12 and total_len > 50, "the sweep judged enough chains to mean something (%d boards, %d steps)" % [boards_judged, total_len])
	ok(total_lies == 0, "no chain step ever eliminates a true value or resolves to a wrong one (%d lies)" % total_lies)
	var fake_chain: Array = [{"axis": "sequence", "star": 2, "eliminated_ranks": [4], "resolved_rank": 0}]
	ok(_count_lies(fake_chain, [], [0, 1, 4, 3, 5, 2]) == 2, "control: the lie counter catches a true rank eliminated and a wrong resolution")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
