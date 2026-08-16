extends "res://dev_tests/test_base.gd"
# CONSTELLATION TOPOLOGY — what hop clues can actually distinguish.
#
# Distance reasoning is only worth what the graph can separate, and that
# varies enormously between constellations. Measured 2026-08-14:
#
#   The Archon    4 components [6,3,3,3]   23% of star pairs reachable
#   The Spark     1 component              100%
#   The Hourglass 1 component              100%
#   The Satchel   1 component              100%
#   The Bellows   5 components [1,1,1,1,14] 59%
#
# The Archon is three ISOLATED TRIANGLES plus a 6-cycle. Inside a triangle
# every star is adjacent to the other two and unreachable from everything
# else, so topology distinguishes nothing at all for 9 of its 15 stars —
# and that is the constellation used most for testing. The Bellows has four
# genuinely isolated single stars, about which a hop clue cannot say even
# "far from": every distance is -1.
#
# This matters beyond clue quality. When two positions are identical in the
# player's real value space — visible colour, audible pitch, hop distances —
# the puzzle admits a swap and has TWO solutions. Measured on the same day:
# 3 of 5 Archon seeds were under-determined that way.
#
# WHY THIS TEST IS A CHARACTERISATION TEST, which is normally a bad shape:
# line_pairs is AUTHORED ART DATA, not derived behaviour. It should only
# ever change deliberately. Recording the current shape means editing a
# constellation, or authoring a new one, surfaces here with the consequence
# spelled out, instead of silently changing what every distance clue is
# worth. A new constellation FAILS until someone records its baseline, which
# is the point — that is the moment to look at its reachability.

## cid -> [component_count, reachable_ordered_pairs, star_count, edge_count]
const BASELINE := {
	0: [4, 48, 15, 15],    # The Archon    — 3 isolated triangles + a 6-cycle
	1: [1, 240, 16, 15],   # The Spark     — fully connected
	2: [1, 156, 13, 14],   # The Hourglass — fully connected
	3: [1, 272, 17, 20],   # The Satchel   — fully connected
	4: [5, 182, 18, 14],   # The Bellows   — 4 isolated singles + one body
}

## Authored but topology-less on purpose; setup() aborts on it.
const NO_TOPOLOGY_YET := [5]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var checked: int = 0

	for cid in range(10):
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty():
			continue
		var nm: String = str(cdef.get("name", "?"))
		var raw = cdef.get("line_pairs")
		var has_edges: bool = (raw is Array) and not (raw as Array).is_empty()

		if not has_edges:
			ok(NO_TOPOLOGY_YET.has(cid),
				"c%d %s has no line_pairs — known-pending, not a surprise" % [cid, nm])
			continue

		var lp: Array = raw
		var scn: int = int(cdef["star_count"])

		# Data sanity first: a bad index here would corrupt every distance.
		var bad: int = 0
		for i in range(0, lp.size() - 1, 2):
			var u: int = int(lp[i])
			var v: int = int(lp[i + 1])
			if u < 0 or v < 0 or u >= scn or v >= scn or u == v:
				bad += 1
		ok(bad == 0, "c%d %s: every edge is a valid, non-self pair (%d bad)" % [cid, nm, bad])
		ok(lp.size() % 2 == 0, "c%d %s: line_pairs is flat and even-length" % [cid, nm])

		var adj: Dictionary = {}
		for s in scn:
			adj[int(s)] = []
		for i2 in range(0, lp.size() - 1, 2):
			var a: int = int(lp[i2])
			var b: int = int(lp[i2 + 1])
			if a < 0 or b < 0 or a >= scn or b >= scn:
				continue
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)

		var seen: Dictionary = {}
		var comps: Array = []
		for s2 in scn:
			if seen.has(int(s2)):
				continue
			var stack: Array = [int(s2)]
			var comp: Array = []
			seen[int(s2)] = true
			while not stack.is_empty():
				var cur: int = int(stack.pop_back())
				comp.append(cur)
				for n in (adj[cur] as Array):
					if not seen.has(int(n)):
						seen[int(n)] = true
						stack.append(int(n))
			comps.append(comp)

		var reach: int = 0
		var sizes: Array = []
		for c in comps:
			var k: int = (c as Array).size()
			sizes.append(k)
			reach += k * (k - 1)
		var total: int = scn * (scn - 1)

		print("\n  c%d %-13s %2d stars, %2d edges | %d component(s) %s | %d/%d pairs reachable (%.0f%%)"
			% [cid, nm, scn, lp.size() / 2, comps.size(), str(sizes), reach, total,
			   100.0 * float(reach) / float(maxi(total, 1))])

		if not BASELINE.has(cid):
			ok(false, "c%d %s is NEW — record its baseline, and look at its reachability first"
				% [cid, nm])
			continue
		var b2: Array = BASELINE[cid]
		ok(comps.size() == int(b2[0]),
			"c%d %s: %d component(s), baseline %d" % [cid, nm, comps.size(), int(b2[0])])
		ok(reach == int(b2[1]),
			"c%d %s: %d reachable pairs, baseline %d" % [cid, nm, reach, int(b2[1])])
		ok(scn == int(b2[2]) and lp.size() / 2 == int(b2[3]),
			"c%d %s: %d stars / %d edges, baseline %d / %d"
				% [cid, nm, scn, lp.size() / 2, int(b2[2]), int(b2[3])])
		checked += 1

	# Non-vacuity: "all baselines match" is also what checking nothing says.
	print("")
	ok(checked >= 5, "actually compared %d constellations against a baseline" % checked)

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
