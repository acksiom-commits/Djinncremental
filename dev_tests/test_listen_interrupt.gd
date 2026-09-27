extends "res://dev_tests/test_base.gd"
# The Listen interrupt in the step hints (tiers 3 and 4).
#
# A pitch group only rules out stars the player has Listened to. When that is
# the ONLY thing standing between the player and a step, the hint says so
# instead of a bare "nothing you can act on yet".
#
# What must hold, and why each case exists:
#  - It fires when nothing is actionable AND knowing every pitch would unlock a
#    step -- and not otherwise. A clue that has nothing to do with pitch must
#    still get the plain "nothing yet" message, or the interrupt is a nag.
#  - It never fires while a step IS available: progress does not require
#    Listening then.
#  - It costs nothing: a hint that only says "go Listen" must not charge.
#  - It clears itself once the player has Listened.
#  - The comparison mode it uses to decide is always switched back off and does
#    not change what the hints report.

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
	var PITCH: int = PuzzleScript.Category.PITCH

	# "Alpha is not the star with pitch <star 3's note>" -- needs star 3's pitch.
	var pitch_clue: Dictionary = {"text": "Alpha is not that pitch.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": PITCH, "star_b": 3, "is_true": false}],
		"search_terms": ["N:Alpha", d._descriptor_term(PITCH, 3)],
		"disclosures": [{"kind": "name_group_neg", "name_star": 0, "cat": PITCH, "group_key": 3}],
		"characteristics": [], "chars": [], "form_id": 2}
	# A colour pair on a blank board: nothing to rule out yet, and no pitch involved.
	var colour_clue: Dictionary = {"text": "Alpha and Beta share a colour.",
		"cells": [{"cat_a": NAME, "star_a": 0, "cat_b": COLOR, "star_b": 2, "is_true": false}],
		"search_terms": ["N:Alpha", "N:Beta", d._descriptor_term(COLOR, 2)],
		"disclosures": [{"kind": "name_same_group", "name_star_a": 0, "name_star_b": 1, "cat": COLOR}],
		"characteristics": [], "chars": [], "form_id": 12}

	d._load_match_records([])
	d._clear_deduction_caches()

	print("=== deciding whether Listening is what blocks progress ===")
	ok(d.clue_indices_with_something_to_give([pitch_clue]) == [0], "the pitch clue IS offered as unrecorded, so the checks below are not vacuous")
	ok(d.hint_next_steps([pitch_clue]).is_empty(), "before any Listen it gives no step")
	ok(d.hint_pitch_blocked([pitch_clue]), "...and knowing every pitch WOULD unlock one, so progress is blocked on Listening")
	ok(not d._hint_assume_pitch_known, "the comparison mode is switched back off afterwards")
	ok(d.hint_next_steps([pitch_clue]).is_empty(), "and it did not change what the hints report")
	ok(d.clue_indices_with_something_to_give([colour_clue]) == [0], "the colour clue IS offered as unrecorded")
	ok(d.hint_next_steps([colour_clue]).is_empty() and not d.hint_pitch_blocked([colour_clue]),
		"a clue with no pitch in it gives no step and is NOT blocked on Listening")

	print("\n=== through the Hint tab ===")
	host._form_clues_cache = [pitch_clue]
	w._populate_hint_markers()
	for c0 in host._markers_content.get_children():
		c0.free()

	var gc = root.get_node_or_null("/root/GameContext")
	var saved_sparks = null
	if gc != null:
		saved_sparks = gc.sparks
		gc.sparks = BigNum.from_int(12)
		w.hint_cost_sparks = {1: 0, 2: 0, 3: 5, 4: 5}

	w._on_hint_tier3_pressed()
	_repaint(host, w)
	ok(w._hint_state == w.HINT_LISTEN, "tier 3 interrupts when Listening is what blocks progress")
	ok(_texts(host).contains("listened"), "and says why (\"%s\")" % _texts(host))
	w._on_hint_tier4_pressed()
	ok(w._hint_state == w.HINT_LISTEN, "tier 4 interrupts the same way")
	if gc != null:
		ok(gc.sparks.to_int() == 12, "the interrupt costs nothing (sparks %d)" % gc.sparks.to_int())

	# The player listens to star 3: the interrupt must go, and the step appears.
	var heard: int = d._get_or_create_match_record_for_star_idx(3)
	d._match_records[heard]["pitch_revealed"] = true
	d._clear_deduction_caches()
	_repaint(host, w)
	ok(w._hint_state == w.HINT_NONE and _texts(host).contains("sorted"),
		"once the player has Listened the interrupt clears itself (\"%s\")" % _texts(host))
	w._on_hint_tier3_pressed()
	ok(w._hint_state == w.HINT_DESCRIPTOR, "and tier 3 now gives the step instead (state %d)" % w._hint_state)
	if gc != null:
		ok(gc.sparks.to_int() == 7, "which IS charged (sparks %d)" % gc.sparks.to_int())
		gc.sparks = saved_sparks
		w.hint_cost_sparks = {1: 0, 2: 0, 3: 0, 4: 0}

	# Nothing left unlistened: never blocked, whatever the clues say.
	for s in 6:
		var rec: int = d._get_or_create_match_record_for_star_idx(s)
		d._match_records[rec]["pitch_revealed"] = true
	d._clear_deduction_caches()
	ok(d._unlistened_star_count() == 0 and not d.hint_pitch_blocked([pitch_clue]),
		"with every star Listened to, progress is never blocked on Listening")

	print("\n=== a clue that has nothing to do with pitch keeps the plain message ===")
	d._load_match_records([])
	d._clear_deduction_caches()
	host._form_clues_cache = [colour_clue]
	_repaint(host, w)
	w._on_hint_tier3_pressed()
	ok(w._hint_state == w.HINT_NO_STEP, "no interrupt when Listening would not help (state %d)" % w._hint_state)
	_repaint(host, w)
	ok(_texts(host).contains("Nothing you can act on"), "it says the plain 'nothing yet' instead (\"%s\")" % _texts(host))

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
