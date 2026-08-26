extends "res://dev_tests/test_base.gd"
# The 2nd Volition must not arrive before the dialogue that introduces it.
#
# INTENDED ORDER: all 15 Tetrad varieties -> first Particle ->
# enqueue_first_particle() ("Two Volitions!"). root_ui gates the Particle
# trigger on all_tetrads_done specifically so that dialogue queues first.
#
# WHAT BREAKS IT: _check_volition_grant() grants Volitions purely on
# archon_foci crossing 5 / 25 / 125, with no reference to that chain. The
# "All Monads - 100 of each type created: +1 Focus" award can push Foci to
# 25 while the randomiser still has not rolled every variety, so Volition
# #2 lands silently, unexplained. Rare compositions (4-of-a-kind, the 3+1
# medials) can go a very long time unseen on pure chance.
#
# THE FIX UNDER TEST: production_manager forces any still-unseen variety
# once the minimum monad total reaches TUTORIAL_FORCE_MIN_MONADS, and
# forces ALL remaining by TUTORIAL_FORCE_DEADLINE_MONADS -- both strictly
# below the 100 that triggers the Focus.
#
# Checks here are on the BACKSTOP's own guarantees, not on the dialogue
# system: that the composition table is a true inverse of _resolve_tetrad,
# that nothing fires early, that the deadline completes the set, and that
# forced varieties are paid for rather than conjured.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_pm():
	var gc = load("res://game_context.gd").new()
	var pm = load("res://production_manager.gd").new()
	pm.gc = gc
	return pm


## Give the context enough monads/sparks that affordability is never the
## thing under test, and set the three monad totals to `monads`.
func _seed(pm, monads: int) -> void:
	var gc = pm.gc
	gc.sparks = BigNum.from_int(10000)
	gc.monad["solid"]  = BigNum.from_int(500)
	gc.monad["liquid"] = BigNum.from_int(500)
	gc.monad["gas"]    = BigNum.from_int(500)
	for k in ["monad_solid", "monad_liquid", "monad_gas"]:
		gc.totals_created[k] = BigNum.from_int(monads)


func run() -> void:
	var pm = _make_pm()

	# ── the table is a real inverse, not a hand-copied guess ─────────────
	print("=== composition table inverts _resolve_tetrad ===")
	var mismatches: int = 0
	for key in pm.TETRAD_COMPOSITIONS:
		var c: Array = pm.TETRAD_COMPOSITIONS[key]
		if pm._resolve_tetrad(int(c[0]), int(c[1]), int(c[2])) != key:
			mismatches += 1
	ok(pm.TETRAD_COMPOSITIONS.size() == 15,
		"all 15 varieties are in the table (%d)" % pm.TETRAD_COMPOSITIONS.size())
	ok(mismatches == 0,
		"every composition resolves back to its own variety (%d mismatches)" % mismatches)

	# ── nothing fires before the window ──────────────────────────────────
	print("\n=== silent below the window ===")
	_seed(pm, pm.TUTORIAL_FORCE_MIN_MONADS - 1)
	ok(pm._missing_tetrad_varieties().size() == 15,
		"a fresh context is missing all 15 (%d)" % pm._missing_tetrad_varieties().size())
	ok(pm._force_missing_tetrad_varieties() == 0,
		"forces nothing at %d monads" % (pm.TUTORIAL_FORCE_MIN_MONADS - 1))

	# ── inside the window it trickles, one per call ──────────────────────
	print("\n=== trickles inside the window ===")
	_seed(pm, pm.TUTORIAL_FORCE_MIN_MONADS)
	var first: int = pm._force_missing_tetrad_varieties()
	ok(first == 1, "exactly one variety forced per call inside the window (%d)" % first)
	ok(pm._missing_tetrad_varieties().size() == 14,
		"and the set shrank by one (%d missing)" % pm._missing_tetrad_varieties().size())

	# ── the deadline completes the set in one go ─────────────────────────
	# A large production batch can jump the whole window in a single tick,
	# so the trickle alone is not a guarantee -- this is what makes it one.
	print("\n=== deadline completes the set ===")
	var pm2 = _make_pm()
	_seed(pm2, pm2.TUTORIAL_FORCE_DEADLINE_MONADS)
	var forced: int = pm2._force_missing_tetrad_varieties()
	ok(forced == 15, "all 15 forced at the deadline in one call (%d)" % forced)
	ok(pm2._missing_tetrad_varieties().is_empty(),
		"no variety left unseen (%d)" % pm2._missing_tetrad_varieties().size())
	ok(pm2.TUTORIAL_FORCE_DEADLINE_MONADS < 100,
		"the deadline (%d) is below the 100-of-each Focus award that races it"
			% pm2.TUTORIAL_FORCE_DEADLINE_MONADS)

	# ── forced varieties are PAID FOR, not conjured ──────────────────────
	print("\n=== forcing costs resources ===")
	var pm3 = _make_pm()
	_seed(pm3, pm3.TUTORIAL_FORCE_DEADLINE_MONADS)
	var sparks_before: int = pm3.gc.sparks.to_int()
	var monads_before: int = pm3.gc.monad["solid"].to_int() \
		+ pm3.gc.monad["liquid"].to_int() + pm3.gc.monad["gas"].to_int()
	var n: int = pm3._force_missing_tetrad_varieties()
	var sparks_spent: int = sparks_before - pm3.gc.sparks.to_int()
	var monads_spent: int = monads_before - (pm3.gc.monad["solid"].to_int() \
		+ pm3.gc.monad["liquid"].to_int() + pm3.gc.monad["gas"].to_int())
	print("  forced %d, spent %d sparks and %d monads" % [n, sparks_spent, monads_spent])
	ok(sparks_spent == n, "one Spark per forced variety (%d for %d)" % [sparks_spent, n])
	ok(monads_spent == n * 4, "four Monads per forced variety (%d for %d)" % [monads_spent, n])

	# ── never re-fires once the set is complete ──────────────────────────
	print("\n=== inert once complete ===")
	ok(pm3._force_missing_tetrad_varieties() == 0,
		"forces nothing more once every variety exists")

	# ── cannot spend monads it does not have ─────────────────────────────
	# adaemant needs 4 solid; with 3 there is no way to make it, and the
	# backstop must skip rather than go negative.
	print("\n=== respects affordability ===")
	var pm4 = _make_pm()
	_seed(pm4, pm4.TUTORIAL_FORCE_DEADLINE_MONADS)
	pm4.gc.monad["solid"]  = BigNum.from_int(3)
	pm4.gc.monad["liquid"] = BigNum.zero()
	pm4.gc.monad["gas"]    = BigNum.zero()
	pm4._force_missing_tetrad_varieties()
	ok(pm4.gc.monad["solid"].to_int() >= 0 and pm4.gc.monad["liquid"].to_int() >= 0
			and pm4.gc.monad["gas"].to_int() >= 0,
		"no monad pool driven negative (s=%d l=%d g=%d)" % [
			pm4.gc.monad["solid"].to_int(), pm4.gc.monad["liquid"].to_int(),
			pm4.gc.monad["gas"].to_int()])

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
