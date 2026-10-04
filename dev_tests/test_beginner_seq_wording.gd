extends "res://dev_tests/test_base.gd"
# Beginner (repeating-melody) Sequence wording, in staff NOTES.
#
# A star's Sequence value is its rank among the stars; the staff counts melody
# notes, and a repeating star owns several of them. The melody's repeat shape
# is public (the staff draws it), so a clue may name a star by ANY one of its
# notes -- "the star that fires 12th note" is the star at note 12 -- and the
# wording stays honest as long as order claims say "first fires" when a star in
# them fires more than once. A 1:1 melody (every hard-mode constellation) must
# keep the original wording byte-for-byte.
#
# What must hold, and why each case exists:
#  - Every Sequence label prints a note that really belongs to the star (the
#    melody itself says so), and the fixture HAS a star whose first note is not
#    rank + 1, otherwise the old rank wording could pass this by luck.
#  - Order wording says "first fires" exactly when a star the sentence mentions
#    repeats, and plain "fires" otherwise (Pairwise Order, Betweenness, Extreme,
#    Count, Group Order).
#  - Range states a note window whose stars are exactly the ones its rank fact
#    covers.
#  - Exact Offset and Adjacency, whose arithmetic is in notes the solver cannot
#    yet carry, are absent from Sequence in a repeating melody and present in
#    hard mode.
#  - The player-side text (deduction/widgets) agrees with the generator's label.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner_puzzle(cid: int, seed: int):
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g._build_record_array()
	g._build_matrix()
	return g


func _hard_puzzle(cid: int, seed: int):
	var cd = load("res://constellation_data.gd").new()   # no GameContext -> hard mode
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var sq: Array = []
	for i in range(int(def["star_count"])):
		sq.append(i)
	var g = PuzzleScript.new()
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g._build_record_array()
	g._build_matrix()
	return g


func _draw(g, builder: String, tries: int) -> Array:
	var out: Array = []
	for i in tries:
		var c: Dictionary = g.call(builder, {})
		if not c.is_empty():
			out.append(c)
	return out


func _stars_of(clue: Dictionary) -> Array:
	var seen: Dictionary = {}
	for ch in (clue.get("chars", []) as Array):
		seen[int((ch as Dictionary)["star"])] = true
	return seen.keys()


func _any_repeats(g, stars: Array) -> bool:
	for s in stars:
		if int(g.repeat_count[int(s)]) > 0:
			return true
	return false


func run() -> void:
	var g = _beginner_puzzle(0, 11)
	var h = _hard_puzzle(0, 11)

	print("=== the repeat switch ===")
	ok(g._melody_repeats(), "The Archon Beginner (%d notes, %d stars) is a repeating melody" % [g.melody_star_sequence.size(), g.star_count])
	ok(not h._melody_repeats(), "The Archon hard mode (1:1 melody) is not")

	print("\n=== a label prints a note that really belongs to the star ===")
	var rank_differs: int = 0
	var bad_label: int = 0
	var bad_note: int = 0
	var bad_pred: int = 0
	for s in g.star_count:
		var tick: int = g._seq_first_tick(s)
		if int(g.melody_star_sequence[tick - 1]) != s:
			bad_note += 1
		if tick != int(g.sequence_rank_solution[s]) + 1:
			rank_differs += 1
		var want: String = "the star that fires %s" % PuzzleScript._ordinal(tick)
		if g._characteristic_label({"cat": PuzzleScript.Category.SEQUENCE, "star": s}) != want:
			bad_label += 1
		if g._characteristic_predicate({"cat": PuzzleScript.Category.SEQUENCE, "star": s}) != "fires %s" % PuzzleScript._ordinal(tick):
			bad_pred += 1
	ok(rank_differs > 0, "fixture has a star whose first note is not rank + 1 (%d), so the old rank wording is not accidentally right here" % rank_differs)
	ok(bad_note == 0, "every label names a note the melody really gives that star (%d wrong)" % bad_note)
	ok(bad_label == 0, "every Sequence label reads 'the star that fires <its first note>' (%d wrong)" % bad_label)
	ok(bad_pred == 0, "every Sequence predicate reads 'fires <its first note>' (%d wrong)" % bad_pred)

	print("\n=== hard mode is byte-identical to the original wording ===")
	var bad_hard: int = 0
	for s3 in h.star_count:
		var rank1: int = int(h.sequence_rank_solution[s3]) + 1
		if h._characteristic_label({"cat": PuzzleScript.Category.SEQUENCE, "star": s3}) != "the star that fires %s" % PuzzleScript._ordinal(rank1):
			bad_hard += 1
		if h._characteristic_predicate({"cat": PuzzleScript.Category.SEQUENCE, "star": s3}) != "fires %s" % PuzzleScript._ordinal(rank1):
			bad_hard += 1
	ok(bad_hard == 0, "hard-mode labels and predicates are exactly the original wording (%d differ)" % bad_hard)
	ok(h._seq_fire_verb(range(h.star_count)) == "fires", "hard mode never says 'first fires'")

	print("\n=== the fire verb tracks whether a mentioned star repeats ===")
	var single: int = -1
	var repeater: int = -1
	for s4 in g.star_count:
		if int(g.repeat_count[s4]) == 0 and single < 0:
			single = s4
		if int(g.repeat_count[s4]) > 0 and repeater < 0:
			repeater = s4
	ok(single >= 0 and repeater >= 0, "fixture has both a star that fires once and one that repeats")
	ok(g._seq_fire_verb([single]) == "fires", "a star that fires once keeps the plain verb")
	ok(g._seq_fire_verb([repeater]) == "first fires", "a star that repeats says 'first fires'")
	ok(g._seq_fire_verb([single, repeater]) == "first fires", "one repeater among several is enough")
	ok(g._seq_fire_base([single]) == "fire" and g._seq_fire_base([repeater]) == "first fire", "the bare forms follow the same rule")

	print("\n=== Forms say it exactly when a mentioned star repeats ===")
	for f in ["_build_form_pairwise_order", "_build_form_betweenness"]:
		var seq_clues: int = 0
		var wrong: int = 0
		for c in _draw(g, f, 300):
			var text: String = str(c.get("text", ""))
			if text.contains("is pitched"):
				continue   # a Pitch clue, no firing verb at all
			seq_clues += 1
			var says_first: bool = text.contains("first fires")
			if says_first != _any_repeats(g, _stars_of(c)):
				wrong += 1
				print("    mismatch: ", text)
		ok(seq_clues > 0, "%s drew Sequence clues (%d)" % [f, seq_clues])
		ok(wrong == 0, "%s: 'first fires' appears exactly when a mentioned star repeats (%d wrong of %d)" % [f, wrong, seq_clues])
	for f2 in ["_build_form_extreme", "_build_form_count"]:
		var n2: int = 0
		var wrong2: int = 0
		for c2 in _draw(g, f2, 300):
			n2 += 1
			var subject: int = int((c2["chars"] as Array)[0]["star"])
			var involved: Array = [subject] + (g.proximity[subject] as Array)
			if str(c2["text"]).contains("first fire") != _any_repeats(g, involved):
				wrong2 += 1
				print("    mismatch: ", c2["text"])
		ok(n2 > 0, "%s drew clues (%d)" % [f2, n2])
		ok(wrong2 == 0, "%s: 'first fire' appears exactly when the subject or a neighbour repeats (%d wrong)" % [f2, wrong2])
	var go_n: int = 0
	var go_wrong: int = 0
	for c3 in _draw(g, "_build_form_group_order", 400):
		go_n += 1
		var ch: Array = c3["chars"]
		var def_cat: int = int((ch[2] as Dictionary)["cat"])
		var def_star: int = int((ch[2] as Dictionary)["star"])
		var involved3: Array = [int((ch[0] as Dictionary)["star"])]
		for m in g.star_count:
			if g._name_group_key(def_cat, m) == g._name_group_key(def_cat, def_star):
				involved3.append(m)
		var t3: String = str(c3["text"])
		var says_first3: bool = t3.contains("first fires")
		if says_first3 != _any_repeats(g, involved3):
			go_wrong += 1
			print("    mismatch: ", t3)
	ok(go_n > 0, "Group Order drew clues (%d)" % go_n)
	ok(go_wrong == 0, "Group Order says 'first fires ... first fires' exactly when a star in it repeats (%d wrong)" % go_wrong)

	print("\n=== Range is a note window that matches its rank fact ===")
	var r_n: int = 0
	var r_bad: int = 0
	var seen_kinds: Dictionary = {}
	var re_first := RegEx.create_from_string("within the first (\\d+) notes\\.$")
	var re_late := RegEx.create_from_string("no earlier than note (\\d+)\\.$")
	for c4 in _draw(g, "_build_form_range", 300):
		r_n += 1
		var fact: Dictionary = {}
		for sf in c4["solver_facts"]:
			if str((sf as Dictionary).get("kind", "")) == "ordinal_range":
				fact = sf
		var t4: String = str(c4["text"])
		var m1 = re_first.search(t4)
		var m2 = re_late.search(t4)
		if fact.is_empty() or (m1 == null and m2 == null):
			r_bad += 1
			print("    unparsed Range: ", t4)
			continue
		seen_kinds["first" if m1 != null else "late"] = true
		var bound: int = int(m1.get_string(1)) if m1 != null else int(m2.get_string(1))
		for s5 in g.star_count:
			var in_rank: bool = int(g.sequence_rank_solution[s5]) >= int(fact["lo"]) and int(g.sequence_rank_solution[s5]) <= int(fact["hi"])
			var ft: int = g._seq_first_tick(s5)
			var in_window: bool = (ft <= bound) if m1 != null else (ft >= bound)
			if in_rank != in_window:
				r_bad += 1
				print("    window disagrees with rank fact: ", t4)
				break
	ok(r_n > 0, "Range drew clues (%d)" % r_n)
	ok(r_bad == 0, "every Range note window covers exactly the stars its rank fact covers (%d bad)" % r_bad)
	ok(seen_kinds.has("first") and seen_kinds.has("late"), "both window shapes occur (%s)" % str(seen_kinds.keys()))
	var h_range_ok: bool = true
	for c5 in _draw(h, "_build_form_range", 100):
		if not str(c5["text"]).contains(" is among the "):
			h_range_ok = false
	ok(h_range_ok, "hard-mode Range keeps 'is among the first/last N'")

	print("\n=== note-arithmetic Forms are off for Sequence in a repeating melody ===")
	var offsets_b: Array = _draw(g, "_build_form_exact_offset", 300)
	var seq_offsets_b: int = 0
	var pitch_offsets_b: int = 0
	for c6 in offsets_b:
		if str(c6["text"]).contains("fires exactly"):
			seq_offsets_b += 1
		if str(c6["text"]).contains("is pitched exactly"):
			pitch_offsets_b += 1
	ok(seq_offsets_b == 0, "Beginner Exact Offset never offers a Sequence offset (%d)" % seq_offsets_b)
	ok(pitch_offsets_b > 0, "Beginner Exact Offset still offers the Pitch version (%d)" % pitch_offsets_b)
	var seq_offsets_h: int = 0
	for c7 in _draw(h, "_build_form_exact_offset", 300):
		if str(c7["text"]).contains("fires exactly"):
			seq_offsets_h += 1
	ok(seq_offsets_h > 0, "hard-mode Exact Offset still offers Sequence offsets (%d)" % seq_offsets_h)
	ok(_draw(g, "_build_form_adjacency", 300).size() == 0, "Beginner Adjacency produces nothing")
	ok(_draw(h, "_build_form_adjacency", 300).size() > 0, "hard-mode Adjacency still produces clues")

	print("\n=== the player-side text agrees with the generator's label ===")
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = g.star_count
	host._sequence_rank_solution = g.sequence_rank_solution.duplicate()
	host._melody_seq_pos_sequence = g.melody_seq_pos_sequence.duplicate()
	var d = host._deduction
	var w = host._widgets
	ok(d._seq_repeats(), "the deduction engine sees the same repeating melody")
	var mismatched: int = 0
	for s6 in g.star_count:
		if d._seq_noun(int(g.sequence_rank_solution[s6]) + 1) != g._characteristic_label({"cat": PuzzleScript.Category.SEQUENCE, "star": s6}):
			mismatched += 1
	ok(mismatched == 0, "_seq_noun matches the generator's label for every star (%d differ)" % mismatched)
	ok(d._seq_rel_verb() == "first fires", "relational player text says 'first fires'")
	# Archon: rank 10 (index 9) first fires at note 15.
	ok(d._describe_disclosure({"kind": "ordinal_exact", "s": 0, "r": 9}).contains("fires 15th note"),
		"a disclosure line names rank 10 as the 15th note (got '%s')" % d._describe_disclosure({"kind": "ordinal_exact", "s": 0, "r": 9}))
	ok(w._step_sentence({"descriptor": "Alpha", "axis": "sequence", "resolved_rank": 9}) == "With what you know, Alpha must fire 15th note.",
		"a hint sentence names it by its note")
	ok(d._seq_ticks_phrase(8) == "notes 8, 10, 12",
		"a star that repeats is listed by every note (got '%s')" % d._seq_ticks_phrase(8))
	ok(d._seq_ticks_phrase(10) == "15th note", "a star that fires once is listed by its one note (got '%s')" % d._seq_ticks_phrase(10))
	host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
