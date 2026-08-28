extends "res://dev_tests/test_base.gd"
# No clue may spend its sentence on something the player already knows.
# Three reports from live puzzles, THREE DIFFERENT MECHANISMS -- which is
# the point of keeping them in one file: "redundant clue" is a symptom, not
# a cause, and each cause has its own pass.
#
# ── 1. A Form that SET nothing (Form 23 Group Membership) ────────────────
#     "Pyrios is one of the stars that play A4."
#     "Neither Pyrios nor the star that fires 7th note is the star that
#      plays E5."
# A star has ONE pitch, so the first clue already carries the second's
# Pyrios half. Dual Negation checks the `used` bit before picking a subject
# (3436/3453/3468) -- but Group Membership emitted only its two
# TAUTOLOGICAL self-identity cells, never the (subject x non-member)
# exclusions its own sentence stated, so there was nothing to read.
#
# ── 2. A Form that READ it too weakly (Form 24 Group Negation) ───────────
#     "Heleai is one of the white stars."
#     "Neither Pyrios nor Heleai is red or plays A4."
# Its any_fresh guard is a TERMINATION guard (a clue consuming no cells lets
# the main loop's stall counter reset forever) and passes on one fresh cell
# anywhere in the subject x group cross product, so a wholly redundant
# subject rode along on an informative one.
#
# ── 3. A fact the CLOSURE could not read (Disjunction) ───────────────────
#     "Neither the star that fires 1st note nor the star that fires 14th
#      note is Keriion."
#     "Keriion is either the star that fires 5th note or the star that
#      fires 15th note."
# `used` cannot catch this one and it is a mistake to try: it only looks
# BACKWARDS, and the first clue was informative when it was written -- the
# second made it redundant RETROACTIVELY. _prune_redundant_clues is the
# pass for that, and its test is "does the closure grow without it", so a
# fact the closure cannot read makes every earlier clue look load-bearing.
# descriptor_either_or had consumers in the player-side engine and none in
# _solve_name_closure. Pruning was working; it was blind.
#
# NONE of this is the True-cell cascade removed on 2026-08-18. That cascade
# reasoned from the SOLUTION ("bijection gives one True per row, so the rest
# are False") -- an answer-key fact driving a claim about player knowledge.
# These read only what a clue SAID plus a rule of the puzzle, which is why
# PART 1 can assert soundness against ground truth instead of deriving
# anything from it.
#
# GRANULARITY for PART 2 is the (descriptor, category) CLAIM, not the cell.
# "Heleai is not red" is one thing the player acts on and spans one cell per
# red star; while any of those cells is open the claim still informs. Only
# an ENTIRELY known claim is waste. Judged per cell, this would reject
# sentences that genuinely teach something.
#
# Form-agnostic on purpose: the defect is a property of the shipped clue
# SET, not of the Forms that happened to show it, so a fourth Form
# acquiring any of these habits fails here rather than reaching a player.

# SAMPLE SIZE IS A SUITE-BUDGET DECISION, not just a statistics one.
#
# This started at 3x2, then went to 8x3 = 24 puzzles to give PART 3 a real
# denominator (name-subject disjunctions are rare in a shipped set). That,
# plus a second module generating 18 more for the anchor checks, put ~42
# puzzle generations into the suite. At the post-2026-08-27 generation cost
# of ~35-70 s per puzzle that is over half an hour in two files, and the
# full suite TIMED OUT at 30 minutes having finished 6 of 36 modules --
# twice. A test nobody can afford to run is not coverage.
#
# So: 2 seeds x 3 constellations here, and the opening-anchor checks were
# folded into this same generation pass rather than paying for their own
# (they need exactly the same thing: puzzles built on the live profile).
# 42 generations -> 6.
#
# PART 3 handles the resulting thin denominator HONESTLY rather than by
# pretending: if no name-subject disjunction lands in the sample it says
# NOT EXERCISED in capitals and does not claim a pass. The property still
# fails the moment a real subsumption appears. That is the point of the
# denominator discipline -- make vacuity VISIBLE -- not "always generate 24
# puzzles". Widen SEEDS by hand for a deep pre-release run.
const SEEDS := [11, 4242]
const CONSTELLATIONS := [0, 1, 2]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


# Read the `cells` encoding, NOT `grid_updates`: `grid_updates` is the raw
# Form return and never reaches the shipped clue. _cells_for_cache()
# translates it -- value INDEX -> star, dropping any non-bijective category
# -- and that translated list is what generation stores and what a cache
# round-trip preserves. Judging the raw dict would test a representation no
# consumer ever sees (see the four-encodings note in memory).


func _key(c: Dictionary) -> String:
	# Cells are symmetric -- (A,B) and (B,A) are the same cell -- so order
	# the two halves before keying, or a restatement with the operands
	# swapped would read as a fresh cell and this test would pass while the
	# duplicate sentence still shipped.
	var a := "%d:%d" % [int(c["cat_a"]), int(c["star_a"])]
	var b := "%d:%d" % [int(c["cat_b"]), int(c["star_b"])]
	return (a + "|" + b) if a < b else (b + "|" + a)


## The star on the far side of `cell` from (NAME, name_star), or -1 if this
## cell does not involve that name at all.
func _partner_of_name(cell: Dictionary, name_star: int, cat_name: int) -> int:
	if int(cell["cat_a"]) == cat_name and int(cell["star_a"]) == name_star:
		return int(cell["star_b"])
	if int(cell["cat_b"]) == cat_name and int(cell["star_b"]) == name_star:
		return int(cell["star_a"])
	return -1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var P = load("res://constellation_logic_puzzle.gd")
	var CAT_NAME: int = P.Category.NAME

	var puzzles: int = 0
	var claims: int = 0        # (descriptor, category) claims made, the denominator
	var cells: int = 0
	var unsound: int = 0       # a FALSE cell that is actually TRUE of the solution
	var wasted: int = 0        # descriptors a clue names that teach nothing -- the FLOOR
	var bucket_waste: int = 0  # stricter bar: single predicates wholly restated
	var cell_repeats: int = 0  # context only: cells restated inside a still-informative claim
	var disjunctions: int = 0  # name-subject disjunctions seen, PART 3's denominator
	var subsumed: int = 0      # clues one of them makes entirely free
	var examples: Array = []
	# PART 4 -- the guaranteed opening Mutual Exclusion, folded in here so
	# it rides the same generation pass instead of paying for its own.
	# PART 5 -- Forms that state a DOMAIN RESTRICTION must mark what they
	# rule out. See the assertion below for why this is not covered by
	# PART 2.
	#   4  Disjunction              "X is either A or B"
	#   21 Pseudo-True (Aligned)    "X and Y can only be A or B"
	#   22 Pseudo-True (Staggered)  "X can be A or B, Y can be B or C, ..."
	#   23 Group Membership         "X is one of the yellow stars"
	var restriction_forms: Array = [4, 21, 22, 23]
	var restriction_clues: int = 0
	var unmarked_restrictions: int = 0
	var unmarked_examples: Array = []
	var opened_mutex: int = 0
	var opening_big: int = 0
	var opening_sizes: Dictionary = {}
	var anchor_misses: Array = []
	var live_profile: String = P.new().difficulty
	var anchors: Array = P.DIFFICULTY_PROFILES[live_profile]["opening_anchors"]
	var anchor_declared: bool = false
	for slot in anchors:
		if slot is Dictionary and int(slot["form"]) == 13 \
				and int(slot.get("min_elements", 0)) >= 4:
			anchor_declared = true

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
			await g._generate_clues_forms_attempt()
			puzzles += 1

			var said: Dictionary = {}     # cell key -> index of the clue that said it
			var clues: Array = g.chosen_form_clues

			# PART 4 -- every puzzle opens with a 4+ element Mutual
			# Exclusion. Element count is DISTINCT STARS NAMED: Form 13 is
			# two builders sharing a form_id, and chars.size() double-counts
			# the axis variant (two chars per participant) while distinct
			# CATEGORIES under-counts it (participants share an id_cat).
			if clues.is_empty():
				anchor_misses.append("c%d seed %d: no clues at all" % [cid, seed])
			elif int((clues[0] as Dictionary).get("form_id", -1)) != 13:
				anchor_misses.append("c%d seed %d: opens with [%s]"
					% [cid, seed, str((clues[0] as Dictionary).get("form_name", "?"))])
			else:
				opened_mutex += 1
				var stars_seen: Dictionary = {}
				for ch in ((clues[0] as Dictionary).get("chars", []) as Array):
					stars_seen[int((ch as Dictionary).get("star", -1))] = true
				var esz: int = stars_seen.size()
				opening_sizes[esz] = int(opening_sizes.get(esz, 0)) + 1
				if esz >= 4:
					opening_big += 1
				else:
					anchor_misses.append("c%d seed %d: opening Mutex names only %d stars"
						% [cid, seed, esz])
			for i in clues.size():
				var c: Dictionary = clues[i]
				# Bucket by (left descriptor, right category). The Forms
				# concerned emit subject-side first, so this is the
				# subject's claim against one axis -- "Heleai vs COLOUR".
				if restriction_forms.has(int(c.get("form_id", -1))):
					restriction_clues += 1
					var false_cells: int = 0
					for u0 in (c.get("cells", []) as Array):
						if not bool((u0 as Dictionary).get("is_true", false)):
							false_cells += 1
					if false_cells == 0:
						unmarked_restrictions += 1
						if unmarked_examples.size() < 3:
							unmarked_examples.append("[%s] %s"
								% [str(c.get("form_name", "?")), str(c.get("text", ""))])

				var buckets: Dictionary = {}
				for u in (c.get("cells", []) as Array):
					var ud: Dictionary = u
					if bool(ud.get("is_true", false)):
						continue
					cells += 1
					# PART 1 -- soundness. The clue says these are false.
					if int(ud["star_a"]) == int(ud["star_b"]):
						unsound += 1
					var bk := "%d:%d>%d" % [int(ud["cat_a"]), int(ud["star_a"]), int(ud["cat_b"])]
					if not buckets.has(bk):
						buckets[bk] = []
					(buckets[bk] as Array).append(ud)

				# PART 2 -- does the clue NAME A DESCRIPTOR that teaches
				# nothing? Escalated from the bucket to the descriptor
				# deliberately, and the calibration matters:
				#
				#   "Oraeides, the star that fires 10th note, the star that
				#    plays B4, and a star 1 hop from Nyxaos are all
				#    different stars."   [Mutual Exclusion]
				#   "The star that plays B4 is not Oraeides."  [Single Neg]
				#
				# One of Mutex's six pairwise claims is already known and
				# the other five are new, so Oraeides earns its place. A
				# per-bucket rule flags this, because it treats "one pair"
				# and "one predicate the reader acts on" as the same unit
				# -- true for Group Negation's subject-vs-group, false for a
				# multi-way distinctness clue, which cannot drop a pair
				# without dropping a participant.
				#
				# So the asserted floor is: every descriptor a sentence
				# names must teach at least one new thing. Per-bucket
				# repeats are still COUNTED (bucket_waste) as a tightness
				# signal -- Forms 23/24 are held to that stricter bar in the
				# generator, which is allowed to over-deliver against the
				# floor the test pins.
				var descriptors: Dictionary = {}     # "cat:star" -> [total, restated]
				for bk2 in buckets:
					var bucket: Array = buckets[bk2]
					claims += 1
					var repeats: int = 0
					for ud2 in bucket:
						if said.has(_key(ud2)):
							repeats += 1
					var whole: bool = repeats == bucket.size()
					if whole:
						bucket_waste += 1
					else:
						cell_repeats += repeats
					var dk: String = str(bk2).split(">")[0]
					if not descriptors.has(dk):
						descriptors[dk] = [0, 0]
					(descriptors[dk] as Array)[0] += 1
					if whole:
						(descriptors[dk] as Array)[1] += 1
				for dk2 in descriptors:
					var tally: Array = descriptors[dk2]
					if int(tally[0]) > 0 and int(tally[0]) == int(tally[1]):
						wasted += 1
						if examples.size() < 4:
							examples.append("[%s] %s\n           names a descriptor that adds nothing"
								% [str(c.get("form_name", "?")), str(c.get("text", ""))])

				for u3 in (c.get("cells", []) as Array):
					var ud3: Dictionary = u3
					if bool(ud3.get("is_true", false)):
						continue
					if not said.has(_key(ud3)):
						said[_key(ud3)] = i

			# PART 3 -- retroactive subsumption, which `used` structurally
			# cannot see. Order-independent on purpose: pruning sweeps the
			# whole set, so a clue made free by a LATER one is just as
			# wasted as one made free by an earlier one.
			for i2 in clues.size():
				var dj: Dictionary = clues[i2]
				var opts: Array = []          # the two stars the subject must be
				var subj: int = -1
				for f in (dj.get("disclosures", []) as Array):
					if not (f is Dictionary):
						continue
					var fd: Dictionary = f
					if str(fd.get("kind", "")) != "descriptor_either_or":
						continue
					if int(fd.get("cat_a", -1)) != CAT_NAME:
						continue
					subj = int(fd["star_a"])
					opts = [int(fd["s1"]), int(fd["s2"])]
				if subj < 0:
					continue
				disjunctions += 1
				for j in clues.size():
					if j == i2:
						continue
					var other: Dictionary = clues[j]
					var ocells: Array = other.get("cells", [])
					if ocells.is_empty():
						continue
					# Wholly free only if EVERY cell it asserts is a
					# negative about this same name against a star the
					# disjunction has already excluded. One TRUE cell, or
					# one cell about anything else, and it still informs.
					var free: bool = true
					for u4 in ocells:
						var ud4: Dictionary = u4
						if bool(ud4.get("is_true", false)):
							free = false
							break
						var partner: int = _partner_of_name(ud4, subj, CAT_NAME)
						if partner < 0 or opts.has(partner):
							free = false
							break
					if free:
						subsumed += 1
						if examples.size() < 6:
							examples.append("[%s] %s\n           made free by [%s] %s"
								% [str(other.get("form_name", "?")), str(other.get("text", "")),
									str(dj.get("form_name", "?")), str(dj.get("text", ""))])

	print("  %d puzzles, %d claims over %d FALSE cells, %d name-subject disjunctions"
		% [puzzles, claims, cells, disjunctions])
	print("  unsound %d | wasted descriptors %d | wholly-restated predicates %d | subsumed by a disjunction %d | cells repeated inside a live claim %d"
		% [unsound, wasted, bucket_waste, subsumed, cell_repeats])
	for e in examples:
		print("      ", e)

	# Denominators first: each check below is free if the thing it judges was
	# never produced.
	ok(puzzles > 0, "generated puzzles to judge (%d)" % puzzles)
	ok(cells > 0, "clues asserted FALSE cells at all (%d) — a 0 here means Group Membership stopped marking and PART 2 proves nothing" % cells)
	ok(claims > 0, "and those cells grouped into readable claims (%d)" % claims)
	ok(unsound == 0, "every asserted cell is genuinely false of the solution (%d violations)" % unsound)
	ok(wasted == 0, "no clue names a descriptor that teaches nothing (%d wasted) — reports 1 and 2" % wasted)
	# PART 3's denominator is thin at suite size. Say so out loud rather
	# than bank a green tick: the property is still enforced, but a sample
	# with no disjunction in it has PROVEN NOTHING about report 3.
	if disjunctions == 0:
		print("  ---   PART 3 NOT EXERCISED: 0 name-subject disjunctions in %d puzzles."
			% puzzles)
		print("        The check below cannot fail here. Widen SEEDS for a real run;")
		print("        8 seeds x 3 constellations gave 7 disjunctions on 2026-08-27.")
	else:
		print("  ---   PART 3 exercised: %d name-subject disjunctions in sample" % disjunctions)
	ok(subsumed == 0, "no clue is made entirely free by a disjunction elsewhere in the set (%d subsumed) — report 3" % subsumed)

	# PART 5 -- WHY THIS EXISTS, and it is the hole PART 2 cannot see.
	#
	# Reported 2026-08-27:
	#   "The star that plays C6 and Astaeis can only be the star that fires
	#    15th note or the star that fires 9th note."
	#   "Neither the star that fires 7th note nor the star that fires 8th
	#    note plays C6."
	# The first confines the C6 star to ranks 15 and 9, so the second is
	# free. PART 2 was run against the pre-fix generator and reported ZERO
	# wasted descriptors: it compares a later clue's cells against cells an
	# EARLIER clue MARKED, and Form 21 marked none of what it ruled out. A
	# Form that states a restriction and records nothing is invisible to
	# every check that reads `cells` — including this whole test.
	#
	# So the marking itself has to be asserted structurally, not inferred
	# from a downstream symptom.
	print("  domain-restriction clues: %d, of which mark nothing: %d"
		% [restriction_clues, unmarked_restrictions])
	for ue in unmarked_examples:
		print("      ", ue)
	ok(restriction_clues > 0,
		"domain-restriction Forms appear in the shipped sets (%d) — otherwise the next check is vacuous" % restriction_clues)
	ok(unmarked_restrictions == 0,
		"every domain-restriction clue marks the values it rules out (%d mark nothing)" % unmarked_restrictions)

	# PART 4 -- the opening anchor.
	print("  opening clue: %d of %d puzzles open with Mutual Exclusion, %d name 4+ stars %s"
		% [opened_mutex, puzzles, opening_big, str(opening_sizes)])
	for am in anchor_misses:
		print("      ", am)
	ok(anchor_declared,
		"the LIVE profile ('%s') declares a Mutex anchor at min_elements>=4 — otherwise the two checks below test nothing"
			% live_profile)
	ok(opened_mutex == puzzles,
		"every puzzle opens with Mutual Exclusion (%d of %d)" % [opened_mutex, puzzles])
	ok(opening_big == puzzles,
		"and every opening Mutex names at least 4 distinct stars (%d of %d)" % [opening_big, puzzles])

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
