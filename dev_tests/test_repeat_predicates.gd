extends "res://dev_tests/test_base.gd"
# Graded Repeat predicates in Group Membership (Form 23) and Group Negation
# (Form 24): "repeat at least once", "at most twice", "between 1 and 3 times"
# on top of the exact "repeat N times".
#
# A predicate is a set of repeat VALUES that decomposes into the exact-value
# negation facts every consumer already understands (see the header above
# _repeat_predicate_containing in constellation_logic_puzzle.gd). What must
# hold, and why each case exists:
#  - Each Form actually draws graded phrases (the denominator that makes every
#    other check non-vacuous), and every kind ("at least", "at most",
#    "between") shows up.
#  - The sentence is TRUE against ground truth, judged by parsing the words
#    the player reads and evaluating them on repeat_count -- independent of
#    the code that produced the clue.
#  - The facts match the sentence exactly: the set of values a subject is
#    declared NOT to be in is precisely the complement (positive claim) or the
#    covered set (negative claim) -- no more, no less.
#  - Every false cell the clue marks is genuinely false in the solution.
#  - A predicate is always a non-empty PROPER subset of the present values,
#    always contains the value it was drawn around, and a degenerate
#    (hard-mode) melody never produces one.
#  - A real end-to-end generated puzzle still ships.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _times(word: String) -> int:
	return 1 if word == "once" else int(word.split(" ")[0])


## Parses the REPEAT predicate out of a clue's sentence. Returns {} when the
## sentence has no graded repeat phrase, else {"kind", "lo", "hi"} with hi == -1
## for an open upper end.
func _parse_graded(text: String) -> Dictionary:
	var re_least := RegEx.create_from_string("repeats? at least (once|\\d+ times)")
	var m = re_least.search(text)
	if m:
		return {"kind": "at_least", "lo": _times(m.get_string(1)), "hi": -1}
	var re_most := RegEx.create_from_string("repeats? at most (once|\\d+ times)")
	m = re_most.search(text)
	if m:
		return {"kind": "at_most", "lo": 0, "hi": _times(m.get_string(1))}
	var re_between := RegEx.create_from_string("repeats? between (\\d+) and (\\d+) times")
	m = re_between.search(text)
	if m:
		return {"kind": "between", "lo": int(m.get_string(1)), "hi": int(m.get_string(2))}
	return {}


func _holds(pred: Dictionary, rc: int) -> bool:
	if rc < int(pred["lo"]):
		return false
	return int(pred["hi"]) < 0 or rc <= int(pred["hi"])


func _present(g) -> Array:
	var seen: Dictionary = {}
	for v in g.repeat_count:
		if int(v) >= 0:
			seen[int(v)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## A cell marked is_true:false must be false in the solution: no single star
## carries both of its values.
func _cell_is_really_false(g, upd: Dictionary) -> bool:
	for s in g.star_count:
		if int(g._cat_star_to_value[int(upd["cat_a"])][s]) == int(upd["val_a"]) \
				and int(g._cat_star_to_value[int(upd["cat_b"])][s]) == int(upd["val_b"]):
			return false
	return true


func _blocked_values(facts: Array, name_star: int) -> Array:
	var out: Array = []
	for f in facts:
		var fd: Dictionary = f
		if str(fd.get("kind", "")) == "name_group_neg" and int(fd.get("cat", -1)) == PuzzleScript.Category.REPEAT \
				and int(fd.get("name_star", -1)) == name_star:
			out.append(int(fd["group_key"]))
	out.sort()
	return out


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[1] = "easy"   # The Spark: repeat counts 0..3, so every kind can occur
	cd.player_seed = 11
	var def: Dictionary = cd.get_constellation_def(1)
	var scn: int = int(def["star_count"])
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(1, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(1)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(scn, def["line_pairs"], sq, 11, 1, def.get("name_theme", {}),
		cd.get_note_assignment(1), cd.get_note_freqs(1), null)
	g._build_record_array()
	g._build_matrix()
	var present: Array = _present(g)
	print("The Spark Beginner: %d stars, present repeat values %s" % [scn, str(present)])
	ok(present.size() >= 3, "fixture has at least 3 distinct repeat values, so 'between' can occur (%s)" % str(present))

	print("\n=== the predicate chooser ===")
	var kinds: Dictionary = {}
	var bad_contains: int = 0
	var bad_proper: int = 0
	var drawn: int = 0
	for v in present:
		for i in 60:
			var p: Dictionary = g._repeat_predicate_containing(int(v))
			if p.is_empty():
				continue
			drawn += 1
			kinds[str(p["kind"])] = int(kinds.get(str(p["kind"]), 0)) + 1
			var vals: Array = p["values"]
			if not vals.has(int(v)):
				bad_contains += 1
			if vals.is_empty() or vals.size() >= present.size():
				bad_proper += 1
	ok(drawn > 0, "the chooser produced predicates (%d)" % drawn)
	ok(bad_contains == 0, "every predicate contains the value it was drawn around (%d violations)" % bad_contains)
	ok(bad_proper == 0, "every predicate is a non-empty PROPER subset of the present values (%d violations)" % bad_proper)
	for k in ["at_least", "at_most", "between"]:
		ok(int(kinds.get(k, 0)) > 0, "kind '%s' is drawn (%d)" % [k, int(kinds.get(k, 0))])

	print("\n=== Group Membership (Form 23) ===")
	var m_graded: int = 0
	var m_kinds: Dictionary = {}
	var m_bad_text: int = 0
	var m_bad_truth: int = 0
	var m_bad_facts: int = 0
	var m_bad_cells: int = 0
	var m_name_checked: int = 0
	for i in 600:
		var clue: Dictionary = g._build_form_group_membership({})
		if clue.is_empty():
			continue
		var text: String = str(clue.get("text", ""))
		var pred: Dictionary = _parse_graded(text)
		if pred.is_empty():
			continue
		m_graded += 1
		m_kinds[str(pred["kind"])] = int(m_kinds.get(str(pred["kind"]), 0)) + 1
		if text.contains("?"):
			m_bad_text += 1
			print("    bad text: '%s'" % text)
		var subject: Dictionary = (clue["chars"] as Array)[0]
		var s_star: int = int(subject["star"])
		var positive: bool = text.contains(" is one of ")
		var in_group: bool = _holds(pred, int(g.repeat_count[s_star]))
		if in_group != positive:
			m_bad_truth += 1
			print("    FALSE claim: '%s' (subject repeat=%d)" % [text, g.repeat_count[s_star]])
		if int(subject["cat"]) == PuzzleScript.Category.NAME:
			m_name_checked += 1
			var expect: Array = []
			for pv in present:
				if _holds(pred, int(pv)) != positive:
					expect.append(int(pv))
			expect.sort()
			var got: Array = _blocked_values(clue.get("value_facts", []), s_star)
			if got != expect:
				m_bad_facts += 1
				print("    facts disagree with '%s': blocked %s, expected %s" % [text, str(got), str(expect)])
		for upd in clue.get("grid_updates", []):
			if not bool((upd as Dictionary).get("is_true", true)) and not _cell_is_really_false(g, upd):
				m_bad_cells += 1
				print("    false cell is actually true for '%s'" % text)
				break
	ok(m_graded > 0, "Form 23 drew graded phrases (%d of 600 draws) -- otherwise every check here is vacuous" % m_graded)
	ok(m_name_checked > 0, "some graded Form 23 clues had a Name subject, so the fact check ran (%d)" % m_name_checked)
	for k2 in ["at_least", "at_most", "between"]:
		ok(int(m_kinds.get(k2, 0)) > 0, "Form 23 drew kind '%s' (%d)" % [k2, int(m_kinds.get(k2, 0))])
	ok(m_bad_text == 0, "no graded Form 23 sentence contains '?' (%d)" % m_bad_text)
	ok(m_bad_truth == 0, "every graded Form 23 sentence is true against ground truth (%d false of %d)" % [m_bad_truth, m_graded])
	ok(m_bad_facts == 0, "graded Form 23 facts block exactly the values the sentence implies (%d mismatches)" % m_bad_facts)
	ok(m_bad_cells == 0, "every false cell a graded Form 23 clue marks is false in the solution (%d bad)" % m_bad_cells)

	print("\n=== Group Negation (Form 24) ===")
	var n_graded: int = 0
	var n_kinds: Dictionary = {}
	var n_bad_text: int = 0
	var n_bad_truth: int = 0
	var n_bad_facts: int = 0
	var n_bad_cells: int = 0
	for i2 in 800:
		var clue2: Dictionary = g._build_form_group_negation({})
		if clue2.is_empty():
			continue
		var text2: String = str(clue2.get("text", ""))
		var pred2: Dictionary = _parse_graded(text2)
		if pred2.is_empty():
			continue
		n_graded += 1
		n_kinds[str(pred2["kind"])] = int(n_kinds.get(str(pred2["kind"]), 0)) + 1
		if text2.contains("?"):
			n_bad_text += 1
			print("    bad text: '%s'" % text2)
		var covered: Array = []
		for pv2 in present:
			if _holds(pred2, int(pv2)):
				covered.append(int(pv2))
		covered.sort()
		for ch in clue2.get("chars", []):
			var cd2: Dictionary = ch
			if int(cd2["cat"]) != PuzzleScript.Category.NAME and int(cd2["cat"]) != PuzzleScript.Category.SEQUENCE:
				continue
			if _holds(pred2, int(g.repeat_count[int(cd2["star"])])):
				n_bad_truth += 1
				print("    FALSE claim: '%s' (subject star %d repeats %d)" % [text2, int(cd2["star"]), g.repeat_count[int(cd2["star"])]])
		var facts_by_subject: Dictionary = {}
		for f in clue2.get("value_facts", []):
			var fd: Dictionary = f
			if str(fd.get("kind", "")) == "descriptor_not_in_group" and int(fd.get("group_cat", -1)) == PuzzleScript.Category.REPEAT:
				var key: String = "%d:%d" % [int(fd["cat"]), int(fd["star"])]
				if not facts_by_subject.has(key):
					facts_by_subject[key] = []
				(facts_by_subject[key] as Array).append(int(fd["group_key"]))
		for key2 in facts_by_subject:
			var got2: Array = facts_by_subject[key2]
			got2.sort()
			if got2 != covered:
				n_bad_facts += 1
				print("    facts disagree with '%s': %s vs covered %s" % [text2, str(got2), str(covered)])
		for upd2 in clue2.get("grid_updates", []):
			if not bool((upd2 as Dictionary).get("is_true", true)) and not _cell_is_really_false(g, upd2):
				n_bad_cells += 1
				print("    false cell is actually true for '%s'" % text2)
				break
	ok(n_graded > 0, "Form 24 drew graded phrases (%d of 800 draws) -- otherwise every check here is vacuous" % n_graded)
	for k3 in ["at_least", "at_most", "between"]:
		ok(int(n_kinds.get(k3, 0)) > 0, "Form 24 drew kind '%s' (%d)" % [k3, int(n_kinds.get(k3, 0))])
	ok(n_bad_text == 0, "no graded Form 24 sentence contains '?' (%d)" % n_bad_text)
	ok(n_bad_truth == 0, "every graded Form 24 sentence is true against ground truth (%d false)" % n_bad_truth)
	ok(n_bad_facts == 0, "graded Form 24 facts negate exactly the covered values (%d mismatches)" % n_bad_facts)
	ok(n_bad_cells == 0, "every false cell a graded Form 24 clue marks is false in the solution (%d bad)" % n_bad_cells)

	print("\n=== a real end-to-end generated puzzle still ships ===")
	var g2 = PuzzleScript.new()
	g2.difficulty = "easy"
	g2.setup(scn, def["line_pairs"], sq, 11, 1, def.get("name_theme", {}),
		cd.get_note_assignment(1), cd.get_note_freqs(1), null)
	await g2.generate_clues_forms()
	ok(g2.gate_passed and not g2.chosen_form_clues.is_empty(),
		"a real Spark Beginner puzzle ships (gate_passed=%s, %d clues)" % [g2.gate_passed, g2.chosen_form_clues.size()])
	var graded_shipped: int = 0
	for c in g2.chosen_form_clues:
		if not _parse_graded(str((c as Dictionary).get("text", ""))).is_empty():
			graded_shipped += 1
			print("    shipped: %s" % str((c as Dictionary).get("text", "")))
	print("    graded repeat clues in this puzzle: %d" % graded_shipped)

	print("\n=== a hard-mode (degenerate) puzzle never produces a predicate ===")
	var cd3 = load("res://constellation_data.gd").new()
	cd3.player_seed = 11
	var def3: Dictionary = cd3.get_constellation_def(0)   # no GameContext -> hard mode
	var sq3: Array = []
	for i3 in range(int(def3["star_count"])):
		sq3.append(i3)
	var g3 = PuzzleScript.new()
	g3.setup(int(def3["star_count"]), def3["line_pairs"], sq3, 11, 0, def3.get("name_theme", {}),
		cd3.get_note_assignment(0), cd3.get_note_freqs(0), null)
	g3._build_record_array()
	g3._build_matrix()
	ok(g3._repeat_count_is_degenerate(), "sanity: hard-mode Archon's repeat_count is degenerate")
	ok(g3._repeat_predicate_containing(0).is_empty(), "no predicate can be drawn from a single present value")
	var hard_graded: int = 0
	for i4 in 300:
		var c3: Dictionary = g3._build_form_group_membership({})
		if not c3.is_empty() and not _parse_graded(str(c3.get("text", ""))).is_empty():
			hard_graded += 1
		var c4: Dictionary = g3._build_form_group_negation({})
		if not c4.is_empty() and not _parse_graded(str(c4.get("text", ""))).is_empty():
			hard_graded += 1
	ok(hard_graded == 0, "hard mode never says a graded repeat phrase (%d)" % hard_graded)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
