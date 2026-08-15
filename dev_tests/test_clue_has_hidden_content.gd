extends "res://dev_tests/test_base.gd"
# Every clue must tell the player something they cannot simply LOOK AT.
#
# Colour is painted on the star map and Pitch is fully recoverable through
# the Listen mechanic, so both are "given" — zero-deduction information once
# looked at. Name and Sequence are the only genuinely hidden axes.
# _is_hidden_category says exactly this, and its own docstring calls a clue
# built entirely from given axes one that "reads as a non-clue" — but the
# rule was only ever enforced on the distance-anchored Forms 15/16/19.
#
# Reported from a live game 2026-08-13, first clue of a fresh puzzle:
#
#     "The star that plays F5 and the star that plays E5 have the same
#      color."
#
# Both ends named by Pitch, asserting Colour. Every part of it is readable
# off the map once the stars have been listened to.
#
# Checked over RENDERED terms (search_terms), which is what the player
# actually sees — not `chars`, which lists nodes several Forms never render.
# Prefixes: N: name, S: sequence (hidden) / C: colour, P: pitch, H: hops
# (given). A clue with no N: and no S: term is entirely given-axis.

# Trimmed 2026-08-14 from 4 constellations x 4 seeds. Each puzzle costs ~18s
# to generate (generate_clues_forms runs the Forms generator AND a uniqueness
# solve), so that sweep alone was ~5 minutes of a suite run. Two DIFFERENT
# constellations is what buys the coverage here — the point is topological
# variety, not seed count, and no violation has ever appeared only on a
# third or fourth seed.
const SEEDS := [11, 31337]
const CONSTELLATIONS := [0, 2]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var total: int = 0
	var offenders: Array = []
	var by_form: Dictionary = {}

	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		for seed_v in SEEDS:
			var scn: int = int(cdef["star_count"])
			var g = load("res://constellation_logic_puzzle.gd").new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed_v, cid, cdef.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
			await g.generate_clues_forms()

			for clue in g.chosen_form_clues:
				var c: Dictionary = clue
				total += 1
				var terms: Array = c.get("search_terms", [])
				var has_hidden: bool = false
				for t in terms:
					var s: String = str(t)
					if s.begins_with("N:") or s.begins_with("S:"):
						has_hidden = true
						break
				if has_hidden:
					continue
				# Naming only given-axis values is NOT enough to condemn a
				# clue — what matters is what it ASSERTS. "The star that
				# plays C6 is among the first 2" names nothing hidden, yet
				# its whole content is a Sequence claim, which is hidden and
				# genuinely useful. So a clue is only a non-clue when its
				# assertions are ALSO confined to the given axes.
				#
				# Read from disclosures, the encoding that records what the
				# clue actually claims: every ordinal_* kind is Sequence
				# content. (Checked here rather than by Form id so a new
				# Form is judged by what it says, not by a list needing
				# maintenance.)
				var asserts_hidden: bool = false
				for d in (c.get("disclosures", []) as Array):
					if not (d is Dictionary):
						continue
					if str((d as Dictionary).get("kind", "")).begins_with("ordinal_"):
						asserts_hidden = true
						break
				if asserts_hidden:
					continue
				var fid: int = int(c.get("form_id", -1))
				by_form[fid] = int(by_form.get(fid, 0)) + 1
				if offenders.size() < 12:
					offenders.append("form %d (c%d seed %d): %s"
						% [fid, cid, seed_v, str(c.get("text", ""))])

	print("  clues generated: %d" % total)
	var bad: int = 0
	for f in by_form:
		bad += int(by_form[f])
	print("  clues with NO hidden-axis term: %d" % bad)
	if not by_form.is_empty():
		print("  by form_id: %s" % str(by_form))
		for o in offenders:
			print("    %s" % str(o))

	ok(total > 100, "generated a meaningful sample (%d clues)" % total)
	ok(bad == 0,
		"every clue names at least one Name or Sequence value — nothing is "
			+ "purely readable off the map (%d non-clues)" % bad)

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
