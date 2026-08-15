extends "res://dev_tests/test_base.gd"
# A merge is DESTRUCTIVE and permanent. _settle_identical_records is the
# engine INFERRING identity, so letting it fold a record into an
# auto-created star-widget stub let an inference the player can retract
# produce a consequence they could not.
#
# Reported 2026-08-14: naming a Sort:Pitch slot whose note only one star
# plays merged the slot into that star's widget record, putting the name on
# the star map. UNDO SELECTS then cleared the name but the star stayed
# identified — there is no un-merge.
#
# The player's OWN confirm path is deliberately untouched:
# _confirm_match_record_identity calls _merge_match_records directly for
# exactly this stub case, and should — there the player asserted the
# identity outright and the widget that owns it can take it back.
#
# The trap this test also pins: a singleton-pitch slot on a fully listened
# board resolves to its star from PITCH ALONE, before any name exists. That
# binding is correct and must survive an undo of the name. Measuring after
# the name and blaming it for the binding is the mistake this file exists to
# stop repeating.

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
	# Every star widget rendered, every star listened — the reporter's board.
	for s in scn:
		e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true

	# A note exactly one star plays; with two sharers the slot pins nothing
	# and the situation cannot arise at all.
	var star: int = -1
	var note: String = ""
	for cand in scn:
		var n: String = h._widgets._note_name_for_star(int(cand))
		var c: int = 0
		for s in scn:
			if h._widgets._note_name_for_star(s) == n:
				c += 1
		if c == 1:
			star = int(cand)
			note = n
			break
	if star < 0:
		print("  (no singleton-pitch star in this puzzle — cannot exercise the case)")
		ok(false, "expected a singleton-pitch star to exist for this seed")
		print("\nFAILURES (%d failures)" % fails)
		finish()
		return

	var freq: float = 0.0
	for i in h._pitch_freqs.size():
		if ConstellationLogicPuzzle.note_name_for_freq(h._pitch_freqs[i]) == note:
			freq = float(h._pitch_freqs[i])
	var slot: int = e._get_or_create_match_record_for_pitch_slot(freq, 0)
	var nm: String = str(g.star_names[star])
	print("  slot '%s' (only star %d plays %s); naming it '%s'"
		% [str(e.record_at(slot).get("pitch_slot_label", "")), star, note, nm])

	e._full_propagation_refresh()
	var star_before: int = e._effective_star_idx(slot)
	var count_before: int = e.record_count()
	print("  before any name: eff_star=%d, map shows '%s'"
		% [star_before, h._widgets._confirmed_name_for_star(star)])

	# The select, exactly as _on_slot_name_check drives it.
	e._propagate_name_states_confirmed_same_record(slot, nm)
	e._full_propagation_refresh()
	var found: int = -1
	for i in e.record_count():
		if str(e.record_at(i).get("pitch_slot_label", "")).begins_with(note):
			found = i
			break
	ok(e.record_count() == count_before,
		"naming the slot does not merge it into the star's widget record (%d -> %d)"
			% [count_before, e.record_count()])
	ok(found >= 0, "the slot record still exists in its own right")
	# CORRECTED 2026-08-14, and this is the third assertion of mine changed
	# today, so: the earlier version demanded the map show NOTHING here.
	# That was an over-correction. The original complaint had two halves —
	# the map claimed the star, AND undo could not take it back — and only
	# the second was the real fault. Removing the merge fixed it; also
	# suppressing the display went too far, and left Name as the only one of
	# the three star-tag readers that did not show what the engine knows
	# (reported the next day: Sequence and Pitch appeared, Name did not).
	#
	# So the invariant is NOT "the map stays blank". It is "the map shows
	# what is currently known, and gives it back when the premise goes" —
	# which is exactly what the undo checks below assert.
	ok(h._widgets._confirmed_name_for_star(star) == nm,
		"the star map shows the deduced name (got '%s')"
			% h._widgets._confirmed_name_for_star(star))

	# The undo, exactly as _on_slot_name_undo_selects drives it.
	e._undo_category_selects(found, "name_states", "manual_name_blocks",
		"protected_staff_names", h._star_names.duplicate())
	e._full_propagation_refresh()
	ok(str(e.record_at(found).get("name", "")) == "",
		"UNDO clears the promoted name")
	ok(e._effective_star_idx(found) == star_before,
		"and the binding returns to what PITCH alone justified (%d, was %d)"
			% [e._effective_star_idx(found), star_before])
	ok(h._widgets._confirmed_name_for_star(star) == "",
		"the star map is still clean after the undo")

	run_no_leak_check(h, e, g, scn)
	h.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()


## The anti-leak that the display change must NOT weaken: a star whose
## widget record is a bare auto-created stub — nothing named, nothing
## deduced — must show no name, or the map would be handing over the answer
## for free on a fresh board.
func run_no_leak_check(h, e, g, scn: int) -> void:
	print("\n=== a bare stub still gives nothing away ===")
	e._load_match_records([])
	for s in scn:
		e._get_or_create_match_record_for_star_idx(s)
	e._full_propagation_refresh()
	var leaked: int = 0
	for s in scn:
		if h._widgets._confirmed_name_for_star(int(s)) != "":
			leaked += 1
	print("  %d stars, names shown on a fresh board: %d" % [scn, leaked])
	ok(leaked == 0, "no star tag shows a name from an unearned stub (%d leaked)" % leaked)
