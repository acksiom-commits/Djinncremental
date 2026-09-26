extends "res://dev_tests/test_base.gd"
# The observable-identity invariant (critical-pass review item 5).
#
# When Colour or Pitch values repeat, _characteristic_label() names one member
# of the group with an INTERNAL sub-rank letter: "the white star marked B".
# That letter is bookkeeping -- neither overlay draws it -- so no player can
# tell which white star is "B". A clue that identifies a star that way is
# unverifiable: it can pass every internal solver gate and still be
# impossible to solve honestly.
#
# The generator is meant never to emit one, but the guard is a CONVENTION at
# each of ~26 call sites (_category_uniquely_labels), not something the label
# function enforces, so a new Form -- or an old one after a refactor -- can
# break it silently. This is the test-level guard the review asked for, ahead
# of any larger type-level refactor.
#
# Two INDEPENDENT detectors, so neither's blind spot hides a violation:
#   - the wording: any shipped text containing "marked <Letter>";
#   - the counter subrank_labels_rendered, which counts every render of the
#     marker branch regardless of how the sentence around it is phrased.
#
# Checked at three levels, because each catches something the others cannot:
#   1. every Form builder, drawn many times on real constellations WITH tied
#      Colour/Pitch groups (a puzzle with none could not show a violation);
#   2. the repair fallback's clue builders, for every star;
#   3. real end-to-end generations on both difficulty profiles.
# Plus a positive control: the detectors are shown to FIRE on a label that
# genuinely is a violation, so "0 found" cannot be a broken detector.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

const DRAWS_PER_FORM: int = 60
const SWEEP_SEEDS: Array = [11, 12]
const END_TO_END_SEED: int = 11

var fails: int = 0
var _marker: RegEx = null


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _has_marker(text: String) -> bool:
	return _marker.search(text) != null


func _setup(cd, cid: int, seed: int, difficulty: String = "hard"):
	var cdef: Dictionary = cd.get_constellation_def(cid)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g.difficulty = difficulty
	return g


## How many stars share a Colour or Pitch value with another star -- the
## exposure this invariant is about.
func _tied_stars(g) -> int:
	var n: int = 0
	for s in g.star_count:
		if g._group_size(g.Category.COLOR, s) > 1 or g._group_size(g.Category.PITCH, s) > 1:
			n += 1
	return n


func run() -> void:
	_marker = RegEx.new()
	_marker.compile("\\bmarked [A-Z]\\b")
	var cd = load("res://constellation_data.gd").new()
	var cids: Array = []
	for c in cd.BUILT_IN:
		var d: Dictionary = c
		if d.has("line_pairs") and not (d["line_pairs"] as Array).is_empty():
			cids.append(int(d["id"]))

	print("=== positive control: the detectors FIRE on a real violation ===")
	var pc = _setup(cd, cids[0], 11)
	var tied_star: int = -1
	for s in pc.star_count:
		if pc._group_size(pc.Category.COLOR, s) > 1:
			tied_star = s
			break
	ok(tied_star >= 0, "the control puzzle has a tied Colour group to mislabel (else there is nothing to test)")
	var before: int = pc.subrank_labels_rendered
	var bad_label: String = pc._characteristic_label({"cat": pc.Category.COLOR, "star": tied_star})
	print("    naming a tied star directly renders: \"%s\"" % bad_label)
	ok(_has_marker(bad_label), "the WORDING detector matches it")
	ok(pc.subrank_labels_rendered == before + 1, "the COUNTER detector counts it (%d -> %d)" % [before, pc.subrank_labels_rendered])
	var before2: int = pc.subrank_labels_rendered
	var ok_label: String = pc._characteristic_label({"cat": pc.Category.SEQUENCE, "star": tied_star})
	ok(not _has_marker(ok_label) and pc.subrank_labels_rendered == before2,
		"and neither fires on a label that is fine (\"%s\")" % ok_label)

	print("\n=== 1. every Form builder, drawn repeatedly on constellations with tied groups ===")
	var forms: Array = PuzzleScript.AUTOMATED_FORM_IDS
	var per_form_builds: Dictionary = {}
	var per_form_clues: Dictionary = {}
	var per_form_bad: Dictionary = {}
	var total_builds: int = 0
	var total_clues: int = 0
	var color_pitch_mentions: int = 0
	var wording_hits: Array = []
	var counter_total: int = 0
	var tied_total: int = 0
	var t0: int = Time.get_ticks_msec()
	for cid in cids:
		for seed in SWEEP_SEEDS:
			var g = _setup(cd, cid, seed)
			g._build_record_array()
			g._build_matrix()
			g._used_characteristics = {}
			g._last_clue_nodes = []
			g.chosen_form_clues.clear()
			tied_total += _tied_stars(g)
			var counter_before: int = g.subrank_labels_rendered
			for form_id in forms:
				for i in DRAWS_PER_FORM:
					# Chain from a realistic previous clue about half the time,
					# so chained draws (which start from a specific star) run too.
					var chain: Dictionary = g._pick_chain_characteristic() if i % 2 == 0 else {}
					g._rendered_terms = {}
					var res: Dictionary = g._build_form(int(form_id), chain)
					per_form_builds[form_id] = int(per_form_builds.get(form_id, 0)) + 1
					total_builds += 1
					if res.is_empty():
						continue
					total_clues += 1
					per_form_clues[form_id] = int(per_form_clues.get(form_id, 0)) + 1
					var text: String = str(res.get("text", ""))
					if text.contains(" plays ") or text.contains(" star") and (text.contains("blue") or text.contains("white") or text.contains("yellow") or text.contains("red")):
						color_pitch_mentions += 1
					if _has_marker(text):
						per_form_bad[form_id] = int(per_form_bad.get(form_id, 0)) + 1
						wording_hits.append("c%d seed %d Form %d: %s" % [cid, seed, int(form_id), text])
					if i % 4 == 0:
						g._last_clue_nodes = res.get("chars", [])
			counter_total += g.subrank_labels_rendered - counter_before
	print("    %d builds over %d constellations x %d seeds, %d produced a clue (%.1fs)" % [
		total_builds, cids.size(), SWEEP_SEEDS.size(), total_clues, float(Time.get_ticks_msec() - t0) / 1000.0])
	print("    %d of those clues mention a colour or a pitch; tied-star exposure summed over setups: %d" % [color_pitch_mentions, tied_total])
	var silent_forms: Array = []
	for f in forms:
		if int(per_form_clues.get(f, 0)) == 0:
			silent_forms.append(int(f))
	print("    Forms that produced NO clue in the sweep (untested here): %s" % str(silent_forms))
	ok(total_clues > 1000, "the sweep produced plenty of clues to judge (%d) -- otherwise 'none violate' proves nothing" % total_clues)
	ok(color_pitch_mentions > 100, "a large share of them actually name a colour or pitch (%d), so the labelling paths under test really ran" % color_pitch_mentions)
	ok(tied_total > 0, "the constellations really have tied Colour/Pitch groups (%d tied stars across setups)" % tied_total)
	ok(silent_forms.size() <= 3, "nearly every Form was exercised (%d silent: %s)" % [silent_forms.size(), str(silent_forms)])
	ok(wording_hits.is_empty(), "no Form ever produced text naming a star by an internal sub-rank marker (%d hits) %s" % [wording_hits.size(), str(wording_hits.slice(0, 3))])
	ok(counter_total == 0, "the marker branch was never even RENDERED, discarded drafts included (counter = %d)" % counter_total)

	print("\n=== 2. the repair fallback's clue builders, every star ===")
	var rg = _setup(cd, cids[0], 11)
	rg._build_record_array()
	rg._build_matrix()
	rg._used_characteristics = {}
	rg._last_clue_nodes = []
	rg.chosen_form_clues.clear()
	var facts: Array = []
	var revealed: Array = []
	for s in rg.star_count:
		revealed.append(false)
	var rc_before: int = rg.subrank_labels_rendered
	var repair_clues: int = 0
	for s2 in rg.star_count:
		if rg._commit_repair_clue(s2, 0, true, facts, revealed, {1: 0, 2: 0, 3: 0}, {}):
			repair_clues += 1
		var other_rank: int = int(rg.sequence_rank_solution[(s2 + 1) % rg.star_count])
		if rg._commit_repair_clue(s2, other_rank, false, facts, revealed, {1: 0, 2: 0, 3: 0}, {}):
			repair_clues += 1
	var repair_bad: int = 0
	for clue in rg.chosen_form_clues:
		if _has_marker(str((clue as Dictionary).get("text", ""))):
			repair_bad += 1
	ok(repair_clues >= rg.star_count, "the repair builders produced clues to judge (%d)" % repair_clues)
	ok(repair_bad == 0 and rg.subrank_labels_rendered == rc_before,
		"pins and negations never name a star by a marker (%d bad, counter delta %d) -- safe by construction, now pinned by a test" % [repair_bad, rg.subrank_labels_rendered - rc_before])

	print("\n=== 3. real end-to-end generations, both difficulty profiles ===")
	var gens: int = 0
	var e2e_clues: int = 0
	var e2e_bad: Array = []
	var e2e_counter: int = 0
	for cid2 in cids:
		for diff in ["easy", "hard"]:
			var g2 = _setup(cd, cid2, END_TO_END_SEED, diff)
			await g2.generate_clues_forms()
			gens += 1
			e2e_clues += g2.chosen_form_clues.size()
			e2e_counter += g2.subrank_labels_rendered
			for clue2 in g2.chosen_form_clues:
				if _has_marker(str((clue2 as Dictionary).get("text", ""))):
					e2e_bad.append("c%d %s: %s" % [cid2, diff, str((clue2 as Dictionary).get("text", ""))])
	print("    %d generations, %d shipped clues in total" % [gens, e2e_clues])
	ok(gens >= 10 and e2e_clues > 200, "enough real puzzles were generated (%d, %d clues) -- otherwise this proves nothing" % [gens, e2e_clues])
	ok(e2e_bad.is_empty(), "no shipped clue names a star by an internal marker (%d) %s" % [e2e_bad.size(), str(e2e_bad.slice(0, 3))])
	ok(e2e_counter == 0, "and the marker branch was never rendered during generation (counter = %d)" % e2e_counter)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
