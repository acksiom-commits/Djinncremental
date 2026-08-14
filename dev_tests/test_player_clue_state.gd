extends "res://dev_tests/test_base.gd"
# PLAYER-CONTROLLED CLUE STATE (built 2026-08-14, replacing the utility
# categorisation).
#
#   GREEN    untouched
#   MAGENTA  the player marked something the clue NAMES
#   USED UP  the player right-clicked it; right-click again restores it
#
# The trap this pins hardest: "the player marked it" must EXCLUDE the
# sibling-clearing fallout of a confirm. Confirming one name sets
# name_states to 2 for every OTHER name on that record, so counting raw
# state != 0 would turn nearly every clue magenta on the first click and
# make the whole colour scheme useless immediately.

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
	# The scene must still expose every tab button the scripts bind to —
	# these are .tscn node paths, so a rename breaks them silently at load.
	ok(h._tab_clues != null and h._tab_used_up != null and h._tab_guide != null
			and h._tab_search != null and h._tab_hint != null,
		"all five tab buttons resolve from the scene")
	ok(h._tab_clues.text == "Clues" and h._tab_hint.text == "HINT",
		"tabs are labelled Clues / ... / HINT")

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

	# ── nothing marked -> nothing magenta ────────────────────────────────
	print("\n=== a fresh board is all green ===")
	ok(e.player_marked_terms().is_empty(),
		"no player-marked terms on a fresh board (%d)" % e.player_marked_terms().size())
	var magenta: int = 0
	var total: int = 0
	for clue in h._widgets._all_final_clues_for_tabs():
		total += 1
		if h._widgets._clue_state_color(clue, e.player_marked_terms()) == h.STATE_COLORS.protected:
			magenta += 1
	print("  %d clues, %d magenta" % [total, magenta])
	ok(magenta == 0, "every clue starts green (%d magenta)" % magenta)

	# ── THE TRAP: a confirm must not turn everything magenta ─────────────
	print("\n=== confirming one name marks ONE name, not all of them ===")
	var rec: int = e._get_or_create_match_record_for_name(str(g.star_names[0]))
	e._propagate_name_states_confirmed_same_record(rec, str(g.star_names[0]))
	var terms: Dictionary = e.player_marked_terms()
	var name_terms: int = 0
	for t in terms:
		if str(t).begins_with("N:"):
			name_terms += 1
	print("  name terms marked: %d (of %d names)" % [name_terms, scn])
	ok(name_terms == 1,
		"only the CONFIRMED name counts, not the %d siblings it eliminated" % (scn - 1))
	ok(terms.has("N:" + str(g.star_names[0])), "and it is the right name")

	# A hand-made block DOES count — that is a player decision too.
	e.record_at(rec)["manual_name_blocks"] = {str(g.star_names[1]): true}
	ok(e.player_marked_terms().has("N:" + str(g.star_names[1])),
		"a manual block counts as a player mark")

	# ── retire / restore ────────────────────────────────────────────────
	print("\n=== right-click retires, right-click restores ===")
	var some: String = ""
	for clue in h._widgets._all_final_clues_for_tabs():
		some = str((clue as Dictionary).get("text", ""))
		if some != "":
			break
	ok(not e.is_clue_retired(some), "clue starts in the working list")
	e.toggle_clue_retired(some)
	ok(e.is_clue_retired(some), "right-click retires it to Used Up")
	e.toggle_clue_retired(some)
	ok(not e.is_clue_retired(some), "right-click again brings it back")

	# ── retirement persists, and does not leak across constellations ────
	print("\n=== persistence ===")
	# set_player_puzzle_notes early-returns unless a puzzle cache entry
	# exists for this constellation. The harness builds its puzzle by hand
	# and never populated one, so give it the minimum to write into.
	if not cd._puzzle_cache.has("0"):
		cd._puzzle_cache["0"] = {}
	e.toggle_clue_retired(some)      # also writes the notes
	var notes: Dictionary = cd.get_player_puzzle_notes(0)
	ok((notes.get("retired_clues", []) as Array).has(some),
		"the retired set reaches the save notes")
	e._retired_clues.clear()
	ok(not e.is_clue_retired(some), "cleared in memory")
	for t2 in (notes.get("retired_clues", []) as Array):
		e._retired_clues[str(t2)] = true
	ok(e.is_clue_retired(some), "and restores from the notes")

	h.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
