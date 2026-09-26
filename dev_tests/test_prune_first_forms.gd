extends "res://dev_tests/test_base.gd"
# prune_first_forms: the prune-side Form preference. It only changes the ORDER
# removals are tried in, so it must never cost the ship gate, must be a no-op
# when empty / naming no Form present, must be deterministic, and must
# actually shift the shipped mix toward the Forms it does NOT name.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const CIDS := [0, 2, 5]
const SEEDS := [11, 12]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _gen(cd, cid: int, seed: int, order: Array, diff: String) -> Dictionary:
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g.difficulty = diff
	g.prune_first_forms = order
	var res: Dictionary = await g._generate_clues_forms_attempt()
	var texts: Array = []
	var single_neg: int = 0
	for c in g.chosen_form_clues:
		texts.append(str((c as Dictionary).get("text", "")))
		if int((c as Dictionary).get("form_id", -1)) == 2:
			single_neg += 1
	return {"texts": texts, "pass": g._gate_result_passes(res), "f2": single_neg}


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	ok((PuzzleScript.new().prune_first_forms as Array).is_empty(), "default is empty (historical newest-first order)")
	for diff in ["hard", "easy"]:
		var base_f2: int = 0
		var pref_f2: int = 0
		var all_pass: bool = true
		var noop_same: int = 0
		var repeat_same: int = 0
		var judged: int = 0
		for cid in CIDS:
			for seed in SEEDS:
				var base: Dictionary = await _gen(cd, cid, seed, [], diff)
				var absent: Dictionary = await _gen(cd, cid, seed, [999], diff)
				var pref: Dictionary = await _gen(cd, cid, seed, [2], diff)
				var pref2: Dictionary = await _gen(cd, cid, seed, [2], diff)
				judged += 1
				base_f2 += int(base["f2"])
				pref_f2 += int(pref["f2"])
				all_pass = all_pass and bool(base["pass"]) and bool(pref["pass"])
				if absent["texts"] == base["texts"]:
					noop_same += 1
				if pref["texts"] == pref2["texts"]:
					repeat_same += 1
		print("  [%s] Single Negation shipped: baseline %d, preferred-first %d (over %d puzzles)" % [diff, base_f2, pref_f2, judged])
		ok(all_pass, "%s: the ship gate passes with and without the preference" % diff)
		ok(noop_same == judged, "%s: naming a Form that is absent changes nothing (%d/%d identical)" % [diff, noop_same, judged])
		ok(repeat_same == judged, "%s: deterministic for a fixed seed (%d/%d identical)" % [diff, repeat_same, judged])
		ok(base_f2 >= 3, "%s: the baseline ships enough Single Negation for the comparison to mean something (%d)" % [diff, base_f2])
		ok(pref_f2 < base_f2, "%s: preferring Single Negation for removal reduces how many ship (%d -> %d)" % [diff, base_f2, pref_f2])
	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
