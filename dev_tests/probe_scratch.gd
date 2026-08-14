extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends: a permanently red
# suite is one whose red stops meaning anything, which would quietly defeat
# test_matrix_up_lint.gd. Open findings go in that file's KNOWN_UNTRIAGED,
# never in a standing failure here.
#
# Current: refresh cost after _settle_alldiff_position_exclusions. Same
# construction as the 240.0 ms measurement taken earlier today (45 records:
# 15 name rows, 15 seq rows, 15 star stubs), which itself replaced a 318.4 ms
# reading from before the column pass. Same machine, same session, so the
# three are comparable.
#
# The worry being checked: the new pass rebuilds 15 descriptor rows, and
# _clear_deduction_caches drops _descriptor_star_cache, so it and the column
# pass may be re-deriving the same rows several times per fixpoint round.

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
	for n in g.star_names:
		e._get_or_create_match_record_for_name(str(n))
	for p in range(1, scn + 1):
		e._get_or_create_match_record_for_seq(p)
	for s in scn:
		e._get_or_create_match_record_for_star_idx(s)
	e._full_propagation_refresh()

	print("  records: %d" % e.record_count())
	var t0: int = Time.get_ticks_msec()
	for _r in 5:
		e._full_propagation_refresh()
	var per: float = float(Time.get_ticks_msec() - t0) / 5.0
	print("  %.1f ms per refresh (5-run mean)" % per)
	print("  same-session baselines at 45 records: 318.4 ms (before column pass),")
	print("                                        240.0 ms (after column pass)")

	# A mid-game board, where the passes have the most to chew on.
	for k in [1, 4, 11]:
		e.record_at(e._find_match_record_by_name(str(g.star_names[k])))["star_idx"] = k
	e._full_propagation_refresh()
	var t1: int = Time.get_ticks_msec()
	for _r2 in 5:
		e._full_propagation_refresh()
	var mid: float = float(Time.get_ticks_msec() - t1) / 5.0
	print("  with 3 names bound: %.1f ms" % mid)

	ok(per < 600.0, "blank board stays inside budget (%.1f ms)" % per)
	ok(mid < 600.0, "partly-solved board stays inside budget (%.1f ms)" % mid)

	h.queue_free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
