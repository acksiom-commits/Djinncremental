extends "res://dev_tests/test_base.gd"
# REDISTRIBUTE moves the CLICK multiplier's worth of Sparks, and nothing
# else scales it.
#
# The user's spec, given when the button was built: "subject to the
# Volumitions click-increase function but categorically NOT subject to the
# 'multi-selector' buttons, which are ONLY for assigning automation
# resources - currently foci and volitions, but eventually sufficiently
# leveled Uonites."
#
# Reported 2026-08-27: "isn't going by the Volitions amount. I think it's
# using the Foci assigned to endowment." It was. The amount was
# `get_constellation_points(id) * get_click_multiplier()`, and
# get_constellation_points sums that constellation's assigned foci +
# volitions + bonus volitions — the multi-selector allocation exactly. The
# function's own doc comment described the correct rule while the line
# below it did something else, so reading the header would not have caught
# it either.
#
# THE TWO NUMBERS ARE DELIBERATELY DIFFERENT AND COPRIME-ISH BELOW. With
# click=3 and points=7 the bug yields 21, the fix yields 3, and a mistake
# that returns the points instead yields 7 — three distinguishable
# outcomes, so a wrong answer names its own cause instead of just failing.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var gc = load("res://game_context.gd").new()
	root.add_child(gc)
	await process_frame

	# click multiplier = 1 + 2 = 3
	gc.assignments["click_volitions"] = 2
	# assigned points on constellation 0 = 4 + 2 + 1 = 7
	gc.assignments["constellation_0_foci"] = 4
	gc.assignments["constellation_0_volitions"] = 2
	gc.assignments["constellation_0_bonus_volitions"] = 1
	gc.sparks = BigNum.from_int(1000)
	gc.constellation_spark_totals = {}

	var click: int = gc.get_click_multiplier()
	var points: int = gc.get_constellation_points(0)
	print("  click multiplier %d, assigned points %d" % [click, points])
	ok(click == 3, "precondition: click multiplier is 3 (got %d)" % click)
	ok(points == 7, "precondition: assigned points is 7 (got %d)" % points)
	ok(click != points, "precondition: the two differ, so the test can tell them apart")

	var moved: float = gc.endow_constellation_sparks_manual(0)
	print("  redistribute moved %s" % str(moved))
	ok(is_equal_approx(moved, float(click)),
		"one press moves the CLICK multiplier (%d), not points*click (%d) nor points (%d) — got %s"
			% [click, points * click, points, str(moved)])
	ok(is_equal_approx(gc.constellation_spark_totals.get("0", 0.0), float(click)),
		"and that much landed on the constellation (got %s)"
			% str(gc.constellation_spark_totals.get("0", 0.0)))
	ok(gc.sparks.to_float() == 1000.0 - float(click),
		"and left the pool (got %s, want %s)"
			% [str(gc.sparks.to_float()), str(1000.0 - float(click))])

	# UNASSIGNED CONSTELLATION still works. The old code needed a floor of 1
	# because points could be 0 and zero out the product; the click
	# multiplier is 1 + volitions and cannot be below 1, so no floor is
	# needed — but the behaviour it protected still has to hold.
	gc.assignments["constellation_1_foci"] = 0
	gc.assignments["constellation_1_volitions"] = 0
	gc.assignments["constellation_1_bonus_volitions"] = 0
	var moved1: float = gc.endow_constellation_sparks_manual(1)
	print("  unassigned constellation moved %s (points %d)" % [str(moved1), gc.get_constellation_points(1)])
	ok(gc.get_constellation_points(1) == 0, "precondition: constellation 1 has nothing assigned")
	ok(is_equal_approx(moved1, float(click)),
		"a constellation with NO assignment still redistributes the full click amount (got %s)"
			% str(moved1))

	# Out of Sparks is a no-op, not a negative pool.
	gc.sparks = BigNum.from_int(0)
	ok(gc.endow_constellation_sparks_manual(0) == 0.0,
		"no Sparks means no transfer")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
