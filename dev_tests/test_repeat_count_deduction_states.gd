extends "res://dev_tests/test_base.gd"
# Repeat Count — step 3 of the axis build order (see
# planned_repeat_count_axis_design.md): per-record repeat_states +
# group-CAPACITY elimination via the existing generic Axis/CLIQUE_AXES
# machinery (Axis.REPEAT added to constellation_puzzle_deduction.gd this
# step). No UI writes this yet -- records are marked directly here, exactly
# as a future Sort:RepeatCount checklist eventually would.
#
# What must hold, and why each case exists:
#  - A single record confirming a value must NOT immediately eliminate that
#    value from every other record's candidates -- Repeat Count is NOT
#    alldiff (most stars share 0), unlike Name. This is the exact mistake
#    the design doc's own "no alldiff cross-elimination" section warns
#    against, and the easiest way to get this wrong by copying Name's code.
#  - Group-CAPACITY elimination must fire once, and only once, enough
#    DIFFERENT (provably distinct) records confirm a value to account for
#    every star that truly holds it -- fewer confirmers than the true count
#    must change nothing anywhere else.
#  - Once eliminated everywhere but one value, a record must auto-promote
#    (singleton confirm) via the same _settle_singleton_for_axis rule every
#    other CLIQUE_AXES member already uses.
#  - Axis.REPEAT must actually be wired into CLIQUE_AXES / the propagation
#    fixpoint, not just have working dispatcher functions nobody calls.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame

	# 6 stars: three share repeat_count 0, two share 1, one is alone at 2.
	host._star_count = 6
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"]
	host._star_colors = [0, 1, 2, 3, 0, 1]
	host._star_degrees = [2, 2, 2, 2, 2, 2]
	host._repeat_count = [0, 0, 0, 1, 1, 2]
	var d = host._deduction

	ok(d.Axis.REPEAT in d.CLIQUE_AXES, "Axis.REPEAT is wired into CLIQUE_AXES")
	ok(d._repeat_count_star_count(0) == 3, "ground truth: 3 stars share repeat_count 0 (got %d)" % d._repeat_count_star_count(0))
	ok(d._repeat_count_star_count(1) == 2, "ground truth: 2 stars share repeat_count 1 (got %d)" % d._repeat_count_star_count(1))
	ok(d._repeat_count_star_count(2) == 1, "ground truth: 1 star has repeat_count 2 (got %d)" % d._repeat_count_star_count(2))

	# Four records, each with a DISTINCT confirmed Name -- Name is alldiff,
	# so distinctly-named records are trivially provably distinct from each
	# other, which is what the capacity rule needs to count a clique.
	var alpha: int = d._get_or_create_match_record_for_name("Alpha")
	var beta: int = d._get_or_create_match_record_for_name("Beta")
	var gamma: int = d._get_or_create_match_record_for_name("Gamma")
	var delta: int = d._get_or_create_match_record_for_name("Delta")

	print("=== a single confirm does NOT cross-eliminate (not alldiff) ===")
	d.record_at(alpha)["repeat_states"] = {0: 1}
	d._full_propagation_refresh()
	ok(d._effective_repeat_state(alpha, 0) == 1, "Alpha's own confirm of 0 reads back as confirmed")
	ok(d._effective_repeat_state(beta, 0) == 0, "Beta's candidate 0 is still neutral after only ONE confirmer (got %d)" % d._effective_repeat_state(beta, 0))
	ok(d._effective_repeat_state(gamma, 0) == 0, "Gamma's candidate 0 is still neutral too (got %d)" % d._effective_repeat_state(gamma, 0))
	ok(d._effective_repeat_state(delta, 0) == 0, "Delta (unrelated) sees no elimination yet (got %d)" % d._effective_repeat_state(delta, 0))

	print("\n=== a SECOND confirmer still isn't enough (2 of 3) ===")
	d.record_at(beta)["repeat_states"] = {0: 1}
	d._full_propagation_refresh()
	ok(d._effective_repeat_state(delta, 0) == 0, "clique size 2 < incidence 3 -- still no elimination anywhere (got %d)" % d._effective_repeat_state(delta, 0))

	print("\n=== the THIRD confirmer completes the clique -> capacity elimination fires ===")
	d.record_at(gamma)["repeat_states"] = {0: 1}
	d._full_propagation_refresh()
	ok(d._effective_repeat_state(delta, 0) == 2, "clique size 3 == incidence 3 -- Delta now has 0 ELIMINATED (got %d)" % d._effective_repeat_state(delta, 0))

	print("\n=== singleton promotion once only one candidate remains ===")
	# Delta's domain is {0,1,2}; 0 is now eliminated (derived, just proven).
	# Manually eliminate 2 as well (simulating an earlier, separate
	# deduction) so exactly one candidate -- 1 -- remains.
	var delta_states: Dictionary = d.record_at(delta).get("repeat_states", {})
	delta_states[2] = 2
	d.record_at(delta)["repeat_states"] = delta_states
	d._full_propagation_refresh()
	ok(d._effective_repeat_state(delta, 1) == 1, "Delta auto-confirms the one remaining candidate, 1 (got %d)" % d._effective_repeat_state(delta, 1))

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
