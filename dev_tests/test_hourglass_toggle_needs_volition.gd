extends "res://dev_tests/test_base.gd"
# The Hourglass mini-icons on the genbars (2026-10-19, author): once the
# Hourglass puzzle is solved they show only while a Volition is assigned to
# the Hourglass. With none, the Hourglass directs nothing and the icons stay
# hidden; they used to show from the solve on, Volition or not.
#
# Drives the real HourglassToggle against the live GameContext and restores the
# two assignment keys it touches.

const ToggleScene = preload("res://HourglassToggle.tscn")
const SOLVE_KEY := "constellation_2_solve_count"
const VOL_KEY := "constellation_2_volitions"
# The count reads Parent + Child (bonus) Volitions; an earlier module in the
# same run can leave a Child one on the Hourglass, so this test owns both keys.
const BONUS_KEY := "constellation_2_bonus_volitions"

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _assign(gc, key: String, v: int) -> void:
	gc.assignments[key] = v


func run() -> void:
	await process_frame
	var gc = root.get_node("GameContext")
	var had_solve = gc.assignments.get(SOLVE_KEY, null)
	var had_vol = gc.assignments.get(VOL_KEY, null)
	var had_bonus = gc.assignments.get(BONUS_KEY, null)
	gc.assignments[BONUS_KEY] = 0
	var had_ops: Array[String] = gc.hourglass_target_ops.duplicate()

	var row := HBoxContainer.new()
	root.add_child(row)
	var t = ToggleScene.instantiate()
	t.operation_key = "monad_compress"
	row.add_child(t)
	await process_frame

	_assign(gc, SOLVE_KEY, 1)
	_assign(gc, VOL_KEY, 0)
	t._on_game_loaded(0.0)
	t._process(0.0)
	ok(not t.visible, "solved, no Volition on the Hourglass: hidden")

	_assign(gc, VOL_KEY, 1)
	t._process(0.0)
	ok(t.visible, "solved, a Volition assigned: shown")

	_assign(gc, SOLVE_KEY, 0)
	t._process(0.0)
	ok(not t.visible, "a Volition but the puzzle unsolved: hidden")

	_assign(gc, SOLVE_KEY, 1)
	t._process(0.0)
	_assign(gc, VOL_KEY, 0)
	t._process(0.0)
	ok(not t.visible, "the Volition taken off again: hidden")

	if had_solve == null:
		gc.assignments.erase(SOLVE_KEY)
	else:
		gc.assignments[SOLVE_KEY] = had_solve
	if had_vol == null:
		gc.assignments.erase(VOL_KEY)
	else:
		gc.assignments[VOL_KEY] = had_vol
	if had_bonus == null:
		gc.assignments.erase(BONUS_KEY)
	else:
		gc.assignments[BONUS_KEY] = had_bonus
	gc.hourglass_target_ops = had_ops
	row.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
