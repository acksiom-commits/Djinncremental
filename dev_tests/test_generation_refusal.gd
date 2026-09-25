extends "res://dev_tests/test_base.gd"
# A puzzle that fails the uniqueness gate on every attempt must be REFUSED,
# not shipped. generate_clues_forms() used to log push_error and ship the last
# attempt anyway; nothing downstream checked, so a puzzle with more than one
# valid solution (or an unbound name) reached the player.
#
# Now: MAX_GENERATION_ATTEMPTS attempts, then EXTRA_GENERATION_ROUNDS more
# rounds of the same size; gate_passed says whether the FINAL attempt passed;
# root_ui refuses (does not cache) a failed puzzle and the Study panel says so.

const Stub = preload("res://dev_tests/support/gate_stub_puzzle.gd")
const RootUiScript = preload("res://root_ui.gd")
const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _stub(script: Array):
	var p = Stub.new()
	p.scripted = script
	return p


func run() -> void:
	await process_frame   # autoloads are unreachable until one frame has passed
	var round_size: int = Stub.MAX_GENERATION_ATTEMPTS
	var all_attempts: int = round_size * (1 + Stub.EXTRA_GENERATION_ROUNDS)

	print("=== the retry loop and gate_passed ===")
	var a = _stub([true])
	await a.generate_clues_forms()
	ok(a.calls == 1 and a.gate_passed, "a passing first attempt stops at once (%d call(s))" % a.calls)

	var b = _stub([false, false, false, false, false, false, true])
	await b.generate_clues_forms()
	ok(b.gate_passed and b.calls == 7,
		"a pass in the SECOND round (attempt 7) is accepted and stops there (%d calls, passed=%s)" % [b.calls, str(b.gate_passed)])

	var c = _stub([false])
	await c.generate_clues_forms()
	ok(not c.gate_passed, "every attempt failing leaves gate_passed false")
	ok(c.calls == all_attempts, "and it tried exactly %d attempts, %d rounds of %d (%d)" % [all_attempts, 1 + Stub.EXTRA_GENERATION_ROUNDS, round_size, c.calls])
	ok(c.is_generation_complete(), "generation still reports complete, so callers are not left waiting")

	var d = _stub([false, true])
	await d.generate_clues_forms()
	ok(d.gate_passed, "gate_passed reflects the FINAL attempt, not an earlier failure")

	print("\n=== the gate definition needs all three conditions ===")
	var g = Stub.new()
	ok(g._gate_result_passes({"seq_unique": true, "name_unique": true, "name_unique_closure": true}), "all three: passes")
	ok(not g._gate_result_passes({"seq_unique": false, "name_unique": true, "name_unique_closure": true}), "Sequence not unique: fails")
	ok(not g._gate_result_passes({"seq_unique": true, "name_unique": false, "name_unique_closure": true}), "a name unbound: fails")
	ok(not g._gate_result_passes({"seq_unique": true, "name_unique": true, "name_unique_closure": false}), "closure not a proof: fails")
	ok(not g._gate_result_passes({}), "a missing result fails rather than passes")

	print("\n=== root_ui refuses a failed puzzle, accepts a good one ===")
	var cd = root.get_node_or_null("/root/ConstellationData")
	ok(cd != null, "ConstellationData reachable -- otherwise the checks below are vacuous")
	if cd == null:
		finish()
		return
	cd.clear_puzzle_cache(0)
	cd.puzzle_generation_failed.erase(0)
	ok(not RootUiScript._accept_generated_puzzle(cd, 0, c), "a failed puzzle is refused")
	ok(cd.get_puzzle_cache(0).is_empty(), "and nothing is cached for it")
	ok(bool(cd.puzzle_generation_failed.get(0, false)), "and the constellation is marked failed")
	ok(RootUiScript._accept_generated_puzzle(cd, 0, a), "a passing puzzle is accepted")
	ok(not cd.get_puzzle_cache(0).is_empty(), "and cached")
	ok(not bool(cd.puzzle_generation_failed.get(0, false)), "and the failed mark is cleared by a later success")
	cd.clear_puzzle_cache(0)

	print("\n=== the Study panel says so ===")
	var gc = root.get_node_or_null("/root/GameContext")
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._cd = cd
	host._gc = gc
	host._constellation_id = 0
	var saved_reveal = gc.ui_unlocks.get("kaleb_identity_revealed", false)
	gc.ui_unlocks["kaleb_identity_revealed"] = true
	cd.puzzle_generation_failed[0] = true
	host._update_header()
	ok(host._title_label.text.contains("not ready"), "empty cache after a refusal: the title says the puzzle is not ready (\"%s\")" % host._title_label.text)
	cd.puzzle_generation_failed.erase(0)
	host._update_header()
	ok(not host._title_label.text.contains("not ready"), "no refusal recorded: no such message")
	gc.ui_unlocks["kaleb_identity_revealed"] = saved_reveal

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
