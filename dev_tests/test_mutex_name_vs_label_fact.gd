extends "res://dev_tests/test_base.gd"
# "Oraeides, the star that first fires on note 6, and every red star are all
# different stars" (2026-10-20). The Name-vs-label pair used to be stated only
# as a matrix cell, which no hint, board rule or proof reads; it now carries
# name_group_neg keyed by the label's rank, as Single Negation's "Oraeides is
# not the star that first fires on note 6" does. The same for a hop element's
# reference ("every star 2 hops from Oraeides") against a label.
#
#  1. Drawn on six Beginner maps: every Name-vs-label and reference-vs-label
#     pair carries the fact, and each fact is true. (On the code before this,
#     none did.)
#  2. The joint proof reads it as "that name's first note is not note T",
#     never as "that name is not the map star that owns note T" (the label
#     over-reading fixed 2026-10-14): it is never an identity fact, and it
#     follows whichever star the name is assigned.
#  3. Shipped Beginner puzzles carrying it: unique, and the joint proof agrees
#     with test_joint_name_note_proof's independent reader (which reads a label
#     as the owner of its note) with each clue removed in turn.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const Cat = preload("res://constellation_logic_puzzle.gd").Category

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## The Name-side stars of a distinct-set clue (Name elements and hop
## references) and its Sequence elements' stars.
func _sides(chars: Array) -> Dictionary:
	var names: Array = []
	var seqs: Array = []
	for ch in chars:
		match int(ch["cat"]):
			Cat.NAME:
				names.append(int(ch["star"]))
			Cat.SEQUENCE:
				seqs.append(int(ch["star"]))
			Cat.DISTANCE:
				names.append(int(ch["ref"]))
	return {"names": names, "seqs": seqs}


func _has_neg(facts: Array, name_star: int, rank: int) -> bool:
	for f in facts:
		if str(f.get("kind", "")) == "name_group_neg" and int(f["cat"]) == Cat.SEQUENCE \
				and int(f["name_star"]) == name_star and int(f["group_key"]) == rank:
			return true
	return false


func run() -> void:
	var R = load("res://dev_tests/test_joint_name_note_proof.gd").new()

	print("=== 1. every Name-vs-label pair of a distinct set carries the fact ===")
	var draws: int = 0
	var pairs: int = 0
	var ref_pairs: int = 0
	var found: int = 0
	var ref_found: int = 0
	var false_facts: int = 0
	var as_identity: int = 0
	var translated_ok: int = 0
	var translated: int = 0
	var shown: int = 0
	var note_checked: int = 0
	var note_ok: int = 0
	for cid in [0, 1, 2, 3, 4, 5]:
		for seed in [11, 23, 37]:
			var g = R._beginner(cid, seed)
			g._build_record_array()
			g._build_matrix()
			for _i in 200:
				g._rendered_terms = {}
				g._rendered_star_handles = {}
				g._rendered_repeat_verbs = {}
				var r: Dictionary = g._mutex_build_distinct_set()
				if r.is_empty():
					continue
				draws += 1
				var vf: Array = r["value_facts"]
				var sd: Dictionary = _sides(r["chars"])
				var refs: Array = []
				for ch in r["chars"]:
					if int(ch["cat"]) == Cat.DISTANCE:
						refs.append(int(ch["ref"]))
				for n in sd["names"]:
					for sq in sd["seqs"]:
						var rank: int = int(g.sequence_rank_solution[int(sq)])
						var is_ref: bool = refs.has(int(n))
						pairs += 1
						if is_ref:
							ref_pairs += 1
						if not _has_neg(vf, int(n), rank):
							continue
						found += 1
						if is_ref:
							ref_found += 1
						if shown < 2:
							print("    e.g. %s -> name_group_neg %s, rank %d (note %d)" % [r["text"], g.star_names[int(n)], rank, g._seq_first_tick(int(sq))])
							shown += 1
						# 2. Read through a name assignment that puts this name on
						# the very star that owns the label's note.
						var pi: Array = []
						for s in g.star_count:
							pi.append(s)
						pi[int(n)] = int(sq)
						pi[int(sq)] = int(n)
						var fact: Dictionary = {"kind": "name_group_neg", "name_star": int(n), "cat": Cat.SEQUENCE, "group_key": rank}
						var split: Dictionary = g._joint_split([{"disclosures": [fact]}])
						if not (split["ident"] as Array).is_empty():
							as_identity += 1
						var tr: Array = g._joint_translate(split["other"], pi)["seq"]
						translated += 1
						if tr.size() == 1 and str(tr[0]["kind"]) == "ordinal_neg" and int(tr[0]["s"]) == int(sq) \
								and int(tr[0]["r"]) == rank and not (tr[0] as Dictionary).has("label_refs"):
							translated_ok += 1
						# The note search under that assignment: it still has
						# answers (read as "not that map star" it would have
						# none), and in each the star does not begin on note T.
						if note_checked < 40:
							note_checked += 1
							var t_lbl: int = int(g._seq_first_tick(int(sq)))
							var sols0: Array = await g._solve_note_owners(tr, 2, [], [])
							var good: bool = sols0.size() == 2 and not g._last_solve_inconclusive
							for sol in sols0:
								if (sol["owners"] as Array).find(int(sq)) == t_lbl - 1:
									good = false
							if good:
								note_ok += 1
				for f in vf:
					if str(f.get("kind", "")) == "name_group_neg" and g._validate_name_group_fact(f) != "":
						false_facts += 1
	print("    %d draws; %d Name-vs-label pairs (%d via a hop reference); fact on %d (%d)" % [draws, pairs, ref_pairs, found, ref_found])
	ok(pairs >= 300, "enough Name-vs-label pairs to judge (%d)" % pairs)
	ok(ref_pairs >= 50, "enough reference-vs-label pairs to judge (%d)" % ref_pairs)
	ok(found == pairs, "every Name-vs-label pair carries name_group_neg on its rank (%d of %d)" % [found, pairs])
	ok(ref_found == ref_pairs, "every reference-vs-label pair does too (%d of %d)" % [ref_found, ref_pairs])
	ok(false_facts == 0, "every name_group_neg a distinct set carries is true (%d false)" % false_facts)

	print("\n=== 2. the joint proof reads it through the label's note, not its star ===")
	ok(translated > 0, "facts read (%d)" % translated)
	ok(as_identity == 0, "never an identity fact about the label's map star (%d were)" % as_identity)
	ok(translated_ok == translated, "with the name put on the note's real owner, it reads 'that star's first note is not the label's note' (%d of %d)" % [translated_ok, translated])
	ok(note_checked >= 20 and note_ok == note_checked, "and the note search then still has answers, none beginning that star on the label's note (%d of %d)" % [note_ok, note_checked])

	print("\n=== 3. shipped Beginner puzzles carrying it: unique, and proof == independent reader ===")
	var kept: Array = []
	for pair in [[2, 23], [4, 11], [1, 23], [5, 11], [0, 11], [3, 23]]:
		if kept.size() >= 2:
			break
		var g2 = R._beginner(int(pair[0]), int(pair[1]))
		await g2.generate_clues_forms()
		var tag: String = "c%d s%d" % [int(pair[0]), int(pair[1])]
		var carries: int = 0
		for cl in g2.chosen_form_clues:
			if str(cl.get("form_name", "")) != "Mutual Exclusion":
				continue
			var sd2: Dictionary = _sides(cl.get("chars", []))
			for n2 in sd2["names"]:
				for sq2 in sd2["seqs"]:
					if _has_neg(cl["disclosures"], int(n2), int(g2.sequence_rank_solution[int(sq2)])):
						carries += 1
		print("    %s: %d Name-vs-label facts from Mutual Exclusion clues" % [tag, carries])
		if carries == 0:
			continue
		ok(g2.gate_passed, "%s: passes the ship gate" % tag)
		R.g = g2
		R.lbl_of_rank = g2._first_fire_ticks()
		var rc: Dictionary = R._reader_count(g2.chosen_form_clues, 2)
		ok(int(rc["count"]) == 1 and not bool(rc["inconclusive"]), "%s: the independent reader finds exactly one answer (%d)" % [tag, int(rc["count"])])
		kept.append(g2)
	ok(kept.size() >= 1, "puzzles carrying the fact found (%d)" % kept.size())

	var compared: int = 0
	var agree: int = 0
	var seen_not_unique: int = 0
	for g3 in kept:
		R.g = g3
		R.lbl_of_rank = g3._first_fire_ticks()
		var all_clues: Array = g3.chosen_form_clues.duplicate()
		for drop in all_clues:
			var rest: Array = []
			var rest_seq: Array = []
			for cl3 in all_clues:
				if cl3 != drop:
					rest.append(cl3)
			for cl4 in rest:
				for d in cl4["disclosures"]:
					if d is Dictionary and not g3.VALUE_FACT_KINDS.has(str(d.get("kind", ""))):
						rest_seq.append(d)
			var rc2: Dictionary = R._reader_count(rest, 2)
			var sols: Array = await g3._solve_notes(rest_seq, 2, rest)
			var gen_inconclusive: bool = g3._last_solve_inconclusive
			compared += 1
			if not gen_inconclusive and not bool(rc2["inconclusive"]) and sols.size() == int(rc2["count"]):
				agree += 1
			else:
				print("    DISAGREE without '%s': reader %d, joint proof %d%s" % [str(drop["text"]), int(rc2["count"]), sols.size(),
					" (inconclusive)" if gen_inconclusive or bool(rc2["inconclusive"]) else ""])
			if int(rc2["count"]) > 1:
				seen_not_unique += 1
	ok(compared >= 15, "enough removals compared (%d)" % compared)
	ok(agree == compared, "the joint proof and the independent reader count the same answers every time (%d of %d)" % [agree, compared])
	ok(seen_not_unique > 0, "'more than one answer' occurred (%d times), so the comparison can fail" % seen_not_unique)

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
