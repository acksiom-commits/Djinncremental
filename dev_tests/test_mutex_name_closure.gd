extends "res://dev_tests/test_base.gd"
# Critical-pass review item 1 (both AIs converged on this as top priority,
# 2026-09-25): the Name closure never read Mutual Exclusion's
# values_all_different content, so a NAME participant in a Mutex clue got
# zero credit toward proving Name uniqueness.
#
# Mutual Exclusion's per-participant identity is either a KNOWN star (any
# id_cat other than NAME -- Sequence resolves through seq_sol, and Colour/
# Pitch identities are always ground truth regardless of what the closure is
# solving for) or a NAME variable whose position is the closure's own
# unknown. So for each pair with at least one NAME participant:
#   - one NAME, one known: the known side's group_key EXCLUDES that group
#     from the NAME side's domain -- name_group_neg, the SAME mechanism
#     Equality Pair's one-NAME case already used, just never fired here.
#   - both NAME: neither position is known yet -- needs the new
#     name_different_group fact and _propagate_different_group.
#
# Checked here: the fact-emission helper in isolation, the propagation
# primitive in isolation (mirroring _propagate_same_group, which itself has
# no dedicated test -- this is the first direct test of that shape),
# soundness against ground truth on a real generated puzzle, and an A/B
# measurement of what it actually buys (mutex_name_facts_enabled).

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _puzzle(n: int, colors: Array):
	var g = PuzzleScript.new()
	g.star_count = n
	# star_colors is Array[int]; assigning an untyped literal through this
	# dynamic reference silently aborts the script (known project gotcha) --
	# build a typed local first.
	var typed_colors: Array[int] = []
	for c in colors:
		typed_colors.append(int(c))
	g.star_colors = typed_colors
	return g


func run() -> void:
	print("=== _mutex_name_value_facts: fact emission in isolation ===")
	# 5 stars, colours: 0,0,1,2,2 -- stars 0/1 share group 0, stars 3/4 share
	# group 2, star 2 is a singleton in group 1.
	var g0 = _puzzle(5, [0, 0, 1, 2, 2])
	var NAME: int = PuzzleScript.Category.NAME
	var SEQUENCE: int = PuzzleScript.Category.SEQUENCE
	var COLOR: int = PuzzleScript.Category.COLOR

	# One NAME (star 3), one known-by-Sequence (star 0): expect exactly one
	# name_group_neg excluding star 3's Name-variable from group 0 (star 0's
	# colour).
	var p1: Array = [
		{"id_cat": NAME, "star": 3},
		{"id_cat": SEQUENCE, "star": 0},
	]
	var f1: Array = g0._mutex_name_value_facts(p1, COLOR)
	ok(f1.size() == 1, "one Name + one known participant -> exactly 1 fact (%d)" % f1.size())
	if f1.size() == 1:
		var fd1: Dictionary = f1[0]
		ok(str(fd1.get("kind", "")) == "name_group_neg", "it is name_group_neg (got %s)" % str(fd1.get("kind", "")))
		ok(int(fd1.get("name_star", -1)) == 3, "on the Name participant's star (got %d)" % int(fd1.get("name_star", -1)))
		ok(int(fd1.get("group_key", -1)) == 0, "excluding the KNOWN participant's true group (got %d)" % int(fd1.get("group_key", -1)))

	# Two NAME participants (stars 1 and 4): expect exactly one
	# name_different_group, unordered.
	var p2: Array = [
		{"id_cat": NAME, "star": 1},
		{"id_cat": NAME, "star": 4},
	]
	var f2: Array = g0._mutex_name_value_facts(p2, COLOR)
	ok(f2.size() == 1, "two Name participants -> exactly 1 fact, not 2 (%d)" % f2.size())
	if f2.size() == 1:
		var fd2: Dictionary = f2[0]
		ok(str(fd2.get("kind", "")) == "name_different_group", "it is name_different_group (got %s)" % str(fd2.get("kind", "")))
		var pair_stars: Array = [int(fd2.get("name_star_a", -1)), int(fd2.get("name_star_b", -1))]
		pair_stars.sort()
		ok(pair_stars == [1, 4], "names the right unordered pair (got %s)" % str(pair_stars))

	# Mixed: 3 Name participants (0,1,4) + 1 known (2, group 1). Expect 3
	# name_group_neg (each Name vs. the known) + 3 name_different_group
	# (each unordered Name pair), 6 total, no duplicates.
	var p3: Array = [
		{"id_cat": NAME, "star": 0}, {"id_cat": NAME, "star": 1},
		{"id_cat": NAME, "star": 4}, {"id_cat": SEQUENCE, "star": 2},
	]
	var f3: Array = g0._mutex_name_value_facts(p3, COLOR)
	var neg3: int = 0
	var diff3: int = 0
	for f in f3:
		if str((f as Dictionary).get("kind", "")) == "name_group_neg":
			neg3 += 1
		elif str((f as Dictionary).get("kind", "")) == "name_different_group":
			diff3 += 1
	ok(neg3 == 3 and diff3 == 3 and f3.size() == 6,
		"3 Name + 1 known -> 3 negations + 3 pairwise differences, no duplicates (got %d neg, %d diff, %d total)" % [neg3, diff3, f3.size()])

	# All-known (no NAME participant at all): nothing to emit.
	var p4: Array = [{"id_cat": SEQUENCE, "star": 0}, {"id_cat": SEQUENCE, "star": 2}]
	ok(g0._mutex_name_value_facts(p4, COLOR).is_empty(), "no Name participant -> no facts")

	print("\n=== _validate_name_different_group_fact: soundness ===")
	ok(g0._validate_name_different_group_fact({"name_star_a": 0, "name_star_b": 4, "cat": COLOR}) == "",
		"a genuinely different pair (group 0 vs group 2) validates clean")
	ok(g0._validate_name_different_group_fact({"name_star_a": 0, "name_star_b": 1, "cat": COLOR}) != "",
		"a genuinely SAME pair (group 0 vs group 0) is caught as a violation")

	print("\n=== _propagate_different_group: the new primitive, mirroring _propagate_same_group ===")
	# 4 stars, colours 0,0,1,2 -- groups {0,1}, {2}, {3}.
	var g1 = _puzzle(4, [0, 0, 1, 2])
	# Case A: a and b both free over all 4 candidates, must differ on colour.
	# a=0 (group 0) must stay possible, since b can pick 2 or 3 (differ).
	var grid_a: Array = [[true, true, true, true], [true, true, true, true],
		[true, true, true, true], [true, true, true, true]]
	ok(g1._propagate_different_group(grid_a, [{"a": 0, "b": 1, "cat": COLOR}]),
		"a fully free pair stays consistent")
	# Neither domain should have narrowed at all yet -- with everything else
	# open, a can always find some b that differs.
	var untouched: bool = true
	for r in 4:
		if not grid_a[0][r] or not grid_a[1][r]:
			untouched = false
	ok(untouched, "and narrows nothing when both sides have plenty of options")

	# Case B: b's domain is forced down to ONLY star 1 (group 0). Then EVERY
	# group-0 candidate becomes impossible for a -- not just star 1 itself --
	# because the constraint is "a's colour differs from b's colour", not
	# "a's STAR differs from b's star" (that's the separate alldiff/
	# permutation constraint _solve() enforces elsewhere). Star 0 is ALSO
	# group 0, so it is excluded from a too, alongside star 1.
	var grid_b: Array = [[true, true, true, true], [false, true, false, false],
		[true, true, true, true], [true, true, true, true]]
	ok(g1._propagate_different_group(grid_b, [{"a": 0, "b": 1, "cat": COLOR}]),
		"still consistent overall")
	ok(not grid_b[0][0] and not grid_b[0][1],
		"EVERY candidate sharing b's forced group is removed from a (stars 0 and 1, both group 0)")
	ok(grid_b[0][2] and grid_b[0][3],
		"a's candidates with a DIFFERENT group (1 and 2) survive")

	# Case C: forcing both sides into the SAME single group is a genuine
	# contradiction -- must report false (empty domain), never silently pass.
	var grid_c: Array = [[true, false, false, false], [true, false, false, false],
		[false, false, false, false], [false, false, false, false]]
	ok(not g1._propagate_different_group(grid_c, [{"a": 0, "b": 1, "cat": COLOR}]),
		"forcing both into the same group is reported as a contradiction, not silently accepted")

	print("\n=== soundness and yield, on a real generated puzzle ===")
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
	ok(g.gate_passed, "the puzzle still passes the ship gate with the new content live")

	var neg_seen: int = 0
	var diff_seen: int = 0
	var bad: int = 0
	for clue in g.chosen_form_clues:
		for f in (clue.get("disclosures", []) as Array):
			var fd: Dictionary = f
			var kind: String = str(fd.get("kind", ""))
			if kind == "name_different_group":
				diff_seen += 1
				if g._validate_name_different_group_fact(fd) != "":
					bad += 1
			elif kind == "name_group_neg" and str(clue.get("form_name", "")) == "Mutual Exclusion":
				neg_seen += 1
				if g._validate_name_group_fact(fd) != "":
					bad += 1
	print("    Mutual Exclusion contributed: %d name_group_neg, %d name_different_group facts" % [neg_seen, diff_seen])
	ok(bad == 0, "every emitted fact is true of the ground truth (%d violations)" % bad)

	print("\n=== A/B: what does this actually buy on real generation? ===")
	var seeds: Array = [11, 12, 13, 14, 15, 16, 17, 18]
	var closure_on: int = 0
	var closure_off: int = 0
	var solved_on: int = 0
	var solved_off: int = 0
	for seed in seeds:
		var gon = PuzzleScript.new()
		gon.setup(scn, cdef["line_pairs"], sq, seed, 0, cdef.get("name_theme", {}),
			cd.get_note_assignment(0), cd.get_note_freqs(0), null)
		gon.mutex_name_facts_enabled = true
		var ron: Dictionary = await gon._generate_clues_forms_attempt()
		if bool(ron.get("name_unique_closure", false)):
			closure_on += 1
		solved_on += int(ron.get("name_solutions_count", -1)) if int(ron.get("name_solutions_count", -1)) > 0 else 0

		var goff = PuzzleScript.new()
		goff.setup(scn, cdef["line_pairs"], sq, seed, 0, cdef.get("name_theme", {}),
			cd.get_note_assignment(0), cd.get_note_freqs(0), null)
		goff.mutex_name_facts_enabled = false
		var roff: Dictionary = await goff._generate_clues_forms_attempt()
		if bool(roff.get("name_unique_closure", false)):
			closure_off += 1
		solved_off += int(roff.get("name_solutions_count", -1)) if int(roff.get("name_solutions_count", -1)) > 0 else 0
	print("    first-attempt name_unique_closure: WITH the fix %d/%d, WITHOUT %d/%d" % [closure_on, seeds.size(), closure_off, seeds.size()])
	ok(closure_on >= closure_off, "the fix never makes closure WORSE on any seed set (%d vs %d)" % [closure_on, closure_off])

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
