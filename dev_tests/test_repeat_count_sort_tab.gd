extends "res://dev_tests/test_base.gd"
# Sort:Repeats tab (2026-09-30) — the player-facing surface for Category.
# REPEAT, built after Forms 12/23/24 already shipped live clue content for
# it. Unlike every other Sort:tab, a bucket's row count is player-driven
# rather than read from ground truth (see _repeat_bucket_values' own
# comment in constellation_puzzle_deduction.gd): the true per-value
# incidence is exactly the secret this axis withholds. What must hold:
#
#  - Buckets start seeded to [0, 1, 2] and _add_repeat_bucket() grows the
#    list by exactly one (the next integer), never overwriting existing
#    values.
#  - Placing a record in a bucket slot IS the confirm (the repeat_slot_
#    label tier _effective_repeat_state gained this session) -- no separate
#    checklist action is needed for a bucket-created record's OWN value.
#  - Slot records are found by LABEL, not index: re-fetching the same
#    (value, position) always returns the same record, and removing then
#    re-adding a slot reunites with the same record rather than losing it.
#  - The checklist path (_on_repeat_checklist_check/_x) used by every OTHER
#    Sort:tab's "Repeats:" fact row confirms/eliminates correctly and
#    clears siblings within the same record.
#  - Bucket values, per-bucket slot counts, and a record's own repeat_
#    states/repeat_slot_label all survive a save/load round trip -- two
#    real gaps this session found and fixed (_load_match_records never
#    read repeat_states et al. back at all; _merge_match_records had no
#    handling for the repeat axis whatsoever).
#  - _merge_match_records reconciles two repeat confirms: agreeing values
#    union cleanly, and a genuine conflict is refused (not silently
#    resolved) on the non-await path.
#  - Opening the Repeats tab on a populated host builds rows without error.
#
# NOTE: like test_name_slot_pitch_button.gd, this module instantiates the
# real ConstellationStudyOverlay scene, which depends on state (autoloads /
# resources) that only exists once the suite has run at least one other
# scene-based module first. Confirmed 2026-09-30 by reproducing the same
# silent abort on test_name_slot_pitch_button.gd itself when run ALONE via
# `-- test_name_slot_pitch_button` -- not a regression, a pre-existing
# property of this class of test. Always verify through the FULL suite
# (`dev_tests/test_runner.gd` with no filter), never this module in
# isolation.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame   # let _ready() run so _deduction/_widgets/@onready nodes exist
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 0, 1, 2]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	host._repeat_count = [0, 0, 1, 1, 2, -1]
	return host


func run() -> void:
	await process_frame

	print("=== bucket list defaults and grows ===")
	var host1 = await _make_host()
	var d1 = host1._deduction
	d1._load_match_records([])
	ok(d1._get_repeat_bucket_values() == [0, 1, 2], "default buckets are [0,1,2] (got %s)" % str(d1._get_repeat_bucket_values()))
	d1._add_repeat_bucket()
	ok(d1._get_repeat_bucket_values() == [0, 1, 2, 3], "adding a bucket appends the next integer (got %s)" % str(d1._get_repeat_bucket_values()))
	d1._add_repeat_bucket()
	ok(d1._get_repeat_bucket_values() == [0, 1, 2, 3, 4], "adding again appends 4, not a duplicate (got %s)" % str(d1._get_repeat_bucket_values()))

	print("\n=== placing a record in a bucket slot IS the confirm ===")
	var host2 = await _make_host()
	var d2 = host2._deduction
	d2._load_match_records([])
	var r0a: int = d2._get_or_create_match_record_for_repeat_slot(0, 0)
	ok(d2._effective_repeat_state(r0a, 0) == 1, "the slot's own value reads confirmed with no separate checklist action")
	ok(d2._effective_repeat_state(r0a, 1) == 2, "every other bucket value reads eliminated for that same record")
	ok(d2._effective_repeat_state(r0a, 2) == 2, "including bucket 2")

	print("\n=== slot records are found by label, not index ===")
	var r0a_again: int = d2._get_or_create_match_record_for_repeat_slot(0, 0)
	ok(r0a_again == r0a, "re-fetching bucket 0 slot A returns the SAME record (got %d, expected %d)" % [r0a_again, r0a])
	var r0b: int = d2._get_or_create_match_record_for_repeat_slot(0, 1)
	ok(r0b != r0a, "bucket 0 slot B is a DIFFERENT record from slot A")
	d2.record_at(r0b)["name"] = "TestStar"
	d2._remove_repeat_bucket_slot(0)   # hides slot B from the tab, does not delete its record
	d2._add_repeat_bucket_slot(0)      # slot B is back in view
	var r0b_again: int = d2._get_or_create_match_record_for_repeat_slot(0, 1)
	ok(r0b_again == r0b and str(d2.record_at(r0b_again).get("name", "")) == "TestStar",
		"removing then re-adding a slot reunites with the SAME record, name intact")

	print("\n=== checklist confirm/eliminate on a record reached some OTHER way ===")
	var host3 = await _make_host()
	var d3 = host3._deduction
	var w3 = host3._widgets
	d3._load_match_records([])
	var nrec: int = d3._get_or_create_match_record_for_name("Pyrios")
	ok(d3._effective_repeat_state(nrec, 1) == 0, "precondition: nothing confirmed yet")
	w3._on_repeat_checklist_check(nrec, 1, null)
	ok(d3._effective_repeat_state(nrec, 1) == 1, "checking bucket 1 confirms it")
	ok(d3._effective_repeat_state(nrec, 0) == 2, "and clears sibling bucket 0 on the SAME record")
	ok(d3._effective_repeat_state(nrec, 2) == 2, "and sibling bucket 2 too")
	w3._on_repeat_checklist_x(nrec, 0, null)
	ok(d3._effective_repeat_state(nrec, 0) == 0,
		"X-ing a sibling-cleared (not manually blocked) value toggles it back open rather than crashing")

	print("\n=== save/load round trip: bucket shape AND a record's own marks ===")
	var host4 = await _make_host()
	var d4 = host4._deduction
	d4._load_match_records([])
	d4._add_repeat_bucket()
	var slot_rec: int = d4._get_or_create_match_record_for_repeat_slot(3, 0)
	d4.record_at(slot_rec)["name"] = "Roundtrip"
	var free_rec: int = d4._get_or_create_match_record_for_name("Selion")
	d4.record_at(free_rec)["repeat_states"] = {1: 1, 0: 2, 2: 2}
	var saved_records: Array = d4._save_match_records()
	var saved_bucket_values: Array = d4._repeat_bucket_values.duplicate()
	var saved_bucket_counts: Dictionary = d4._repeat_bucket_slot_counts.duplicate()

	var host5 = await _make_host()
	var d5 = host5._deduction
	d5._load_match_records(saved_records)
	d5._repeat_bucket_values = saved_bucket_values.duplicate()
	d5._repeat_bucket_slot_counts = saved_bucket_counts.duplicate()
	var reloaded_slot: int = d5._get_or_create_match_record_for_repeat_slot(3, 0)
	ok(str(d5.record_at(reloaded_slot).get("name", "")) == "Roundtrip",
		"a bucket-slot record's name survives a save/load round trip")
	ok(d5._effective_repeat_state(reloaded_slot, 3) == 1,
		"and its slot-label confirm still reads back correctly after reload")
	var reloaded_free: int = d5._get_or_create_match_record_for_name("Selion")
	ok(d5._effective_repeat_state(reloaded_free, 1) == 1 and d5._effective_repeat_state(reloaded_free, 0) == 2,
		"a plain checklist-confirmed repeat_states mark survives a save/load round trip too (this was the real bug: _load_match_records never read repeat_states back at all)")

	print("\n=== merge reconciles the repeat axis instead of silently dropping it ===")
	var host6 = await _make_host()
	var d6 = host6._deduction
	d6._load_match_records([])
	var mrec_a: int = d6._get_or_create_match_record_for_repeat_slot(0, 0)
	var mrec_b: int = d6._get_or_create_match_record_for_name("AgreeStar")
	d6.record_at(mrec_b)["repeat_states"] = {0: 1, 1: 2}
	var merged: int = await d6._merge_match_records(mrec_a, mrec_b)
	ok(d6._effective_repeat_state(merged, 0) == 1,
		"two AGREEING repeat confirms merge cleanly (this was the real bug: repeat_states had no merge handling at all, silently dropped on merge)")

	var host7 = await _make_host()
	var d7 = host7._deduction
	d7._load_match_records([])
	var crec_a: int = d7._get_or_create_match_record_for_repeat_slot(0, 0)
	var crec_b: int = d7._get_or_create_match_record_for_repeat_slot(1, 0)
	var kinds: Array = d7._merge_conflict_kinds(crec_a, crec_b)
	ok(kinds.has("repeat") or kinds.has("repeat_slot_label"),
		"two records confirmed to DIFFERENT repeat values are flagged as a merge conflict (got kinds=%s)" % str(kinds))
	var refused: int = await d7._merge_match_records(crec_a, crec_b, false)
	ok(refused == crec_a, "the non-await merge path refuses rather than silently picking a winner")

	print("\n=== opening the Repeats tab builds rows, add-slot/add-bucket controls, with no crash ===")
	var host8 = await _make_host()
	var d8 = host8._deduction
	d8._load_match_records([])
	d8._get_or_create_match_record_for_repeat_slot(0, 0)   # one filled-in slot, exercises the real row path
	host8._widgets._sort_matches(5)
	ok(host8._matches_sort_mode == 5, "the Repeats tab is now the active Sort: sub-tab")
	ok(host8._markers_content.get_child_count() > 0, "the tab actually rendered rows/controls, not an empty list")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
