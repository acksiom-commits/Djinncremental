extends "res://dev_tests/test_base.gd"
# Form 25, Firing Position: clues about WHEN a star fires in a repeating melody.
#
# The Form is generated from a SELECTOR (the note of its k-th firing / how many
# firings fall in a window / the gap between two firings) and a PREDICATE (an
# interval on that number).
#
# REWRITTEN 2026-10-10 (repeats are earned). Until then every sentence was
# reduced to the set of Sequence RANKS whose stars satisfy it, read off a public
# note -> star table, and this file judged that set. Which star a repeat note
# belongs to is no longer given, so that reduction is gone: the clue now carries
# a firing_position fact that the repeat-note gate reads, and nothing for the
# Sequence solver or the Name closure beyond what its own label discloses.
# What must hold:
#
#  - It exists only on a repeating melody. A 1:1 melody (every hard-mode
#    constellation) never offers it, builds nothing from it and draws NO random
#    numbers for it, so every hard-mode seed is unchanged.
#  - Every clue is TRUE of its subject, and the gate reads its fact exactly as a
#    reader reads the SENTENCE: the judge below parses the English, and for the
#    sets of repeat notes the subject could have it compares the sentence's
#    verdict with the gate's. It shares no helper with the builder and is itself
#    shown to FAIL on a tampered fact, sentence and cell.
#  - It can be false of the subject for SOME choice of repeat notes (otherwise
#    it is readable off the public first notes and says nothing).
#  - It carries no rank set (value_in_set / name_rank_set): those need every
#    star's notes.
#  - Real generated Beginner puzzles still pass the ship gate, repeat notes
#    included, pruned and unpruned.
#  - The player-side engine still reads a rank set when handed one.

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


# ── the independent judge: English -> predicate -> set of ranks, melody only ──

func _ticks_of(melody: Array, star: int) -> Array:
	var t: Array = []
	for i in melody.size():
		if int(melody[i]) == star:
			t.append(i + 1)
	return t


func _times_to_int(w: String) -> int:
	if w == "once":
		return 1
	if w == "twice":
		return 2
	return int(w.split(" ")[0])


## "on note 5" / "within the first 9 notes" / "from note 9 onwards" /
## "from note 5 to note 11" -> [lo, hi] in notes, [] if it is none of those.
func _window(w: String, n: int) -> Array:
	var m = RegEx.create_from_string("^on note (\\d+)$").search(w)
	if m:
		return [int(m.get_string(1)), int(m.get_string(1))]
	m = RegEx.create_from_string("^within the first (\\d+) notes$").search(w)
	if m:
		return [1, int(m.get_string(1))]
	m = RegEx.create_from_string("^from note (\\d+) onwards$").search(w)
	if m:
		return [int(m.get_string(1)), n]
	m = RegEx.create_from_string("^from note (\\d+) to note (\\d+)$").search(w)
	if m:
		return [int(m.get_string(1)), int(m.get_string(2))]
	return []


## Parse one Firing Position sentence into {kind, shape, value: Callable(ticks)->int
## (-1 undefined), lo, hi}. {} when it is not one of the generator's shapes.
func _parse(text: String, n: int) -> Dictionary:
	var m = RegEx.create_from_string("^(.+) fires for the (\\w+) time (.+)\\.$").search(text)
	if m and ORDS.has(m.get_string(2)):
		var win: Array = _window(m.get_string(3), n)
		if win.is_empty():
			return {}
		var k: int = int(ORDS[m.get_string(2)])
		var shape: String = "exact" if win[0] == win[1] else ("prefix" if win[0] == 1 else ("suffix" if win[1] == n else "interval"))
		var nth_fn: Callable = func(t: Array) -> int:
			var kk: int = t.size() if k == -1 else k
			if kk >= 1 and kk <= t.size():
				return int(t[kk - 1])
			return -1
		return {"kind": "nth", "shape": shape, "last": k == -1, "lo": win[0], "hi": win[1], "value": nth_fn,
			"label": m.get_string(1)}
	m = RegEx.create_from_string("^The (\\w+) and (\\w+) times (.+) fires are (.+) apart\\.$").search(text)
	if m and ORDS.has(m.get_string(1)) and ORDS.has(m.get_string(2)):
		var i: int = int(ORDS[m.get_string(1)])
		var j: int = int(ORDS[m.get_string(2)])
		var gap: String = m.get_string(4)
		var lo2: int = 0
		var hi2: int = 99999
		var shape2: String = ""
		var g1 = RegEx.create_from_string("^exactly (\\d+) notes?$").search(gap)
		var g2 = RegEx.create_from_string("^at least (\\d+) notes?$").search(gap)
		var g3 = RegEx.create_from_string("^at most (\\d+) notes?$").search(gap)
		var g4 = RegEx.create_from_string("^between (\\d+) and (\\d+) notes$").search(gap)
		if g1:
			lo2 = int(g1.get_string(1))
			hi2 = lo2
			shape2 = "exactly"
		elif g2:
			lo2 = int(g2.get_string(1))
			shape2 = "atleast"
		elif g3:
			hi2 = int(g3.get_string(1))
			shape2 = "atmost"
		elif g4:
			lo2 = int(g4.get_string(1))
			hi2 = int(g4.get_string(2))
			shape2 = "between"
		else:
			return {}
		var span_fn: Callable = func(t: Array) -> int:
			var jj: int = t.size() if j == -1 else j
			if i < 1 or jj > t.size() or i >= jj:
				return -1
			return int(t[jj - 1]) - int(t[i - 1])
		return {"kind": "span", "shape": shape2, "last": j == -1, "lo": lo2, "hi": hi2, "value": span_fn,
			"label": m.get_string(3)}
	# count family: the window comes last
	var counted: Array = [
		["^(.+) does not fire (.+)\\.$", "zero"],
		["^(.+) fires exactly (once|twice|\\d+ times) (.+)\\.$", "exactly"],
		["^(.+) fires at least (once|twice|\\d+ times) (.+)\\.$", "atleast"],
		["^(.+) fires at most (once|twice|\\d+ times) (.+)\\.$", "atmost"],
		["^(.+) fires between (\\d+) and (\\d+) times (.+)\\.$", "between"],
		# The repair pin: one note can only be fired once, so no "exactly once".
		["^(.+) fires (on note \\d+)\\.$", "pin"],
	]
	for pat in counted:
		var cm = RegEx.create_from_string(str(pat[0])).search(text)
		if not cm:
			continue
		var shape3: String = str(pat[1])
		var lo3: int = 0
		var hi3: int = 99999
		var wtext: String = ""
		if shape3 == "zero":
			hi3 = 0
			wtext = cm.get_string(2)
		elif shape3 == "pin":
			lo3 = 1
			hi3 = 1
			wtext = cm.get_string(2)
		elif shape3 == "exactly":
			lo3 = _times_to_int(cm.get_string(2))
			hi3 = lo3
			wtext = cm.get_string(3)
		elif shape3 == "atleast":
			lo3 = _times_to_int(cm.get_string(2))
			wtext = cm.get_string(3)
		elif shape3 == "atmost":
			hi3 = _times_to_int(cm.get_string(2))
			wtext = cm.get_string(3)
		else:
			lo3 = int(cm.get_string(2))
			hi3 = int(cm.get_string(3))
			wtext = cm.get_string(4)
		var win3: Array = _window(wtext, n)
		if win3.is_empty():
			return {}
		var wlo: int = int(win3[0])
		var whi: int = int(win3[1])
		var count_fn: Callable = func(t: Array) -> int:
			var c: int = 0
			for x in t:
				if int(x) >= wlo and int(x) <= whi:
					c += 1
			return c
		return {"kind": "count", "shape": shape3, "last": false, "lo": lo3, "hi": hi3, "value": count_fn,
			"label": cm.get_string(1)}
	return {}


## "" when the clue is sound, else why not. Reads the sentence and the melody;
## the fact and the cells are only compared against what that gives.
func _judge(g, clue: Dictionary, tally: Dictionary, stored: bool = false) -> String:
	var n: int = g.melody_star_sequence.size()
	var p: Dictionary = _parse(str(clue["text"]), n)
	if p.is_empty():
		return "unparseable sentence: %s" % str(clue["text"])
	var melody: Array = g.melody_star_sequence
	var facts: Array = []
	for f in (clue.get("value_facts", []) as Array):
		if str((f as Dictionary).get("kind", "")) == "firing_position":
			facts.append(f)
	if facts.size() != 1:
		return "expected exactly one firing_position fact, got %d" % facts.size()
	for f2 in (clue["solver_facts"] as Array) + (clue.get("value_facts", []) as Array):
		var k: String = str((f2 as Dictionary).get("kind", ""))
		if k == "value_in_set" or k == "name_rank_set" or k == "ordinal_pair_set":
			return "carries a %s: a rank set needs every star's notes, which are hidden" % k
	var fact: Dictionary = facts[0]
	var subject: int = int(fact["s"])
	var true_ticks: Array = _ticks_of(melody, subject)
	if not _holds(p, true_ticks):
		return "the sentence is false of its own subject: %s" % str(clue["text"])
	# Every set of repeat notes the subject COULD have: its first note plus any
	# of the repeat notes after it. The sentence is checked on all of them for
	# "can it be false"; the gate's reading is compared on up to ~256 of them.
	var rticks: Array = _repeat_ticks_of(melody)
	var first: int = int(true_ticks[0])
	var later_bits: Array = []   # indices into rticks
	for i in rticks.size():
		if int(rticks[i]) > first:
			later_bits.append(i)
	var total: int = 1 << later_bits.size()
	@warning_ignore("integer_division")
	var step: int = maxi(1, total / 256)
	var falsifiable: bool = false
	var m: int = 0
	while m < total:
		var ticks: Array = [first]
		var gmask: int = 0
		for j in later_bits.size():
			if m & (1 << j):
				ticks.append(int(rticks[int(later_bits[j])]))
				gmask |= 1 << int(later_bits[j])
		var want: bool = _holds(p, ticks)
		if not want:
			falsifiable = true
		if m % step == 0:
			_gate_compares += 1
			if g._repeat_mask_satisfies(subject, rticks, gmask, [fact]) != want:
				return "the gate reads the fact as %s but the sentence is %s for notes %s: %s" % [str(not want), str(want), str(ticks), str(clue["text"])]
		m += 1
	if not falsifiable:
		return "cannot be false whatever the subject's repeat notes are: %s" % str(clue["text"])
	# The cell: one true cell on the Repeat axis (bookkeeping, not a rank claim).
	# A STORED clue has none: the cache keeps no Repeat-axis cells.
	var cells: Array = clue["grid_updates"]
	if cells.size() != (0 if stored else 1):
		return "expected %d cell(s), got %d" % [0 if stored else 1, cells.size()]
	for cell in cells:
		if not bool((cell as Dictionary)["is_true"]) or int(cell["cat_b"]) != PuzzleScript.Category.REPEAT:
			return "expected a true Repeat-axis cell"
	# The label: a Sequence descriptor discloses the subject's rank, nothing else does.
	var id_cat: int = int((clue["chars"] as Array)[0]["cat"])
	var exacts: Array = []
	for f3 in (clue["solver_facts"] as Array):
		if str((f3 as Dictionary).get("kind", "")) == "ordinal_exact":
			exacts.append(f3)
		else:
			return "an unexpected Sequence fact (%s)" % str((f3 as Dictionary).get("kind", ""))
	if id_cat == PuzzleScript.Category.SEQUENCE:
		if exacts.size() != 1 or int(exacts[0]["s"]) != subject or int(exacts[0]["r"]) != int(g.sequence_rank_solution[subject]):
			return "a Sequence label should disclose exactly the subject's rank"
	elif not exacts.is_empty():
		return "a non-Sequence label should disclose no rank"
	tally["kind_" + str(p["kind"])] = int(tally.get("kind_" + str(p["kind"]), 0)) + 1
	tally["shape_" + str(p["kind"]) + "_" + str(p["shape"])] = int(tally.get("shape_" + str(p["kind"]) + "_" + str(p["shape"]), 0)) + 1
	if bool(p["last"]):
		tally["last"] = int(tally.get("last", 0)) + 1
	if id_cat == PuzzleScript.Category.NAME:
		tally["name_subject"] = int(tally.get("name_subject", 0)) + 1
	if id_cat == PuzzleScript.Category.SEQUENCE:
		tally["seq_subject"] = int(tally.get("seq_subject", 0)) + 1
	return ""


## How many (clue, note set) pairs the gate's reading was compared on: the
## denominator behind "none disagreed".
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


func _holds(p: Dictionary, ticks: Array) -> bool:
	var v: int = int(p["value"].call(ticks))
	return v >= 0 and v >= int(p["lo"]) and v <= int(p["hi"])


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
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func run() -> void:
	var h = _hard_puzzle(0, 11)

	print("=== it exists only on a repeating melody ===")
	var g0 = _beginner_puzzle(0, 11)
	ok(g0._firing_position_available(), "The Archon Beginner offers it (%d notes, %d stars)" % [g0.melody_star_sequence.size(), g0.star_count])
	ok(not h._firing_position_available(), "The Archon hard mode (1:1 melody) does not")
	ok(g0._forms_in_tier(2).has(25), "Beginner's tier-2 pool contains Form 25")
	var hard_pool: Array = []
	for t in [1, 2, 3]:
		hard_pool.append_array(h._forms_in_tier(t))
	ok(not hard_pool.has(25), "hard mode's Form pool does not contain it, so the seeded draw is unchanged")
	ok(h._forms_in_tier(2) == [5, 7, 12, 15, 16, 17, 19, 21, 22, 23], "hard mode's tier-2 pool is exactly the pre-existing list (%s)" % str(h._forms_in_tier(2)))
	var st_before = h._rng.state
	var hard_try: Dictionary = h._build_form(25, {})
	ok(hard_try.is_empty() and h._rng.state == st_before, "building it on a 1:1 melody makes nothing and draws no random numbers")

	print("\n=== every clue is true and means exactly what its sentence says ===")
	var tally: Dictionary = {}
	var built: int = 0
	var judged_bad: Array = []
	var active_cids: Array = []
	for cid in range(0, 7):
		for seed in [11, 12, 13]:
			var g = _beginner_puzzle(cid, seed)
			if not g._firing_position_available():
				continue
			if not active_cids.has(cid):
				active_cids.append(cid)
			if g._repeat_ticks() != _repeat_ticks_of(g.melody_star_sequence):
				judged_bad.append("c%d s%d: the generator's repeat notes are not the melody's" % [cid, seed])
			# 150 draws, down from 400: the judge now walks note sets per clue.
			for i in 150:
				g._rendered_terms = {}
				var clue: Dictionary = g._build_form(25, {})
				if clue.is_empty():
					continue
				built += 1
				var why: String = _judge(g, clue, tally)
				if why != "":
					judged_bad.append("c%d s%d: %s" % [cid, seed, why])
	print("    constellations with a repeating melody: %s; clues built: %d; gate comparisons: %d" % [str(active_cids), built, _gate_compares])
	print("    tally: %s" % str(tally))
	ok(_gate_compares > built, "the gate's reading was compared on more note sets than there are clues (%d)" % _gate_compares)
	ok(built > 500, "plenty of clues to judge (%d), so 'none are wrong' means something" % built)
	var judged_ok: int = int(tally.get("kind_nth", 0)) + int(tally.get("kind_count", 0)) + int(tally.get("kind_span", 0))
	ok(judged_ok == built, "every clue built was parsed and judged (%d of %d) -- none skipped as unparseable" % [judged_ok, built])
	ok(judged_bad.is_empty(), "no clue is false or disagrees with its own facts (%d bad) %s" % [judged_bad.size(), str(judged_bad.slice(0, 3))])
	ok(active_cids.size() >= 2, "more than one constellation exercised (%d)" % active_cids.size())

	print("\n=== the variety is real, not one shape repeated ===")
	for key in ["kind_nth", "kind_count", "kind_span", "last", "name_subject", "seq_subject",
			"shape_nth_exact", "shape_nth_prefix", "shape_nth_suffix", "shape_nth_interval",
			"shape_count_zero", "shape_count_exactly", "shape_count_atleast", "shape_count_atmost", "shape_count_between",
			"shape_span_exactly", "shape_span_atleast", "shape_span_atmost", "shape_span_between"]:
		ok(int(tally.get(key, 0)) > 0, "drawn at least once: %s (%d)" % [key, int(tally.get(key, 0))])

	print("\n=== the judge is not vacuous: it FAILS on a tampered fact, sentence and cell ===")
	var gj = _beginner_puzzle(0, 11)
	var sample: Dictionary = {}
	for i in 400:
		gj._rendered_terms = {}
		var c: Dictionary = gj._build_form(25, {})
		if not c.is_empty() and str(c["text"]).contains(" fires at least "):
			sample = c
			break
	ok(not sample.is_empty(), "found a sample clue to tamper with")
	if not sample.is_empty():
		ok(_judge(gj, sample, {}) == "", "the untouched sample passes")
		var bad_fact: Dictionary = sample.duplicate(true)
		(bad_fact["value_facts"] as Array)[0]["lo"] = 0
		ok(_judge(gj, bad_fact, {}) != "", "widening the fact to 'at least 0 times' is caught")
		var bad_text: Dictionary = sample.duplicate(true)
		bad_text["text"] = str(sample["text"]).replace(" at least ", " at most ")
		ok(_judge(gj, bad_text, {}) != "", "flipping 'at least' to 'at most' in the sentence is caught")
		var bad_cells: Dictionary = sample.duplicate(true)
		(bad_cells["grid_updates"] as Array)[0]["is_true"] = false
		ok(_judge(gj, bad_cells, {}) != "", "a false cell is caught")
		var bad_rank: Dictionary = sample.duplicate(true)
		(bad_rank["solver_facts"] as Array).append({"kind": "value_in_set", "s": 0, "allowed": [0, 1]})
		ok(_judge(gj, bad_rank, {}) != "", "a rank set smuggled back in is caught")

	print("\n=== a real Beginner puzzle that uses them still passes the ship gate ===")
	var shipped_total: int = 0
	var shipped_bad: Array = []
	for seed2 in [11, 12]:
		var gp = _beginner_puzzle(0, seed2)
		gp.prune_enabled = false
		await gp.generate_clues_forms()
		ok(gp.gate_passed, "seed %d: Sequence, Name closure and repeat notes all proven with Form 25 in the pool" % seed2)
		var here: int = 0
		for cl in gp.chosen_form_clues:
			if int(cl["form_id"]) != 25:
				continue
			here += 1
			var as_clue: Dictionary = {"text": cl["text"], "chars": cl["chars"], "grid_updates": [],
				"solver_facts": [], "value_facts": []}
			# Re-judge from what actually shipped: the disclosures hold both halves.
			var sf: Array = []
			var vf: Array = []
			for d in (cl["disclosures"] as Array):
				if str((d as Dictionary)["kind"]) == "ordinal_exact":
					sf.append(d)
				else:
					vf.append(d)
			as_clue["solver_facts"] = sf
			as_clue["value_facts"] = vf
			var cells_out: Array = []
			for cell in (cl["cells"] as Array):
				cells_out.append(cell)
			as_clue["grid_updates"] = cells_out
			var why2: String = _judge(gp, as_clue, {}, true)
			if why2 != "":
				shipped_bad.append(why2)
		shipped_total += here
		print("    seed %d: %d Form-25 clues among %d" % [seed2, here, gp.chosen_form_clues.size()])
	ok(shipped_total > 0, "the generator actually ships Form 25 clues (%d across the runs)" % shipped_total)
	ok(shipped_bad.is_empty(), "every shipped Form 25 clue judges clean from its stored form (%d bad) %s" % [shipped_bad.size(), str(shipped_bad.slice(0, 3))])

	print("\n=== pruning keeps the repeat notes proven ===")
	# Firing clues used to be exempt from pruning, because under a public repeat
	# shape they were always redundant. They now carry the repeat-note gate, so
	# pruning may drop the ones it does not need and must keep the rest: every
	# pruned puzzle still has exactly one assignment of its repeat notes.
	# (test_repeat_note_gate checks that verdict against a brute force.)
	var gates_ok: int = 0
	var runs_p: int = 0
	var repeats_ok: int = 0
	var repeat_clues_shipped: int = 0
	for cidp in [0, 1, 3, 5]:
		var gpr = _beginner_puzzle(cidp, 11)
		await gpr.generate_clues_forms()
		runs_p += 1
		if gpr.gate_passed:
			gates_ok += 1
		# 2026-10-12: the proof is _solve_notes with the first notes hidden. It
		# takes each star's firing COUNT as given (Listen), which the older
		# _solve_repeat_notes did not, so that older search is no longer the
		# one a shipped puzzle has to satisfy.
		var sols: Array = gpr._solve_notes(gpr._seq_facts_from_clues(), 3)
		if sols.size() == 1 and not gpr._last_solve_inconclusive and sols[0]["owners"] == gpr.melody_star_sequence:
			repeats_ok += 1
		for cl in gpr.chosen_form_clues:
			if gpr._clue_has_repeat_fact(cl):
				repeat_clues_shipped += 1
	print("    %d pruned puzzles; %d clues about the repeat notes shipped" % [runs_p, repeat_clues_shipped])
	ok(gates_ok == runs_p, "every pruned puzzle passes the ship gate (%d of %d)" % [gates_ok, runs_p])
	ok(repeats_ok == runs_p, "and has exactly one assignment of its repeat notes (%d of %d)" % [repeats_ok, runs_p])
	ok(repeat_clues_shipped >= runs_p, "which takes clues about them to prove (%d shipped)" % repeat_clues_shipped)

	print("\n=== the player-side engine reads the set ===")
	# 4 stars, notes -> ranks [1,2,2,3,4,1]; the set {rank 0, rank 2} = 1-based 1 and 3.
	var host = await _host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var fd: Dictionary = {"kind": "name_rank_set", "name_star": 0, "allowed": [0, 2]}
	d._star_positions_cache = {}
	ok(d._stars_allowed_by_position_fact(fd).size() == 4, "on an empty board no star is ruled out (superset of the truth)")
	ok(not d._disclosure_satisfied({"kind": "value_in_set", "s": 0, "allowed": [0, 2]}), "an empty board does not satisfy the fact")
	d._load_match_records([{"star_idx": 1, "seq_lo": 2, "seq_hi": 2}, {"star_idx": 2, "seq_lo": 3, "seq_hi": 3}, {"star_idx": 0, "seq_lo": 1, "seq_hi": 1}])
	d._star_positions_cache = {}
	var allowed_now: Array = d._stars_allowed_by_position_fact(fd)
	ok(not allowed_now.has(1), "a star the player has placed at position 2 is dropped (certainly outside {1, 3})")
	ok(allowed_now.has(0) and allowed_now.has(2), "stars placed inside the set stay allowed")
	ok(allowed_now.has(3), "a star with no position knowledge stays allowed")
	ok(d._disclosure_satisfied({"kind": "value_in_set", "s": 2, "allowed": [0, 2]}), "a star pinned inside the set satisfies the fact")
	ok(not d._disclosure_satisfied({"kind": "value_in_set", "s": 1, "allowed": [0, 2]}), "a star pinned outside it does not")
	ok(d.SCOREABLE_DISCLOSURE_KINDS.has("value_in_set"), "value_in_set counts toward a clue's coverage")
	var phrase: String = d._position_fact_phrase(fd)
	ok(phrase == "a star that first fires on one of notes 1, 4", "the hint phrase names the notes the star could first fire on (got '%s')" % phrase)
	ok(d._describe_disclosure({"kind": "value_in_set", "s": 0, "allowed": [0, 2]}) == "Alpha first fires on one of notes 1, 4.", "the dev explainer words it the same way")
	ok(d._firing_set_phrase([0, 1, 2, 3, 0, 1, 2]).begins_with("has a firing pattern"), "a set too long to list says so instead of naming notes")
	host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
