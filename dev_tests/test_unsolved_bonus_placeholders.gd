extends "res://dev_tests/test_base.gd"
# Constellation Slideout info panel (author 2026-10-29): an unsolved
# constellation's "Effects by Tier:" block -- the header and its "??? (puzzle
# unsolved)" line, plus the separator above it -- stays HIDDEN until The
# Archon (constellation 0) has been solved once. After that it shows as
# before. A solved constellation's real ladder is never hidden by the gate.
#
# InfoBonusLabel also carries "??? (puzzle unsolved)" text but is hidden in
# the scene and never shown; checked here so it stays that way.
#
# Judged on constellation 1 (The Spark) unsolved, across the Archon gate, and
# on constellation 0 itself before and after its first solve.

const PopoutScene = preload("res://ConstellationPopout.tscn")
const ARCHON_KEY := "constellation_0_solve_count"
const SPARK_KEY := "constellation_1_solve_count"

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## [block shown, its text]; also fails the run if InfoBonusLabel ever shows.
func _block(p) -> Array:
	p._refresh_info_panel()
	if p._info_bonus_label.visible:
		ok(false, "InfoBonusLabel stays hidden (it is hidden in the scene)")
	var shown: bool = p._info_tier_effects.visible and p._info_tier_effects_sep.visible
	return [shown, str(p._info_tier_effects.text) if p._info_tier_effects.visible else ""]


func run() -> void:
	await process_frame   # autoloads are unreachable until one frame has passed
	var gc = root.get_node_or_null("/root/GameContext")
	var cd = root.get_node_or_null("/root/ConstellationData")
	if gc == null or cd == null:
		ok(false, "autoloads reachable -- otherwise every check below is vacuous")
		finish()
		return
	var p = PopoutScene.instantiate()
	root.add_child(p)
	await process_frame
	var saved_unlocked = cd.unlocked.duplicate()
	var saved_assign = gc.assignments.duplicate(true)
	cd.unlocked = [0, 1]
	p._build_slots()
	await process_frame
	ok(p._slot_grid.visible, "precondition: the slot grid is showing")

	# The Spark, unsolved, while The Archon has never been solved.
	gc.assignments[ARCHON_KEY] = 0
	gc.assignments[SPARK_KEY] = 0
	p._selected_slot = 1
	var b: Array = _block(p)
	ok(p._info_vbox.visible, "precondition: the info panel is showing for The Spark")
	ok(not b[0] and not p._info_tier_effects.visible and not p._info_tier_effects_sep.visible,
		"Archon unsolved: The Spark shows no 'Effects by Tier' block, line or separator")

	# The Archon itself, unsolved.
	p._selected_slot = 0
	b = _block(p)
	ok(not p._info_tier_effects.visible, "The Archon's own panel hides the block before its first solve")

	# Solve The Archon once: its real ladder shows, and The Spark's placeholder returns.
	gc.assignments[ARCHON_KEY] = 1
	b = _block(p)
	ok(b[0] and str(b[1]).contains("Effects by Tier") and not str(b[1]).contains("???"),
		"Archon solved: its own block shows its real ladder")
	p._selected_slot = 1
	b = _block(p)
	ok(b[0] and str(b[1]).contains("Effects by Tier:") and str(b[1]).contains("??? (puzzle unsolved)"),
		"Archon solved: The Spark shows 'Effects by Tier:' and '??? (puzzle unsolved)' again")

	# A solved constellation is never hidden by the gate, even with the
	# Archon count at 0 (a hand-edited save, or any future ordering).
	gc.assignments[ARCHON_KEY] = 0
	gc.assignments[SPARK_KEY] = 1
	b = _block(p)
	ok(b[0] and not str(b[1]).contains("???"),
		"a solved Spark shows its real ladder whatever the Archon's count")

	gc.assignments = saved_assign
	cd.unlocked = saved_unlocked
	p.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
