extends "res://dev_tests/test_base.gd"
# Repeat Count — Form 14 (Group Comparison), the fourth LIVE clue-generation
# user of Category.REPEAT. User decision (2026-09-30): Form 14 gets its OWN
# local comparison-axis pool (`comparison_cats` inside
# _build_form_group_comparison) rather than extending the shared
# _orderable_categories() -- that function also drives Form 5 (Pairwise
# Order), which already ships live, already-tuned puzzles. Form 5 must stay
# completely unaffected; see the dedicated check for that below.
#
# What must hold, and why each case exists:
#  - _build_form_group_comparison must actually draw axis == Category.REPEAT
#    sometimes (a 1-in-3 coin flip on a non-degenerate constellation) --
#    otherwise every check below is vacuous.
#  - Every Repeat-axis clue's text must render real words, never "?".
#  - The claim ("X has a higher/lower repeat count than Y, Z, ...") must be
#    TRUE against ground truth: the subject's real repeat_count must
#    actually be higher (or lower) than EVERY named group member's.
#  - Neither the subject nor any group member may be the -1 never-fires
#    sentinel -- _sample_identity_axis_cell only validates the IDENTITY
#    label's uniqueness, never the comparison axis's validity for the star
#    it returns, so this is a guard Form 14 has to supply itself.
#  - A real end-to-end generated puzzle must still ship cleanly.
#  - A hard-mode/degenerate puzzle must never draw Category.REPEAT here.
#  - Form 5 (Pairwise Order), which shares _orderable_categories() in name
#    only (not in the actual pool Form 14 draws from anymore), must NEVER
#    draw Category.REPEAT as its axis -- confirming the "leave Form 5
#    untouched" decision actually held across many draws, not just by
#    reading the diff.

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

	print("=== drawing Group Comparison directly, many times, matrix never committed ===")
	var repeat_clues: Array = []
	var total_drawn: int = 0
	for i in 500:
		var clue: Dictionary = g._build_form_group_comparison({})
		if clue.is_empty():
			continue
		total_drawn += 1
		var chars: Array = clue.get("chars", [])
		# chars[1] is subj's own axis-value char ({"cat": axis, "star": subject}) --
		# see _build_form_group_comparison's chars.append(subject_axis_ch).
		if chars.size() >= 2 and int((chars[1] as Dictionary).get("cat", -1)) == PuzzleScript.Category.REPEAT:
			repeat_clues.append(clue)
	ok(total_drawn > 0, "sanity: Group Comparison actually produced some clues (got %d of 500 draws)" % total_drawn)
	ok(repeat_clues.size() > 0, "at least one of those draws used axis == Category.REPEAT (got %d) -- otherwise every check below is vacuous" % repeat_clues.size())

	print("\n=== every Repeat-axis Group Comparison clue is well-formed and TRUE ===")
	var bad_text: int = 0
	var bad_truth: int = 0
	var bad_sentinel: int = 0
	for c in repeat_clues:
		var text: String = str(c.get("text", ""))
		if text.strip_edges() == "" or text.contains("?"):
			bad_text += 1
			print("    bad text: '%s'" % text)
		var chars2: Array = c.get("chars", [])
		# chars layout: [subject_id, subject_axis_ch, (group_id, group_axis_ch) * N]
		var subject_star: int = int((chars2[1] as Dictionary).get("star", -1))
		var is_higher: bool = text.contains(" higher ")
		var subject_rc: int = int(g.repeat_count[subject_star])
		if subject_rc < 0:
			bad_sentinel += 1
			print("    subject used the never-fires sentinel: star %d" % subject_star)
		var i2: int = 2
		var all_true: bool = true
		while i2 + 1 < chars2.size():
			var member_star: int = int((chars2[i2 + 1] as Dictionary).get("star", -1))
			var member_rc: int = int(g.repeat_count[member_star])
			if member_rc < 0:
				bad_sentinel += 1
				print("    group member used the never-fires sentinel: star %d" % member_star)
			var holds: bool = (subject_rc > member_rc) if is_higher else (subject_rc < member_rc)
			if not holds:
				all_true = false
				print("    FALSE claim: '%s' (subject repeat=%d, member star %d repeat=%d)" % [text, subject_rc, member_star, member_rc])
			i2 += 2
		if not all_true:
			bad_truth += 1
	ok(bad_text == 0, "no Repeat-axis clue's text is blank or contains '?' (%d bad of %d)" % [bad_text, repeat_clues.size()])
	ok(bad_truth == 0, "every Repeat-axis clue's claim is actually true against ground truth (%d false of %d)" % [bad_truth, repeat_clues.size()])
	ok(bad_sentinel == 0, "no Repeat-axis clue ever uses the -1 never-fires sentinel (%d bad of %d)" % [bad_sentinel, repeat_clues.size()])
	if not repeat_clues.is_empty():
		print("    sample: %s" % str(repeat_clues[0].get("text", "")))

	print("\n=== Form 5 (Pairwise Order) stays completely untouched ===")
	var form5_repeat_draws: int = 0
	var form5_total: int = 0
	for i3 in 500:
		var clue5: Dictionary = g._build_form_pairwise_order({})
		if clue5.is_empty():
			continue
		form5_total += 1
		var chars5: Array = clue5.get("chars", [])
		for ch in chars5:
			if int((ch as Dictionary).get("cat", -1)) == PuzzleScript.Category.REPEAT:
				form5_repeat_draws += 1
				break
	ok(form5_total > 0, "sanity: Pairwise Order actually produced some clues (got %d of 500 draws)" % form5_total)
	ok(form5_repeat_draws == 0, "Pairwise Order NEVER draws Category.REPEAT (got %d of %d) -- confirms Form 5 was left untouched" % [form5_repeat_draws, form5_total])

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
	for i4 in range(int(def3["star_count"])):
		sq3.append(i4)
	var g3 = PuzzleScript.new()
	g3.setup(int(def3["star_count"]), def3["line_pairs"], sq3, 11, 0, def3.get("name_theme", {}),
		cd3.get_note_assignment(0), cd3.get_note_freqs(0), null)
	g3._build_record_array()
	g3._build_matrix()
	ok(g3._repeat_count_is_degenerate(), "sanity: hard-mode Archon's repeat_count is degenerate (all-zero)")
	var hard_repeat_draws: int = 0
	for i5 in 500:
		var clue3: Dictionary = g3._build_form_group_comparison({})
		if clue3.is_empty():
			continue
		var chars3: Array = clue3.get("chars", [])
		if chars3.size() >= 2 and int((chars3[1] as Dictionary).get("cat", -1)) == PuzzleScript.Category.REPEAT:
			hard_repeat_draws += 1
	ok(hard_repeat_draws == 0, "hard mode never draws Category.REPEAT for Group Comparison (got %d of 500)" % hard_repeat_draws)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
