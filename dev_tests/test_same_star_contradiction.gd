extends "res://dev_tests/test_base.gd"
# When are two records on ONE star impossible?
#
# Reported from a live game 2026-08-13:
#
#     "Slot C#5 A and The star that fires 4th are both set to the same star."
#
# flagged as an IMPOSSIBLE STATE on a board where C#5 really WAS the 4th
# note. The check treated "a star holds at most one record" as an invariant.
# It is not: a record is a VIEW, and one star is routinely held by a
# Sort:Name row, a Sort:Pitch slot, a Staff position and a map widget at
# once — that is what _records_provably_identical and the merge path exist
# for. Only two views that CANNOT be the same star are a contradiction.
#
# It became reachable when the identity passes were unblocked (54d71d9):
# merging deliberately runs against an EMPTY derived layer, so a
# co-identification the engine DERIVES can never be folded away.
#
# BOTH directions are pinned here. Silencing the false alarm is worthless —
# worse than the bug — if it also silences a real one.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _build(cd) -> Array:
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
	return [g, h, e, scn]


func _freq_for_note(h, note: String) -> float:
	for i in h._pitch_freqs.size():
		if ConstellationLogicPuzzle.note_name_for_freq(h._pitch_freqs[i]) == note:
			return float(h._pitch_freqs[i])
	return 0.0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()

	# ── 1: the reported case — two VIEWS of one star, correctly ───────────
	print("=== 1: two views of the same star is not a conflict ===")
	var b: Array = await _build(cd)
	var g = b[0]
	var h = b[1]
	var e = b[2]

	# A real star, its real note, its real firing position — so the state
	# being judged is a TRUE one. That is the whole complaint: a correct
	# board was called impossible.
	var star: int = 6
	var note: String = h._widgets._note_name_for_star(star)
	var pos: int = int(g.pitch_rank_solution[star]) + 1
	var pitch_rec: int = e._get_or_create_match_record_for_pitch_slot(_freq_for_note(h, note), 0)
	var seq_rec: int = e._get_or_create_match_record_for_seq(pos)
	print("  star %d plays %s and fires %s" % [star, note, str(pos)])

	# Force the co-identification into the DERIVED layer and judge it there,
	# with no refresh in between to wipe it — a derived binding is exactly
	# what merging is forbidden to fold, and so exactly what the check has
	# to rule on.
	e._reset_derived()
	e._derived[pitch_rec]["star_idx"] = star
	e._derived[seq_rec]["star_idx"] = star
	ok(e._same_star_value_clash(pitch_rec, seq_rec).is_empty(),
		"the two views disagree about nothing single-valued")
	e._detect_contradictions()
	for c in e._contradictions:
		print("    reported: %s" % str((c as Dictionary).get("text", "")))
	ok(e._contradictions.is_empty(),
		"a correct co-identification reports nothing (%d reported)" % e._contradictions.size())

	# And the point of allowing it: the sequence row inherits the pitch.
	ok(e._effective_pitch_state(seq_rec, note) == 1,
		"and the sequence row now knows its pitch is %s" % note)
	h.queue_free()
	await process_frame

	# ── 2: a GENUINE clash must still be caught ──────────────────────────
	print("\n=== 2: two records that cannot be the same star still fail ===")
	var b2: Array = await _build(cd)
	var g2 = b2[0]
	var h2 = b2[1]
	var e2 = b2[2]
	# Two DIFFERENT names. Name is alldiff, so these are provably distinct
	# stars by construction — putting both on one star is genuinely broken.
	var n1: int = e2._get_or_create_match_record_for_name(str(g2.star_names[3]))
	var n2: int = e2._get_or_create_match_record_for_name(str(g2.star_names[8]))
	e2._reset_derived()
	e2._clear_deduction_caches()
	e2._derived[n1]["star_idx"] = 5
	e2._derived[n2]["star_idx"] = 5
	ok(not e2._same_star_value_clash(n1, n2).is_empty(),
		"two different names DO clash: %s" % str(e2._same_star_value_clash(n1, n2)))
	# The gate must read each record's OWN fields. _records_provably_distinct
	# cannot be used: once both are pinned, _effective_name_state hands BOTH
	# of them the star's real name, so they stop looking distinct at exactly
	# the moment they are most broken. Pinned here because gating on it
	# silently disabled this very check when first attempted.
	print("    (for contrast, _records_provably_distinct says: %s)"
		% str(e2._records_provably_distinct(n1, n2)))
	e2._detect_contradictions()
	var found: bool = false
	for c2 in e2._contradictions:
		var txt: String = str((c2 as Dictionary).get("text", ""))
		print("    reported: %s" % txt)
		if txt.contains("same star"):
			found = true
	ok(found, "the real clash is still reported")
	h2.queue_free()

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
