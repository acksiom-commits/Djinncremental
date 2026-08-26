extends "res://dev_tests/test_base.gd"
# The MERGE half of contradiction absorption.
#
# _merge_match_records unions two records' state with
#     if sv == 1 or tv == 1: target[k] = 1
# so a confirm silently beats an elimination. Merging "this IS G4" with
# "this is NOT G4" produced "this IS G4" and the elimination ceased to
# exist. The board then looked perfectly consistent — the worst outcome,
# because the player's mistake was concealed rather than corrected, and
# the evidence needed to report it was the thing destroyed.
#
# Now such a merge is REFUSED, both records survive with both marks, and
# the pair is reported. The refusal is re-derived every refresh from
# records that still exist, so it needs no persistence and clears itself
# the moment either mark is fixed.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


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
	host._widgets.clear_pitch_caches()

	# Two records the engine can prove are the same star (same name), one
	# confirming a colour the other rules out.
	print("\n=== a clashing merge is refused, not absorbed ===")
	d._load_match_records([])
	var a: int = d._get_or_create_match_record_for_name("Pyrios")
	d._match_records[a]["color_states"] = {1: 1}
	var b: int = d._get_or_create_match_record_for_seq(4)
	d._match_records[b]["name"] = "Pyrios"
	d._match_records[b]["color_states"] = {1: 2}
	var before: int = d.record_count()
	d._full_propagation_refresh()
	ok(d.record_count() == before,
		"both records survive — no lossy merge (%d -> %d)" % [before, d.record_count()])

	var merge_reported := false
	for c in d._contradictions:
		print("      %s" % str((c as Dictionary).get("text", "")))
		if str((c as Dictionary).get("axis", "")) == "merge":
			merge_reported = true
	ok(merge_reported, "the disagreement is reported")

	print("\n=== both marks are still intact afterwards ===")
	var keep_a := -1
	var keep_b := -1
	for i in d.record_count():
		var st: Dictionary = d.record_at(i).get("color_states", {})
		if int(st.get(1, 0)) == 1:
			keep_a = i
		if int(st.get(1, 0)) == 2:
			keep_b = i
	ok(keep_a >= 0, "the confirm survived")
	ok(keep_b >= 0, "the elimination survived (this is what used to vanish)")

	print("\n=== fixing either mark clears it AND lets the merge happen ===")
	if keep_b >= 0:
		d.record_at(keep_b)["color_states"] = {}
	d._full_propagation_refresh()
	var still := false
	for c in d._contradictions:
		if str((c as Dictionary).get("axis", "")) == "merge":
			still = true
	ok(not still, "warning gone once the clash is resolved")
	ok(d.record_count() < before,
		"and the records now merge normally (%d -> %d)" % [before, d.record_count()])

	print("\n=== a compatible merge is untouched ===")
	d._load_match_records([])
	var c1: int = d._get_or_create_match_record_for_name("Helios")
	d._match_records[c1]["color_states"] = {1: 1}
	var c2: int = d._get_or_create_match_record_for_seq(2)
	d._match_records[c2]["name"] = "Helios"
	d._match_records[c2]["degree_states"] = {1: 1}   # different axis, no clash
	var before2: int = d.record_count()
	d._full_propagation_refresh()
	ok(d.record_count() < before2,
		"non-clashing records still merge (%d -> %d)" % [before2, d.record_count()])
	var merge_noise := false
	for c in d._contradictions:
		if str((c as Dictionary).get("axis", "")) == "merge":
			merge_noise = true
	ok(not merge_noise, "and raise no warning")

	print("\n=== nothing about this is persisted ===")
	var leaked := false
	for e in d._save_match_records():
		if (e as Dictionary).has("merge_refusals") or (e as Dictionary).has("clashes"):
			leaked = true
	ok(not leaked, "refusals never reach the save file")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
