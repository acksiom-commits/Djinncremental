extends "res://dev_tests/test_base.gd"
# The COLUMN half of the identity rule (_settle_identity_from_value_columns).
#
# The engine only ever scanned ROWS: "this record has one position left, so
# it is that one". A logic-grid player scans both directions after every
# mark, and neither implies the other — a column can collapse while the row
# is still wide open. Every such collapse used to go unnoticed until the
# player spotted it and placed it by hand.
#
# Two things to prove, and the second matters more than the first:
#   1. it fires — a column the player collapsed actually binds
#   2. it never binds WRONG — an unsound binding makes a puzzle unsolvable
#      while every tab still looks healthy, so the engine cannot catch it
#      and only an outside check against the solution can.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _build(cd, cid: int, seed_v: int) -> Array:
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = load("res://constellation_logic_puzzle.gd").new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed_v, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	await g.generate_clues_forms()

	var h = OverlayScene.instantiate()
	root.add_child(h)
	await process_frame
	h._cd = cd
	h._constellation_id = cid
	h._star_count = scn
	h._star_names = g.star_names
	h._star_colors = g.star_colors
	h._star_degrees = []
	for _s in scn:
		h._star_degrees.append(0)
	h._pitch_rank_solution = g.pitch_rank_solution
	h._pitch_freqs = cd.get_note_freqs(cid)
	h._star_pitch_index = cd.get_note_assignment(cid)
	h._form_clues_cache = g.chosen_form_clues
	h._rebuild_star_distances()
	h._widgets.clear_pitch_caches()

	var e = h._deduction
	e._load_match_records([])
	for n in g.star_names:
		e._get_or_create_match_record_for_name(str(n))
	for p in range(1, scn + 1):
		e._get_or_create_match_record_for_seq(p)
	return [g, h, e, scn]


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var CAT = ConstellationLogicPuzzle.Category

	# ── 1: it fires, on a column the ROW half cannot see ─────────────────
	#
	# Constructed deliberately rather than hoped for: rule out one target
	# position for every name but one. That leaves the surviving name's own
	# ROW untouched — it can still be anywhere — so the row half has nothing
	# to say and only a column scan can reach the conclusion.
	print("=== 1: a collapsed column binds, where the row half is blind ===")
	var built: Array = await _build(cd, 0, 4242)
	var g0 = built[0]
	var h0 = built[1]
	var e0 = built[2]
	var sc0: int = int(built[3])

	var target_star: int = 3
	var true_name: String = str(g0.star_names[target_star])
	var survivor: int = e0._find_match_record_by_name(true_name)
	for v in sc0:
		if int(v) == target_star:
			continue
		var ri: int = e0._find_match_record_by_name(str(g0.star_names[int(v)]))
		if ri >= 0:
			# The player's own mark: "this name is not that map star."
			e0.record_at(ri)["star_elim"][target_star] = 2
	# Measured BEFORE the refresh. Afterwards the row reads as collapsed —
	# but only because the column rule already bound it, so checking then
	# would prove nothing about which half did the work.
	e0._clear_deduction_caches()
	var row_before: int = e0._candidate_stars_for_record(survivor).size()
	var own_marks: int = (e0.record_at(survivor).get("star_elim", {}) as Dictionary).size()
	print("  before deriving: survivor '%s' has %d/%d candidate positions and %d marks of its own"
		% [true_name, row_before, sc0, own_marks])
	ok(row_before > 1, "the survivor's ROW is wide open (%d candidates) — the row half is blind here"
		% row_before)
	ok(own_marks == 0, "and it carries no eliminations of its own (%d)" % own_marks)

	e0._full_propagation_refresh()
	ok(e0._effective_star_idx(survivor) == target_star,
		"the collapsed COLUMN bound '%s' to star %d (got %d)"
			% [true_name, target_star, e0._effective_star_idx(survivor)])
	h0.queue_free()
	await process_frame

	# ── 2: it stays silent when the column has NOT collapsed ─────────────
	print("\n=== 2: an uncollapsed column binds nothing ===")
	var b2: Array = await _build(cd, 0, 4242)
	var g2 = b2[0]
	var h2 = b2[1]
	var e2 = b2[2]
	var sc2: int = int(b2[3])
	# One short of a collapse: two names still able to be the target.
	var left_open: int = -1
	for v in sc2:
		if int(v) == target_star:
			continue
		if left_open < 0:
			left_open = int(v)
			continue
		var ri2: int = e2._find_match_record_by_name(str(g2.star_names[int(v)]))
		if ri2 >= 0:
			e2.record_at(ri2)["star_elim"][target_star] = 2
	e2._full_propagation_refresh()
	var bound2: int = e2._effective_star_idx(e2._find_match_record_by_name(str(g2.star_names[target_star])))
	ok(bound2 < 0 or bound2 == target_star,
		"with two candidates left, nothing was bound prematurely (star_idx=%d)" % bound2)
	h2.queue_free()
	await process_frame

	# ── 3: soundness sweep — never bind a record to a star it is not ─────
	print("\n=== 3: soundness across seeds and constellations ===")
	var checked: int = 0
	var bindings: int = 0
	var wrong: int = 0
	for cid in [0, 1, 2, 3]:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		for seed_v in [7, 1234, 55555]:
			var b: Array = await _build(cd, cid, seed_v)
			var gg = b[0]
			var hh = b[1]
			var ee = b[2]
			var scn: int = int(b[3])
			# Listen to everything, then let the engine run flat out: this is
			# the state with the most derived facts, so the most chances to
			# bind something wrong.
			for s in scn:
				ee.record_at(ee._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true
			# Force one real column collapse per puzzle, or the sweep binds
			# nothing and its soundness check passes vacuously. The target
			# rotates with the seed so different topologies and different
			# positions get exercised.
			var tgt: int = seed_v % scn
			var want_name: String = str(gg.star_names[tgt])
			for v in scn:
				if int(v) == tgt:
					continue
				var rj: int = ee._find_match_record_by_name(str(gg.star_names[int(v)]))
				if rj >= 0:
					ee.record_at(rj)["star_elim"][tgt] = 2
			ee._full_propagation_refresh()
			var got: int = ee._effective_star_idx(ee._find_match_record_by_name(want_name))
			if got != tgt:
				wrong += 1
				print("    MISSED c%d seed %d: column on star %d did not bind '%s' (got %d)"
					% [cid, seed_v, tgt, want_name, got])

			for i in ee.record_count():
				var bound: int = ee._effective_star_idx(i)
				if bound < 0:
					continue
				# What does this record actually claim to be? Its own name is
				# the ground-truth handle; a name maps to exactly one star.
				var nm: String = str(ee.record_at(i).get("name", ""))
				if nm == "":
					continue
				var truth: int = -1
				for s2 in scn:
					if str(gg.star_names[s2]) == nm:
						truth = s2
						break
				if truth < 0:
					continue
				bindings += 1
				if bound != truth:
					wrong += 1
					if wrong <= 5:
						print("    WRONG c%d seed %d: record %d '%s' bound to %d, truly %d"
							% [cid, seed_v, i, nm, bound, truth])
			checked += 1
			hh.queue_free()
			await process_frame

	print("  puzzles checked: %d, name-bearing records bound: %d" % [checked, bindings])
	ok(checked >= 8, "swept enough puzzles to be meaningful (%d)" % checked)
	ok(bindings >= checked,
		"the sweep actually produced bindings to check (%d over %d puzzles) — "
			% [bindings, checked] + "a vacuous pass here would hide anything")
	ok(wrong == 0,
		"every binding matches the solution, and every forced column fired (%d failures)" % wrong)

	print("\nALL PASS (0 failures)" if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
