extends "res://dev_tests/test_base.gd"
# Form 26, Firing Relation, and the note-arithmetic versions of Exact Offset (6)
# and Adjacency (7) in a repeating melody.
#
# A sentence relates a PICK of one star's firings (any one of them / first / last /
# k-th) to a pick of another's by a gap in notes (exactly n / immediately / at
# least n / within n, optionally negated between two specific firings). It reduces
# to the set of (rank of A, rank of B) pairs it allows -- an ordinal_pair_set.
#
# What must hold:
#  - Offered only on a repeating melody; building it on a 1:1 melody makes
#    nothing and draws no random numbers.
#  - Every clue is TRUE, and its pair table is exactly what the SENTENCE means,
#    worked out here from the melody alone by an independent parser (it shares no
#    helper with the builder, and is shown to FAIL on tampered input).
#  - Form 7 in a repeating melody is melody adjacency ("immediately after/before",
#    one firing of each); Form 6's Sequence version is "exactly N notes after".
#  - The SOLVER carries the table: with one star pinned, propagation and forward
#    checking leave exactly the partner ranks the table allows for the other.
#  - A real Beginner puzzle that uses them still passes the ship gate.
#  - The player-side engine scores the table.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const ORDS: Dictionary = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
	"sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "last": -1}

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


# ── the independent judge ────────────────────────────────────────────────

func _ticks_of(melody: Array, star: int) -> Array:
	var t: Array = []
	for i in melody.size():
		if int(melody[i]) == star:
			t.append(i + 1)
	return t


## "one of the firings of X" / "the first firing of X" / "the second firing of X" ->
## {label, fn: ticks -> Array of notes}, {} if it is none of those.
func _parse_pick(p: String) -> Dictionary:
	var m = RegEx.create_from_string("^one of the firings of (.+)$").search(p)
	if m:
		var all_fn: Callable = func(t: Array) -> Array:
			return t.duplicate()
		return {"label": m.get_string(1), "fn": all_fn, "any": true, "first": false}
	# "the only firing of X" (2026-10-12): the wording for a star that fires
	# once. As a relation it is the star's first note; THAT the star fires once
	# is a separate fact the clue carries (the verb fact), and _judge checks
	# the wording against the real melody.
	m = RegEx.create_from_string("^the only firing of (.+)$").search(p)
	if m:
		var only_fn: Callable = func(t: Array) -> Array:
			return [t[0]]
		return {"label": m.get_string(1), "fn": only_fn, "any": false, "first": true, "only": true}
	m = RegEx.create_from_string("^the (\\w+) firing of (.+)$").search(p)
	if m and ORDS.has(m.get_string(1)):
		var k: int = int(ORDS[m.get_string(1)])
		var nth_fn: Callable = func(t: Array) -> Array:
			var kk: int = t.size() if k == -1 else k
			if kk >= 1 and kk <= t.size():
				return [t[kk - 1]]
			return []
		return {"label": m.get_string(2), "fn": nth_fn, "any": false, "first": k == 1}
	return {}


## -> {left, right (picks), neg, rel, n, dir, shape} or {}.
func _parse(text: String) -> Dictionary:
	var re = RegEx.create_from_string("^(.+?) is (not )?(immediately (after|before)|exactly (\\d+) notes? (after|before)|at least (\\d+) notes? (after|before)|within (\\d+) notes? of) (one of the firings of .+|the \\w+ firing of .+)\\.$")
	var m = re.search(text)
	if not m:
		return {}
	# A committed clue has its first letter capitalised ("One of the firings...",
	# "The first firing..."); undo only that, so a Name label keeps its case.
	var left_text: String = m.get_string(1)
	if left_text.begins_with("One ") or left_text.begins_with("The "):
		left_text = left_text[0].to_lower() + left_text.substr(1)
	var left: Dictionary = _parse_pick(left_text)
	var right: Dictionary = _parse_pick(m.get_string(10))
	if left.is_empty() or right.is_empty():
		return {}
	var out: Dictionary = {"left": left, "right": right, "neg": m.get_string(2) != ""}
	if m.get_string(4) != "":
		out["rel"] = "exact"
		out["n"] = 1
		out["dir"] = 1 if m.get_string(4) == "after" else -1
		out["shape"] = "immediately"
	elif m.get_string(5) != "":
		out["rel"] = "exact"
		out["n"] = int(m.get_string(5))
		out["dir"] = 1 if m.get_string(6) == "after" else -1
		out["shape"] = "exactly"
	elif m.get_string(7) != "":
		out["rel"] = "atleast"
		out["n"] = int(m.get_string(7))
		out["dir"] = 1 if m.get_string(8) == "after" else -1
		out["shape"] = "atleast"
	else:
		out["rel"] = "within"
		out["n"] = int(m.get_string(9))
		out["dir"] = 1
		out["shape"] = "within"
	return out


func _holds(p: Dictionary, ticks_a: Array, ticks_b: Array) -> bool:
	var na: Array = p["left"]["fn"].call(ticks_a)
	var nb: Array = p["right"]["fn"].call(ticks_b)
	if na.is_empty() or nb.is_empty():
		return false
	var found: bool = false
	for ta in na:
		for tb in nb:
			var d: int = int(ta) - int(tb)
			var good: bool
			if p["rel"] == "exact":
				good = int(p["dir"]) * d == int(p["n"])
			elif p["rel"] == "atleast":
				good = int(p["dir"]) * d >= int(p["n"])
			else:
				good = absi(d) <= int(p["n"])
			if good:
				found = true
	return (not found) if bool(p["neg"]) else found


## "" when sound, else why not.
##
## REWRITTEN 2026-10-10 (repeats are earned). The clue's content is a
## firing_relation fact read by the repeat-note gate; this compares the gate's
## reading of it with the sentence's, over note sets the two stars could have.
## A rank pair table survives only between two FIRST firings, which are public.
func _judge(g, clue: Dictionary, tally: Dictionary, stored: bool = false) -> String:
	var p: Dictionary = _parse(str(clue["text"]))
	if p.is_empty():
		return "unparseable sentence: %s" % str(clue["text"])
	var melody: Array = g.melody_star_sequence
	var rels: Array = []
	for f in (clue.get("value_facts", []) as Array):
		if str((f as Dictionary).get("kind", "")) == "firing_relation":
			rels.append(f)
	if rels.size() != 1:
		return "expected exactly one firing_relation fact, got %d" % rels.size()
	var rel: Dictionary = rels[0]
	var sa: int = int(rel["a"])
	var sb: int = int(rel["b"])
	if sa == sb:
		return "a clue relates a star to itself"
	var true_a: Array = _ticks_of(melody, sa)
	var true_b: Array = _ticks_of(melody, sb)
	if not _holds(p, true_a, true_b):
		return "the sentence is FALSE of its own stars: %s" % str(clue["text"])
	# WELL-FORMED (reported 2026-10-12, "one of the firings of the star that
	# plays B5" for a star that never repeats): a star that fires once reads
	# "the only firing of", and only such a star does.
	if bool(p["left"].get("only", false)) != (true_a.size() == 1) \
			or bool(p["right"].get("only", false)) != (true_b.size() == 1):
		return "ill-formed for how often its stars fire (%d and %d times): %s" % [true_a.size(), true_b.size(), str(clue["text"])]
	tally["only_wording"] = int(tally.get("only_wording", 0)) \
		+ (1 if bool(p["left"].get("only", false)) or bool(p["right"].get("only", false)) else 0)
	# Sentence vs gate. The real note sets first, then other sets the two stars
	# could have (each star's first note plus some later repeat notes, disjoint).
	var rticks: Array = _repeat_ticks_of(melody)
	var masks: Array = []
	for _s in g.star_count:
		masks.append(0)
	var elig_a: int = 0
	var elig_b: int = 0
	var real_a: int = 0
	var real_b: int = 0
	for i in rticks.size():
		if int(rticks[i]) > int(true_a[0]):
			elig_a |= 1 << i
		if int(rticks[i]) > int(true_b[0]):
			elig_b |= 1 << i
		if true_a.has(rticks[i]):
			real_a |= 1 << i
		if true_b.has(rticks[i]):
			real_b |= 1 << i
	var trials: Array = [[real_a, real_b], [0, 0], [elig_a, 0], [0, elig_b]]
	var walk: int = 0
	for t in 12:
		walk = (walk * 37 + 11 + t) & 0xFFFF
		var ma: int = walk & elig_a
		trials.append([ma, (walk >> 3) & elig_b & ~ma])
	for tr in trials:
		var ta: Array = [true_a[0]]
		var tb: Array = [true_b[0]]
		for i2 in rticks.size():
			if int(tr[0]) & (1 << i2):
				ta.append(rticks[i2])
			if int(tr[1]) & (1 << i2):
				tb.append(rticks[i2])
		masks[sa] = int(tr[0])
		masks[sb] = int(tr[1])
		var want: bool = _holds(p, ta, tb)
		_gate_compares += 1
		if g._repeat_binary_holds(rel, rticks, masks) != want:
			return "the gate reads the fact as %s but the sentence is %s for notes %s / %s: %s" % [str(not want), str(want), str(ta), str(tb), str(clue["text"])]
	# Sequence facts: a rank disclosed by a Sequence label, and a pair table
	# only when BOTH picks are first firings.
	var both_first: bool = bool(p["left"]["first"]) and bool(p["right"]["first"])
	var tables: Array = []
	for f2 in (clue["solver_facts"] as Array):
		var k: String = str((f2 as Dictionary).get("kind", ""))
		if k == "ordinal_pair_set":
			tables.append(f2)
		elif k == "repeat_count_range" and bool((f2 as Dictionary).get("from_verb", false)):
			# The wording's own "fires once" / "fires more than once" fact
			# (2026-10-12), present in a stored clue's disclosures. Must be true.
			var real_n: int = _ticks_of(melody, int(f2["star"])).size() - 1
			if real_n < int(f2["lo"]) or real_n > int(f2["hi"]):
				return "the wording's repeat fact is false of the melody: %s" % str(clue["text"])
		elif k != "ordinal_exact":
			return "an unexpected Sequence fact (%s)" % k
	if tables.size() != (1 if both_first else 0):
		return "expected %d pair table(s) for %s picks, got %d: %s" % [1 if both_first else 0,
			"first/first" if both_first else "repeat-dependent", tables.size(), str(clue["text"])]
	if both_first:
		var fact: Dictionary = tables[0]
		# What the sentence means between FIRST notes, over every ordered pair.
		var want_t: Dictionary = {}
		for x in g.star_count:
			for y in g.star_count:
				if x != y and _holds(p, [_ticks_of(melody, x)[0]], [_ticks_of(melody, y)[0]]):
					want_t[int(g.sequence_rank_solution[x]) * 1000 + int(g.sequence_rank_solution[y])] = true
		var got: Dictionary = {}
		for pr in fact["pairs"]:
			got[int(pr[0]) * 1000 + int(pr[1])] = true
		if got.size() != (fact["pairs"] as Array).size():
			return "the pair list has duplicates"
		var got_keys: Array = got.keys()
		var want_keys: Array = want_t.keys()
		got_keys.sort()
		want_keys.sort()
		if got_keys != want_keys:
			return "table has %d pairs but the sentence means %d: %s" % [got_keys.size(), want_keys.size(), str(clue["text"])]
		var v: String = g._validate_sequence_fact(fact)
		if v != "":
			return v
		tally["first_first"] = int(tally.get("first_first", 0)) + 1
	# The two TRUE cells the Form consumes, one per star, on the Repeat axis
	# (none in a stored clue: the cache keeps no Repeat-axis cells).
	var cells: Array = clue["grid_updates"]
	if cells.size() != (0 if stored else 2):
		return "expected %d bookkeeping cells, got %d" % [0 if stored else 2, cells.size()]
	for c in cells:
		if not bool((c as Dictionary)["is_true"]) or int(c["cat_b"]) != PuzzleScript.Category.REPEAT:
			return "a bookkeeping cell is not a true Repeat-axis cell"
	tally["shape_" + str(p["shape"])] = int(tally.get("shape_" + str(p["shape"]), 0)) + 1
	tally["neg" if bool(p["neg"]) else "pos"] = int(tally.get("neg" if bool(p["neg"]) else "pos", 0)) + 1
	tally["left_any" if bool(p["left"]["any"]) else "left_specific"] = int(tally.get("left_any" if bool(p["left"]["any"]) else "left_specific", 0)) + 1
	tally["right_any" if bool(p["right"]["any"]) else "right_specific"] = int(tally.get("right_any" if bool(p["right"]["any"]) else "right_specific", 0)) + 1
	tally["dir_before" if int(p["dir"]) < 0 else "dir_after"] = int(tally.get("dir_before" if int(p["dir"]) < 0 else "dir_after", 0)) + 1
	return ""


## How many (clue, note sets) pairs the gate's reading was compared on.
var _gate_compares: int = 0


func _repeat_ticks_of(melody: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for i in melody.size():
		if seen.has(int(melody[i])):
			out.append(i + 1)
		else:
			seen[int(melody[i])] = true
	return out


func _host(melody: Array):
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
	host._star_colors = [0, 1, 2, 3]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = melody
	# SEAM ONLY since 2026-10-12: the checks that use this board read a rank
	# pair table (ordinal_pair_set) against the board's firing-order positions.
	# With the first notes hidden the board keeps no positions and that table
	# is not judged at all (the same clue's firing_relation is, on the notes
	# each row holds -- see test_owner_hints.gd), so this pins the older
	# reading as the seam keeps it.
	host._deduction.notes_hidden_enabled = false
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func run() -> void:
	var h = _hard_puzzle(0, 11)
	var g0 = _beginner_puzzle(0, 11)

	print("=== offered only on a repeating melody ===")
	ok(g0._forms_in_tier(2).has(26), "Beginner's tier-2 pool contains Form 26")
	var hard_pool: Array = []
	for t in [1, 2, 3]:
		hard_pool.append_array(h._forms_in_tier(t))
	ok(not hard_pool.has(26), "hard mode's Form pool does not contain it")
	var st_before = h._rng.state
	var hard_try: Dictionary = h._build_form(26, {})
	ok(hard_try.is_empty() and h._rng.state == st_before, "building it on a 1:1 melody makes nothing and draws no random numbers")

	print("\n=== every clue is true and means exactly what its sentence says ===")
	var tally: Dictionary = {}
	var built: int = 0
	var bad: Array = []
	var by_form: Dictionary = {"26": 0, "6": 0, "7": 0}
	var form7_not_immediate: int = 0
	var form6_not_exact: int = 0
	var form6_pitch: int = 0
	var rank_wording: int = 0
	for cid in range(0, 7):
		for seed in [11, 12, 13]:
			var g = _beginner_puzzle(cid, seed)
			if not g._firing_position_available():
				continue
			for form_id in [26, 6, 7]:
				for i in 200:
					g._rendered_terms = {}
					var clue: Dictionary = g._build_form(form_id, {})
					if clue.is_empty():
						continue
					var text: String = str(clue["text"])
					if form_id == 6 and text.contains("is pitched"):
						form6_pitch += 1
						continue   # the Pitch version is the old rank-space clue, judged elsewhere
					if text.contains("fires exactly") or text.contains("first fires immediately"):
						rank_wording += 1
					built += 1
					by_form[str(form_id)] = int(by_form[str(form_id)]) + 1
					var why: String = _judge(g, clue, tally)
					if why != "":
						bad.append("c%d s%d F%d: %s" % [cid, seed, form_id, why])
						continue
					if form_id == 7 and not text.contains(" is immediately "):
						form7_not_immediate += 1
					if form_id == 6 and not text.contains(" is exactly "):
						form6_not_exact += 1
	print("    clues built: %d (Form 26: %d, Form 6: %d, Form 7: %d); Form 6 Pitch clues skipped: %d" % [built, by_form["26"], by_form["6"], by_form["7"], form6_pitch])
	print("    tally: %s; gate comparisons: %d" % [str(tally), _gate_compares])
	ok(built > 500, "plenty of clues to judge (%d)" % built)
	ok(_gate_compares >= built * 4, "the gate's reading was compared on several note sets per clue (%d)" % _gate_compares)
	ok(int(tally.get("first_first", 0)) > 0, "some clues relate two first firings and keep a rank table (%d)" % int(tally.get("first_first", 0)))
	var judged: int = int(tally.get("pos", 0)) + int(tally.get("neg", 0))
	ok(judged == built - bad.size(), "every clue built was parsed and judged (%d judged, %d bad of %d)" % [judged, bad.size(), built])
	ok(bad.is_empty(), "no clue is false or disagrees with its own pair table (%d bad) %s" % [bad.size(), str(bad.slice(0, 3))])
	ok(int(by_form["26"]) > 100 and int(by_form["6"]) > 20 and int(by_form["7"]) > 20, "Forms 26, 6 and 7 all produced clues in a repeating melody")
	ok(form7_not_immediate == 0, "every Form 7 clue is melody adjacency ('is immediately after/before') (%d not)" % form7_not_immediate)
	ok(form6_not_exact == 0, "every Form 6 Sequence clue is an exact gap in notes (%d not)" % form6_not_exact)
	ok(rank_wording == 0, "the old rank-space wording never appears in a repeating melody (%d)" % rank_wording)

	print("\n=== the variety is real ===")
	for key in ["shape_immediately", "shape_exactly", "shape_atleast", "shape_within", "pos", "neg",
			"left_any", "left_specific", "right_any", "right_specific", "dir_before", "dir_after", "only_wording"]:
		ok(int(tally.get(key, 0)) > 0, "drawn at least once: %s (%d)" % [key, int(tally.get(key, 0))])

	print("\n=== the judge is not vacuous ===")
	var gj = _beginner_puzzle(0, 11)
	var sample: Dictionary = {}
	for i in 600:
		gj._rendered_terms = {}
		var c: Dictionary = gj._build_form(26, {})
		if not c.is_empty() and str(c["text"]).contains(" is exactly ") and str(c["text"]).contains(" notes after "):
			sample = c
			break
	ok(not sample.is_empty(), "found a sample clue to tamper with")
	if not sample.is_empty():
		ok(_judge(gj, sample, {}) == "", "the untouched sample passes")
		var bad_fact: Dictionary = sample.duplicate(true)
		(bad_fact["value_facts"] as Array)[0]["spec"]["dir"] = -int((sample["value_facts"] as Array)[0]["spec"]["dir"])
		ok(_judge(gj, bad_fact, {}) != "", "reversing the direction in the fact is caught")
		var bad_table: Dictionary = sample.duplicate(true)
		(bad_table["solver_facts"] as Array).append({"kind": "ordinal_pair_set", "a": 0, "b": 1, "pairs": [[0, 1]]})
		ok(_judge(gj, bad_table, {}) != "", "a rank table that does not belong is caught")
		var bad_dir: Dictionary = sample.duplicate(true)
		bad_dir["text"] = str(sample["text"]).replace(" notes after ", " notes before ")
		ok(_judge(gj, bad_dir, {}) != "", "flipping 'after' to 'before' is caught")
		var bad_n: Dictionary = sample.duplicate(true)
		var m_n = RegEx.create_from_string("exactly (\\d+) notes").search(str(sample["text"]))
		ok(m_n != null, "the sample states an exact gap")
		if m_n:
			bad_n["text"] = str(sample["text"]).replace("exactly %s notes" % m_n.get_string(1), "exactly %d notes" % (int(m_n.get_string(1)) + 1))
			ok(_judge(gj, bad_n, {}) != "", "changing the gap by one note is caught")

	print("\n=== the solver carries the table ===")
	var checked_pins: int = 0
	var wrong_prop: int = 0
	var wrong_fc: int = 0
	# Only a relation between two FIRST firings carries a table now, so most
	# draws are skipped; Form 6 (two specific firings) supplies them fastest.
	for i in 6000:
		gj._rendered_terms = {}
		var c2: Dictionary = gj._build_form(6 if i % 2 == 0 else 26, {})
		if c2.is_empty():
			continue
		var f2: Dictionary = {}
		for sf in (c2["solver_facts"] as Array):
			if str((sf as Dictionary).get("kind", "")) == "ordinal_pair_set":
				f2 = sf
		if f2.is_empty():
			continue
		var ra: int = int(gj.sequence_rank_solution[int(f2["a"])])
		var partners: Array = []
		for pr in f2["pairs"]:
			if int(pr[0]) == ra:
				partners.append(int(pr[1]))
		partners.sort()
		var facts: Array[Dictionary] = [{"kind": "ordinal_exact", "s": int(f2["a"]), "r": ra}, f2]
		var prop: Dictionary = gj._propagate_only(facts)
		var open_b: Array = []
		for r in gj.star_count:
			if bool(prop["possible"][int(f2["b"])][r]):
				open_b.append(r)
		if not bool(prop["consistent"]) or open_b != partners:
			wrong_prop += 1
		var domains: Array = []
		for s in gj.star_count:
			var dom: Array = []
			for r in gj.star_count:
				dom.append(r)
			domains.append(dom)
		var adj: Array[Dictionary] = [gj._pair_clue_runtime(f2)]
		var nd = gj._forward_check(int(f2["a"]), ra, domains, [], adj)
		var fc_b: Array = []
		if nd != null:
			for v in nd[int(f2["b"])]:
				fc_b.append(int(v))
		fc_b.sort()
		if nd == null or fc_b != partners:
			wrong_fc += 1
		checked_pins += 1
		if checked_pins >= 60:
			break
	ok(checked_pins >= 15, "checked the solver on %d tables" % checked_pins)
	ok(wrong_prop == 0, "propagation with one star pinned leaves exactly the partner ranks the table allows (%d wrong)" % wrong_prop)
	ok(wrong_fc == 0, "forward checking restricts the other star to the same partners (%d wrong)" % wrong_fc)

	print("\n=== a real Beginner puzzle that uses them still passes the ship gate ===")
	var shipped: int = 0
	var shipped_bad: Array = []
	for seed2 in [11, 12, 13]:
		var gp = _beginner_puzzle(0, seed2)
		gp.prune_enabled = false
		await gp.generate_clues_forms()
		ok(gp.gate_passed, "seed %d: Sequence, Name closure and repeat notes all proven with note relations in the pool" % seed2)
		for cl in gp.chosen_form_clues:
			var sf2: Array = []
			var vf2: Array = []
			for d in (cl["disclosures"] as Array):
				if str((d as Dictionary)["kind"]) == "firing_relation":
					vf2.append(d)
				else:
					sf2.append(d)
			if vf2.is_empty():
				continue
			shipped += 1
			var as_clue: Dictionary = {"text": cl["text"], "chars": cl["chars"], "grid_updates": cl["cells"],
				"solver_facts": sf2, "value_facts": vf2}
			var why2: String = _judge(gp, as_clue, {}, true)
			if why2 != "":
				shipped_bad.append(why2)
	ok(shipped > 0, "the generator ships note-relation clues (%d across the runs)" % shipped)
	ok(shipped_bad.is_empty(), "every shipped one judges clean from its stored form (%d bad) %s" % [shipped_bad.size(), str(shipped_bad.slice(0, 3))])

	print("\n=== the player-side engine scores the table ===")
	var host = await _host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var fact: Dictionary = {"kind": "ordinal_pair_set", "a": 0, "b": 1, "pairs": [[0, 1], [0, 3]]}
	d._star_positions_cache = {}
	ok(not d._disclosure_satisfied(fact), "an empty board does not satisfy it")
	d._load_match_records([{"star_idx": 0, "seq_lo": 1, "seq_hi": 1}, {"star_idx": 1, "seq_lo": 2, "seq_hi": 2}])
	d._star_positions_cache = {}
	ok(d._disclosure_satisfied(fact), "both stars pinned onto an allowed pair satisfies it")
	d._load_match_records([{"star_idx": 0, "seq_lo": 1, "seq_hi": 1}, {"star_idx": 1, "seq_lo": 3, "seq_hi": 3}])
	d._star_positions_cache = {}
	ok(not d._disclosure_satisfied(fact), "a pair off the table does not")
	var wide: Dictionary = {"kind": "ordinal_pair_set", "a": 0, "b": 1, "pairs": [[0, 1], [0, 2], [0, 3]]}
	# Named, so the record is the player's own confirmed star rather than an
	# auto-created widget stub (a stub identifies no star until it has a name or pin).
	d._load_match_records([{"star_idx": 0, "seq_lo": 1, "seq_hi": 1}, {"star_idx": 1, "name": "Beta", "seq_lo": 2, "seq_hi": 4}])
	d._star_positions_cache = {}
	ok(d._player_positions_for_star(1) == [2, 3, 4], "fixture: the named record leaves positions 2 to 4 open (got %s)" % str(d._player_positions_for_star(1)))
	ok(d._disclosure_satisfied(wide), "positions still open (2 to 4) but all on the table count as satisfied")
	ok(not d._disclosure_satisfied(fact), "the same open positions are NOT satisfied by a table missing one of them")
	ok(d.SCOREABLE_DISCLOSURE_KINDS.has("ordinal_pair_set"), "it counts toward a clue's coverage")
	ok(d._describe_disclosure(fact).begins_with("The firings of Alpha and Beta"), "the dev explainer names both stars (got '%s')" % d._describe_disclosure(fact))
	host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
