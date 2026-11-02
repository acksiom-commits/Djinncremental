extends "res://dev_tests/test_base.gd"
# prune_first_forms: the prune-side Form preference. It only changes the ORDER
# removals are tried in, so it must never cost the ship gate, must be a no-op
# when empty / naming no Form present, must be deterministic, and must
# actually shift the shipped mix toward the Forms it does NOT name.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const CIDS := [0, 2, 5]
const SEEDS := [11, 12]
# The Form each difficulty's comparison watches, one its puzzles really ship: real
# Beginner boards shipped 1 Single Negation over these six puzzles, too few to
# compare, against 5 Group Negation (measured 2026-11-01, historical order).
const PROBE_FORM := {"hard": 2, "easy": 24}

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _gen(cid: int, seed: int, order: Array, diff: String) -> Dictionary:
	var g = real_puzzle(cid, seed, diff)
	# An empty list now means "use the difficulty profile's own list" (Easy has one
	# since 2026-10-15); [-1] names no Form, so it is the historical order.
	g.prune_first_forms = order if not order.is_empty() else [-1]
	var res: Dictionary = await g._generate_clues_forms_attempt()
	var texts: Array = []
	var shipped: int = 0
	for c in g.chosen_form_clues:
		texts.append(str((c as Dictionary).get("text", "")))
		if int((c as Dictionary).get("form_id", -1)) == int(PROBE_FORM[diff]):
			shipped += 1
	return {"texts": texts, "pass": g._gate_result_passes(res), "probe": shipped}


func run() -> void:
	ok((PuzzleScript.new().prune_first_forms as Array).is_empty(), "default is empty (historical newest-first order)")
	for diff in ["hard", "easy"]:
		var base_n: int = 0
		var pref_n: int = 0
		var all_pass: bool = true
		var form: int = int(PROBE_FORM[diff])
		var noop_same: int = 0
		var repeat_same: int = 0
		var judged: int = 0
		for cid in CIDS:
			for seed in SEEDS:
				var base: Dictionary = await _gen(cid, seed, [], diff)
				var absent: Dictionary = await _gen(cid, seed, [999], diff)
				var pref: Dictionary = await _gen(cid, seed, [form], diff)
				var pref2: Dictionary = await _gen(cid, seed, [form], diff)
				judged += 1
				base_n += int(base["probe"])
				pref_n += int(pref["probe"])
				all_pass = all_pass and bool(base["pass"]) and bool(pref["pass"])
				if absent["texts"] == base["texts"]:
					noop_same += 1
				if pref["texts"] == pref2["texts"]:
					repeat_same += 1
		print("  [%s] Form %d shipped: baseline %d, preferred-first %d (over %d puzzles)" % [diff, form, base_n, pref_n, judged])
		ok(all_pass, "%s: the ship gate passes with and without the preference" % diff)
		ok(noop_same == judged, "%s: naming a Form that is absent changes nothing (%d/%d identical)" % [diff, noop_same, judged])
		ok(repeat_same == judged, "%s: deterministic for a fixed seed (%d/%d identical)" % [diff, repeat_same, judged])
		ok(base_n >= 3, "%s: the baseline ships enough of Form %d for the comparison to mean something (%d)" % [diff, form, base_n])
		ok(pref_n < base_n, "%s: preferring Form %d for removal reduces how many ship (%d -> %d)" % [diff, form, base_n, pref_n])
	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
