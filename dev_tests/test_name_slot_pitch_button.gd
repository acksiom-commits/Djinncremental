extends "res://dev_tests/test_base.gd"
# A Sort:Name slot's pitch trigger button must show a pitch the player has
# earned, however it was earned.
#
# Reported 2026-09-24: a pitch positively known for a star (Listen) did not
# reach its Name tab slot's entry window, which kept reading "Select Pitch".
# The button read only the raw pitch_states; a Listen never writes that
# dict, it sets pitch_revealed, and the star-anchored effective state (which
# the checklist popup already used) carries the note. The cases below pin
# both halves: the note SHOWS when earned, and does NOT show when it merely
# could be read off the star (the leak an ungated effective read would open).

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33, 622.25]
	host._star_pitch_index = [0, 1, 2, 3, 4, 5]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	var d = host._deduction
	var w = host._widgets
	w.clear_pitch_caches()
	var truth: String = w._note_name_for_star(0)

	print("=== Listen-revealed pitch on an identity-confirmed star shows ===")
	d._load_match_records([])
	var e: int = d._get_or_create_match_record_for_name("Keriion")
	e = await d._confirm_match_record_identity(e, 0, "Keriion")
	d._match_records[e]["pitch_revealed"] = true
	d._full_propagation_refresh()
	ok(d._match_records[e].get("pitch_states", {}).is_empty(),
		"precondition: nothing was written to the raw pitch_states (a Listen never does)")
	var t1: String = w._make_pitch_checklist_trigger_button(e).text
	ok(t1 == truth, "the button reads the known pitch '%s' (got '%s')" % [truth, t1])

	print("\n=== the same star with pitch NOT revealed must not leak it ===")
	d._load_match_records([])
	var f: int = d._get_or_create_match_record_for_name("Keriion")
	f = await d._confirm_match_record_identity(f, 0, "Keriion")
	d._full_propagation_refresh()
	var t2: String = w._make_pitch_checklist_trigger_button(f).text
	ok(t2 == "Select Pitch",
		"an un-earned pitch stays hidden even though the star is identified (got '%s')" % t2)

	print("\n=== a player's own raw confirm still shows ===")
	d._load_match_records([])
	var b: int = d._get_or_create_match_record_for_name("Keriion")
	d._match_records[b]["pitch_states"] = {truth: 1}
	d._full_propagation_refresh()
	var t3: String = w._make_pitch_checklist_trigger_button(b).text
	ok(t3 == truth, "a raw confirmed pitch is shown (got '%s')" % t3)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
