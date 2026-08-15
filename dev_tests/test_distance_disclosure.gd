extends "res://dev_tests/test_base.gd"
# Part 0 + Part 1 of the proximity hop-clue framework
# (proximity_hop_clue_framework_design memory).
#
# Part 0: the player-side minimum-distance matrix. The generator has always
# had `_distances`, but never persisted it, so the deduction engine had NO
# distance data at all — a distance disclosure had nothing to evaluate
# against. Rebuilt overlay-side by BFS over line_pairs (authored constant
# data, already read for drawing), so no save-format change was needed.
#
# Part 1: the `distance_hop` disclosure kind. Before it, Form 15's only
# scoreable content was an ordinal_exact derived from the clue MENTIONING a
# Sequence descriptor — not from anything the clue asserts.
#
# The load-bearing check here is that the player-side matrix agrees with the
# generator's own BFS on EVERY pair of EVERY constellation. Two independent
# implementations over the same topology must not disagree.

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

	# ── Part 0: player-side matrix == generator's BFS, all constellations ──
	print("=== Part 0: distance matrix agreement ===")
	var checked_constellations := 0
	var total_pairs := 0
	var mismatches := 0
	var disconnected_seen := 0

	for cid in range(10):
		var def: Dictionary = cd.get_constellation_def(cid)
		if def.is_empty():
			continue
		var sc: int = int(def["star_count"])
		# The Djinn (id 5) is an unfinished placeholder — its def carries
		# star_count and note data but NO line_pairs ("pending per-vessel
		# art design"), and setup() aborts on it. Skip rather than fail:
		# a topology test cannot say anything about a constellation with no
		# topology yet.
		var raw_pairs: Array = def.get("line_pairs") if def.get("line_pairs") is Array else []
		if raw_pairs.is_empty():
			print("  -- cid %d (%s): no line_pairs yet, skipping" % [cid, str(def.get("name", "?"))])
			continue

		var lp = load("res://constellation_logic_puzzle.gd").new()
		var seq: Array = []
		for i in range(sc):
			seq.append(i)
		lp.setup(sc, def["line_pairs"], seq, 4242, cid, def.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)

		var host = OverlayScene.instantiate()
		root.add_child(host)
		await process_frame
		host._cd = cd
		host._constellation_id = cid
		host._star_count = sc
		host._rebuild_star_distances()

		checked_constellations += 1
		for a in sc:
			for b in sc:
				total_pairs += 1
				var mine: int = host.star_distance(a, b)
				var theirs: int = int(lp._distances[a][b])
				if mine != theirs:
					mismatches += 1
					if mismatches <= 5:
						print("    MISMATCH c%d (%d,%d): player=%d generator=%d" % [cid, a, b, mine, theirs])
				if theirs == -1 and a != b:
					disconnected_seen += 1
		host.queue_free()
		await process_frame

	print("  constellations checked: %d, pairs compared: %d, disconnected pairs seen: %d"
		% [checked_constellations, total_pairs, disconnected_seen])
	ok(checked_constellations >= 5, "all constellations checked")
	ok(mismatches == 0, "player matrix matches generator BFS on every pair (%d mismatches)" % mismatches)
	ok(disconnected_seen > 0, "unreachable pairs exist and are represented as -1 (Bellows has isolated stars)")

	# ── Part 1: distance_hop is emitted, and scores conservatively ──
	print("\n=== Part 1: distance_hop disclosure ===")
	var def0: Dictionary = cd.get_constellation_def(0)
	var sc0: int = int(def0["star_count"])
	var lp0 = load("res://constellation_logic_puzzle.gd").new()
	var seq0: Array = []
	for i in range(sc0):
		seq0.append(i)
	lp0.setup(sc0, def0["line_pairs"], seq0, 31337, 0, def0.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await lp0.generate_clues_forms()

	var emitted := 0
	var negated_emitted := 0
	for c in lp0.chosen_form_clues:
		for dsc in (c as Dictionary).get("disclosures", []):
			if str((dsc as Dictionary).get("kind", "")) == "distance_hop":
				emitted += 1
				if bool((dsc as Dictionary).get("negated", false)):
					negated_emitted += 1
	print("  distance_hop disclosures emitted in one puzzle: %d (of which negated: %d)"
		% [emitted, negated_emitted])
	ok(emitted > 0, "Forms now emit distance_hop")

	# Truth check: every emitted distance_hop must be TRUE of the real map,
	# or the generator is asserting something false to the player.
	var untrue := 0
	for c2 in lp0.chosen_form_clues:
		for dsc2 in (c2 as Dictionary).get("disclosures", []):
			var d2: Dictionary = dsc2
			if str(d2.get("kind", "")) != "distance_hop":
				continue
			var actual: int = int(lp0._distances[int(d2["ref"])][int(d2["target"])])
			var claimed: int = int(d2["hops"])
			var holds: bool = (actual != claimed) if bool(d2.get("negated", false)) else (actual == claimed)
			if not holds:
				untrue += 1
	ok(untrue == 0, "every emitted distance_hop is true of the real map (%d false)" % untrue)

	# Conservatism: on a board with NO player notes, nothing may be entailed.
	var host2 = OverlayScene.instantiate()
	root.add_child(host2)
	await process_frame
	host2._cd = cd
	host2._constellation_id = 0
	host2._star_count = sc0
	host2._star_names = lp0.star_names
	host2._star_colors = lp0.star_colors
	host2._star_degrees = []
	for s in sc0:
		host2._star_degrees.append(0)
	host2._pitch_rank_solution = lp0.pitch_rank_solution
	host2._pitch_freqs = cd.get_note_freqs(0)
	host2._star_pitch_index = cd.get_note_assignment(0)
	host2._rebuild_star_distances()
	host2._widgets.clear_pitch_caches()
	host2._deduction._load_match_records([])

	var entailed_on_blank := 0
	for c3 in lp0.chosen_form_clues:
		for dsc3 in (c3 as Dictionary).get("disclosures", []):
			if str((dsc3 as Dictionary).get("kind", "")) != "distance_hop":
				continue
			if host2._deduction._disclosure_satisfied(dsc3):
				entailed_on_blank += 1
	ok(entailed_on_blank == 0,
		"nothing is entailed on an empty board — no vacuous truth (%d were)" % entailed_on_blank)

	# And it must be reachable through the real coverage path, not just
	# callable directly.
	ok(host2._deduction.SCOREABLE_DISCLOSURE_KINDS.has("distance_hop"),
		"distance_hop is in SCOREABLE_DISCLOSURE_KINDS (enters the denominator)")

	# REGRESSION (reported 2026-08-12): knowing a star's NAME is not knowing
	# WHERE it is. The first version of this disclosure used
	# _records_identifying_star(), which a bare Sort:Name row satisfies for
	# free — the row's whole identity IS that name — so every hop clue on a
	# barely-started board scored Used Up. The two tiers are now separate
	# functions; this pins the distinction itself, not either caller.
	print("\n=== regression: DENOTES and BOUND are different tiers ===")
	var d2 = host2._deduction
	d2._load_match_records([])
	var name_rec: int = d2._get_or_create_match_record_for_name(str(lp0.star_names[0]))
	d2._full_propagation_refresh()
	ok(not d2._records_identifying_star(0).is_empty(),
		"the Name row DOES denote star 0 (%d record(s))" % d2._records_identifying_star(0).size())
	ok(d2._records_bound_to_star(0).is_empty(),
		"but nothing is BOUND to star 0 — the distinction that was missed")

	d2.record_at(name_rec)["star_idx"] = 0
	d2._full_propagation_refresh()
	ok(not d2._records_bound_to_star(0).is_empty(),
		"binding the record to a map star reaches the bound tier")

	# ── Part 2: the constraint must PROPAGATE, not just be scored ────────
	#
	# Soundness first, and against ground truth: no elimination this pass
	# writes may ever rule out the star a descriptor really denotes. A
	# distance rule that narrows in the wrong direction would make puzzles
	# unsolvable while looking like it was working.
	print("\n=== Part 2: distance constraints propagate ===")
	# _distance_constraints() reads the host's clue cache, which the manual
	# field-poking above never populated (show_for_constellation would have).
	host2._form_clues_cache = lp0.chosen_form_clues
	d2._load_match_records([])
	d2._full_propagation_refresh()
	var constraints: Array = d2._distance_constraints()
	print("  parsed constraints: %d" % constraints.size())
	ok(not constraints.is_empty(), "distance_hop disclosures parse into constraints")

	var unsound: int = 0
	var narrowing: int = 0
	for c in constraints:
		var cc: Dictionary = c
		for side in [["ref_cat", "ref"], ["target_cat", "target"]]:
			var scat: int = int(cc.get(side[0], -1))
			var sstar: int = int(cc.get(side[1], -1))
			var poss: Array = d2._stars_possible_for_descriptor(scat, sstar)
			# The descriptor's TRUE star must always survive.
			if not poss.has(sstar):
				unsound += 1
				if unsound <= 3:
					print("    UNSOUND: %s cat=%d star=%d dropped its own star; poss=%s"
						% [str(side[1]), scat, sstar, str(poss)])
			if poss.size() < sc0:
				narrowing += 1
	ok(unsound == 0,
		"no descriptor row ever excludes the star it really denotes (%d violations)" % unsound)
	print("  descriptor rows already narrower than 'any star': %d" % narrowing)

	# The reported case: a colour group whose members are pairwise
	# non-adjacent forbids that colour to anything one hop from it, with NO
	# player input. Checked directly against this constellation's topology
	# so the test states a fact about the map rather than trusting the rule.
	var yellow_like: int = -1
	for ci in range(8):
		var members: Array = []
		for s in sc0:
			if s < lp0.star_colors.size() and int(lp0.star_colors[s]) == ci:
				members.append(s)
		if members.size() < 2:
			continue
		var any_adjacent: bool = false
		for a2 in members:
			for b2 in members:
				if int(a2) != int(b2) and host2.star_distance(int(a2), int(b2)) == 1:
					any_adjacent = true
		if not any_adjacent:
			yellow_like = ci
			break
	if yellow_like < 0:
		print("  (no pairwise non-adjacent colour group in this constellation — "
			+ "topology exclusion not exercisable here)")
	else:
		var group: Array = []
		for s in sc0:
			if s < lp0.star_colors.size() and int(lp0.star_colors[s]) == yellow_like:
				group.append(s)
		var allowed: Array = d2._distance_allowed_stars(group, group, 1, false)
		print("  colour %d has %d pairwise non-adjacent members" % [yellow_like, group.size()])
		ok(allowed.is_empty(),
			"no member of a pairwise non-adjacent colour group is 1 hop from another "
			+ "(%d survived) — this is the '6th note cannot be yellow' deduction" % allowed.size())

	# Negation is not the mirror of the positive case: a position dies only
	# when EVERY possible partner sits at the forbidden distance.
	var solo: Array = [0]
	var neighbours_of_0: Array = []
	for s in sc0:
		if host2.star_distance(0, s) == 1:
			neighbours_of_0.append(s)
	# A genuine non-neighbour, not n0 itself — a star is skipped as its own
	# partner, so passing n0 in would have tested nothing.
	var far_from_n0: int = -1
	if not neighbours_of_0.is_empty():
		var n0a: int = int(neighbours_of_0[0])
		for s in sc0:
			if s != n0a and host2.star_distance(n0a, s) != 1:
				far_from_n0 = s
				break
	if not neighbours_of_0.is_empty() and far_from_n0 >= 0:
		var n0: int = int(neighbours_of_0[0])
		ok(not d2._distance_allowed_stars([n0], solo, 1, true).has(n0),
			"negated: a star whose only possible partner is 1 hop away is ruled out")
		ok(d2._distance_allowed_stars([n0], [0, far_from_n0], 1, true).has(n0),
			"negated: adding a partner it is NOT 1 hop from keeps it alive (star %d)" % far_from_n0)
		ok(d2._distance_allowed_stars([n0], solo, 1, false).has(n0),
			"positive: the same star survives when one witness at 1 hop exists")
		ok(not d2._distance_allowed_stars([far_from_n0], solo, 1, false).has(far_from_n0),
			"positive: a star with no witness at 1 hop is ruled out")
	host2.queue_free()
	await process_frame

	# ── Part 2b: a descriptor needs no RECORD to be narrowed ─────────────
	#
	# Reported 2026-08-14: "the star that fires 11th note is 3 hops from a
	# red star" only identified its star after an unrelated clue was worked,
	# and the player correctly objected that it needed no input at all —
	# Sequence is alldiff, so that descriptor denotes exactly one star by
	# definition, and hop distance plus colour are both readable from the
	# map at load.
	#
	# The cause was that the narrowing was written only onto records holding
	# the descriptor, so with no UI row for that position the conclusion was
	# DISCARDED, then reappeared when some interaction created the row. The
	# check is therefore made with ZERO records: whatever a constraint can
	# prove must be provable before any row exists.
	print("\n=== Part 2b: narrowing survives with no records at all ===")
	var h3 = OverlayScene.instantiate()
	root.add_child(h3)
	await process_frame
	h3._cd = cd
	h3._constellation_id = 0
	h3._star_count = sc0
	h3._star_names = lp0.star_names
	h3._star_colors = lp0.star_colors
	h3._star_degrees = []
	for _s3 in sc0:
		h3._star_degrees.append(0)
	h3._pitch_rank_solution = lp0.pitch_rank_solution
	h3._pitch_freqs = cd.get_note_freqs(0)
	h3._star_pitch_index = cd.get_note_assignment(0)
	h3._form_clues_cache = lp0.chosen_form_clues
	h3._rebuild_star_distances()
	h3._widgets.clear_pitch_caches()
	var e3 = h3._deduction
	e3._load_match_records([])          # deliberately EMPTY
	e3._full_propagation_refresh()
	print("  records: %d" % e3.record_count())

	var narrowed_no_records: int = 0
	var checked_c: int = 0
	for c4 in e3._distance_constraints():
		var cc4: Dictionary = c4
		var rc4: int = int(cc4.get("ref_cat", -1))
		var rs4: int = int(cc4.get("ref", -1))
		# Only the hidden side can be narrowed; Colour/Pitch groups are read
		# off the map and are not a target.
		if rc4 != ConstellationLogicPuzzle.Category.NAME \
				and rc4 != ConstellationLogicPuzzle.Category.SEQUENCE:
			continue
		checked_c += 1
		var poss4: Array = e3._stars_possible_for_descriptor(rc4, rs4)
		if poss4.size() < sc0:
			narrowed_no_records += 1
		if not poss4.has(rs4):
			ok(false, "UNSOUND with no records: descriptor lost its own star")
	print("  hidden-side constraints: %d, narrowed with zero records: %d"
		% [checked_c, narrowed_no_records])
	ok(checked_c > 0, "the puzzle has hidden-side distance constraints to check")
	ok(narrowed_no_records > 0,
		"a distance constraint narrows its descriptor with NO records present "
			+ "(%d of %d) — the conclusion is a fact about the value, not about a UI row"
			% [narrowed_no_records, checked_c])
	h3.queue_free()
	await process_frame

	# ── Part 3: soundness sweep ──────────────────────────────────────────
	#
	# The worst failure mode for a distance rule is not "derives nothing" —
	# it is "derives something false", which eliminates the true star and
	# makes the puzzle unsolvable while every tab still looks healthy. The
	# engine cannot catch that itself: a wrongly-eliminated star just looks
	# like progress. So check it from outside, against the solution, across
	# enough puzzles that a topology-specific mistake cannot hide.
	print("\n=== Part 3: soundness across seeds and constellations ===")
	var checked: int = 0
	var constraints_seen: int = 0
	var violations: int = 0
	for cid in [0, 1, 2, 3]:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		for seed_v in [11, 2027, 90210]:
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
			# The Sort tabs' rows, which exist before any player input — the
			# records the derived eliminations actually land on.
			for n in g.star_names:
				e._get_or_create_match_record_for_name(str(n))
			for p in range(1, scn + 1):
				e._get_or_create_match_record_for_seq(p)
			# Listen to everything, so the PITCH-group rules are exercised
			# too rather than sitting inert behind the unlistened guard.
			for s in scn:
				e.record_at(e._get_or_create_match_record_for_star_idx(s))["pitch_revealed"] = true
			e._full_propagation_refresh()

			for c in e._distance_constraints():
				constraints_seen += 1
				var cc: Dictionary = c
				for side in [["ref_cat", "ref"], ["target_cat", "target"]]:
					var scat: int = int(cc.get(side[0], -1))
					var sstar: int = int(cc.get(side[1], -1))
					if not e._stars_possible_for_descriptor(scat, sstar).has(sstar):
						violations += 1
						if violations <= 5:
							print("    UNSOUND c%d seed %d: %s cat=%d lost star %d"
								% [cid, seed_v, str(side[1]), scat, sstar])
				# Every record must still be able to be the star it really is.
				for i in e.record_count():
					var truth: int = -1
					for s2 in scn:
						if e._record_descriptor_state(i, ConstellationLogicPuzzle.Category.NAME, s2) == 1 \
								or e._record_descriptor_state(i, ConstellationLogicPuzzle.Category.SEQUENCE, s2) == 1:
							truth = s2
							break
					if truth >= 0 and not e._candidate_stars_for_record(i).has(truth):
						violations += 1
						if violations <= 5:
							print("    UNSOUND c%d seed %d: record %d cannot be its own star %d"
								% [cid, seed_v, i, truth])
			checked += 1
			h.queue_free()
			await process_frame

	print("  puzzles checked: %d, distance constraints applied: %d" % [checked, constraints_seen])
	ok(checked >= 8, "swept enough puzzles to be meaningful (%d)" % checked)
	ok(constraints_seen > 0, "the sweep actually exercised distance constraints (%d)" % constraints_seen)
	ok(violations == 0,
		"no distance elimination ever rules out the truth (%d violations)" % violations)

	print("\nALL PASS (0 failures)" if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
