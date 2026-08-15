extends "res://dev_tests/test_base.gd"
# _settle_alldiff_position_exclusions, and the leak it replaced.
#
# _propagate_name_confirmed used to broadcast "no other name is this star"
# by writing star_elim=2 into every OTHER name record's OWN dict — the
# player-input layer. Measured 2026-08-13: those writes survived the binding
# being undone, leaving marks indistinguishable from the player's own X's
# and released by nothing.
#
# It could not simply be deleted. The same measurement showed the engine did
# NOT derive the alldiff conclusion by itself, so the broadcast was
# load-bearing. Both halves are pinned here, because fixing either one alone
# is a regression: keep the broadcast and the leak stays, drop it without
# the pass and the deduction is lost.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _build(cd, seed_v: int) -> Array:
	var cdef: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(cdef["star_count"])
	var g = load("res://constellation_logic_puzzle.gd").new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed_v, 0, cdef.get("name_theme", {}),
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
	for n in g.star_names:
		e._get_or_create_match_record_for_name(str(n))
	return [g, h, e, scn]


func run() -> void:
	var cd = load("res://constellation_data.gd").new()

	# ── 1: the deduction still happens, with no broadcast involved ────────
	print("=== 1: alldiff exclusion is DERIVED, not broadcast ===")
	var b: Array = await _build(cd, 4242)
	var g = b[0]
	var h = b[1]
	var e = b[2]
	var scn: int = int(b[3])

	var owner: int = e._find_match_record_by_name(str(g.star_names[7]))
	var other: int = e._find_match_record_by_name(str(g.star_names[9]))
	# Bind the way the ENGINE would — set the field directly, never calling
	# _propagate_name_confirmed. Nothing broadcasts anything here.
	e.record_at(owner)["star_idx"] = 7
	e._full_propagation_refresh()

	ok(e._star_elim_state_for_record(other, 7) == 2,
		"star 7 is ruled out for another name, with no broadcast (state=%d)"
			% e._star_elim_state_for_record(other, 7))
	ok(not e._candidate_stars_for_record(other).has(7),
		"and star 7 has left that record's candidate set")
	# It must live in the DERIVED layer, not in the record's own input.
	ok(int((e.record_at(other).get("star_elim", {}) as Dictionary).get(7, 0)) == 0,
		"the conclusion did NOT touch the other record's own input dict")

	# ── 2: and it RELEASES when its premise goes away ─────────────────────
	print("\n=== 2: undoing the binding releases it ===")
	e.record_at(owner)["star_idx"] = -1
	e._full_propagation_refresh()
	var after: int = e._star_elim_state_for_record(other, 7)
	ok(after == 0,
		"star 7 is open again for the other name (state=%d) — this is exactly "
			% after + "what the old broadcast could never do")
	h.queue_free()
	await process_frame

	# ── 3: the confirm path keeps the player's OWN assertion ─────────────
	print("\n=== 3: confirming still records what the player asserted ===")
	var b3: Array = await _build(cd, 4242)
	var g3 = b3[0]
	var h3 = b3[1]
	var e3 = b3[2]
	var owner3: int = e3._find_match_record_by_name(str(g3.star_names[7]))
	var other3: int = e3._find_match_record_by_name(str(g3.star_names[9]))
	e3._propagate_name_confirmed(7, str(g3.star_names[7]))
	var own_elim: Dictionary = e3.record_at(owner3).get("star_elim", {})
	ok(int(own_elim.get(7, 0)) == 1,
		"the confirming record still records star 7 as ITS star")
	ok(int((e3.record_at(other3).get("star_elim", {}) as Dictionary).get(7, 0)) == 0,
		"but nothing was written into any OTHER record's input dict — the leak is gone")
	h3.queue_free()
	await process_frame

	# ── 4: soundness — never rule out a name's own true star ─────────────
	print("\n=== 4: soundness across seeds ===")
	var checked: int = 0
	var violations: int = 0
	for seed_v in [7, 4242]:
		var bb: Array = await _build(cd, seed_v)
		var gg = bb[0]
		var hh = bb[1]
		var ee = bb[2]
		var sn: int = int(bb[3])
		# Bind several names at once, so the cascade runs deep.
		for k in [1, 4, 11]:
			ee.record_at(ee._find_match_record_by_name(str(gg.star_names[k])))["star_idx"] = k
		ee._full_propagation_refresh()
		for v in sn:
			var ri: int = ee._find_match_record_by_name(str(gg.star_names[v]))
			if ri < 0:
				continue
			if ee._star_elim_state_for_record(ri, int(v)) == 2:
				violations += 1
				if violations <= 5:
					print("    UNSOUND seed %d: '%s' ruled out of its OWN star %d"
						% [seed_v, str(gg.star_names[v]), int(v)])
		checked += 1
		hh.queue_free()
		await process_frame
	print("  puzzles checked: %d" % checked)
	ok(checked >= 2, "swept enough puzzles (%d)" % checked)

	var sa: Array = await _build(cd, 4242)
	run_storage_audit(cd, sa[1], sa[2], sa[0], int(sa[3]))
	(sa[1] as Node).queue_free()
	await process_frame
	ok(violations == 0,
		"no name is ever ruled out of the star it really is (%d violations)" % violations)

	print("\nALL PASS (0 failures)" if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()


## Added 2026-08-14 by re-auditing the STORAGE question across every pass
## written since the lint went in — the lint could not see this class at all.
##
## A conclusion about a VALUE must survive when that value has no Sort row.
## Both of these used to write only onto records, so with no row the loop
## ran zero times and the fact was DISCARDED rather than undisplayed.
func run_storage_audit(cd, h, e, g, scn: int) -> void:
	print("\n=== STORAGE: conclusions survive with no record for the value ===")
	# Only ONE name has a row. Every other name value is rowless.
	e._load_match_records([])
	var owner_v: int = 5
	var rec: int = e._get_or_create_match_record_for_name(str(g.star_names[owner_v]))
	e.record_at(rec)["star_idx"] = owner_v          # that name IS that star
	e._full_propagation_refresh()

	var rowless_v: int = (owner_v + 4) % scn
	var row: Array = e._stars_possible_for_descriptor(
		ConstellationLogicPuzzle.Category.NAME, rowless_v)
	print("  '%s' has NO record; its row is %d/%d stars"
		% [str(g.star_names[rowless_v]), row.size(), scn])
	ok(not row.has(owner_v),
		"a rowless name lost the position another name owns (alldiff reached the VALUE)")
	ok(row.size() == scn - 1,
		"and lost exactly that one (%d of %d)" % [row.size(), scn])
