extends "res://dev_tests/test_base.gd"
# Pruning must not reduce the LIVE generation gate's pass rate.
#
# generate_clues_forms() ships a puzzle only when `seq_unique and
# name_unique`. name_unique is MENTION COVERAGE (_recompute_name_revealed):
# every star must appear in some surviving clue BOTH by NAME and by another
# category. It is NOT the name closure.
#
# WHY THIS EXISTS: _prune_redundant_clues dropped a clue whenever Sequence
# stayed unique and the closure did not grow. Mention coverage was not one
# of its conditions, so it stripped the last clue binding a name and then
# called _recompute_name_revealed(), which honestly reported the damage it
# had just done. Measured 2026-08-19, 15 seeds, one attempt each:
#
#     pruning OFF   name gate  9/15      names unbound  6  (worst 1)
#     pruning ON    name gate  0/15      names unbound 79  (worst 9)
#
# Zero. Every puzzle generated since pruning landed burned all five retries
# and shipped anyway; a player hit it as
# "STILL NOT UNIQUE after 5 generation attempts".
#
# It went unseen because the closure holds at 15/15 in BOTH conditions, and
# every probe reported name_unique_closure -- the aspirational gate -- while
# the live one collapsed. The suite was 29 modules green throughout.
#
# So this test pins the RELATIONSHIP, not an absolute rate: pruning is a
# minimisation pass and must be neutral with respect to the gate. An
# absolute threshold would drift with clue-mix tuning and would not have
# caught this any earlier; "ON must be no worse than OFF" catches it the
# first time pruning trades the gate for a smaller clue set.
#
# The OFF rate is asserted non-zero first: if the baseline itself never
# passes, "ON is no worse" is trivially true and proves nothing.

const SEEDS := [11, 4242]
const CONSTELLATIONS := [0, 2]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _measure(cd, prune: bool) -> Dictionary:
	var puzzles: int = 0
	var gate_ok: int = 0
	var unbound: int = 0
	var clues: int = 0
	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in SEEDS:
			var g = load("res://constellation_logic_puzzle.gd").new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
			g.prune_enabled = prune
			var r: Dictionary = await g._generate_clues_forms_attempt()
			puzzles += 1
			clues += g.chosen_form_clues.size()
			# Exactly the condition generate_clues_forms() breaks its retry
			# loop on -- read from the same returned dictionary, so this
			# cannot drift from the real gate.
			if bool(r.get("seq_unique", false)) and bool(r.get("name_unique", false)):
				gate_ok += 1
			var nr: Array = []
			for _i in scn:
				nr.append(false)
			g._recompute_name_revealed(nr)
			for v in nr:
				if not bool(v):
					unbound += 1
	return {"puzzles": puzzles, "gate": gate_ok, "unbound": unbound, "clues": clues}


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var off: Dictionary = await _measure(cd, false)
	var on: Dictionary = await _measure(cd, true)

	print("  pruning OFF: gate %d/%d, names unbound %d, clues %d"
		% [int(off["gate"]), int(off["puzzles"]), int(off["unbound"]), int(off["clues"])])
	print("  pruning ON : gate %d/%d, names unbound %d, clues %d"
		% [int(on["gate"]), int(on["puzzles"]), int(on["unbound"]), int(on["clues"])])

	# Non-vacuity: "ON is no worse than OFF" is free if OFF never passes.
	ok(int(off["gate"]) > 0,
		"the unpruned baseline passes the live gate at all (%d/%d) — otherwise the next check is vacuous"
			% [int(off["gate"]), int(off["puzzles"])])
	ok(int(on["gate"]) >= int(off["gate"]),
		"pruning does not reduce the live-gate pass rate (ON %d vs OFF %d)"
			% [int(on["gate"]), int(off["gate"])])
	ok(int(on["unbound"]) <= int(off["unbound"]),
		"pruning unbinds no name the unpruned set had bound (ON %d vs OFF %d)"
			% [int(on["unbound"]), int(off["unbound"])])
	# And it must still actually prune -- a trivially gate-neutral pruning
	# pass is one that removes nothing.
	ok(int(on["clues"]) < int(off["clues"]) / 2,
		"pruning still removes most clues (%d vs %d) — it was corrected, not disabled"
			% [int(on["clues"]), int(off["clues"])])

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
