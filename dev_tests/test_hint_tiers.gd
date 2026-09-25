extends "res://dev_tests/test_base.gd"
# Hint tiers 1 and 2 (the first phase of the ZebraTutor hint ladder).
#
#   tier 1  is anything waiting?     tier 2  point me to a clue
#
# What must hold, and why each case exists:
#  - A clue "has something to give" exactly while its content is NOT yet on
#    the player's own board, and stops the moment the player records it.
#    A pointer to a spent clue would be a hint that lies.
#  - A clue asserting nothing measurable is never offered.
#  - The pointer never outlives its cause: repainting after the player has
#    used the clue drops it.
#  - Tier 2 reveals the clue ONLY -- no descriptor, no conclusion.
#  - Every hint goes through the ONE cost hook, free by default, and a
#    nonzero price both charges and refuses when unaffordable.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

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
	var NAME: int = PuzzleScript.Category.NAME

	# clue 0: "Neither Alpha nor Beta fires 3rd" -> two negation cells.
	var neg_cells: Array = [
		{"cat_a": NAME, "star_a": 0, "cat_b": SEQ, "star_b": 2, "is_true": false},
		{"cat_a": NAME, "star_a": 1, "cat_b": SEQ, "star_b": 2, "is_true": false},
	]
	# clue 1: asserts nothing scoreable at all.
	var empty_clue: Dictionary = {"text": "Flavour only.", "cells": [], "search_terms": [], "disclosures": [], "characteristics": [], "chars": [], "form_id": 0}
	var neg_clue: Dictionary = {"text": "Neither Alpha nor Beta fires 3rd note.", "cells": neg_cells, "search_terms": [], "disclosures": [], "characteristics": [], "chars": [], "form_id": 0}
	var clues: Array = [neg_clue, empty_clue]

	print("=== the engine query: something-to-give tracks the player's board ===")
	d._load_match_records([])
	var before: Array = d.clue_indices_with_something_to_give(clues)
	ok(before == [0], "an unrecorded clue is offered, an unmeasurable one is not (got %s)" % str(before))

	var slot: int = d._get_or_create_match_record_for_seq(3)
	d._match_records[slot]["name_states"] = {"Alpha": 2, "Beta": 2}
	d._clear_deduction_caches()
	var after: Array = d.clue_indices_with_something_to_give(clues)
	ok(after.is_empty(), "recording the clue's content removes it (got %s)" % str(after))

	print("\n=== tier 1 / tier 2 through the Hint tab ===")
	d._load_match_records([])
	d._clear_deduction_caches()
	host._form_clues_cache = [neg_clue, empty_clue]
	# The buttons only exist once the tab has painted, and that first paint is
	# what binds the hint state to this puzzle -- mirror the real order.
	w._populate_hint_markers()
	for c0 in host._markers_content.get_children():
		c0.free()

	w._on_hint_tier1_pressed()
	ok(w._hint_state == w.HINT_WAITING, "tier 1 says something is waiting while a clue is unrecorded")

	w._on_hint_tier2_pressed()
	# The list is presentation-shuffled, so find the clue by text, not slot 0.
	var neg_idx: int = -1
	var shown: Array[Dictionary] = w._all_final_clues_for_tabs()
	for si in shown.size():
		if shown[si]["text"] == neg_clue["text"]:
			neg_idx = si
	ok(w._hint_state == w.HINT_POINTED and w._hint_clue_index == neg_idx and neg_idx >= 0,
		"tier 2 points at the clue that has something to give (state %d, idx %d, want %d)"
			% [w._hint_state, w._hint_clue_index, neg_idx])

	# Tier 2 reveals the clue only: the Hint tab paints a message and ONE clue
	# row, nothing naming what the clue bears on.
	w._populate_hint_markers()
	var rows: int = 0
	for ch in host._markers_content.get_children():
		if ch is PanelContainer:
			rows += 1
	ok(rows == 1, "the Hint tab shows exactly one clue row, no extra revelation (got %d)" % rows)

	print("\n=== the pointer never outlives its cause ===")
	var slot2: int = d._get_or_create_match_record_for_seq(3)
	d._match_records[slot2]["name_states"] = {"Alpha": 2, "Beta": 2}
	d._clear_deduction_caches()
	for c in host._markers_content.get_children():
		c.free()
	w._populate_hint_markers()
	ok(w._hint_state == w.HINT_NONE and w._hint_clue_index == -1,
		"once the player has used the clue, repainting drops the pointer")

	w._on_hint_tier1_pressed()
	ok(w._hint_state == w.HINT_NOTHING, "tier 1 says nothing is waiting once every clue is reflected")
	w._on_hint_tier2_pressed()
	ok(w._hint_state == w.HINT_NOTHING and w._hint_clue_index == -1,
		"tier 2 with nothing waiting points at nothing rather than inventing a clue")

	print("\n=== a real generated puzzle, empty board ===")
	# Synthetic clues prove the mechanism; a real puzzle proves it survives
	# real disclosures. On a blank board no clue has been recorded, so every
	# MEASURABLE clue must be on offer -- and the denominator is printed so a
	# silent "0 of 0" cannot pass for a check.
	# Its own host, configured from the generated puzzle -- the synthetic
	# 6-star host above would make real 15-star disclosures read out of range.
	var cd = load("res://constellation_data.gd").new()
	var cdef: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 31337, 0, cdef.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g.generate_clues_forms()
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
	var real: Array = g.chosen_form_clues
	var offered: Array = rd.clue_indices_with_something_to_give(real)
	var measurable: int = 0
	for rc in real:
		var f: float = rd._clue_coverage_fraction(rc["cells"], rc["search_terms"], rc["disclosures"])
		if f != rd.COVERAGE_UNMEASURABLE:
			measurable += 1
	print("    clues: %d   measurable: %d   offered: %d" % [real.size(), measurable, offered.size()])
	ok(measurable > 0, "the puzzle has measurable clues to judge (%d) -- otherwise the next check is vacuous" % measurable)
	ok(offered.size() == measurable,
		"on a blank board every measurable clue is offered (%d of %d)" % [offered.size(), measurable])

	print("\n=== the cost hook: free by default, charges and refuses when priced ===")
	ok(w._hint_cost(1) == 0 and w._hint_cost(2) == 0, "both tiers are free by default")
	ok(w._try_pay_hint(1) and w._try_pay_hint(2), "a free hint always passes")

	var gc = root.get_node_or_null("/root/GameContext")
	if gc == null:
		print("  (no GameContext autoload here -- charging path not exercised)")
	else:
		var saved = gc.sparks
		w.hint_cost_sparks = {1: 5, 2: 5}
		gc.sparks = BigNum.from_int(3)
		ok(not w._try_pay_hint(1), "an unaffordable priced hint is refused")
		ok(gc.sparks.to_int() == 3, "and nothing is taken when refused (got %d)" % gc.sparks.to_int())
		gc.sparks = BigNum.from_int(12)
		ok(w._try_pay_hint(2), "an affordable priced hint passes")
		ok(gc.sparks.to_int() == 7, "and exactly the price is taken (got %d)" % gc.sparks.to_int())
		w.hint_cost_sparks = {1: 0, 2: 0}
		gc.sparks = saved

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
