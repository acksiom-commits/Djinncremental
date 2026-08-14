extends "res://dev_tests/test_base.gd"
# Right-click "still possible" (magenta, state 4) and its sibling
# soft-eliminated (state 3) must reach EVERY popup, not just the star map.
#
# The row renderers always painted both — staff_popup_row.gd and
# _style_color_toggle_btn each have explicit 3 and 4 branches. What was
# missing is that _effective_*_state collapses 3 -> 2 and 4 -> 0 for
# deduction, and the popups read through it, so the styling was
# unreachable. Only the star map showed magenta, via its own separate
# _effective_name_display_state().

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame

	host._constellation_id = 0
	# Six stars, no colour unique, and TWO values protected per axis.
	# Protecting exactly one value is a singleton confirm — the engine
	# rightly promotes it to state 1, and no magenta is involved. The soft
	# tier only exists while a genuine choice remains open.
	host._star_count = 6
	host._star_names = ["Pyrios", "Beta", "Gamma", "Delta", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 3]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33, 622.25]
	host._star_pitch_index = [0, 1, 2, 3, 4, 5]
	host._pitch_rank_solution = [0, 1, 2, 3, 4, 5]
	var d = host._deduction
	var w = host._widgets
	w.clear_pitch_caches()

	var notes: Array = []
	for s in host._star_count:
		notes.append(w._note_name_for_star(s))

	d._load_match_records([])
	var rec: int = d._get_or_create_match_record_for_name("Pyrios")
	# Right-click "still possible" on one value per axis.
	d._match_records[rec]["protected_color_idxs"] = {0: true, 1: true}
	d._match_records[rec]["protected_pitch_notes"] = {str(notes[0]): true, str(notes[1]): true}
	d._full_propagation_refresh()
	rec = d._find_match_record_by_name("Pyrios")

	print("\n=== LOGIC readers still collapse (deduction must not see soft) ===")
	ok(d._effective_color_state(rec, 0) == 0, "protected colour reads neutral to logic")
	ok(d._effective_color_state(rec, 2) == 2, "sibling colour reads eliminated to logic")
	ok(d._effective_pitch_state(rec, str(notes[0])) == 0, "protected pitch neutral to logic")
	ok(d._effective_pitch_state(rec, str(notes[2])) == 2, "sibling pitch eliminated to logic")

	print("\n=== DISPLAY readers expose the magenta tier ===")
	ok(d._effective_color_state(rec, 0, false) == 4, "protected colour is 4 (magenta)")
	ok(d._effective_color_state(rec, 2, false) == 3, "sibling colour is 3 (soft)")
	ok(d._effective_pitch_state(rec, str(notes[0]), false) == 4, "protected pitch is 4")
	ok(d._effective_pitch_state(rec, str(notes[2]), false) == 3, "sibling pitch is 3")
	# Name rows need a record with NO confirmed name — a record that already
	# IS Pyrios cannot be Beta, protect or not, and rightly short-circuits to
	# a hard 2. The staff popup shows name rows for exactly this kind of
	# unidentified slot record.
	var slot: int = d._get_or_create_match_record_for_seq(3)
	d._match_records[slot]["protected_staff_names"] = {"Beta": true, "Gamma": true}
	d._full_propagation_refresh()
	ok(d._effective_name_state(slot, "Beta", false) == 4, "protected name is 4")
	ok(d._effective_name_state(slot, "Delta", false) == 3, "sibling name is 3")
	ok(d._effective_name_state(slot, "Beta") == 0, "...still neutral to logic")
	ok(d._effective_name_state(slot, "Delta") == 2, "...sibling still hard to logic")

	print("\n=== a HARD state still outranks the soft tier ===")
	d._match_records[rec]["color_states"] = {3: 2}
	d._full_propagation_refresh()
	rec = d._find_match_record_by_name("Pyrios")
	ok(d._effective_color_state(rec, 3, false) == 2,
		"a hard X shows as eliminated, not soft-eliminated")
	ok(d._effective_color_state(rec, 0, false) == 4,
		"...and the protected one is still magenta")

	print("\n=== every row renderer handles 3 and 4 ===")
	# Guards against a popup being added later that only styles 0/1/2.
	var row_script = load("res://staff_popup_row.gd")
	var src: String = FileAccess.get_file_as_string("res://staff_popup_row.gd")
	ok(src.contains("3:") and src.contains("4:"), "staff_popup_row styles 3 and 4")
	var wsrc: String = FileAccess.get_file_as_string("res://constellation_puzzle_widgets.gd")
	ok(wsrc.contains("STATE_COLORS.protected"), "widgets styles the protected colour")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
