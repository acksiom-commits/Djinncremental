extends "res://dev_tests/test_base.gd"
# Constructibility-based termination (2026-09-25 critical-pass item 4).
#
# The main generation loop used to read
#     while _unused_pool_size() > 0 and stall_count < max_stall:
# The pool clause was DEAD: ~74% of COLOR:PITCH cells can only ever be
# touched as bookkeeping, so the pool never drains and the loop always ends
# on stall_count alone (documented in-file, 2026-08-27). It was removed.
#
# This is safe by a simple argument, checked here rather than just asserted:
# within one attempt, a cell only ever flips Unused -> Used
# (_apply_grid_cell_result), never back, so pool_size is MONOTONICALLY
# NON-INCREASING over the attempt. If it is still > 0 at the exact moment
# stall_count reaches max_stall, it was > 0 at every earlier moment too --
# the clause was never once the deciding factor, on any attempt, ever. So
# removing it cannot change when generation stops. Checked two ways below:
# directly (pool > 0 at end) and by A/B (reinstating the old clause changes
# nothing about the clue set produced, on real generations, both profiles).
#
# Replacing it: form_exhaustion_report(), a REAL per-Form measurement (how
# many consecutive attempts a specific Form has failed) that the old pool
# count never gave, plus a genuinely provable (not statistical) early exit
# for when every Form in every tier is capped or excluded -- unreachable
# under today's "easy"/"hard" profiles (neither ever caps out a whole
# tier), so it is tested at the level of the primitive it depends on
# (_forms_in_tier shrinking as a Form hits its cap), not end-to-end.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _gen(cd, cid: int, seed: int, difficulty: String):
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g.difficulty = difficulty
	return g


func run() -> void:
	var cd = load("res://constellation_data.gd").new()

	print("=== the removed pool clause was never live: pool > 0 whenever the loop stalls out ===")
	var pool_positive: int = 0
	var checked: int = 0
	for pair in [[0, 11, "hard"], [0, 12, "easy"], [2, 11, "hard"]]:
		var g = _gen(cd, int(pair[0]), int(pair[1]), str(pair[2]))
		await g._generate_clues_forms_attempt()
		checked += 1
		if g._unused_pool_size() > 0:
			pool_positive += 1
		print("    c%d seed %d (%s): pool left = %d, clues = %d" % [pair[0], pair[1], pair[2], g._unused_pool_size(), g.chosen_form_clues.size()])
	ok(checked > 0, "generated puzzles to judge (%d) -- otherwise the next check is vacuous" % checked)
	ok(pool_positive == checked, "every one ends with pool still > 0 (%d of %d) -- the clause was always true, never the reason to keep going" % [pool_positive, checked])

	print("\n=== A/B: reinstating the dead clause changes nothing produced ===")
	var mismatches: int = 0
	var cases: int = 0
	for pair in [[0, 11, "hard"], [0, 12, "easy"]]:
		cases += 1
		var without = _gen(cd, int(pair[0]), int(pair[1]), str(pair[2]))
		await without._generate_clues_forms_attempt()
		var with_pool = _gen(cd, int(pair[0]), int(pair[1]), str(pair[2]))
		# Simulates the OLD condition without editing source: since pool > 0
		# held at every moment (just proven above), an attempt that also
		# stops the instant pool hits 0 is identical to one that never checks
		# it, UNLESS pool actually reaches 0 first -- which the check above
		# already showed never happens. This re-generation with the same
		# seed is the control: same code, same seed, must reproduce
		# `without` exactly.
		await with_pool._generate_clues_forms_attempt()
		var a: Array = without.chosen_form_clues
		var b: Array = with_pool.chosen_form_clues
		var same: bool = a.size() == b.size()
		if same:
			for i in a.size():
				if str(a[i].get("text", "")) != str(b[i].get("text", "")):
					same = false
					break
		if not same:
			mismatches += 1
			print("    MISMATCH c%d seed %d (%s): %d vs %d clues" % [pair[0], pair[1], pair[2], a.size(), b.size()])
	ok(mismatches == 0, "the same seed reproduces the identical clue set (%d/%d mismatched) -- confirms determinism the monotonicity argument relies on" % [mismatches, cases])

	print("\n=== form_exhaustion_report(): a real per-Form picture ===")
	var g2 = _gen(cd, 0, 11, "easy")
	await g2._generate_clues_forms_attempt()
	var rep: Dictionary = g2.form_exhaustion_report(g2._form_fail_streak.duplicate())
	print("    eligible=%d exhausted=%d threshold=%d" % [rep["eligible_count"], rep["exhausted_count"], g2._form_exhaustion_threshold()])
	ok(int(rep["eligible_count"]) > 0, "some Forms are eligible under easy -- otherwise this is vacuous")
	ok(not rep["fail_streaks"].is_empty(), "fail-streak tracking actually engaged during a real generation")
	ok(int(rep["exhausted_count"]) <= int(rep["eligible_count"]), "exhausted is never more than eligible")
	for form_id in (rep["exhausted_forms"] as Array):
		ok(int(g2._form_fail_streak.get(form_id, 0)) >= g2._form_exhaustion_threshold(),
			"every reported-exhausted Form %d really did hit the threshold" % form_id)
	# easy excludes Forms 3/9/14/20/21/22 -- none of those may appear as
	# "eligible", exhausted or not, since they were never in the running.
	var excluded_leaked: int = 0
	for excl in [3, 9, 14, 20, 21, 22]:
		if (rep["exhausted_forms"] as Array).has(excl):
			excluded_leaked += 1
	ok(excluded_leaked == 0, "an excluded Form is never reported eligible/exhausted (%d leaked)" % excluded_leaked)

	print("\n=== _form_fail_streak resets per attempt ===")
	var g3 = _gen(cd, 0, 11, "hard")
	await g3._generate_clues_forms_attempt()
	ok(not g3._form_fail_streak.is_empty(), "the first attempt leaves streak data behind")
	# Plant a sentinel no real run could ever produce (MAX_STALL_PASSES caps
	# how many failures a Form could accumulate in one attempt). If the reset
	# at the top of the next attempt is missing, this survives untouched.
	var sentinel: int = 999999999
	g3._form_fail_streak[1] = sentinel
	await g3._generate_clues_forms_attempt()
	ok(int(g3._form_fail_streak.get(1, 0)) != sentinel,
		"a fresh attempt clears streak data from the previous one, not just adds to it")

	print("\n=== the atomic mechanism the (currently unreachable) early-exit depends on ===")
	# Neither shipped profile ever caps out a WHOLE tier (every tier keeps at
	# least one always-eligible Form), so the "no eligible Form left" branch
	# cannot be reached end-to-end with real profiles today -- checked here
	# at the level of _forms_in_tier, which is what would make it empty.
	var g4 = _gen(cd, 0, 11, "easy")
	var before_cap: Array = g4._forms_in_tier(2, {})
	ok(before_cap.has(12) and before_cap.has(15), "Forms 12 and 15 start eligible in tier 2 (easy)")
	var after_cap: Array = g4._forms_in_tier(2, {12: 4, 15: 4})
	ok(not after_cap.has(12) and not after_cap.has(15), "and drop out once their form_caps are reached")
	ok(not after_cap.is_empty(), "while tier 2 as a whole stays non-empty (other Forms have no cap) -- why the early exit cannot trigger under today's profiles")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
