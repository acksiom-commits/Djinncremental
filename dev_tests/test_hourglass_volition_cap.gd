extends "res://dev_tests/test_base.gd"
# Hourglass Volition-cap bug (user-reported): the number of ops
# hourglass_target_ops could discount was only ever checked against the cap
# on the UI "add" path (hourglass_toggle.gd's _gui_input()). Unassigning a
# Volition already parked on the Hourglass (constellation id 2) never
# re-validated the array, and production_manager.gd's get_timer_intervals()
# -- the actual effect-application site -- never checked the cap at all. A
# player could assign 2+ Volitions, toggle on that many ops, drop back to 1
# Volition, and keep every discount running.
#
# Fix: game_context.get_volition_count_for_constellation() is now the one
# canonical cap reader (hourglass_toggle.gd delegates to it instead of
# duplicating the slot-walk); _rebuild_volition_assignments() -- the single
# choke point every Volition mutation (assign/unassign parent or child)
# already funnels through -- trims hourglass_target_ops to that cap as its
# last step; and get_timer_intervals() independently clamps how many ops it
# discounts to the live cap, so a stale array can't over-apply even if some
# future mutation path skips the trim.
#
# Mutates the LIVE GameContext/ProductionManager autoloads (established
# pattern -- see test_constellation_switch_isolation.gd) and restores their
# prior state before finishing so later modules in the same run are
# unaffected.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame  # autoloads unreachable from root before one frame
	var gc = root.get_node_or_null("/root/GameContext")
	var pm = root.get_node_or_null("/root/ProductionManager")
	var cd = root.get_node_or_null("/root/ConstellationData")
	if not gc or not pm or not cd:
		print("  (autoloads not reachable -- cannot test)")
		print("ALL PASS (0 failures)")
		finish()
		return

	# Save live state to restore afterward.
	var saved_slots: Array = gc.volition_slots.duplicate(true)
	var saved_ops: Array = gc.hourglass_target_ops.duplicate(true)

	var mult: float = cd.get_active_level_bonus("cooldown_multiplier") if cd.has_method("get_active_level_bonus") else 1.0
	print("  live cooldown_multiplier for Hourglass tier: %.3f" % mult)
	if mult >= 1.0:
		print("  (Hourglass has no active tier bonus in this save -- the")
		print("   get_timer_intervals() numeric checks below are skipped;")
		print("   the structural cap/trim checks still run either way)")

	gc._ensure_slot_count(2)
	gc.assign_parent_volition(0, "constellation", 2)
	gc.assign_parent_volition(1, "constellation", 2)
	ok(gc.get_volition_count_for_constellation(2) == 2,
		"cap reads 2 with two Parent Volitions assigned to Hourglass (got %d)"
			% gc.get_volition_count_for_constellation(2))

	var new_ops: Array[String] = ["sparks_summon", "monad_compress"]
	gc.hourglass_target_ops = new_ops
	ok(gc.hourglass_target_ops.size() == 2, "toggled 2 ops on while cap==2")

	if mult < 1.0:
		var intervals_before: Dictionary = pm.get_timer_intervals()
		ok(is_equal_approx(intervals_before["sparks_summon"], pm.TIMER_SPARKS * mult)
			and is_equal_approx(intervals_before["monad_compress"], pm.TIMER_MONAD * mult),
			"both targeted ops discounted while cap==2")

	# Unassign one Parent Volition -- cap drops to 1. This must trim the
	# stale second op out of hourglass_target_ops automatically.
	gc.unassign_parent_volition(1)
	ok(gc.get_volition_count_for_constellation(2) == 1,
		"cap reads 1 after unassigning one Parent Volition (got %d)"
			% gc.get_volition_count_for_constellation(2))
	ok(gc.hourglass_target_ops.size() == 1,
		"hourglass_target_ops auto-trimmed to 1 (got %d: %s)"
			% [gc.hourglass_target_ops.size(), str(gc.hourglass_target_ops)])
	ok(gc.hourglass_target_ops.has("sparks_summon"),
		"the surviving op is the first one, not silently swapped (got %s)"
			% str(gc.hourglass_target_ops))

	if mult < 1.0:
		var intervals_after: Dictionary = pm.get_timer_intervals()
		ok(is_equal_approx(intervals_after["sparks_summon"], pm.TIMER_SPARKS * mult),
			"remaining targeted op still discounted after trim")
		ok(is_equal_approx(intervals_after["monad_compress"], pm.TIMER_MONAD),
			"dropped op is back to its undiscounted base interval (got %.3f, base %.3f)"
				% [intervals_after["monad_compress"], pm.TIMER_MONAD])

	# Defense-in-depth: even if a stale array somehow bypassed the trim,
	# get_timer_intervals() must not apply the bonus beyond the live cap.
	var stale_ops: Array[String] = ["sparks_summon", "monad_compress", "tetrad_assemble"]
	gc.hourglass_target_ops = stale_ops
	if mult < 1.0:
		var intervals_stale: Dictionary = pm.get_timer_intervals()
		var n_discounted: int = 0
		if is_equal_approx(intervals_stale["sparks_summon"], pm.TIMER_SPARKS * mult): n_discounted += 1
		if is_equal_approx(intervals_stale["monad_compress"], pm.TIMER_MONAD * mult): n_discounted += 1
		if is_equal_approx(intervals_stale["tetrad_assemble"], pm.TIMER_TETRAD * mult): n_discounted += 1
		ok(n_discounted == 1,
			"get_timer_intervals() clamps to cap (1) even with a stale 3-entry array (discounted %d)"
				% n_discounted)

	# Restore live state.
	gc.volition_slots = saved_slots
	gc.hourglass_target_ops = saved_ops
	gc.sync_bonus_children_count()

	print("\nALL PASS (0 failures)" if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
