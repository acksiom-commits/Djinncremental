extends "res://dev_tests/test_base.gd"
# THE NOTE PROOF WITH THE FIRST NOTES HIDDEN (author ruling 2026-10-12).
#
# The player is never told which notes are a star's first firing, so the
# generator may not assume it: the unknown is simply who fires on each note.
# _solve_note_owners searches that. This file checks it from outside, on
# melodies small enough to enumerate EVERY assignment of stars to notes.
#
#  1. THE VERDICT IS RIGHT. Every assignment that gives each star the number of
#     notes it really fires (that count is given by Listen) is enumerated here
#     and tested against the shipped clues with this file's OWN reading of each
#     fact. Exactly one must survive, and it must be the real melody.
#  2. THE SOLVER AGREES WITH THE BRUTE FORCE IN BOTH DIRECTIONS. Each clue is
#     removed in turn; solver and brute force must report the same number of
#     answers (capped at 3) every time, and "more than one" has to occur.
#  3. HIDING THE FIRST NOTES IS A STRICTER PROOF. The older proof, which takes
#     the first notes as given (the seam), must call some clue set unique that
#     the brute force shows is not -- otherwise this file would not be testing
#     the thing that changed.
#
# What a fact means is this file's reading of the SENTENCE, written out below;
# the generator's header above _solve_note_owners states the same table.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## A small repeating melody on a ring of stars. Small on purpose: 5 stars and
## 8 notes is 5040 assignments, 6 stars and 9 notes 45360.
func _small_puzzle(melody: Array, star_count: int, seed: int):
	var cd = load("res://constellation_data.gd").new()
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(0)
	var lines: Array = []
	for i in star_count:
		lines.append([i, (i + 1) % star_count])
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	# This file checks the NOTE proof, with names read as their real stars (its
	# brute force does the same). The joint name-and-note proof is checked
	# against an independent reader in test_joint_name_note_proof.gd.
	g.names_honoured = false
	g.setup(star_count, lines, melody, seed, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	return g


# ── this file's own reading of every fact ────────────────────────────────

func _fp_value(ticks: Array, sel: Dictionary) -> int:
	var kind: String = str(sel["kind"])
	if kind == "count":
		var c: int = 0
		for t in ticks:
			if int(t) >= int(sel["lo"]) and int(t) <= int(sel["hi"]):
				c += 1
		return c
	if kind == "nth":
		var k: int = ticks.size() if int(sel["k"]) == -1 else int(sel["k"])
		return int(ticks[k - 1]) if k >= 1 and k <= ticks.size() else -1
	var i: int = int(sel["i"])
	var j: int = ticks.size() if int(sel["j"]) == -1 else int(sel["j"])
	if i < 1 or j > ticks.size() or i >= j:
		return -1
	return int(ticks[j - 1]) - int(ticks[i - 1])


func _pick(ticks: Array, pick: Dictionary) -> Array:
	match str(pick["kind"]):
		"any":
			return ticks
		"first":
			return [ticks[0]]
		"last":
			return [ticks[ticks.size() - 1]]
	var k: int = int(pick["k"])
	return [ticks[k - 1]] if k >= 1 and k <= ticks.size() else []


## A star a clue names only by a note label ("the star that first fires on note
## 5") is whoever owns that note in the assignment being tried (2026-10-14):
## the fact's "label_refs" says which fields, and which note.
func _resolve_label_refs(fd: Dictionary, notes: Array) -> Dictionary:
	if not (fd.get("label_refs", {}) as Dictionary).is_empty():
		var out: Dictionary = fd.duplicate()
		for field in fd["label_refs"]:
			for s in notes.size():
				if (notes[s] as Array).has(int(fd["label_refs"][field])):
					out[field] = s
		return out
	return fd


## `notes[s]` = the notes star s fires on in the assignment being tried
## (ascending). `label` = the note number a Sequence label prints for a rank.
func _fact_ok(fd_in: Dictionary, notes: Array, label: Array) -> bool:
	var fd: Dictionary = _resolve_label_refs(fd_in, notes)
	match str(fd.get("kind", "")):
		# A label names a star by its FIRST note (2026-10-14): "the star that
		# first fires on note T", or "fires T-th note" for a star that fires once.
		"ordinal_exact":      # "s is the star that first fires on note T"
			return int(notes[int(fd["s"])][0]) == int(label[int(fd["r"])])
		"ordinal_neg":        # "s is not the star that first fires on note T"
			return int(notes[int(fd["s"])][0]) != int(label[int(fd["r"])])
		"ordinal_either_or":
			var f_e: int = int(notes[int(fd["s"])][0])
			return f_e == int(label[int(fd["r1"])]) or f_e == int(label[int(fd["r2"])])
		"ordinal_range":      # "first fires within the first T notes" / "no earlier than note T"
			var f0: int = int((notes[int(fd["s"])] as Array)[0])
			if int(fd["lo"]) > 0 and f0 < int(label[int(fd["lo"])]):
				return false
			if int(fd["hi"]) < notes.size() - 1 and f0 > int(label[int(fd["hi"])]):
				return false
			return true
		"ordinal_cmp":        # "a first fires after / before b"
			return (int(notes[int(fd["a"])][0]) > int(notes[int(fd["b"])][0])) == bool(fd["a_gt_b"])
		"ordinal_chain":
			return int(notes[int(fd["a"])][0]) < int(notes[int(fd["mid"])][0]) \
				and int(notes[int(fd["mid"])][0]) < int(notes[int(fd["b"])][0])
		"ordinal_extreme":
			for nb in fd["neighbors"]:
				var earlier: bool = int(notes[int(fd["s"])][0]) < int(notes[int(nb)][0])
				if earlier != bool(fd["want_lowest"]):
					return false
			return true
		"ordinal_count_before":
			var before: int = 0
			for nb2 in fd["neighbors"]:
				if int(notes[int(nb2)][0]) < int(notes[int(fd["s"])][0]):
					before += 1
			return before == int(fd["k"])
		"firing_position":
			var v: int = _fp_value(notes[int(fd["s"])], fd["sel"])
			return v >= 0 and v >= int(fd["lo"]) and v <= int(fd["hi"])
		"firing_relation":
			var na: Array = _pick(notes[int(fd["a"])], fd["pick_a"])
			var nb3: Array = _pick(notes[int(fd["b"])], fd["pick_b"])
			if na.is_empty() or nb3.is_empty():
				return false
			var spec: Dictionary = fd["spec"]
			var found: bool = false
			for ta in na:
				for tb in nb3:
					var d: int = int(ta) - int(tb)
					if str(spec["rel"]) == "exact":
						found = found or int(spec["dir"]) * d == int(spec["n"])
					elif str(spec["rel"]) == "atleast":
						found = found or int(spec["dir"]) * d >= int(spec["n"])
					else:
						found = found or absi(d) <= int(spec["n"])
			return found != bool(spec["neg"])
		"repeat_count_range":
			var n: int = (notes[int(fd["star"])] as Array).size() - 1
			return (n >= int(fd["lo"]) and n <= int(fd["hi"])) != bool(fd.get("negated", false))
	return true


## The kinds _fact_ok reads, and the ones it deliberately does not.
const READ_KINDS: Array = ["ordinal_exact", "ordinal_neg", "ordinal_either_or", "ordinal_range", "ordinal_cmp",
	"ordinal_chain", "ordinal_extreme", "ordinal_count_before", "firing_position", "firing_relation", "repeat_count_range"]


func _facts_of(clues: Array) -> Array:
	var out: Array = []
	for cl in clues:
		for d in (cl["disclosures"] as Array):
			if d is Dictionary:
				out.append(d)
	return out


var _enumerated: int = 0


## Every assignment of a star to each note that gives star s exactly need[s]
## notes and satisfies `facts`. {"count", "kept" (up to 3)}.
func _brute(n_notes: int, need: Array, facts: Array, label: Array) -> Dictionary:
	var result: Dictionary = {"count": 0, "kept": []}
	var owners: Array = []
	var have: Array = []
	for _t in n_notes:
		owners.append(-1)
	for _s in need.size():
		have.append(0)
	_brute_step(0, owners, have, need, facts, label, result)
	return result


func _brute_step(i: int, owners: Array, have: Array, need: Array, facts: Array, label: Array, result: Dictionary) -> void:
	if i == owners.size():
		_enumerated += 1
		var notes: Array = []
		for _s in need.size():
			notes.append([])
		for t in owners.size():
			(notes[int(owners[t])] as Array).append(t + 1)
		for f in facts:
			if not _fact_ok(f, notes, label):
				return
		result["count"] = int(result["count"]) + 1
		if (result["kept"] as Array).size() < 3:
			(result["kept"] as Array).append(owners.duplicate())
		return
	for s in need.size():
		if int(have[s]) < int(need[s]):
			have[s] = int(have[s]) + 1
			owners[i] = s
			_brute_step(i + 1, owners, have, need, facts, label, result)
			have[s] = int(have[s]) - 1


func run() -> void:
	var compared: int = 0
	var agree: int = 0
	var seen_not_unique: int = 0
	var seam_too_generous: int = 0
	var label_seam_too_generous: int = 0
	var label_ref_facts: int = 0
	var kinds_seen: Dictionary = {}
	var unread: Dictionary = {}
	var cases: Array = [
		{"melody": [0, 1, 0, 2, 3, 1, 4, 2], "stars": 5, "seed": 11},
		{"melody": [0, 1, 0, 2, 3, 1, 4, 2], "stars": 5, "seed": 12},
		{"melody": [3, 0, 3, 3, 1, 4, 0, 2], "stars": 5, "seed": 13},
		{"melody": [0, 1, 2, 0, 3, 1, 4, 5, 2], "stars": 6, "seed": 14},
	]
	for case in cases:
		var melody: Array = case["melody"]
		print("=== %d stars, melody %s, seed %d ===" % [int(case["stars"]), str(melody), int(case["seed"])])
		var g = _small_puzzle(melody, int(case["stars"]), int(case["seed"]))
		await g.generate_clues_forms()
		ok(g.gate_passed, "the puzzle passes the ship gate")
		ok(g._first_notes_hidden(), "its first notes are hidden")
		var need: Array = []
		var label: Array = []
		var seen: Dictionary = {}
		for s in g.star_count:
			need.append(0)
		for t in melody.size():
			need[int(melody[t])] = int(need[int(melody[t])]) + 1
			if not seen.has(int(melody[t])):
				seen[int(melody[t])] = true
				label.append(t + 1)
		var facts: Array = _facts_of(g.chosen_form_clues)
		for f in facts:
			var k: String = str(f.get("kind", ""))
			kinds_seen[k] = int(kinds_seen.get(k, 0)) + 1
			if not (f.get("label_refs", {}) as Dictionary).is_empty():
				label_ref_facts += 1
			if (k.begins_with("ordinal_") and not READ_KINDS.has(k) and k != "ordinal_pair_set"):
				unread[k] = true

		# 1. the verdict
		var before: int = _enumerated
		var b: Dictionary = _brute(melody.size(), need, facts, label)
		print("    %d clues, %d facts; brute force tried %d assignments" % [g.chosen_form_clues.size(), facts.size(), _enumerated - before])
		ok(_enumerated - before >= 1000, "the brute force really enumerated (%d assignments)" % (_enumerated - before))
		ok(int(b["count"]) == 1, "exactly ONE assignment of stars to notes satisfies the shipped clues (got %d)" % int(b["count"]))
		ok(int(b["count"]) >= 1 and (b["kept"] as Array)[0] == melody, "and it is the real melody")
		var sols: Array = await g._solve_notes(g._seq_facts_from_clues(), 3)
		ok(sols.size() == 1 and not g._last_solve_inconclusive and sols[0]["owners"] == melody,
			"the generator's solver finds that same single assignment (%d found)" % sols.size())

		# 2 and 3. one clue removed at a time
		for drop in g.chosen_form_clues:
			var rest: Array = []
			var rest_seq: Array = []
			for cl in g.chosen_form_clues:
				if cl != drop:
					rest.append(cl)
			for d in _facts_of(rest):
				if not g.VALUE_FACT_KINDS.has(str(d.get("kind", ""))):
					rest_seq.append(d)
			var b_rest: Dictionary = _brute(melody.size(), need, _facts_of(rest), label)
			var s_rest: Array = await g._solve_notes(rest_seq, 3, rest)
			compared += 1
			if not g._last_solve_inconclusive and s_rest.size() == mini(3, int(b_rest["count"])):
				agree += 1
			else:
				print("    DISAGREE without '%s': brute %d, solver %d (inconclusive %s)" % [
					str(drop["text"]), int(b_rest["count"]), s_rest.size(), str(g._last_solve_inconclusive)])
			if int(b_rest["count"]) > 1:
				seen_not_unique += 1
				g.first_notes_hidden = false
				var old: Array = await g._solve_notes(rest_seq, 2, rest)
				if old.size() == 1 and not g._last_solve_inconclusive:
					seam_too_generous += 1
				g.first_notes_hidden = true
				# The proof before 2026-10-14 read a note label as the real star.
				g.label_refs_honoured = false
				var old_lab: Array = await g._solve_notes(rest_seq, 2, rest)
				if old_lab.size() == 1 and not g._last_solve_inconclusive:
					label_seam_too_generous += 1
				g.label_refs_honoured = true

	print("\n=== solver vs brute force, one clue removed at a time ===")
	print("    fact kinds in these puzzles: %s" % str(kinds_seen))
	ok(unread.is_empty(), "every ordinal fact kind in these puzzles is one this file reads (unread: %s)" % str(unread.keys()))
	ok(compared >= 30,"enough removals compared to mean something (%d)" % compared)
	ok(agree == compared, "the solver and the brute force report the same number of answers every time (%d of %d)" % [agree, compared])
	ok(seen_not_unique > 0, "'more than one answer' actually occurred (%d times), so the comparison can fail" % seen_not_unique)
	ok(seam_too_generous > 0,
		"the older proof, which takes the first notes as given, called %d of those %d non-unique clue sets unique" % [seam_too_generous, seen_not_unique])
	ok(label_ref_facts > 0, "the shipped clues name stars by a note label alone (%d facts read as 'whoever owns that note')" % label_ref_facts)
	ok(label_seam_too_generous > 0,
		"reading a note label as the real star (the proof before 2026-10-14) called %d of those %d non-unique clue sets unique" % [label_seam_too_generous, seen_not_unique])

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
