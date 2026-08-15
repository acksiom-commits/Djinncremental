extends "res://dev_tests/test_base.gd"
# ANONYMOUS SLOT INVARIANT — a deliberate design rule, easy to break by
# accident and invisible when broken.
#
# Sort-tab slots for a SHARED characteristic ("Blue A"/"Blue B",
# "A#4 A"/"A#4 B") are anonymous. The letter is a placeholder for ordering
# the rows, NOT a claim about which star in that group the slot is. The
# player can drop a deduction into any slot of the group and the engine
# must integrate it WITHOUT pinning that slot to a specific star — which is
# what lets them say "one of the blue stars is Keriion" before knowing
# which one.
#
# Confirmed still intact 2026-08-14, after eceea49 changed how identity is
# inferred (derived star_idx where a record is provably identical to a
# star-widget stub). Written as a standing test because the user relies on
# this and nothing else guards it: the failure mode is the engine quietly
# deciding "Blue B" IS star 4, which looks like progress rather than a bug.
#
# The boundary, deliberately NOT treated as a violation: a group of exactly
# ONE star ("only one star plays C6") is not anonymous — that slot denotes
# that star by definition, and resolving it is correct. Confirmed as
# intended behaviour by the user on 2026-08-14.

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
	for s in scn:
		e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true

	# ── A shared COLOUR group ────────────────────────────────────────────
	var ci: int = -1
	var members: Array = []
	for c in range(8):
		var m: Array = []
		for s in scn:
			if s < g.star_colors.size() and int(g.star_colors[s]) == c:
				m.append(s)
		if m.size() >= 3:
			ci = c
			members = m
			break
	print("  colour %d has %d members: %s" % [ci, members.size(), str(members)])

	# FIRST, the invariant itself, with NOTHING in the slot: an empty "Blue B"
	# must not be tied to any particular blue star. That is what "the letter
	# is a placeholder" means, and it is independent of any clue set.
	var empty_slot: int = e._get_or_create_match_record_for_color_slot(ci, 1)
	e._full_propagation_refresh()
	var empty_cands: Array = e._candidate_stars_for_record(empty_slot)
	print("  EMPTY slot '%s': %d candidate stars %s"
		% [str(e.record_at(empty_slot).get("color_slot_label", "")),
		   empty_cands.size(), str(empty_cands)])
	ok(e._effective_star_idx(empty_slot) < 0,
		"an empty colour slot is pinned to nothing")
	ok(empty_cands.size() == members.size(),
		"and it can be ANY member of its colour group (%d of %d)"
			% [empty_cands.size(), members.size()])

	# The player deduced some star is that colour and dropped it into the
	# SECOND slot of the group. The letter must stay a placeholder.
	var slot_b: int = empty_slot
	var nm: String = str(g.star_names[int(members[0])])
	e._propagate_name_states_confirmed_same_record(slot_b, nm)
	e._full_propagation_refresh()

	var found: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("color_slot_label", "")).ends_with(" B"):
			found = i
			break
	var named_b: Array = e._candidate_stars_for_record(found)
	print("\n  after naming '%s' into slot '%s': candidates %s"
		% [nm, str(e.record_at(found).get("color_slot_label", "")), str(named_b)])
	# The "no star map name was claimed" assertion that stood here is GONE,
	# not silently — it was the same over-correction corrected in
	# test_stub_merge_refusal.gd: the map is supposed to show what the engine
	# knows, and withholding a deduced name left Name as the only star-tag
	# reader that did not.
	#
	# It also did not belong in this file. This test is about SLOT LETTER
	# NEUTRALITY; what the star map displays is display policy, and it is
	# tested properly next door — shown when deduced, released on undo, and
	# never shown for a bare stub.

	# CORRECTED 2026-08-14. This used to assert that naming a slot must leave
	# it unpinned — which is NOT the invariant, and the assertion was mine.
	# A name belongs to exactly one star; if the clues determine which, then
	# the slot IS that star and saying so is correct deduction. It began
	# failing when the tautology fix shifted the RNG draw and the new clue
	# set happened to place this name.
	#
	# The real invariant is that the LETTER is a placeholder, and that has
	# two testable halves, both asserted here:
	#   * an EMPTY slot is pinned to nothing (checked above — 4 of 4)
	#   * which letter you drop a deduction into changes NOTHING
	#
	# The second is the sharper one, because it holds no matter what the
	# clues happen to determine: put the same name in slot A instead of slot
	# B and the answer must be identical. If the letters meant anything, it
	# would not be.
	e._load_match_records([])
	var slot_a: int = e._get_or_create_match_record_for_color_slot(ci, 0)
	e._propagate_name_states_confirmed_same_record(slot_a, nm)
	e._full_propagation_refresh()
	var found_a: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("color_slot_label", "")).ends_with(" A"):
			found_a = i
			break
	var named_a: Array = e._candidate_stars_for_record(found_a) if found_a >= 0 else []
	print("  same name into slot 'A' instead: candidates %s" % str(named_a))
	ok(found_a >= 0, "the A slot exists")
	ok(str(named_a) == str(named_b),
		"slot A and slot B reach the SAME answer — the letter carries no meaning "
			+ "(A=%s vs B=%s)" % [str(named_a), str(named_b)])

	# ── A shared PITCH group ─────────────────────────────────────────────
	e._load_match_records([])
	for s in scn:
		e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true
	var note: String = ""
	var pmembers: Array = []
	for cand in scn:
		var n: String = h._widgets._note_name_for_star(int(cand))
		var m2: Array = []
		for s in scn:
			if h._widgets._note_name_for_star(s) == n:
				m2.append(s)
		if m2.size() >= 2:
			note = n
			pmembers = m2
			break
	var freq: float = 0.0
	for i in h._pitch_freqs.size():
		if ConstellationLogicPuzzle.note_name_for_freq(h._pitch_freqs[i]) == note:
			freq = float(h._pitch_freqs[i])
	print("\n  note %s shared by %d stars: %s" % [note, pmembers.size(), str(pmembers)])
	var pslot: int = e._get_or_create_match_record_for_pitch_slot(freq, 1)
	var nm2: String = str(g.star_names[int(pmembers[0])])
	e._propagate_name_states_confirmed_same_record(pslot, nm2)
	e._full_propagation_refresh()
	var pfound: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("pitch_slot_label", "")).ends_with(" B"):
			pfound = i
			break
	var pitch_b: Array = e._candidate_stars_for_record(pfound) if pfound >= 0 else []
	print("  after naming '%s' into slot '%s': candidates %s"
		% [nm2, str(e.record_at(pfound).get("pitch_slot_label", "")), str(pitch_b)])

	# Same correction as the colour half: letter-neutrality, not inertness.
	e._load_match_records([])
	for s in scn:
		e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true
	var pslot_a: int = e._get_or_create_match_record_for_pitch_slot(freq, 0)
	e._propagate_name_states_confirmed_same_record(pslot_a, nm2)
	e._full_propagation_refresh()
	var pfound_a: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("pitch_slot_label", "")).ends_with(" A"):
			pfound_a = i
			break
	var pitch_a: Array = e._candidate_stars_for_record(pfound_a) if pfound_a >= 0 else []
	print("  same name into pitch slot 'A' instead: candidates %s" % str(pitch_a))
	ok(str(pitch_a) == str(pitch_b),
		"pitch slot A and slot B reach the SAME answer (A=%s vs B=%s)"
			% [str(pitch_a), str(pitch_b)])

	h.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
