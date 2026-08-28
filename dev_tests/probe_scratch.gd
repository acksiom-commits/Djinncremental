extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver -- EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# GENERATOR HEALTH at a glance: per-puzzle wall time, shipped clue count,
# gate/closure, tier mix vs target, Form share, and each puzzle's opening
# clue (the guaranteed Mutual Exclusion) so its WORDING is in front of a
# human every run -- the one thing the suite structurally cannot check.
#
# Two puzzles on purpose. This runs inside every suite invocation, and at
# six it was the most expensive module in the run.

const SEEDS := [11]
const CONSTELLATIONS := [0, 2]

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var P = load("res://constellation_logic_puzzle.gd")

	var puzzles: int = 0
	var total_clues: int = 0
	var tier_counts: Dictionary = {1: 0, 2: 0, 3: 0}
	var form_counts: Dictionary = {}
	var gate_ok: int = 0
	var closure_ok: int = 0
	var unbound: int = 0

	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in SEEDS:
			var g = P.new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
			var t0: int = Time.get_ticks_msec()
			var r: Dictionary = await g._generate_clues_forms_attempt()
			var elapsed: int = Time.get_ticks_msec() - t0
			puzzles += 1
			var clues: Array = g.chosen_form_clues
			total_clues += clues.size()
			print("    c%d seed %-6d %6.1f s   %d clues" % [cid, seed,
				float(elapsed) / 1000.0, clues.size()])
			if not clues.is_empty():
				print("        %s" % str((clues[0] as Dictionary).get("text", "")))
			if bool(r.get("seq_unique", false)) and bool(r.get("name_unique", false)):
				gate_ok += 1
			if bool(r.get("name_unique_closure", false)):
				closure_ok += 1
			var nr: Array = []
			for _i in scn:
				nr.append(false)
			g._recompute_name_revealed(nr)
			for v in nr:
				if not bool(v):
					unbound += 1
			for c in clues:
				var fid: int = int((c as Dictionary).get("form_id", -1))
				tier_counts[int(P.FORM_TIER.get(fid, 2))] = int(tier_counts[int(P.FORM_TIER.get(fid, 2))]) + 1
				var fn: String = str((c as Dictionary).get("form_name", "?"))
				form_counts[fn] = int(form_counts.get(fn, 0)) + 1

	print("\n  %d puzzles, %.1f clues/puzzle (shipped, post-prune)"
		% [puzzles, float(total_clues) / maxf(1.0, float(puzzles))])
	print("\n  GATE HEALTH — read this BEFORE the mix:")
	print("    live gate (seq_unique and name_unique): %d/%d" % [gate_ok, puzzles])
	print("    full name closure:                      %d/%d" % [closure_ok, puzzles])
	print("    names left unbound:                     %d" % unbound)
	print("\n  TIER MIX vs target 25/45/30:")
	for t2 in [1, 2, 3]:
		print("    tier %d: %5.1f%%  (target %.0f%%)   n=%d"
			% [t2, 100.0 * float(tier_counts[t2]) / maxf(1.0, float(total_clues)),
				100.0 * float(P.TIER_TARGET_RATIO[t2]), int(tier_counts[t2])])
	print("\n  FORM SHARE:")
	var names: Array = form_counts.keys()
	names.sort_custom(func(a, b): return int(form_counts[a]) > int(form_counts[b]))
	for nm in names:
		print("    %-28s %4d  %5.1f%%"
			% [nm, int(form_counts[nm]), 100.0 * float(form_counts[nm]) / maxf(1.0, float(total_clues))])

	print("ALL PASS (%d failures)" % fails)
	finish()
