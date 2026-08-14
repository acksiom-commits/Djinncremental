extends "res://dev_tests/test_base.gd"
# DERIVED-VS-INPUT OWNERSHIP.
#
# Reported live (2026-08-10), clue "Keriion fires between the star that
# plays F5 and Selion": X-ing both Keriion and Selion off the F5 star's
# name checklist was impossible — the second X released the first — and
# then typing Keriion's sequence position un-X'd Keriion again.
#
# Root cause: _recompute_color_star_elim marked EVERY non-candidate star as
# engine-owned, including stars the player had already X'd. Its release
# pass then handed the player's own input back to neutral.
#
# The rule this file pins down: a derived pass may release only what it
# itself derived. Player input is never the engine's to take back.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame

	# 5 stars. Colours chosen so a single colour elimination constrains a
	# record's candidate set without collapsing it to one star.
	host._constellation_id = 0
	host._star_count = 5
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Nyxeai"]
	host._star_colors = [0, 0, 1, 2, 3]        # Blue Blue White Yellow Red
	host._star_degrees = [2, 2, 3, 1, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33]
	host._star_pitch_index = [0, 1, 2, 3, 4]
	host._pitch_rank_solution = [0, 1, 2, 3, 4]
	var d = host._deduction
	host._widgets.clear_pitch_caches()

	var F5_STAR: int = 3        # stand-in for "the star that plays F5"
	var WHITE: int = 1

	# ---------------------------------------------------------------
	print("\n=== REPORTED CASE: two X's on the same star's checklist ===")
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)

	# Constrain both name records so _recompute_color_star_elim has
	# something to derive at all (an unconstrained record marks nothing).
	for nm in ["Keriion", "Selion"]:
		var rec: int = d._get_or_create_match_record_for_name(nm)
		d._match_records[rec]["color_states"] = {WHITE: 2}

	# Player X's Keriion off the F5 star, exactly as _on_name_x does.
	x_off(d, "Keriion", F5_STAR)
	d._full_propagation_refresh()
	ok(d._star_elim_state(F5_STAR, "Keriion") == 2,
		"Keriion stays X'd off the F5 star after a refresh")

	# Player X's Selion off the SAME star. This is the reported failure:
	# the second X used to release the first.
	x_off(d, "Selion", F5_STAR)
	d._full_propagation_refresh()
	ok(d._star_elim_state(F5_STAR, "Keriion") == 2,
		"Keriion STILL X'd after Selion is X'd off the same star")
	ok(d._star_elim_state(F5_STAR, "Selion") == 2,
		"Selion is X'd off the F5 star")

	# ---------------------------------------------------------------
	print("\n=== REPORTED CASE 2: a sequence entry must not un-X a name ===")
	var k: int = d._find_match_record_by_name("Keriion")
	d._match_records[k]["seq_lo"] = 1
	d._match_records[k]["seq_hi"] = 1
	d._full_propagation_refresh()
	ok(d._star_elim_state(F5_STAR, "Keriion") == 2,
		"pinning Keriion to position 1 does not un-X it on the F5 star")
	ok(d._star_elim_state(F5_STAR, "Selion") == 2,
		"...and does not un-X Selion either")

	# ---------------------------------------------------------------
	print("\n=== the engine may still release its OWN derivations ===")
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	var p: int = d._get_or_create_match_record_for_name("Pyrios")
	d._match_records[p]["color_states"] = {WHITE: 2}
	d._full_propagation_refresh()
	# Star 2 is the only White star, so eliminating White must rule it out.
	ok(d._star_elim_state(2, "Pyrios") == 2,
		"eliminating White derives a star-2 exclusion for Pyrios")
	ok(not d._is_star_name_user_blocked(2, "Pyrios"),
		"...and that exclusion is NOT recorded as player input")
	d._match_records[d._find_match_record_by_name("Pyrios")]["color_states"] = {}
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Pyrios") != 2,
		"undoing the colour elimination releases the derived exclusion")

	# ---------------------------------------------------------------
	print("\n=== a player X survives an unrelated derivation cycle ===")
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	var h: int = d._get_or_create_match_record_for_name("Helios")
	x_off(d, "Helios", 2)                      # player's own X on star 2
	d._match_records[h]["color_states"] = {WHITE: 2}   # ALSO derives star 2
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Helios") == 2, "X holds while a derivation agrees")
	d._match_records[d._find_match_record_by_name("Helios")]["color_states"] = {}
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Helios") == 2,
		"X SURVIVES when the agreeing derivation is withdrawn")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()


## Exactly what _on_name_x() writes: the elimination on the name record,
## plus the manual-block flag on the star's own record.
func x_off(d, name_str: String, star_idx: int) -> void:
	var rec: int = d._get_or_create_match_record_for_name(name_str)
	var elim: Dictionary = d._match_records[rec].get("star_elim", {})
	elim[star_idx] = 2
	d._match_records[rec]["star_elim"] = elim
	d._set_star_name_user_blocked(star_idx, name_str, true)
