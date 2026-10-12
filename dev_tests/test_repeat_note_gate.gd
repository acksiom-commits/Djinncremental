extends "res://dev_tests/test_base.gd"
# THE REPEAT-NOTE GATE (2026-10-10, repeats are earned).
#
# On a Beginner melody some notes are an earlier star firing again, and which
# star is no longer shown: the player works it out. So the generator has to
# PROVE it can be worked out. This file checks that proof from outside.
#
#  1. THE VERDICT IS RIGHT. For shipped puzzles, every possible assignment of
#     the repeat notes is enumerated here by brute force and tested against the
#     clues' repeat facts with this file's OWN evaluators (no generator helper).
#     Exactly one assignment must survive, and it must be the real melody.
#  2. THE SOLVER AGREES WITH THE BRUTE FORCE IN BOTH DIRECTIONS. Each clue that
#     says something about the repeat notes is removed in turn; the generator's
#     solver and the brute force must give the same unique / not-unique answer
#     every time, and "not unique" has to actually occur (so this is not a
#     check that can only ever say yes). With every such clue removed there
#     must be many assignments.
#  3. NO ORDINAL OR NAME FACT IS READ OFF THE ANSWER'S LATER NOTES. A clue about
#     a later firing reaches the proof only as a firing fact, which the note
#     proof weighs against every firing order still open. Shown to bite: with
#     the old public-shape behaviour switched back on, the same check finds
#     the rank sets.
#  4. A 1:1 (hard-mode) melody has no repeat notes and is untouched.
#  5. THE NOTE PROOF IS JOINT (2026-10-12): the firing order and the repeat
#     notes are proven together, so a clue about a note can settle the order.
#
# Two puzzles (Archon, Hourglass: five repeat notes each, so the brute force is
# at most 9^5 assignments) -- different constellations rather than more seeds.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner_puzzle(cid: int, seed: int, earned: bool = true):
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.repeats_earned = earned
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	return g


# ── this file's own reading of a repeat fact ─────────────────────────────

func _fp_value(ticks: Array, sel: Dictionary) -> int:
	var kind: String = str(sel["kind"])
	if kind == "count":
		var c: int = 0
		for t in ticks:
			if int(t) >= int(sel["lo"]) and int(t) <= int(sel["hi"]):
				c += 1
		return c
	if kind == "nth":
		var k: int = ticks.size() if int(sel["k"]) == -1 else int(sel["k"])
		return int(ticks[k - 1]) if k >= 1 and k <= ticks.size() else -1
	var i: int = int(sel["i"])
	var j: int = ticks.size() if int(sel["j"]) == -1 else int(sel["j"])
	if i < 1 or j > ticks.size() or i >= j:
		return -1
	return int(ticks[j - 1]) - int(ticks[i - 1])


func _pick(ticks: Array, pick: Dictionary) -> Array:
	match str(pick["kind"]):
		"any":
			return ticks
		"first":
			return [ticks[0]]
		"last":
			return [ticks[ticks.size() - 1]]
	var k: int = int(pick["k"])
	return [ticks[k - 1]] if k >= 1 and k <= ticks.size() else []


func _fact_ok(fd: Dictionary, notes: Array) -> bool:
	match str(fd["kind"]):
		"firing_position":
			var v: int = _fp_value(notes[int(fd["s"])], fd["sel"])
			return v >= 0 and v >= int(fd["lo"]) and v <= int(fd["hi"])
		"repeat_count_range":
			var n: int = (notes[int(fd["star"])] as Array).size() - 1
			return (n >= int(fd["lo"]) and n <= int(fd["hi"])) != bool(fd.get("negated", false))
		"values_same":
			return (notes[int(fd["a"])] as Array).size() == (notes[int(fd["b"])] as Array).size()
		"firing_relation":
			var na: Array = _pick(notes[int(fd["a"])], fd["pick_a"])
			var nb: Array = _pick(notes[int(fd["b"])], fd["pick_b"])
			if na.is_empty() or nb.is_empty():
				return false
			var spec: Dictionary = fd["spec"]
			var found: bool = false
			for ta in na:
				for tb in nb:
					var d: int = int(ta) - int(tb)
					if str(spec["rel"]) == "exact":
						found = found or int(spec["dir"]) * d == int(spec["n"])
					elif str(spec["rel"]) == "atleast":
						found = found or int(spec["dir"]) * d >= int(spec["n"])
					else:
						found = found or absi(d) <= int(spec["n"])
			return found != bool(spec["neg"])
	return true


func _is_repeat_fact(fd: Dictionary) -> bool:
	var k: String = str(fd.get("kind", ""))
	return k == "firing_position" or k == "firing_relation" or k == "repeat_count_range" \
		or (k == "values_same" and int(fd.get("cat", -1)) == PuzzleScript.Category.REPEAT)


func _repeat_facts(clues: Array) -> Array:
	var out: Array = []
	for cl in clues:
		for d in (cl["disclosures"] as Array):
			if d is Dictionary and _is_repeat_fact(d):
				out.append(d)
	return out


var _enumerated: int = 0


## Every assignment of the repeat notes to an earlier-heard star that satisfies
## `facts`, counted (and the survivors kept, up to 3). Reads the melody only for
## its public part: which notes are first firings, and each star's first note.
## `swap` = [a, b] asks the same question for a DIFFERENT firing order: the one
## where stars a and b have traded first notes.
func _brute(melody: Array, star_count: int, facts: Array, swap: Array = []) -> Dictionary:
	var first: Array = []
	for _s in star_count:
		first.append(-1)
	var rticks: Array = []
	for i in melody.size():
		var s: int = int(melody[i])
		if int(first[s]) < 0:
			first[s] = i + 1
		else:
			rticks.append(i + 1)
	if swap.size() == 2:
		var keep: int = int(first[int(swap[0])])
		first[int(swap[0])] = first[int(swap[1])]
		first[int(swap[1])] = keep
	var result: Dictionary = {"count": 0, "kept": [], "rticks": rticks}
	var assign: Array = []
	for _r in rticks:
		assign.append(-1)
	_brute_step(0, rticks, first, star_count, assign, facts, result)
	return result


func _brute_step(i: int, rticks: Array, first: Array, star_count: int, assign: Array, facts: Array, result: Dictionary) -> void:
	if i == rticks.size():
		_enumerated += 1
		var notes: Array = []
		for s in star_count:
			notes.append([first[s]])
		for j in rticks.size():
			(notes[int(assign[j])] as Array).append(rticks[j])
		for f in facts:
			if not _fact_ok(f, notes):
				return
		result["count"] = int(result["count"]) + 1
		if (result["kept"] as Array).size() < 3:
			(result["kept"] as Array).append(assign.duplicate())
		return
	for s2 in star_count:
		if int(first[s2]) >= 0 and int(first[s2]) < int(rticks[i]):
			assign[i] = s2
			_brute_step(i + 1, rticks, first, star_count, assign, facts, result)


func run() -> void:
	var agree: int = 0
	var compared: int = 0
	var seen_not_unique: int = 0
	for cid in [0, 2]:
		print("=== constellation %d, Beginner ===" % cid)
		var g = _beginner_puzzle(cid, 11)
		# Sections 1-3 check the repeat-note search (_solve_repeat_notes), which
		# since 2026-10-12 is only the seam's proof: it takes the first notes as
		# given and does not use the stars' firing counts. Generated under that
		# seam so the puzzle is one that proof was asked to make unique. The
		# live proof has its own brute-force check in test_note_owner_proof.gd.
		g.first_notes_hidden = false
		await g.generate_clues_forms()
		ok(g.gate_passed, "the puzzle passes the ship gate")
		ok(g._repeats_hidden(), "its repeats are hidden")
		var melody: Array = g.melody_star_sequence
		var facts: Array = _repeat_facts(g.chosen_form_clues)
		var with_facts: Array = []
		for cl in g.chosen_form_clues:
			if g._clue_has_repeat_fact(cl):
				with_facts.append(cl)

		# 1. the verdict
		var before: int = _enumerated
		var b: Dictionary = _brute(melody, g.star_count, facts)
		var rticks: Array = b["rticks"]
		print("    %d stars, %d notes, repeat notes %s; %d clues carry %d repeat facts; brute force tried %d assignments" % [
			g.star_count, melody.size(), str(rticks), with_facts.size(), facts.size(), _enumerated - before])
		ok(rticks == g._repeat_ticks() and rticks.size() >= 3, "the repeat notes here are the generator's, and there are several (%d)" % rticks.size())
		ok(_enumerated - before > 100, "the brute force really enumerated (%d assignments)" % (_enumerated - before))
		ok(int(b["count"]) == 1, "exactly ONE assignment of the repeat notes satisfies the shipped clues (got %d)" % int(b["count"]))
		var truth: Array = []
		for t in rticks:
			truth.append(int(melody[int(t) - 1]))
		ok(int(b["count"]) >= 1 and (b["kept"] as Array)[0] == truth, "and it is the real melody")
		var sols: Array = g._solve_repeat_notes(3)
		ok(sols.size() == 1 and not g._last_repeat_solve_inconclusive and sols[0] == truth,
			"the generator's solver finds that same single assignment (%d found)" % sols.size())

		# 2. both directions
		var none: Array = []
		for cl2 in g.chosen_form_clues:
			if not g._clue_has_repeat_fact(cl2):
				none.append(cl2)
		var b_none: Dictionary = _brute(melody, g.star_count, _repeat_facts(none))
		ok(int(b_none["count"]) > 10, "with every repeat clue removed there are many assignments (%d)" % int(b_none["count"]))
		ok(g._solve_repeat_notes(2, none).size() == 2, "and the solver reports more than one")
		for drop in with_facts:
			var rest: Array = []
			for cl3 in g.chosen_form_clues:
				if cl3 != drop:
					rest.append(cl3)
			var b_rest: Dictionary = _brute(melody, g.star_count, _repeat_facts(rest))
			var s_rest: Array = g._solve_repeat_notes(2, rest)
			var solver_unique: bool = s_rest.size() == 1 and not g._last_repeat_solve_inconclusive
			compared += 1
			if solver_unique == (int(b_rest["count"]) == 1):
				agree += 1
			else:
				print("    DISAGREE without '%s': brute %d, solver %d" % [str(drop["text"]), int(b_rest["count"]), s_rest.size()])
			if int(b_rest["count"]) > 1:
				seen_not_unique += 1

		# 3. the other gates do not lean on the hidden notes
		var leaks: Array = []
		for cl4 in g.chosen_form_clues:
			var has_repeat: bool = g._clue_has_repeat_fact(cl4)
			for d in (cl4["disclosures"] as Array):
				var k: String = str((d as Dictionary).get("kind", ""))
				if k == "name_rank_set" or (k == "value_in_set" and has_repeat):
					leaks.append("%s in '%s'" % [k, str(cl4["text"])])
				if k == "ordinal_pair_set":
					var first_first: bool = false
					for d2 in (cl4["disclosures"] as Array):
						if str((d2 as Dictionary).get("kind", "")) == "firing_relation" \
								and str(d2["pick_a"]["kind"]) == "first" and str(d2["pick_b"]["kind"]) == "first":
							first_first = true
					if not first_first:
						leaks.append("ordinal_pair_set not between first firings in '%s'" % str(cl4["text"]))
		ok(leaks.is_empty(), "no Sequence or Name fact is read off a star's later notes (%d found) %s" % [leaks.size(), str(leaks.slice(0, 2))])

	print("\n=== solver vs brute force, one repeat clue removed at a time ===")
	ok(compared >= 8, "enough removals compared to mean something (%d)" % compared)
	ok(agree == compared, "the solver and the brute force agree on unique / not unique every time (%d of %d)" % [agree, compared])
	ok(seen_not_unique > 0, "and 'not unique' actually occurred (%d times), so the comparison can fail" % seen_not_unique)

	# 5. THE NOTE PROOF IS JOINT (2026-10-12, every note is a Sequence position).
	# A hand-built case where the ordinal facts alone leave TWO firing orders
	# open and a clue about a note settles which: "A fires on note <A's first
	# note>" cannot be true if A first fired later than that. The brute force
	# above, asked about the other order, must find nothing; the old two-stage
	# proof (the seam) must fail to call it unique.
	print("\n=== the note proof: a clue about a note settles the firing order ===")
	var gj = _beginner_puzzle(2, 11)
	# This section is about the proof that takes the first notes as GIVEN (a
	# seam since the first notes were hidden later the same day; the live
	# proof is checked in test_note_owner_proof.gd).
	gj.first_notes_hidden = false
	var by_rank: Array = []
	for _r in gj.star_count:
		by_rank.append(-1)
	for s0 in gj.star_count:
		by_rank[int(gj.sequence_rank_solution[s0])] = s0
	var sa: int = int(by_rank[0])
	var sb: int = int(by_rank[1])
	var seq_facts: Array = []
	for s1 in gj.star_count:
		if s1 != sa and s1 != sb:
			seq_facts.append({"kind": "ordinal_exact", "s": s1, "r": int(gj.sequence_rank_solution[s1])})
	var typed_facts: Array[Dictionary] = []
	for f0 in seq_facts:
		typed_facts.append(f0)
	ok(gj._solve(typed_facts, 5).size() == 2, "the ordinal facts alone leave exactly two firing orders (got %d)" % gj._solve(typed_facts, 5).size())
	var jr: Array = gj._repeat_ticks()
	var note_clues: Array = [{"disclosures": [{"kind": "firing_position", "s": sa,
		"sel": {"kind": "count", "lo": gj._seq_first_tick(sa), "hi": gj._seq_first_tick(sa)}, "lo": 1, "hi": 1}]}]
	var loose: Array = gj._solve_notes(seq_facts, 3, note_clues)
	var loose_same_order: bool = loose.size() == 3
	for ls in loose:
		if ls["ranks"] != gj.sequence_rank_solution:
			loose_same_order = false
	ok(loose_same_order, "with that one clue every answer left has the real firing order; only repeat notes are open (%d answers)" % loose.size())
	for jt in jr:
		note_clues.append({"disclosures": [{"kind": "firing_position", "s": int(gj.melody_star_sequence[int(jt) - 1]),
			"sel": {"kind": "count", "lo": int(jt), "hi": int(jt)}, "lo": 1, "hi": 1}]})
	var settled_before: int = gj.note_proof_order_settled_by_notes
	var joint: Array = gj._solve_notes(seq_facts, 3, note_clues)
	var j_truth: Array = []
	for jt2 in jr:
		j_truth.append(int(gj.melody_star_sequence[int(jt2) - 1]))
	ok(joint.size() == 1 and not gj._last_solve_inconclusive, "with each repeat note stated too there is exactly one answer (got %d)" % joint.size())
	ok(joint.size() == 1 and joint[0]["ranks"] == gj.sequence_rank_solution and joint[0]["repeats"] == j_truth, "and it is the real melody")
	ok(gj.note_proof_order_settled_by_notes == settled_before + 1, "the solver counted it as an order settled by a note")
	var jfacts: Array = _repeat_facts(note_clues)
	ok(int(_brute(gj.melody_star_sequence, gj.star_count, jfacts)["count"]) == 1, "brute force, real order: one assignment")
	var b_swapped: Dictionary = _brute(gj.melody_star_sequence, gj.star_count, jfacts, [sa, sb])
	ok(int(b_swapped["count"]) == 0, "brute force, the OTHER order: none (got %d)" % int(b_swapped["count"]))
	var b_swapped_free: Dictionary = _brute(gj.melody_star_sequence, gj.star_count, jfacts.slice(1), [sa, sb])
	ok(int(b_swapped_free["count"]) > 0, "and without the first clue the other order does fit (%d), so that clue is what rules it out" % int(b_swapped_free["count"]))
	gj.note_proof_joint = false
	var staged: Array = gj._solve_notes(seq_facts, 3, note_clues)
	ok(staged.size() != 1, "the old two-stage proof does NOT find it unique (%d), so this section can fail" % staged.size())
	gj.note_proof_joint = true

	# 2026-10-11: Listen gives each star's repeat COUNT, so the Name closure
	# reads a Repeat-count group like a Pitch group. (On 2026-10-10 it skipped
	# them as hidden; this section then asserted the skip.)
	print("\n=== the Name closure counts Repeat-count groups ===")
	var gh = _beginner_puzzle(0, 11)
	var key: int = int(gh.repeat_count[0])
	var same_count: Array = []
	for s in gh.star_count:
		if int(gh.repeat_count[s]) == key:
			same_count.append(s)
	var rep_clue: Dictionary = {"disclosures": [{"kind": "name_group", "name_star": 0, "cat": PuzzleScript.Category.REPEAT, "group_key": key}]}
	var built: Dictionary = gh._build_name_clues([gh.sequence_rank_solution], [rep_clue])
	var read: Array = built["name_clues"]
	ok(bool(built["ok"]) and read.size() == 1, "a Repeat-count group fact reaches the closure (%d constraint)" % read.size())
	if read.size() == 1:
		var allowed: Array = (read[0]["allowed"] as Array).duplicate()
		allowed.sort()
		ok(allowed == same_count and same_count.size() < gh.star_count,
			"as 'this name is one of the %d stars with that count' (got %s, want %s)" % [same_count.size(), str(allowed), str(same_count)])
	var gpub = _beginner_puzzle(0, 11, false)

	print("\n=== the leak check bites: the old public-shape behaviour fails it ===")
	gpub._build_record_array()
	gpub._build_matrix()
	var old_rank_sets: int = 0
	for i in 200:
		gpub._rendered_terms = {}
		var c: Dictionary = gpub._build_form(25, {})
		if c.is_empty():
			continue
		for f in (c["solver_facts"] as Array):
			if str((f as Dictionary).get("kind", "")) == "value_in_set":
				old_rank_sets += 1
	ok(old_rank_sets > 0, "public-shape Firing Position clues DO carry rank sets (%d), which check 3 above would flag" % old_rank_sets)

	print("\n=== a 1:1 melody is untouched ===")
	var cd = load("res://constellation_data.gd").new()
	cd.player_seed = 11
	var def: Dictionary = cd.get_constellation_def(0)
	var sq: Array = []
	for i2 in range(int(def["star_count"])):
		sq.append(i2)
	var hard = PuzzleScript.new()
	hard.setup(int(def["star_count"]), def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	ok(not hard._repeats_hidden() and hard._repeat_ticks().is_empty(), "hard mode has no repeat notes and nothing hidden")
	ok(hard._repeat_notes_unique(), "so its repeat-note gate is trivially met")
	ok(not hard._gate_result_passes({"seq_unique": true, "name_unique": true, "name_unique_closure": true}),
		"the ship gate refuses a result that does not state repeat_unique")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
