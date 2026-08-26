extends "res://dev_tests/test_base.gd"
# PHASE 2: the derived layer.
#
# _match_records holds only what the player asserted; everything the engine
# concludes lives in _derived, which is wiped and rebuilt every refresh.
# The guarantee under test is that a derived fact cannot outlive its cause,
# and cannot touch player input on its way out.

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
	host._star_count = 5
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Nyxeai"]
	host._star_colors = [0, 0, 1, 2, 3]
	host._star_degrees = [2, 2, 3, 1, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33]
	host._star_pitch_index = [0, 1, 2, 3, 4]
	host._sequence_rank_solution = [0, 1, 2, 3, 4]
	var d = host._deduction
	host._widgets.clear_pitch_caches()

	# ---------------------------------------------------------------
	print("\n=== derived SEQUENCE pin is visible, and releasable ===")
	d._load_match_records([])
	var recs: Array = []
	for nm in host._star_names:
		recs.append(d._get_or_create_match_record_for_name(nm))
	for i in range(4):
		d._match_records[int(recs[i])]["seq_lo"] = i + 1
		d._match_records[int(recs[i])]["seq_hi"] = i + 1
	d._full_propagation_refresh()

	var last: int = d._find_match_record_by_name("Nyxeai")
	ok(d._seq_candidate_set_for(last) == [5],
		"exclusion narrows Nyxeai to position 5")
	ok(int(d._match_records[last].get("seq_lo", 0)) == 0,
		"...WITHOUT writing into the player's own seq_lo")

	# The whole point: withdraw the cause, get the conclusion back.
	var k: int = d._find_match_record_by_name("Keriion")
	d._match_records[k]["seq_lo"] = 0
	d._match_records[k]["seq_hi"] = 0
	d._full_propagation_refresh()
	last = d._find_match_record_by_name("Nyxeai")
	ok(d._seq_candidate_set_for(last) != [5],
		"un-pinning Keriion RELEASES Nyxeai's derived position")

	# ---------------------------------------------------------------
	print("\n=== derived value eliminations are releasable ===")
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	var p: int = d._get_or_create_match_record_for_name("Pyrios")
	# Star 2 is the only White star.
	d._match_records[p]["color_states"] = {1: 2}
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Pyrios") == 2,
		"eliminating White rules Pyrios out of the White star")
	ok(not (d._match_records[d._find_match_record_by_name("Pyrios")]
			.get("star_elim", {}) as Dictionary).has(2),
		"...WITHOUT writing into the player's own star_elim")
	d._match_records[d._find_match_record_by_name("Pyrios")]["color_states"] = {}
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Pyrios") != 2, "undoing the colour releases it")

	# ---------------------------------------------------------------
	print("\n=== player input is never derived over ===")
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	var h: int = d._get_or_create_match_record_for_name("Helios")
	var elim: Dictionary = d._match_records[h].get("star_elim", {})
	elim[2] = 2
	d._match_records[h]["star_elim"] = elim
	d._set_star_name_user_blocked(2, "Helios", true)
	d._match_records[h]["color_states"] = {1: 2}      # derives the same thing
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Helios") == 2, "X holds while a derivation agrees")
	d._match_records[d._find_match_record_by_name("Helios")]["color_states"] = {}
	d._full_propagation_refresh()
	ok(d._star_elim_state(2, "Helios") == 2,
		"X SURVIVES the agreeing derivation being withdrawn")

	# ---------------------------------------------------------------
	print("\n=== nothing derived reaches the save file ===")
	d._load_match_records([])
	var p2: int = d._get_or_create_match_record_for_name("Pyrios")
	d._match_records[p2]["color_states"] = {1: 2}
	d._full_propagation_refresh()
	var saved: Array = d._save_match_records()
	var leaked: Array = []
	for e in saved:
		var ee: Dictionary = e
		if (ee.get("star_elim", {}) as Dictionary).size() > 0 \
				and str(ee.get("name", "")) == "Pyrios":
			leaked.append("star_elim")
		if ee.has("color_star_elim_marks") or ee.has("derived_value_elim_marks"):
			leaked.append("ownership marks")
	ok(leaked.is_empty(), "saved records carry no derived state (%s)" % str(leaked))

	# ---------------------------------------------------------------
	print("\n=== the fixpoint settles ===")
	ok(d._derived_fact_count() > 0, "the layer holds facts after a refresh")
	var n1: int = d._derived_fact_count()
	d._full_propagation_refresh()
	ok(d._derived_fact_count() == n1,
		"a second refresh reaches the same total — derivation is stable")

	print("\n=== KNOWN PHASE 3 GAP (not a failure) ===")
	d._load_match_records([])
	var p3: int = d._get_or_create_match_record_for_name("Pyrios")
	d._match_records[p3]["color_states"] = {0: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	p3 = d._find_match_record_by_name("Pyrios")
	var bound: int = int(d._match_records[p3].get("star_idx", -1))
	d._match_records[p3]["color_states"] = {}
	d._full_propagation_refresh()
	p3 = d._find_match_record_by_name("Pyrios")
	print("   derived star_idx: bound=%d, still bound after withdrawal=%s" \
		% [bound, str(int(d._match_records[p3].get("star_idx", -1)) == bound)])
	print("   (identity stays input-only in Phase 2 — merges are destructive)")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
