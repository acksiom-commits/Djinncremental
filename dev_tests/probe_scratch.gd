extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver -- EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# HIERARCHY REVIEW, 2026-08-26. The user wants a 4-or-5 element Mutual
# Exclusion guaranteed near the top of every puzzle, via the Form-selection
# hierarchy. Before tuning anything, measure what that hierarchy actually
# produces NOW -- DIFFICULTY_PROFILES' baseline comment is dated
# 2026-08-12 ("~44.5 clues/puzzle, tier mix 17/68/15, Equality Pair +
# Distance Existential = 55%") and is one of the figures the cascade
# removal explicitly invalidated.
#
# Reports, over the SHIPPED (pruned) clue set:
#   clues/puzzle, tier mix vs TIER_TARGET_RATIO
#   per-Form share
#   Mutual Exclusion: puzzles containing >=1, and its element-count spread
#   where the first Mutex lands in reading order

# TWO puzzles. This probe runs as part of every suite invocation, and at 6
# it was the single most expensive module in the run. Two different
# CONSTELLATIONS beats two seeds on one map: the tier/Form shares are
# directional at this size, and anything needing a real denominator belongs
# in a test_ module with its own non-vacuity guard, not here.
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
	var mutex_puzzles: int = 0
	var mutex_sizes: Dictionary = {}
	var first_mutex_pos: Array = []
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
			# GATE HEALTH, read from the attempt's own return dict so it
			# cannot drift from the real gate. Capping a Form that feeds the
			# name closure is exactly the change that could buy a prettier
			# tier mix by making puzzles unsolvable, so the mix numbers
			# below are worthless without these next to them.
			# WALL TIME PER PUZZLE, printed AS IT GOES. The game generates
			# puzzles at runtime, so this number is a player-facing budget,
			# not a test-speed curiosity -- and on 2026-08-27 the full suite
			# hit a 30-minute timeout having finished 5 of 36 modules, with
			# no per-puzzle figure anywhere to say why.
			#
			# Printing incrementally matters as much as the number: this
			# probe used to print only at the end, so a killed run threw
			# away everything it had computed. One 18-puzzle run was killed
			# after 10+ minutes and yielded nothing at all.
			var t0: int = Time.get_ticks_msec()
			var r: Dictionary = await g._generate_clues_forms_attempt()
			var elapsed: int = Time.get_ticks_msec() - t0
			print("    c%d seed %-6d %6.1f s   %d clues" % [cid, seed,
				float(elapsed) / 1000.0, g.chosen_form_clues.size()])
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
			puzzles += 1
			var clues: Array = g.chosen_form_clues
			total_clues += clues.size()
			var saw_mutex: int = -1
			for i2 in clues.size():
				var c: Dictionary = clues[i2]
				var fid: int = int(c.get("form_id", -1))
				var t: int = int(P.FORM_TIER.get(fid, 2))
				tier_counts[t] = int(tier_counts[t]) + 1
				var fn: String = str(c.get("form_name", "?"))
				form_counts[fn] = int(form_counts.get(fn, 0)) + 1
				if fid == 13:
					if saw_mutex < 0:
						saw_mutex = i2
					# ELEMENT COUNT, and it took two wrong metrics to get
					# here — worth the comment so the third person does not
					# repeat them.
					#
					#   chars.size()        WRONG. The axis variant appends
					#                       TWO chars per participant (its
					#                       identifier and its axis value),
					#                       so a 4-participant clue reads 8.
					#   distinct categories WRONG. Right for the
					#                       heterogeneous variant, where one
					#                       element IS one category — but
					#                       the axis variant identifies
					#                       several participants off the
					#                       same id_cat, so it under-counts
					#                       and reported 2s and 3s.
					#
					# Form 13 is TWO builders sharing a form_id. The count
					# that means the same thing in both is how many DISTINCT
					# STARS the sentence names.
					var stars_seen: Dictionary = {}
					for ch in (c.get("chars", []) as Array):
						stars_seen[int((ch as Dictionary).get("star", -1))] = true
					var n: int = stars_seen.size()
					mutex_sizes[n] = int(mutex_sizes.get(n, 0)) + 1
			if saw_mutex >= 0:
				mutex_puzzles += 1
				first_mutex_pos.append(saw_mutex + 1)

	print("\n  %d puzzles, %.1f clues/puzzle (shipped, post-prune)"
		% [puzzles, float(total_clues) / maxf(1.0, float(puzzles))])

	print("\n  GATE HEALTH — read this BEFORE the mix:")
	print("    live gate (seq_unique and name_unique): %d/%d" % [gate_ok, puzzles])
	print("    full name closure:                      %d/%d" % [closure_ok, puzzles])
	print("    names left unbound:                     %d" % unbound)

	print("\n  TIER MIX vs target 25/45/30:")
	for t2 in [1, 2, 3]:
		var share: float = 100.0 * float(tier_counts[t2]) / maxf(1.0, float(total_clues))
		print("    tier %d: %5.1f%%  (target %.0f%%)   n=%d"
			% [t2, share, 100.0 * float(P.TIER_TARGET_RATIO[t2]), int(tier_counts[t2])])

	print("\n  FORM SHARE:")
	var names: Array = form_counts.keys()
	names.sort_custom(func(a, b): return int(form_counts[a]) > int(form_counts[b]))
	for nm in names:
		print("    %-28s %4d  %5.1f%%"
			% [nm, int(form_counts[nm]), 100.0 * float(form_counts[nm]) / maxf(1.0, float(total_clues))])

	print("\n  MUTUAL EXCLUSION — the Form to be guaranteed:")
	print("    puzzles containing at least one: %d of %d" % [mutex_puzzles, puzzles])
	print("    element-count spread: %s" % str(mutex_sizes))
	print("    position of the first one: %s" % str(first_mutex_pos))

	print("\n  ANCHOR PASS: difficulty='%s', opening_anchors=%s"
		% [str(P.new().difficulty),
			str(P.DIFFICULTY_PROFILES[P.new().difficulty]["opening_anchors"])])

	print("ALL PASS (%d failures)" % fails)
	finish()
