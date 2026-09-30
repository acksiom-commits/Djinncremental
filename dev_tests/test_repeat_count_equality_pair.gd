extends "res://dev_tests/test_base.gd"
# Repeat Count — step 4 of the axis build order (see
# planned_repeat_count_axis_design.md): Form 12 (Equality Pair) is the
# first LIVE clue-generation user of Category.REPEAT. Everything before
# this step (ground truth, matrix encoding, deduction states) was inert;
# this is where a real generated puzzle can, for the first time, ship a
# clue whose content is "these two stars repeat the same number of times".
#
# What must hold, and why each case exists:
#  - _build_form_equality_pair must actually draw axis == Category.REPEAT
#    sometimes (a 1-in-3 coin flip) -- if it never does across many draws,
#    every check below is vacuous (see vacuous_check_reported_as_
#    verification memory: a check without its denominator proves nothing).
#  - Every Repeat-axis clue's text must render real words, never the bare
#    "?" _characteristic_label falls through to for an unhandled category
#    -- the exact failure the Category enum's own POSITION comment warns
#    a premature activation causes.
#  - The clue's claim must be TRUE: both named stars' real repeat_count
#    values must actually match (checked against ground truth directly,
#    not re-derived from the same code path that produced the clue).
#  - Neither named star may be the -1 "never fires" sentinel -- asserting
#    two non-existent-repeat stars "repeat the same number of times" would
#    be nonsense, not merely a boring clue.
#  - A real end-to-end generated puzzle (full generate_clues_forms(), not
#    a direct Form call) must still ship cleanly with Repeat Count wired
#    in, with zero clues anywhere in the set rendering as a bare "?".

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[0] = "easy"

	cd.player_seed = 11
	var def: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(def["star_count"])
	var overlay_engine = load("res://click_sequence_puzzle_engine.gd").new()
	overlay_engine.set_constellation(0, cd, gc)
	var sq: Array = overlay_engine.get_correct_star_sequence(0)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	g._build_record_array()
	g._build_matrix()

	print("=== drawing Equality Pair directly, many times, matrix never committed ===")
	var repeat_clues: Array = []
	var total_drawn: int = 0
	for i in 300:
		var clue: Dictionary = g._build_form_equality_pair({})
		if clue.is_empty():
			continue
		total_drawn += 1
		var vf: Array = clue.get("value_facts", [])
		if not vf.is_empty() and int((vf[0] as Dictionary).get("cat", -1)) == PuzzleScript.Category.REPEAT:
			repeat_clues.append(clue)
	ok(total_drawn > 0, "sanity: Equality Pair actually produced some clues (got %d of 300 draws)" % total_drawn)
	ok(repeat_clues.size() > 0, "at least one of those draws used axis == Category.REPEAT (got %d) -- otherwise every check below is vacuous" % repeat_clues.size())

	print("\n=== every Repeat-axis clue drawn is well-formed and TRUE ===")
	var bad_text: int = 0
	var bad_truth: int = 0
	var bad_sentinel: int = 0
	for c in repeat_clues:
		var text: String = str(c.get("text", ""))
		if text.strip_edges() == "" or text.contains("?"):
			bad_text += 1
			print("    bad text: '%s'" % text)
		var vf2: Array = c.get("value_facts", [])
		var f: Dictionary = vf2[0]
		var star_a: int = int(f.get("a", -1))
		var star_b: int = int(f.get("b", -1))
		if int(g.repeat_count[star_a]) != int(g.repeat_count[star_b]):
			bad_truth += 1
			print("    FALSE claim: star %d (repeat=%d) vs star %d (repeat=%d)" % [star_a, g.repeat_count[star_a], star_b, g.repeat_count[star_b]])
		if int(g.repeat_count[star_a]) < 0 or int(g.repeat_count[star_b]) < 0:
			bad_sentinel += 1
			print("    used the never-fires sentinel: star_a=%d star_b=%d" % [star_a, star_b])
	ok(bad_text == 0, "no Repeat-axis clue's text is blank or contains '?' (%d bad of %d)" % [bad_text, repeat_clues.size()])
	ok(bad_truth == 0, "every Repeat-axis clue's claim is actually true against ground truth (%d false of %d)" % [bad_truth, repeat_clues.size()])
	ok(bad_sentinel == 0, "no Repeat-axis clue ever uses the -1 never-fires sentinel (%d bad of %d)" % [bad_sentinel, repeat_clues.size()])
	if not repeat_clues.is_empty():
		print("    sample: %s" % str(repeat_clues[0].get("text", "")))

	print("\n=== a real end-to-end generated puzzle still ships cleanly ===")
	var g2 = PuzzleScript.new()
	g2.difficulty = "easy"
	g2.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g2.generate_clues_forms()
	ok(g2.gate_passed and not g2.chosen_form_clues.is_empty(),
		"a real puzzle still ships (gate_passed=%s, %d clues)" % [g2.gate_passed, g2.chosen_form_clues.size()])
	var broken: int = 0
	for c2 in g2.chosen_form_clues:
		var t2: String = str((c2 as Dictionary).get("text", ""))
		if t2.strip_edges() == "" or t2.strip_edges() == "?" or t2.contains(" ? "):
			broken += 1
			print("    broken clue text: '%s'" % t2)
	ok(broken == 0, "no clue anywhere in a real generated puzzle rendered as broken '?' text (got %d)" % broken)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
