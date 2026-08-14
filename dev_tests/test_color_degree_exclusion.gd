extends "res://dev_tests/test_base.gd"
# The Color/Degree half of the display-only exclusion asymmetry family
# (Name and Pitch fixed 2026-08-11/12; see
# constellation_puzzle_record_identity_unification memory).
#
# _compute_excluded_colors_for / _compute_excluded_degrees_for existed and
# were correct, but were only ever called from constellation_puzzle_widgets.gd
# display sites -- no deduction pass ever pushed their conclusions into a
# form _settle_singleton_colors/_settle_singleton_degrees could see, so a
# record narrowed to its last remaining colour/degree by cross-record
# incidence accounting never got promoted to a confirm.
#
# Fixing Degree surfaced a SECOND, deeper, pre-existing bug: unlike
# _effective_color_state/_effective_pitch_state/_effective_name_state (which
# all route through _record_effective_state and its derived-layer fallback
# tier), _effective_degree_state was a hand-rolled two-tier implementation
# (raw player input, then ground truth) that never consulted the derived
# layer at all. _settle_singleton_degrees's own confirm promotion has been
# dead code since the derived layer was introduced -- writing into
# _derived[i]["degree_states"] that nothing downstream ever read back.
# Both fixes are covered here since the exclusion pass's writes are what
# exposed the reader bug.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


func make_host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	return host


func run() -> void:
	# ---- 1. Color: incidence-2 exclusion promotes the last remaining one ----
	print("\n=== 1. colour incidence-2 exclusion promotes a confirm ===")
	var host = make_host()
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [5, 5, 6, 6, 7, 7]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
	host._star_pitch_index = [0, 1, 2, 3, 0, 1]
	host._pitch_rank_solution = [0, 1, 2, 3, 0, 1]
	host._widgets.clear_pitch_caches()
	var d = host._deduction

	d._load_match_records([])
	var blue_a: int = d._get_or_create_match_record_for_star_idx(2)   # colour 1, degree 6
	var blue_b: int = d._get_or_create_match_record_for_star_idx(3)   # colour 1, degree 6
	var third: int = d._get_or_create_match_record_for_name("Eos")
	# Proven distinct from both Blue stars via DEGREE (not colour, the axis
	# under test): confirms degree 5, which both Blue stars are eliminated
	# on by ground truth (their true degree is 6).
	d._match_records[third]["degree_states"] = {5: 1}
	# Narrowed by hand to exactly two remaining colours: 1 (shared, about to
	# be excluded once both its carriers are accounted for) and 2.
	d._match_records[third]["color_states"] = {0: 2}
	d._full_propagation_refresh()

	ok(d._records_provably_distinct(third, blue_a) and d._records_provably_distinct(third, blue_b),
		"sanity: third is provably distinct from both Blue stars")
	ok(d._effective_color_state(third, 1) == 2 and d._effective_color_state(third, 2) == 1,
		"colour 1 excluded, colour 2 promoted (got %d, %d)"
			% [d._effective_color_state(third, 1), d._effective_color_state(third, 2)])

	# ---- 2. release: un-pinning the distinguishing fact withdraws it ----
	print("\n=== 2. the promotion releases with its cause ===")
	d._match_records[third]["degree_states"] = {}
	d._full_propagation_refresh()
	ok(d._effective_color_state(third, 2) != 1,
		"colour 2 is no longer confirmed once third can't be proven distinct")

	# ---- 3. Degree: incidence-2 exclusion promotes (mirror of 1) ----
	print("\n=== 3. degree incidence-2 exclusion promotes a confirm ===")
	d._load_match_records([])
	var deg_a: int = d._get_or_create_match_record_for_star_idx(0)   # degree 5, colour 0
	var deg_b: int = d._get_or_create_match_record_for_star_idx(1)   # degree 5, colour 0
	var third2: int = d._get_or_create_match_record_for_name("Eos")
	# Proven distinct via COLOUR this time (mirror axis choice of case 1).
	d._match_records[third2]["color_states"] = {2: 1}
	# Narrowed by hand to exactly two remaining degrees: 5 (shared) and 6.
	d._match_records[third2]["degree_states"] = {7: 2}
	d._full_propagation_refresh()

	ok(d._records_provably_distinct(third2, deg_a) and d._records_provably_distinct(third2, deg_b),
		"sanity: third2 is provably distinct from both degree-5 stars")
	ok(d._effective_degree_state(third2, 5) == 2 and d._effective_degree_state(third2, 6) == 1,
		"degree 5 excluded, degree 6 promoted (got %d, %d)"
			% [d._effective_degree_state(third2, 5), d._effective_degree_state(third2, 6)])

	# ---- 4. the deeper bug directly: _effective_degree_state's derived tier ----
	# Isolates the reader bug from the exclusion-pass bug: a bare
	# _add_derived_state call with no exclusion logic involved at all must
	# be visible through _effective_degree_state, the same as it already is
	# for color/pitch/name.
	print("\n=== 4. _effective_degree_state reads the derived layer directly ===")
	d._load_match_records([])
	var bare: int = d._get_or_create_match_record_for_name("Zeta")
	ok(d._effective_degree_state(bare, 6) == 0, "sanity: neutral before any derived fact")
	d._add_derived_state(bare, "degree_states", 6, 1)
	ok(d._effective_degree_state(bare, 6) == 1,
		"a bare derived confirm is visible (this is what was dead code before the fix)")

	# ---- 5. no leak: a resolved star's degree still comes from ground truth ----
	# Fresh record, not deg_a/deg_b -- both went stale when section 4 above
	# reloaded an empty record set.
	print("\n=== 5. a resolved record still reads ground truth, not the derived layer ===")
	var resolved: int = d._get_or_create_match_record_for_star_idx(0)   # degree 5, colour 0
	ok(d._effective_star_idx(resolved) >= 0, "sanity: resolved is star_idx-bound")
	ok(d._effective_degree_state(resolved, 5) == 1 and d._effective_degree_state(resolved, 6) == 2,
		"ground truth still wins over any derived state for a resolved record")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
