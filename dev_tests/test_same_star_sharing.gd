extends "res://dev_tests/test_base.gd"
# Records that denote the SAME STAR must agree about that star.
#
# Reported 2026-08-14: once "the star that fires 11th" resolved to a
# specific star, its Staff popup showed that star's pitch and colour, but
#   * the Sort:Pitch row for that pitch showed nothing
#   * the Sort:Colour row for that colour showed nothing
#   * the star map popup never learned the name exclusion entered against
#     the 11th
#
# Three surfaces, one cause: those are different RECORDS for one star, and
# _share_derived_facts had exactly one caller — _settle_same_position_
# identity — which keys on sequence POSITION. Two records known to be the
# same star still knew different things about it.

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
	h._sequence_rank_solution = g.sequence_rank_solution
	h._pitch_freqs = cd.get_note_freqs(0)
	h._star_pitch_index = cd.get_note_assignment(0)
	h._form_clues_cache = g.chosen_form_clues
	h._rebuild_star_distances()
	h._widgets.clear_pitch_caches()

	var e = h._deduction
	e._load_match_records([])
	for s in scn:
		e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true

	# The reported shape: a sequence row that has resolved to a star, and a
	# separate star-widget record for that same star.
	var star: int = 6
	var pos: int = int(g.sequence_rank_solution[star]) + 1
	var note: String = h._widgets._note_name_for_star(star)
	var seq_rec: int = e._get_or_create_match_record_for_seq(pos)
	# The player's own entry against that sequence row: this name is not it.
	var excluded_name: String = str(g.star_names[(star + 3) % scn])
	e.record_at(seq_rec)["name_states"] = {excluded_name: 2}
	e.record_at(seq_rec)["manual_name_blocks"] = {excluded_name: true}
	# And the sequence row is now known to BE that star.
	e.record_at(seq_rec)["star_idx"] = star
	e._full_propagation_refresh()

	var star_rec: int = e._find_match_record_by_star_idx(star)
	print("  seq row %d (fires %d) and star record %d both denote star %d"
		% [seq_rec, pos, star_rec, star])
	ok(star_rec >= 0 and star_rec != seq_rec,
		"they really are two separate records")

	# ── surface 3: the star's own record learns the name exclusion ───────
	print("\n=== the star map record learns the excluded name ===")
	print("    '%s' on the star record: state=%d (2 = ruled out)"
		% [excluded_name, e._effective_name_state(star_rec, excluded_name)])
	ok(e._effective_name_state(star_rec, excluded_name) == 2,
		"the exclusion entered against the sequence row reached the star's record")

	# ── surfaces 1 and 2: a Sort slot on the same star agrees ────────────
	print("\n=== a Sort:Pitch slot on the same star agrees about it ===")
	var freq: float = 0.0
	for i in h._pitch_freqs.size():
		if ConstellationLogicPuzzle.note_name_for_freq(h._pitch_freqs[i]) == note:
			freq = float(h._pitch_freqs[i])
	var pslot: int = e._get_or_create_match_record_for_pitch_slot(freq, 0)
	e.record_at(pslot)["star_idx"] = star     # same star, third view of it
	e._full_propagation_refresh()
	var pslot2: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("pitch_slot_label", "")).begins_with(note):
			pslot2 = i
			break
	ok(pslot2 >= 0, "the pitch slot record still exists")
	if pslot2 >= 0:
		print("    '%s' on the pitch slot: state=%d" % [excluded_name,
			e._effective_name_state(pslot2, excluded_name)])
		ok(e._effective_name_state(pslot2, excluded_name) == 2,
			"the pitch slot learned the same exclusion")
		ok(e._seq_candidate_set_for(pslot2).has(pos)
				or e._seq_candidate_set_for(pslot2).is_empty(),
			"and its sequence view is consistent with position %d" % pos)

	# ── the guard: disagreeing records must NOT be laundered ────────────
	print("\n=== a genuine disagreement is not shared across ===")
	e._load_match_records([])
	var n1: int = e._get_or_create_match_record_for_name(str(g.star_names[1]))
	var n2: int = e._get_or_create_match_record_for_name(str(g.star_names[2]))
	e.record_at(n1)["star_idx"] = 4
	e.record_at(n2)["star_idx"] = 4
	e._full_propagation_refresh()
	ok(not e._same_star_value_clash(n1, n2).is_empty(),
		"two differently-named records on one star still clash")
	var reported: bool = false
	for c in e._contradictions:
		if str((c as Dictionary).get("axis", "")) == "identity":
			reported = true
	ok(reported, "and the clash is still reported rather than shared away")

	h.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
