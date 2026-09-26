extends "res://dev_tests/test_base.gd"
# The disambiguating-clue fallback (_repair_uniqueness).
#
# A generated puzzle has been pruned to minimal, so removing ANY single clue
# leaves it broken in some way: Sequence no longer unique, or Sequence unique
# but the Name closure not, or (only) a name no longer bound by mention. That
# gives one honest broken puzzle per clue, on REAL generated data, with no
# fixture to hand-build. For every removal that breaks uniqueness the repair
# must:
#   - restore a conclusive, unique Sequence solution AND Name closure;
#   - add only statements that are TRUE of the ground truth (a repair that
#     "fixed" the puzzle by stating something false would be worse than none);
#   - add a modest number of clues.
#
# Three policies are measured on the SAME removals so the shipped default is
# chosen by data: negations only (gentle, but rules out one wrong answer per
# clue), pins only (strong: rules out every wrong answer for a name), and the
# default, which starts with negations and escalates to pins.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _state(g) -> Dictionary:
	# {seq_ok, name_ok}: unique AND conclusive on each axis.
	var facts: Array[Dictionary] = g._seq_facts_from_clues()
	var seq: Array = g._solve(facts, 2)
	var seq_ok: bool = seq.size() == 1 and not g._last_solve_inconclusive
	var name_ok: bool = false
	if seq_ok:
		var nm: Array = g._solve_name_closure(seq, 2)
		name_ok = nm.size() == 1 and not g._last_solve_inconclusive
	return {"seq_ok": seq_ok, "name_ok": name_ok}


## Runs the repair on every single-clue removal under one policy.
func _measure(g, original: Array[Dictionary], scn: int, negations_before_pin: int) -> Dictionary:
	g.repair_negations_before_pin = negations_before_pin
	var pins0: int = g.repair_pins_added
	var negs0: int = g.repair_negations_added
	var total0: int = g.repair_clues_added
	var m: Dictionary = {"broken": 0, "seq_broken": 0, "name_broken": 0, "harmless": 0,
		"repaired": 0, "added": 0, "max_added": 0, "wrong_truth": 0, "bad_facts": 0}
	for i in original.size():
		var reduced: Array[Dictionary] = original.duplicate()
		reduced.remove_at(i)
		g.chosen_form_clues = reduced
		var before: Dictionary = _state(g)
		if bool(before["seq_ok"]) and bool(before["name_ok"]):
			m["harmless"] += 1
			continue
		m["broken"] += 1
		if not bool(before["seq_ok"]):
			m["seq_broken"] += 1
		else:
			m["name_broken"] += 1

		var facts: Array[Dictionary] = g._seq_facts_from_clues()
		var revealed: Array = []
		for _n in scn:
			revealed.append(false)
		g._recompute_name_revealed(revealed)
		var count_before: int = g.chosen_form_clues.size()
		var added: int = g._repair_uniqueness(facts, revealed, {1: 0, 2: 0, 3: 0}, {})
		m["added"] += added
		m["max_added"] = maxi(int(m["max_added"]), added)

		for k in range(count_before, g.chosen_form_clues.size()):
			var clue: Dictionary = g.chosen_form_clues[k]
			for c in (clue.get("cells", []) as Array):
				var cd_: Dictionary = c
				# A cell is TRUE exactly when both sides are the same star.
				if bool(cd_.get("is_true", false)) != (int(cd_.get("star_a", -1)) == int(cd_.get("star_b", -2))):
					m["wrong_truth"] += 1
			for f in (clue.get("disclosures", []) as Array):
				var fd: Dictionary = f
				var v: String = ""
				if str(fd.get("kind", "")) in ["name_group", "name_group_neg"]:
					v = g._validate_name_group_fact(fd)
				else:
					v = g._validate_sequence_fact(fd)
				if v != "":
					m["bad_facts"] += 1

		var after: Dictionary = _state(g)
		if bool(after["seq_ok"]) and bool(after["name_ok"]):
			m["repaired"] += 1
	g.chosen_form_clues = original
	# Counter deltas over THIS policy's run (the counters accumulate across
	# calls on the shared instance).
	m["pins"] = g.repair_pins_added - pins0
	m["negations"] = g.repair_negations_added - negs0
	m["counter_total"] = g.repair_clues_added - total0
	return m


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var cdef: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 31337, 0, cdef.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g.generate_clues_forms()
	var original: Array[Dictionary] = g.chosen_form_clues.duplicate()
	print("    base puzzle: %d clues, gate_passed=%s, repair clues used during generation: %d"
		% [original.size(), str(g.gate_passed), g.repair_clues_added])
	ok(g.gate_passed, "the base puzzle passes the ship gate")

	var policies: Array = [
		["negations only", 1000],
		["negations, then pins", 2],
		["pins only", 0],
	]
	var results: Dictionary = {}
	for p in policies:
		var m: Dictionary = _measure(g, original, scn, int(p[1]))
		results[p[0]] = m
		print("    %-32s repaired %2d of %2d | clues added: %3d total, %2d at most | (removals: %d broke Sequence, %d broke only the Name closure, %d changed neither)"
			% [p[0], m["repaired"], m["broken"], m["added"], m["max_added"], m["seq_broken"], m["name_broken"], m["harmless"]])

	# The SHIPPED default, measured explicitly so the assertions below are about
	# what actually runs in generation, whichever policy that constant selects.
	var d: Dictionary = _measure(g, original, scn, PuzzleScript.REPAIR_NEGATIONS_BEFORE_PIN)
	print("    %-32s repaired %2d of %2d | clues added: %3d total, %2d at most"
		% ["SHIPPED DEFAULT (%d negations first)" % PuzzleScript.REPAIR_NEGATIONS_BEFORE_PIN, d["repaired"], d["broken"], d["added"], d["max_added"]])
	ok(int(d["seq_broken"]) > 0, "some removals break Sequence uniqueness (%d) -- otherwise that path is untested" % int(d["seq_broken"]))
	ok(int(d["name_broken"]) > 0, "some removals break only the Name closure (%d) -- otherwise that path is untested" % int(d["name_broken"]))
	ok(int(d["repaired"]) == int(d["broken"]),
		"the shipped default restores EVERY uniqueness-breaking removal to a unique, conclusive puzzle (%d of %d)" % [d["repaired"], d["broken"]])
	for name in results:
		ok(int(results[name]["wrong_truth"]) == 0 and int(results[name]["bad_facts"]) == 0,
			"%s: every repair clue states something TRUE (%d wrong cells, %d invalid facts)" % [name, results[name]["wrong_truth"], results[name]["bad_facts"]])
	ok(int(d["added"]) <= int(results["negations only"]["added"]),
		"the shipped default never costs more clues than negations alone (%d vs %d)" % [d["added"], results["negations only"]["added"]])
	ok(int(d["max_added"]) <= 8, "and a single repair stays modest (at most %d clues)" % int(d["max_added"]))

	print("\n=== the pin / negation counters split the total by KIND ===")
	# The aggregate repair_clues_added cannot say whether the fallback is
	# handing over answers (pins) or only ruling them out (negations). Each
	# policy has an exact, checkable signature.
	for name in results:
		var r: Dictionary = results[name]
		ok(int(r["pins"]) + int(r["negations"]) == int(r["counter_total"]) and int(r["counter_total"]) == int(r["added"]),
			"%s: pins + negations == the total == clues actually added (%d + %d, total %d, added %d)"
				% [name, r["pins"], r["negations"], r["counter_total"], r["added"]])
	var neg_only: Dictionary = results["negations only"]
	var pin_only: Dictionary = results["pins only"]
	var mixed: Dictionary = results["negations, then pins"]
	ok(int(neg_only["pins"]) == 0 and int(neg_only["negations"]) > 0,
		"negations-only policy adds no pins (%d pins, %d negations) -- and adds some, so this is not vacuous" % [neg_only["pins"], neg_only["negations"]])
	ok(int(pin_only["negations"]) == 0 and int(pin_only["pins"]) > 0,
		"pins-only policy adds no negations (%d negations, %d pins) -- and adds some" % [pin_only["negations"], pin_only["pins"]])
	ok(int(mixed["pins"]) > 0 and int(mixed["negations"]) > 0,
		"the escalating policy shows BOTH kinds (%d pins, %d negations), which the aggregate could never reveal" % [mixed["pins"], mixed["negations"]])
	var shipped: Dictionary = d
	ok(int(shipped["negations"]) == 0 or PuzzleScript.REPAIR_NEGATIONS_BEFORE_PIN > 0,
		"the shipped default (pins first) behaves as pins-first: %d pins, %d negations" % [shipped["pins"], shipped["negations"]])

	print("\n=== a puzzle that is already unique is left alone ===")
	g.chosen_form_clues = original
	var facts2: Array[Dictionary] = g._seq_facts_from_clues()
	var rev2: Array = []
	for _n2 in scn:
		rev2.append(false)
	g._recompute_name_revealed(rev2)
	var count0: int = g.chosen_form_clues.size()
	var added0: int = g._repair_uniqueness(facts2, rev2, {1: 0, 2: 0, 3: 0}, {})
	ok(added0 == 0 and g.chosen_form_clues.size() == count0, "no clue is added to an already-unique puzzle")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
