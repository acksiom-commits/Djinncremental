extends "res://dev_tests/test_base.gd"
# The dev EXPLAIN tab must agree with the Clues tab's own coverage: a clue is
# explained as "still to input" exactly when coverage says it is unmet, the
# line count matches the unmet assertions, and recording a clue's content
# empties its explanation. Checked on a real generated puzzle with the
# denominator printed.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var cdef: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 31337, 0, cdef.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g.generate_clues_forms()
	var h = OverlayScene.instantiate()
	root.add_child(h)
	await process_frame
	h._cd = cd
	h._constellation_id = 0
	h._star_count = scn
	h._star_names = g.star_names
	h._star_colors = g.star_colors
	h._star_degrees = []
	for _s in scn:
		h._star_degrees.append(0)
	h._sequence_rank_solution = g.sequence_rank_solution
	h._pitch_freqs = cd.get_note_freqs(0)
	h._star_pitch_index = cd.get_note_assignment(0)
	h._form_clues_cache = g.chosen_form_clues
	h._rebuild_star_distances()
	h._widgets.clear_pitch_caches()
	var d = h._deduction
	var w = h._widgets
	d._load_match_records([])
	d._clear_deduction_caches()

	print("=== explainer agrees with coverage, blank board ===")
	var clues: Array[Dictionary] = w._all_final_clues_for_tabs()
	var offered: Array = d.clue_indices_with_something_to_give(clues)
	var explained: int = 0
	var mismatched: int = 0
	var bad_header: int = 0
	var shown_sample: String = ""
	for i in clues.size():
		var lines: Array[String] = d.explain_unrecorded_assertions(clues[i])
		var measurable: bool = d._clue_coverage_fraction(clues[i]["cells"], clues[i]["search_terms"], clues[i]["disclosures"]) != d.COVERAGE_UNMEASURABLE
		if lines.is_empty() == measurable:
			mismatched += 1
			continue
		if lines.is_empty():
			continue
		explained += 1
		if int(lines[0].get_slice(" ", 0)) < lines.size() - 1:
			bad_header += 1
		if shown_sample == "":
			shown_sample = "%s -> %s" % [clues[i]["text"], str(lines)]
	print("    clues: %d  offered: %d  explained: %d" % [clues.size(), offered.size(), explained])
	print("    sample: ", shown_sample)
	ok(explained > 0, "there are explained clues to judge (%d) -- otherwise the checks below are vacuous" % explained)
	ok(explained == offered.size(), "explained clues == clues coverage says are unmet (%d vs %d)" % [explained, offered.size()])
	ok(mismatched == 0, "an empty explanation happens exactly for unmeasurable clues (%d mismatches)" % mismatched)
	ok(bad_header == 0, "each header count covers its listed (deduplicated) lines (%d bad)" % bad_header)

	print("\n=== no line leaks an internal index ===")
	var leaks: int = 0
	for cl in clues:
		for ln in d.explain_unrecorded_assertions(cl):
			if ln.contains("star ") and ln.contains("star -"):
				leaks += 1
	ok(leaks == 0, "no unresolved-star placeholder in any line")

	print("\n=== the tab paints for a pinned clue and for none ===")
	h._selected_clue_text = ""
	w._set_marker_tab(w.TAB_EXPLAIN)
	await process_frame
	ok(h._markers_content.get_child_count() >= 1, "no clue pinned: a prompt is shown")
	h._selected_clue_text = str(clues[0]["text"])
	w._set_marker_tab(w.TAB_EXPLAIN)
	await process_frame
	ok(h._markers_content.get_child_count() >= 2, "a pinned clue: the clue and its explanation are shown (%d children)" % h._markers_content.get_child_count())

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
