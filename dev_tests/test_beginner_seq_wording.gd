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
#  - Exact Offset and Adjacency, whose arithmetic is in NOTES, never print the
#    rank wording ("fires exactly N steps later") in a repeating melody -- they
#    become note-gap / melody-adjacency sentences (test_firing_relation judges
#    those) -- and keep the original wording in hard mode.
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


func _count_containing(clues: Array, frag: String) -> int:
	var n: int = 0
	for c in clues:
		if str(c["text"]).contains(frag):
			n += 1
	return n


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

	print("\n=== 'first fires' is said of a star only if THAT star repeats ===")
	# Per-star wording (2026-10-08): a star that fires once never gets the words,
	# even when another star in the same sentence repeats; every repeating star
	# the sentence mentions is marked -- as the verb's subject (its own verb) or,
	# when it is only the other side of the comparison, with a " first fires"
	# tail. A label that is itself a Sequence descriptor ("the star that fires
	# 12th note") already names the first note, so it takes no tail.
	# Each Form below prints judged/parsed counts so a silent 0 cannot pass.
	var pw_n: int = 0
	var pw_wrong: int = 0
	var re_pw := RegEx.create_from_string("^(.+?) (first fires|fires) (?:earlier|later) than (.+?)( first fires)?\\.$")
	var pw_mixed: int = 0
	for c in _draw(g, "_build_form_pairwise_order", 400):
		var text: String = str(c.get("text", ""))
		if text.contains("is pitched") or text.contains("higher") or text.contains("lower"):
			continue
		var m = re_pw.search(text)
		var fact_pw: Dictionary = {}
		for sf in c["solver_facts"]:
			if str((sf as Dictionary).get("kind", "")) == "ordinal_cmp":
				fact_pw = sf
		if m == null or fact_pw.is_empty():
			pw_wrong += 1
			print("    unparsed: ", text)
			continue
		pw_n += 1
		var a_rep: bool = _rep(g, int(fact_pw["a"]))
		var b_rep: bool = _rep(g, int(fact_pw["b"]))
		if a_rep != b_rep:
			pw_mixed += 1
		var ok_verb: bool = (m.get_string(2) == "first fires") == a_rep
		var ok_tail: bool = (m.get_string(4) != "") == (b_rep and not _is_seq_label(m.get_string(3)))
		if not (ok_verb and ok_tail):
			pw_wrong += 1
			print("    mismatch: ", text)
	ok(pw_n > 0 and pw_mixed > 0, "Pairwise Order drew %d Sequence clues, %d of them mixing a repeating and a single star" % [pw_n, pw_mixed])
	ok(pw_wrong == 0, "Pairwise Order marks exactly the repeating stars (%d wrong)" % pw_wrong)

	var bt_n: int = 0
	var bt_wrong: int = 0
	var bt_mixed: int = 0
	var re_b0 := RegEx.create_from_string("^(.+?) (first fires|fires) between (.+?)( first fires)? and (.+?)( first fires)?\\.$")
	var re_b1 := RegEx.create_from_string("^(.+?) (first fires|fires) (?:before|after) (.+?), which (first fires|fires) (?:before|after) (.+?)( first fires)?\\.$")
	for c5 in _draw(g, "_build_form_betweenness", 400):
		var t5: String = str(c5.get("text", ""))
		if t5.contains("is pitched"):
			continue
		var chain: Dictionary = {}
		for sf5 in c5["solver_facts"]:
			if str((sf5 as Dictionary).get("kind", "")) == "ordinal_chain":
				chain = sf5
		var lo: int = int(chain.get("a", -1))
		var mid: int = int(chain.get("mid", -1))
		var hi: int = int(chain.get("b", -1))
		var good: bool = false
		var m0 = re_b0.search(t5)
		var m1 = re_b1.search(t5)
		if chain.is_empty():
			good = false
		elif m0 != null:
			good = (m0.get_string(2) == "first fires") == _rep(g, mid) \
				and (m0.get_string(4) != "") == (_rep(g, lo) and not _is_seq_label(m0.get_string(3))) \
				and (m0.get_string(6) != "") == (_rep(g, hi) and not _is_seq_label(m0.get_string(5)))
		elif m1 != null:
			# the first star is the chain's lo (before/before) or hi (after/after);
			# the last is the other end
			var first_star: int = lo if t5.contains(" before ") else hi
			var last_star: int = hi if t5.contains(" before ") else lo
			good = (m1.get_string(2) == "first fires") == _rep(g, first_star) \
				and (m1.get_string(4) == "first fires") == _rep(g, mid) \
				and (m1.get_string(6) != "") == (_rep(g, last_star) and not _is_seq_label(m1.get_string(5)))
		bt_n += 1
		if int(_rep(g, lo)) + int(_rep(g, mid)) + int(_rep(g, hi)) in [1, 2]:
			bt_mixed += 1
		if not good:
			bt_wrong += 1
			print("    mismatch: ", t5)
	ok(bt_n > 0 and bt_mixed > 0, "Betweenness drew %d Sequence clues, %d of them mixing repeating and single stars" % [bt_n, bt_mixed])
	ok(bt_wrong == 0, "Betweenness marks exactly the repeating stars (%d wrong)" % bt_wrong)

	var ex_n: int = 0
	var ex_wrong: int = 0
	var re_ex := RegEx.create_from_string("^(.+) is the (?:earliest|latest) to (first fire|fire) among its connected stars(, going by each star's first note)?\\.$")
	for c2 in _draw(g, "_build_form_extreme", 300):
		var m2 = re_ex.search(str(c2["text"]))
		var subject: int = int((c2["chars"] as Array)[0]["star"])
		ex_n += 1
		if m2 == null \
				or (m2.get_string(2) == "first fire") != _rep(g, subject) \
				or (m2.get_string(3) != "") != _any_repeats(g, g.proximity[subject]):
			ex_wrong += 1
			print("    mismatch: ", c2["text"])
	ok(ex_n > 0, "Extreme drew clues (%d)" % ex_n)
	ok(ex_wrong == 0, "Extreme: the verb follows the subject, the 'first note' clause follows the neighbours (%d wrong)" % ex_wrong)

	var ct_n: int = 0
	var ct_wrong: int = 0
	var re_ct := RegEx.create_from_string("^Exactly \\d+ of (.+)'s connected stars (first fire|fire) before it( first fires)?\\.$")
	for c6 in _draw(g, "_build_form_count", 300):
		var m6 = re_ct.search(str(c6["text"]))
		var subject6: int = int((c6["chars"] as Array)[0]["star"])
		ct_n += 1
		if m6 == null \
				or (m6.get_string(2) == "first fire") != _any_repeats(g, g.proximity[subject6]) \
				or (m6.get_string(3) != "") != _rep(g, subject6):
			ct_wrong += 1
			print("    mismatch: ", c6["text"])
	ok(ct_n > 0, "Count drew clues (%d)" % ct_n)
	ok(ct_wrong == 0, "Count: 'first fire' follows the neighbours, 'it first fires' follows the subject (%d wrong)" % ct_wrong)

	var go_n: int = 0
	var go_wrong: int = 0
	var go_mixed: int = 0
	var re_go_plain := RegEx.create_from_string("^(.+?) (?:precedes|follows) (.+)\\.$")
	var re_go := RegEx.create_from_string("^(.+?) (first fires|fires) (?:before|after) (.+?)( first fires)?\\.$")
	for c3 in _draw(g, "_build_form_group_order", 400):
		go_n += 1
		var ch: Array = c3["chars"]
		var def_cat: int = int((ch[2] as Dictionary)["cat"])
		var def_star: int = int((ch[2] as Dictionary)["star"])
		var subj3: int = int((ch[0] as Dictionary)["star"])
		var members: Array = []
		for mm in g.star_count:
			if g._name_group_key(def_cat, mm) == g._name_group_key(def_cat, def_star):
				members.append(mm)
		var t3: String = str(c3["text"])
		var s_rep: bool = _rep(g, subj3)
		var g_rep: bool = _any_repeats(g, members)
		if s_rep != g_rep:
			go_mixed += 1
		var good3: bool
		if not s_rep and not g_rep:
			good3 = re_go_plain.search(t3) != null
		else:
			var m3 = re_go.search(t3)
			good3 = m3 != null and (m3.get_string(2) == "first fires") == s_rep and (m3.get_string(4) != "") == g_rep
		if not good3:
			go_wrong += 1
			print("    mismatch: ", t3)
	ok(go_n > 0 and go_mixed > 0, "Group Order drew %d clues, %d with a repeating subject xor group" % [go_n, go_mixed])
	ok(go_wrong == 0, "Group Order: the subject's verb and the group's tail are decided separately (%d wrong)" % go_wrong)

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

	print("\n=== note-arithmetic Forms speak in notes in a repeating melody ===")
	var offsets_b: Array = _draw(g, "_build_form_exact_offset", 300)
	var seq_offsets_b: int = 0
	var note_offsets_b: int = 0
	var pitch_offsets_b: int = 0
	for c6 in offsets_b:
		if str(c6["text"]).contains("fires exactly"):
			seq_offsets_b += 1
		if str(c6["text"]).contains(" notes after ") or str(c6["text"]).contains(" notes before "):
			note_offsets_b += 1
		if str(c6["text"]).contains("is pitched exactly"):
			pitch_offsets_b += 1
	ok(seq_offsets_b == 0, "Beginner Exact Offset never prints the rank wording 'fires exactly' (%d)" % seq_offsets_b)
	ok(note_offsets_b > 0, "Beginner Exact Offset's Sequence version is a gap in notes (%d)" % note_offsets_b)
	ok(pitch_offsets_b > 0, "Beginner Exact Offset still offers the Pitch version (%d)" % pitch_offsets_b)
	var seq_offsets_h: int = 0
	for c7 in _draw(h, "_build_form_exact_offset", 300):
		if str(c7["text"]).contains("fires exactly"):
			seq_offsets_h += 1
	ok(seq_offsets_h > 0, "hard-mode Exact Offset still offers Sequence offsets (%d)" % seq_offsets_h)
	var adj_b: Array = _draw(g, "_build_form_adjacency", 300)
	var adj_plain: int = 0
	for c8 in adj_b:
		if str(c8["text"]).contains("immediately after") and not str(c8["text"]).contains("first fires"):
			adj_plain += 1
	ok(adj_b.size() > 0, "Beginner Adjacency is back, as melody adjacency (%d clues)" % adj_b.size())
	ok(adj_b.size() == 0 or adj_plain + _count_containing(adj_b, "immediately before") == adj_b.size(), "every Beginner Adjacency clue says 'immediately after/before'")
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


func _rep(g, star: int) -> bool:
	return int(g.repeat_count[star]) > 0


func _is_seq_label(label: String) -> bool:
	return label.begins_with("the star that fires")
