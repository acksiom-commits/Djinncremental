extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# Current: 2026-08-14 report. On a Sort:Pitch slot's name checklist,
#   1. selecting "Heleai" then pressing UNDO SELECTS does not undo it
#   2. selecting it also identified the slot's star on the map, which it did
#      not do before
#
# Both are driven exactly as the widget layer drives them, so the repro
# exercises the real call path rather than a hand-built state.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

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
	var g = load("res://constellation_logic_puzzle.gd").new()
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
	h._pitch_rank_solution = g.pitch_rank_solution
	h._pitch_freqs = cd.get_note_freqs(0)
	h._star_pitch_index = cd.get_note_assignment(0)
	h._form_clues_cache = g.chosen_form_clues
	h._rebuild_star_distances()
	h._widgets.clear_pitch_caches()

	var e = h._deduction
	e._load_match_records([])

	# The reporter had been using LISTEN heavily, so model a board where
	# every star's pitch is known.
	for s in scn:
		e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true

	# Report 2 needs a note only ONE star plays — with two sharers the slot
	# cannot pin anything and the question does not arise.
	var star: int = -1
	var note: String = ""
	var sharers: int = 0
	for cand in scn:
		var n: String = h._widgets._note_name_for_star(int(cand))
		var c: int = 0
		for s in scn:
			if h._widgets._note_name_for_star(s) == n:
				c += 1
		if c == 1:
			star = int(cand)
			note = n
			sharers = 1
			break
	if star < 0:
		star = 6
		note = h._widgets._note_name_for_star(star)
		for s in scn:
			if h._widgets._note_name_for_star(s) == note:
				sharers += 1
		print("  (no singleton-pitch star in this puzzle)")
	var pitch_rec: int = e._get_or_create_match_record_for_pitch_slot(_freq_for_note(h, note), 0)
	var nm: String = str(g.star_names[star])
	print("  slot '%s' (note %s, shared by %d star(s)); naming it '%s'"
		% [str(e.record_at(pitch_rec).get("pitch_slot_label", "")), note, sharers, nm])

	# ── the SELECT, exactly as _on_slot_name_check does it ───────────────
	var before_count: int = e.record_count()
	e._propagate_name_states_confirmed_same_record(pitch_rec, nm)
	e._save_puzzle_notes()
	e._full_propagation_refresh()
	# A merge DESTROYS a record and reindexes, so the pre-refresh index can
	# silently point at something else. Re-find by the defining label.
	var found: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("pitch_slot_label", "")).begins_with(note):
			found = i
			break
	print("\n  records %d -> %d (merged: %s); slot record now index %d"
		% [before_count, e.record_count(), str(e.record_count() < before_count), found])
	if found >= 0:
		pitch_rec = found
	print("\n  after SELECT:")
	print("    r['name']='%s'  name_states['%s']=%s  eff_star=%d"
		% [str(e.record_at(pitch_rec).get("name", "")), nm,
		   str((e.record_at(pitch_rec).get("name_states", {}) as Dictionary).get(nm, 0)),
		   e._effective_star_idx(pitch_rec)])
	print("    candidate stars: %s" % str(e._candidate_stars_for_record(pitch_rec)))
	var bound_after_select: int = e._effective_star_idx(pitch_rec)

	# ── the UNDO, exactly as _on_slot_name_undo_selects does it ──────────
	e._undo_category_selects(pitch_rec, "name_states", "manual_name_blocks",
		"protected_staff_names", h._star_names.duplicate())
	e._save_puzzle_notes()
	e._full_propagation_refresh()
	print("\n  after UNDO SELECTS:")
	print("    r['name']='%s'  name_states['%s']=%s  eff_star=%d  eff_name_state=%d"
		% [str(e.record_at(pitch_rec).get("name", "")), nm,
		   str((e.record_at(pitch_rec).get("name_states", {}) as Dictionary).get(nm, 0)),
		   e._effective_star_idx(pitch_rec), e._effective_name_state(pitch_rec, nm)])

	ok(str(e.record_at(pitch_rec).get("name", "")) == "",
		"UNDO SELECTS clears the promoted identity field r['name']")
	ok(e._effective_name_state(pitch_rec, nm) != 1,
		"and the name no longer reads as confirmed")
	print("\n  (for report 2, star binding after the select was: %d; %d star(s) share %s)"
		% [bound_after_select, sharers, note])

	# A Sort:Name row's name is its DEFINING field. Undoing marks on it must
	# not delete the row — the first version of the fix above would have.
	print("\n  === a Sort:Name row must survive its own undo ===")
	var keep: String = str(g.star_names[3])
	var name_row: int = e._get_or_create_match_record_for_name(keep)
	e._propagate_name_states_confirmed_same_record(name_row, keep)
	e._undo_category_selects(name_row, "name_states", "manual_name_blocks",
		"protected_staff_names", h._star_names.duplicate())
	print("    after undo, row's name = '%s'" % str(e.record_at(name_row).get("name", "")))
	ok(str(e.record_at(name_row).get("name", "")) == keep,
		"the Sort:Name row for '%s' still exists after undoing its marks" % keep)

	h.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()


func _freq_for_note(h, note: String) -> float:
	for i in h._pitch_freqs.size():
		if ConstellationLogicPuzzle.note_name_for_freq(h._pitch_freqs[i]) == note:
			return float(h._pitch_freqs[i])
	return 0.0
