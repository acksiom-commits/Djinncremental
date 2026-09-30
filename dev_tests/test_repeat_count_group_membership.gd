extends "res://dev_tests/test_base.gd"
# Repeat Count — Form 23 (Group Membership), the second LIVE clue-generation
# user of Category.REPEAT (see planned_repeat_count_axis_design.md). Same
# rigor as Form 12/Equality Pair's own test module.
#
# What must hold, and why each case exists:
#  - _build_form_group_membership must actually draw group_cat ==
#    Category.REPEAT sometimes (a 1-in-3 coin flip on a non-degenerate
#    constellation) -- otherwise every check below is vacuous.
#  - Every Repeat-axis clue's text must render real words, never "?".
#  - The claim ("X is/is not one of the stars that repeat N times") must be
#    TRUE against ground truth: membership must match repeat_count exactly,
#    checked independently of the code path that produced the clue.
#  - The group-defining star's repeat_count must never be the -1 never-
#    fires sentinel.
#  - A real end-to-end generated puzzle must still ship cleanly.

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

	print("=== drawing Group Membership directly, many times, matrix never committed ===")
	var repeat_clues: Array = []
	var total_drawn: int = 0
	for i in 400:
		var clue: Dictionary = g._build_form_group_membership({})
		if clue.is_empty():
			continue
		total_drawn += 1
		var chars: Array = clue.get("chars", [])
		if chars.size() >= 2 and int((chars[1] as Dictionary).get("cat", -1)) == PuzzleScript.Category.REPEAT:
			repeat_clues.append(clue)
	ok(total_drawn > 0, "sanity: Group Membership actually produced some clues (got %d of 400 draws)" % total_drawn)
	ok(repeat_clues.size() > 0, "at least one of those draws used group_cat == Category.REPEAT (got %d) -- otherwise every check below is vacuous" % repeat_clues.size())

	print("\n=== every Repeat-axis Group Membership clue is well-formed and TRUE ===")
	var bad_text: int = 0
	var bad_truth: int = 0
	var bad_sentinel: int = 0
	for c in repeat_clues:
		var text: String = str(c.get("text", ""))
		if text.strip_edges() == "" or text.contains("?"):
			bad_text += 1
			print("    bad text: '%s'" % text)
		var chars2: Array = c.get("chars", [])
		var subject_ch: Dictionary = chars2[0]
		var group_ch: Dictionary = chars2[1]
		var subject_star: int = int(subject_ch.get("star", -1))
		var def_star: int = int(group_ch.get("star", -1))
		var is_positive: bool = text.contains(" is one of ")
		var same_group: bool = int(g.repeat_count[subject_star]) == int(g.repeat_count[def_star])
		if same_group != is_positive:
			bad_truth += 1
			print("    FALSE claim: '%s' (subject repeat=%d, group repeat=%d)" % [text, g.repeat_count[subject_star], g.repeat_count[def_star]])
		if int(g.repeat_count[def_star]) < 0:
			bad_sentinel += 1
			print("    used the never-fires sentinel as the group definer: star %d" % def_star)
	ok(bad_text == 0, "no Repeat-axis clue's text is blank or contains '?' (%d bad of %d)" % [bad_text, repeat_clues.size()])
	ok(bad_truth == 0, "every Repeat-axis clue's membership claim is actually true against ground truth (%d false of %d)" % [bad_truth, repeat_clues.size()])
	ok(bad_sentinel == 0, "no Repeat-axis clue's group is ever defined by the -1 never-fires sentinel (%d bad of %d)" % [bad_sentinel, repeat_clues.size()])
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

	print("\n=== a hard-mode (degenerate repeat_count) puzzle never draws REPEAT ===")
	var cd3 = load("res://constellation_data.gd").new()
	cd3.player_seed = 11
	var def3: Dictionary = cd3.get_constellation_def(0)   # no GameContext -> hard mode
	var sq3: Array = []
	for i in range(int(def3["star_count"])):
		sq3.append(i)
	var g3 = PuzzleScript.new()
	g3.setup(int(def3["star_count"]), def3["line_pairs"], sq3, 11, 0, def3.get("name_theme", {}),
		cd3.get_note_assignment(0), cd3.get_note_freqs(0), null)
	g3._build_record_array()
	g3._build_matrix()
	ok(g3._repeat_count_is_degenerate(), "sanity: hard-mode Archon's repeat_count is degenerate (all-zero)")
	var hard_repeat_draws: int = 0
	for i2 in 400:
		var clue3: Dictionary = g3._build_form_group_membership({})
		if clue3.is_empty():
			continue
		var chars3: Array = clue3.get("chars", [])
		if chars3.size() >= 2 and int((chars3[1] as Dictionary).get("cat", -1)) == PuzzleScript.Category.REPEAT:
			hard_repeat_draws += 1
	ok(hard_repeat_draws == 0, "hard mode never draws Category.REPEAT for Group Membership (got %d of 400)" % hard_repeat_draws)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
