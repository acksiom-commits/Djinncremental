extends "res://dev_tests/test_base.gd"
# Resetting a solved puzzle to enjoy another version must not switch off the
# Constellation's effect (reported 2026-11-01). RESET erased
# "constellation_N_solve_count", which every effect reads as "earned", because
# the click puzzle reads the same count as "already done" and would not open.
#
#  1. A solved Constellation's effect works before a reset and after one.
#  2. The new version is still playable, and that survives a save.
#  3. Solving it leaves the Constellation solved, and shut until the next reset.
#  4. Resetting a puzzle never solved does not mark it as anything.

const CID: int = 2   # The Hourglass: its effect is cooldown_multiplier, < 1 when on
const BONUS: String = "cooldown_multiplier"
const FRAME_CAP: int = 6000

var fails: int = 0


## root_ui.gd without its scene: RootUI.tscn will not instantiate headless.
class TestRoot extends "res://root_ui.gd":
	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _input(_event: InputEvent) -> void:
		pass

	func _unhandled_input(_event: InputEvent) -> void:
		pass


## Stands in for ConstellationOverlay, which _generate_puzzle asks for the melody.
class FakeOverlay extends Node:
	var seq: Array = []

	func get_correct_star_sequence(_cid: int) -> Array:
		return seq


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _stop_builds(ui) -> void:
	var builds = ui.get("_puzzle_builds")
	if builds == null:
		return
	for b in builds.values():
		b.abort_requested = true
	var frames: int = 0
	while frames < FRAME_CAP and not builds.is_empty():
		await process_frame
		frames += 1


func run() -> void:
	await process_frame
	var cd = root.get_node("ConstellationData")
	var gc = root.get_node("GameContext")
	var cd_saved: Dictionary = cd.get_save_data()
	var solve_key: String = "constellation_%d_solve_count" % CID
	var vol_key: String = "constellation_%d_volitions" % CID
	var octant_was: int = cd.active_per_octant[0]
	var unlock_was: bool = bool(gc.ui_unlocks.get("constellation", false))
	var sparks_was = gc.constellation_spark_totals.get(str(CID), 0.0)

	cd._unlock_constellation(CID)
	cd.active_per_octant[0] = CID
	gc.ui_unlocks["constellation"] = true
	gc.constellation_spark_totals[str(CID)] = cd.SPARKS_TIER_STARS
	gc.assignments[vol_key] = 1
	gc.assignments[solve_key] = 1

	var holder := Node.new()
	root.add_child(holder)
	var ui = TestRoot.new()
	ui.name = "RootUI"
	ui.game_context = gc
	holder.add_child(ui)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(CID, cd, gc)
	eng._redraw_cb = func() -> void:
		pass
	var ov := FakeOverlay.new()
	ov.name = "ConstellationOverlay"
	ov.seq = eng.get_correct_star_sequence(CID)
	holder.add_child(ov)

	print("=== 1. the effect outlasts a reset ===")
	var before: float = cd.get_active_level_bonus(BONUS)
	ok(before < 1.0, "solved and active, the effect is on (%.3f)" % before)
	eng.check_availability()
	ok(eng.state == eng.State.IDLE, "a solved puzzle is shut")
	ui.reset_constellation_puzzle(CID)
	await _stop_builds(ui)
	ok(gc._assignment_int(solve_key, 0) == 1, "the Constellation still counts as solved")
	var after: float = cd.get_active_level_bonus(BONUS)
	ok(is_equal_approx(after, before), "the effect is unchanged after a reset (%.3f)" % after)

	print("\n=== 2. the new version can be played, and that is saved ===")
	eng.check_availability()
	ok(eng.state == eng.State.ACTIVE, "the reset puzzle is open")
	var data: Dictionary = gc.get_save_data()
	var fresh = load("res://game_context.gd").new()
	fresh.load_save_data(JSON.parse_string(JSON.stringify({"constellation_puzzle_reopened": data["constellation_puzzle_reopened"]})))
	ok(bool(fresh.constellation_puzzle_reopened.get(CID, false)), "it is still open after a save and load")
	fresh.free()

	print("\n=== 3. solving it closes it again ===")
	eng.force_complete()
	ok(gc._assignment_int(solve_key, 0) == 1, "still solved")
	ok(not gc.constellation_puzzle_reopened.has(CID), "no longer marked open")
	ok(eng.state == eng.State.IDLE, "and shut until the next reset")
	ok(is_equal_approx(cd.get_active_level_bonus(BONUS), before), "the effect is still on")

	print("\n=== 4. a puzzle never solved is not marked ===")
	gc.assignments.erase(solve_key)
	ui.reset_constellation_puzzle(CID)
	await _stop_builds(ui)
	ok(not gc.constellation_puzzle_reopened.has(CID), "reset unsolved: nothing is marked")
	ok(gc._assignment_int(solve_key, 0) == 0, "and it does not count as solved")
	eng.check_availability()
	ok(eng.state == eng.State.ACTIVE, "it is open, as it always was")

	holder.queue_free()
	await process_frame
	gc.assignments.erase(vol_key)
	gc.assignments.erase(solve_key)
	gc.constellation_puzzle_reopened.clear()
	gc.ui_unlocks["constellation"] = unlock_was
	gc.constellation_spark_totals[str(CID)] = sparks_was
	cd.load_save_data(cd_saved)
	cd.active_per_octant[0] = octant_was

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
