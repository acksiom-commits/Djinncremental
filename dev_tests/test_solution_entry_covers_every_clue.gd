extends "res://dev_tests/test_base.gd"
# COMPLETENESS of propagation to the clue readers (2026-10-07).
#
# test_widget_path_independence proves the entry widgets agree with each other.
# This proves the board they all feed is COMPLETE: once the player has entered
# the entire solution -- every star's name, firing position, colour and pitch
# -- no scoreable clue may still read "not reflected on your board". Whatever
# route the facts took (a Sort:Name row, a position slot, a colour slot), the
# clue readers (_disclosure_satisfied, _cell_resolved_by_player) must see the
# same finished board. A clue left unreflected after the full truth is on the
# board is a propagation failure by definition: nothing is left to enter.
#
# Real generated puzzle, not a synthetic one -- real disclosures are what
# exercise the readers. One generation (~18s) is shared by every variant.
#
# Denominators are printed (clues, measurable) so a silent 0-of-0 cannot pass.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host_for(g, cd, scn: int, cid: int):
	var h = OverlayScene.instantiate()
	root.add_child(h)
	await process_frame
	h._cd = cd
	h._constellation_id = cid
	h._star_count = scn
	h._star_names = g.star_names
	h._star_colors = g.star_colors
	h._star_degrees = []
	for _s in scn:
		h._star_degrees.append(0)
	h._sequence_rank_solution = g.sequence_rank_solution
	h._pitch_freqs = cd.get_note_freqs(cid)
	h._star_pitch_index = cd.get_note_assignment(cid)
	h._form_clues_cache = g.chosen_form_clues
	h._rebuild_star_distances()
	h._widgets.clear_pitch_caches()
	return h


func _record(d, s: int, h, getter: String, color_slots: Dictionary) -> int:
	match getter:
		"name":
			return d._get_or_create_match_record_for_name(str(h._star_names[s]))
		"seq":
			return d._get_or_create_match_record_for_seq(int(h._sequence_rank_solution[s]) + 1)
		_:
			var c: int = int(h._star_colors[s])
			var n: int = int(color_slots.get(c, 0))
			color_slots[c] = n + 1
			return d._get_or_create_match_record_for_color_slot(c, n)


func _enter_solution(h, getter: String, listen: bool, loc: bool) -> void:
	var d = h._deduction
	var w = h._widgets
	d._load_match_records([])
	var scn: int = h._star_count
	if listen:
		for s in scn:
			var sr: int = d._get_or_create_match_record_for_star_idx(s)
			d._propagate_pitch_confirmed_same_record(sr, w._note_name_for_star(s))
			d.record_at(sr)["pitch_revealed"] = true
		d._full_propagation_refresh()
	var slots: Dictionary = {}
	var refs: Array = []
	for s in scn:
		refs.append(d.record_at(_record(d, s, h, getter, slots)))
	for s in scn:
		var nm: String = str(h._star_names[s])
		var pos: int = int(h._sequence_rank_solution[s]) + 1
		var col: int = int(h._star_colors[s])
		var note: String = w._note_name_for_star(s)
		var rec: int = _index(d, refs[s])
		# location: which map star this is (what the star-map name checklist
		# asserts). Part of "the whole solution" -- every hop/distance
		# assertion is a claim about the map, unreadable without it.
		if loc:
			var cr: int = d._get_or_create_match_record_for_name(nm)
			await w._on_name_check(s, nm, Label.new(), Button.new(), Button.new())
			var found0: int = d._find_match_record_by_name(nm)
			if found0 >= 0:
				refs[s] = d.record_at(found0)
				rec = found0
		# name
		if getter == "name":
			await w._on_record_name_selected(rec, nm)
		else:
			w._on_slot_name_check(rec, nm, null)
		rec = _index(d, refs[s])
		# position
		var lo := LineEdit.new()
		var mid := LineEdit.new()
		var hi := LineEdit.new()
		h.add_child(lo)
		h.add_child(mid)
		h.add_child(hi)
		lo.text = str(d._first_tick_for_rank(pos))
		hi.text = lo.text
		await w._commit_sequence_range(rec, lo, mid, hi)
		rec = _index(d, refs[s])
		# colour
		await w._on_record_color_toggle(rec, col, Button.new())
		rec = _index(d, refs[s])
		# pitch (not when it came from Listen alone)
		if not listen:
			w._on_pitch_checklist_check(rec, note, null)
		if _index(d, refs[s]) < 0:
			var found: int = d._find_match_record_by_name(nm)
			if found >= 0:
				refs[s] = d.record_at(found)
	d._full_propagation_refresh()
	await process_frame


func _index(d, ref: Dictionary) -> int:
	for i in d.record_count():
		if is_same(d.record_at(i), ref):
			return i
	return -1


func _unreflected(h, clues: Array) -> Array:
	var d = h._deduction
	d._clear_deduction_caches()
	var out: Array = []
	for i in clues.size():
		var c: Dictionary = clues[i]
		var f: float = d._clue_coverage_fraction(c["cells"], c["search_terms"], c["disclosures"])
		if f != d.COVERAGE_UNMEASURABLE and f < 1.0:
			out.append(i)
	return out


# kind: "complete"  -> every measurable clue must be reflected
#       "control"   -> information is deliberately missing; clues MUST remain
#                      unreflected (proves the check can fail)
#       "info"      -> printed only; see the comment on each
func _run_constellation(cid: int, variants: Array) -> void:
	var cd = load("res://constellation_data.gd").new()
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 31337, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	await g.generate_clues_forms()
	var clues: Array = g.chosen_form_clues
	print("\n##### constellation %d: %d stars, %d clues" % [cid, scn, clues.size()])
	for v in variants:
		print("\n=== c%d  %s ===" % [cid, str(v[0])])
		var h = await _host_for(g, cd, scn, cid)
		# a blank board must leave every measurable clue unreflected, or
		# "none unreflected" below proves nothing
		h._deduction._load_match_records([])
		var measurable: int = _unreflected(h, clues).size()
		await _enter_solution(h, str(v[1]), bool(v[2]), bool(v[3]))
		var left: Array = _unreflected(h, clues)
		print("  clues: %d   measurable: %d   unreflected after the full solution: %d"
			% [clues.size(), measurable, left.size()])
		ok(measurable > 0, "the puzzle has measurable clues (%d) -- otherwise the checks below are vacuous" % measurable)
		var kind: String = str(v[4])
		match kind:
			"complete":
				ok(left.is_empty(), "every measurable clue is reflected once the whole solution is entered (%d left)" % left.size())
			"control":
				ok(not left.is_empty(), "control: clues DO stay unreflected when the board lacks the information (%d left)" % left.size())
		if kind != "control":
			for i in left:
				print("      clue %d: %s" % [i, str((clues[i] as Dictionary).get("text", ""))])
				for ln in h._deduction.explain_unrecorded_assertions(clues[i]):
					print("         - %s" % ln)
		variants_run += 1
		h.queue_free()


var variants_run: int = 0


func run() -> void:
	# The premise (see the memory on Listen): players are presumed to have
	# Listened to every star, so pitch is "given" and the realistic full
	# solution is Listen + map locations + the Sort-tab facts.
	var asserted: Array = [
		["Sort:Name rows", "name", true, true, "complete"],
		["position slots", "seq", true, true, "complete"],
		["colour slots", "color", true, true, "complete"],
		# Listen is keyed to MAP stars, so without the name<->map-star link
		# nothing says which NAME carries a note: clues about a named star's
		# pitch correctly stay open.
		["control: Sort:Name rows, no map locations", "name", true, false, "control"],
		# Typing a pitch on a row without Listening is not treated as knowing
		# that star's note (an unlistened star "could be carrying" any note),
		# so a distance clue naming "the star with pitch X" stays open. By
		# design under the Listen premise; printed, not asserted.
		["info: pitch typed instead of Listened", "name", false, true, "info"],
	]
	await _run_constellation(0, asserted)
	# A second topology: the coverage tabs and distance readers are map-shaped.
	await _run_constellation(2, [asserted[0], asserted[3]])

	ok(variants_run == 7, "every variant was run (%d)" % variants_run)
	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
