extends "res://dev_tests/test_base.gd"
# Early-stop must not change what ships: the main loop's late clues are all
# pruned away, so stopping it once the gate is met (+ margin) has to yield the
# SAME final clue texts as running it to stall. Guards that assumption -- if
# pruning ever stops discarding those clues, this fails before players notice.

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


func _gen(cd, cid: int, seed: int, early: bool) -> Dictionary:
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g.early_stop_enabled = early
	var res: Dictionary = await g._generate_clues_forms_attempt()
	var texts: Array = []
	for c in g.chosen_form_clues:
		texts.append(str((c as Dictionary).get("text", "")))
	return {"texts": texts, "pass": g._gate_result_passes(res), "stopped": g.early_stopped}


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var stopped_count: int = 0
	var judged: int = 0
	for cid in CIDS:
		for seed in SEEDS:
			var off: Dictionary = await _gen(cd, cid, seed, false)
			var on: Dictionary = await _gen(cd, cid, seed, true)
			judged += 1
			if on["stopped"]:
				stopped_count += 1
			ok(not off["stopped"], "c%d s%d: flag off never stops early" % [cid, seed])
			ok(on["pass"] and off["pass"], "c%d s%d: gate passes both ways" % [cid, seed])
			ok(on["texts"] == off["texts"], "c%d s%d: identical shipped clues (%d vs %d)" % [cid, seed, on["texts"].size(), off["texts"].size()])
	ok(judged == CIDS.size() * SEEDS.size() and stopped_count >= judged - 1,
		"early-stop actually engaged, so equality is not vacuous (%d of %d stopped)" % [stopped_count, judged])
	var default_g = PuzzleScript.new()
	ok(default_g.early_stop_enabled, "early-stop is on by default")
	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
