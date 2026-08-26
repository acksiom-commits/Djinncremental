extends "res://dev_tests/test_base.gd"
# PHASE 3: derived identity.
#
# "This record IS star N" concluded by the engine now lives in the derived
# layer and releases with its cause. It used to be written into
# r["star_idx"] — a player-input field, with no ownership mark — so
# eliminating every colour but one bound the record permanently, and
# clearing those eliminations did not undo it.
#
# The reason it outlived Phase 2 is that identity is not just another
# fact: two records agreeing on a star triggers a DESTRUCTIVE merge, and a
# destroyed record cannot return when the derived layer is wiped. So the
# tests below check both halves — that state resolution follows derived
# identity, and that nothing destructive or durable does.

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

	# ── THE HEADLINE ────────────────────────────────────────────────
	print("\n=== derived identity RELEASES (the Phase 2 gap) ===")
	d._load_match_records([])
	var p: int = d._get_or_create_match_record_for_name("Pyrios")
	# Star 2 is the only White star, so ruling out the rest forces it.
	d._match_records[p]["color_states"] = {0: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	p = d._find_match_record_by_name("Pyrios")
	ok(d._effective_star_idx(p) == 2, "narrowing binds Pyrios to star 2")
	ok(int(d._match_records[p].get("star_idx", -1)) == -1,
		"...WITHOUT writing the player's own star_idx")

	d._match_records[p]["color_states"] = {}
	d._full_propagation_refresh()
	p = d._find_match_record_by_name("Pyrios")
	ok(d._effective_star_idx(p) == -1,
		"withdrawing the cause RELEASES the binding (this is the bug)")

	print("\n=== a derived binding still resolves the other axes ===")
	d._match_records[p]["color_states"] = {0: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	p = d._find_match_record_by_name("Pyrios")
	ok(d._effective_degree_state(p, int(host._star_degrees[2])) == 1,
		"degree resolves off the derived identity")
	ok(d._effective_color_state(p, 1) == 1, "colour resolves off it too")
	ok((d._match_records[p].get("color_states", {}) as Dictionary).get(1, 0) != 1,
		"...and none of that was written back into the record")

	print("\n=== a player confirm still wins and still persists ===")
	d._load_match_records([])
	var h: int = d._get_or_create_match_record_for_name("Helios")
	d._match_records[h]["star_idx"] = 3
	d._full_propagation_refresh()
	h = d._find_match_record_by_name("Helios")
	ok(d._effective_star_idx(h) == 3, "confirmed identity reads through")
	var saved: Array = d._save_match_records()
	var found_confirmed := false
	var leaked_derived := false
	for e in saved:
		var ee: Dictionary = e
		if str(ee.get("name", "")) == "Helios" and int(ee.get("star_idx", -1)) == 3:
			found_confirmed = true
		if str(ee.get("name", "")) == "Pyrios" and int(ee.get("star_idx", -1)) >= 0:
			leaked_derived = true
	ok(found_confirmed, "a CONFIRMED identity is saved")
	ok(not leaked_derived, "a DERIVED identity is never saved")

	# ── THE DANGEROUS HALF ──────────────────────────────────────────
	print("\n=== derived identity never triggers a destructive merge ===")
	d._load_match_records([])
	var before_count: int = 0
	var s2: int = d._get_or_create_match_record_for_star_idx(2)
	var p2: int = d._get_or_create_match_record_for_name("Pyrios")
	d._match_records[p2]["color_states"] = {0: 2, 2: 2, 3: 2}   # derives star 2
	before_count = d.record_count()
	d._full_propagation_refresh()
	ok(d.record_count() == before_count,
		"record count unchanged — no merge (%d -> %d)" % [before_count, d.record_count()])
	ok(d._find_match_record_by_name("Pyrios") >= 0, "the name record still exists")
	# And it must survive the cause being withdrawn, which a merge would
	# have made impossible.
	d._match_records[d._find_match_record_by_name("Pyrios")]["color_states"] = {}
	d._full_propagation_refresh()
	ok(d._find_match_record_by_name("Pyrios") >= 0
			and d._effective_star_idx(d._find_match_record_by_name("Pyrios")) == -1,
		"...and releases cleanly afterwards")

	print("\n=== two records cannot both derive the same star ===")
	d._load_match_records([])
	var a: int = d._get_or_create_match_record_for_name("Keriion")
	var b: int = d._get_or_create_match_record_for_name("Selion")
	d._match_records[a]["color_states"] = {0: 2, 2: 2, 3: 2}
	d._match_records[b]["color_states"] = {0: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	a = d._find_match_record_by_name("Keriion")
	b = d._find_match_record_by_name("Selion")
	# `var both: bool =`, NOT `:=`. `d` is untyped here, so every call on it
	# returns Variant, and := cannot infer a type through the comparison —
	# which fails to COMPILE, and a non-compiling .gd is completely silent
	# in every Godot mode. Cost 20 minutes to find; can_instantiate() is
	# the only thing that reports it.
	var both: bool = d._effective_star_idx(a) >= 0 \
		and d._effective_star_idx(a) == d._effective_star_idx(b)
	ok(not both, "at most one of the two claims star 2")

	# ── THE ABSORPTION HOLE, NOW CLOSED ─────────────────────────────
	print("\n=== a mark contradicting the settled star is reported ===")
	# This can only arise from a CONFIRMED identity, never a derived one:
	# any mark that rules the star out also removes it from the candidate
	# set, so the engine would never have derived that binding in the first
	# place. The reachable case is the player pinning a star on the map
	# while an older mark of theirs says it cannot be that star — and
	# before this, ground truth simply overruled the mark in silence.
	d._load_match_records([])
	var n: int = d._get_or_create_match_record_for_name("Nyxeai")
	d._match_records[n]["star_idx"] = 2          # confirmed via the map
	d._match_records[n]["color_states"] = {1: 2} # ...but star 2's colour was X'd
	d._full_propagation_refresh()
	n = d._find_match_record_by_name("Nyxeai")
	var ground_clash := false
	for c in d._contradictions:
		print("      %s" % str((c as Dictionary).get("text", "")))
		if str((c as Dictionary).get("axis", "")) == "ground-truth":
			ground_clash = true
	ok(ground_clash, "the mark/ground-truth conflict surfaces, not absorbed")
	# And it must clear when the stale mark goes, like any other.
	d._match_records[n]["color_states"] = {}
	d._full_propagation_refresh()
	var still := false
	for c in d._contradictions:
		if str((c as Dictionary).get("axis", "")) == "ground-truth":
			still = true
	ok(not still, "clears once the contradicting mark is removed")

	print("\n=== the fixpoint still settles with identity inside it ===")
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	for nm in host._star_names:
		d._get_or_create_match_record_for_name(nm)
	d._match_records[d._find_match_record_by_name("Pyrios")]["color_states"] = {0: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	var n1: int = d._derived_fact_count()
	d._full_propagation_refresh()
	ok(d._derived_fact_count() == n1,
		"two refreshes reach the same total (%d)" % n1)

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
