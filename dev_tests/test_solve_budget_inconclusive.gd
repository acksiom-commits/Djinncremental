extends "res://dev_tests/test_base.gd"
# The solver's node budget must never turn an unfinished search into a "unique"
# verdict.
#
# _backtrack_fc stops when MAX_BACKTRACK_NODES runs out and returns whatever it
# had found. Found 1 used to read as UNIQUE and ship as proven although the
# search never finished. _solve now reports _last_solve_inconclusive, and the
# property that makes it trustworthy is checked here directly, across a sweep
# of budgets from starvation to plenty:
#
#   (a) a conclusive solve returns min(true_count, cap) solutions -- exactly
#       what a finished search would;
#   (b) an inconclusive solve is flagged whenever it returned fewer than that.
#
# i.e. NEVER "fewer solutions than exist, yet reported conclusive".

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _puzzle(n: int):
	var g = PuzzleScript.new()
	g.star_count = n
	return g


func _cmp(a: int, b: int) -> Dictionary:
	return {"kind": "ordinal_cmp", "a": a, "b": b, "a_gt_b": false}   # a fires before b


func _typed(facts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in facts:
		out.append(f)
	return out


func _sweep(name: String, n: int, facts: Array, cap: int) -> void:
	var g = _puzzle(n)
	var typed: Array[Dictionary] = _typed(facts)
	g.backtrack_node_budget = 1000000
	var full: Array = g._solve(typed, 1000)
	var true_count: int = full.size()
	var expected: int = mini(true_count, cap)
	var conclusive: int = 0
	var inconclusive: int = 0
	var lying: int = 0        # fewer than a finished search, yet reported conclusive
	var wrong_count: int = 0  # conclusive but not the finished-search answer
	for budget in range(1, 121):
		g.backtrack_node_budget = budget
		var sols: Array = g._solve(typed, cap)
		if g._last_solve_inconclusive:
			inconclusive += 1
		else:
			conclusive += 1
			if sols.size() != expected:
				wrong_count += 1
		if sols.size() < expected and not g._last_solve_inconclusive:
			lying += 1
	print("    %s: %d true solutions, cap %d -> %d conclusive / %d inconclusive over 120 budgets"
		% [name, true_count, cap, conclusive, inconclusive])
	ok(true_count >= 2, "%s: fixture has several solutions (%d) so a cut-off search can find just one" % [name, true_count])
	ok(inconclusive > 0 and conclusive > 0,
		"%s: the sweep covers BOTH regimes (%d inconclusive, %d conclusive) -- otherwise it proves nothing" % [name, inconclusive, conclusive])
	ok(lying == 0, "%s: never fewer solutions than exist while reporting conclusive (%d lies)" % [name, lying])
	ok(wrong_count == 0, "%s: every conclusive solve returns exactly what a finished search does (%d wrong)" % [name, wrong_count])


func run() -> void:
	print("=== budget sweep: a cut-off search is never reported conclusive ===")
	# 0<1<2<3 and star 4 anywhere: five solutions.
	_sweep("chain+free", 5, [_cmp(0, 1), _cmp(1, 2), _cmp(2, 3)], 10)
	# Two independent pairs: several solutions among six stars.
	_sweep("two pairs", 6, [_cmp(0, 1), _cmp(2, 3)], 8)
	# cap 2 is what the ship gate actually uses.
	_sweep("gate cap", 5, [_cmp(0, 1), _cmp(1, 2), _cmp(2, 3)], 2)

	print("\n=== the exact bug: one solution found, search unfinished ===")
	var g = _puzzle(5)
	var typed: Array[Dictionary] = _typed([_cmp(0, 1), _cmp(1, 2), _cmp(2, 3)])
	var hit_one: bool = false
	var one_reported_unique: bool = false
	for budget in range(1, 121):
		g.backtrack_node_budget = budget
		var sols: Array = g._solve(typed, 2)
		if sols.size() == 1:
			hit_one = true
			if not g._last_solve_inconclusive:
				one_reported_unique = true
	ok(hit_one, "some budget yields exactly ONE solution from a puzzle with five (the false-unique shape)")
	ok(not one_reported_unique, "and every such result is flagged inconclusive, never read as unique")

	print("\n=== a genuinely unique puzzle is still conclusive ===")
	var u = _puzzle(4)
	var utyped: Array[Dictionary] = _typed([_cmp(0, 1), _cmp(1, 2), _cmp(2, 3)])
	var usols: Array = u._solve(utyped, 2)
	ok(usols.size() == 1 and not u._last_solve_inconclusive, "one solution, search finished: conclusive")
	ok(u.inconclusive_solves == 0, "and nothing was counted as inconclusive")

	print("\n=== the verdict is per-solve, not sticky ===")
	var s = _puzzle(5)
	s.backtrack_node_budget = 1
	s._solve(_typed([_cmp(0, 1), _cmp(1, 2), _cmp(2, 3)]), 2)
	var was_flagged: bool = s._last_solve_inconclusive
	s.backtrack_node_budget = 100000
	s._solve(_typed([_cmp(0, 1), _cmp(1, 2), _cmp(2, 3), _cmp(3, 4)]), 2)
	ok(was_flagged and not s._last_solve_inconclusive, "an inconclusive solve does not poison the next one")
	ok(s.inconclusive_solves >= 1, "the running count recorded it (%d)" % s.inconclusive_solves)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
