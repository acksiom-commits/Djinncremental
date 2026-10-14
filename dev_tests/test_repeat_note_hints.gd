extends "res://dev_tests/test_base.gd"
# Three things added 2026-10-11, all about the repeat notes of a Beginner melody.
#
#  1. THE VERB IS COUNTED. "first fires" says the star repeats, the plain verb
#     says it fires once; that is intended information, so every clue now
#     carries it as a repeat_count_range fact the repeat-note gate reads.
#     Checked here: each such fact is TRUE, it agrees with the wording of its
#     own sentence, and with the old public-shape switch on none is emitted.
#  2. HINTS FOR PLACING REPEAT NOTES. A step says a note must / cannot be a
#     star firing again. Checked on hand-built boards (exact steps and
#     sentences), and for SOUNDNESS on real puzzles: starting from a board that
#     knows every star's position and nothing about the repeat notes, every
#     step in the chain is compared with the real melody. The comparison is
#     shown to fail on a wrong step.
#  3. NOTES PLACED BOUND THE REPEATS MARKS. Placing a note on a star rules out
#     the repeat counts that no longer fit, and letting it go takes that back.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner_puzzle(cid: int, seed: int, earned: bool = true):
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
	g.repeats_earned = earned
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	return [g, cd, cid]


func _small_host(melody: Array):
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
	# SEAM ONLY since 2026-10-12: the hint finder is switched OFF in the game on
	# a repeating melody (its steps reason about firing-order positions, which
	# the player is no longer told). This file keeps checking the finder as
	# the seam leaves it, until it is re-based on who fires on each note.
	host._deduction.notes_hidden_enabled = false
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


## A host carrying a generated puzzle's public data, with no player records.
func _host_for(g, cd, cid: int):
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = cid
	host._star_count = g.star_count
	host._star_names = g.star_names.duplicate()
	host._star_colors = g.star_colors.duplicate()
	host._star_degrees = g.star_degrees.duplicate()
	host._pitch_freqs = cd.get_note_freqs(cid)
	host._star_pitch_index = g.star_pitch_index.duplicate()
	host._sequence_rank_solution = g.sequence_rank_solution.duplicate()
	host._melody_seq_pos_sequence = g.melody_seq_pos_sequence.duplicate()
	host._deduction.notes_hidden_enabled = false   # seam; see _host above
	host._melody_star_sequence = g.melody_star_sequence.duplicate()
	host._repeat_count = g.repeat_count.duplicate()
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _truth_seq_grid(ranks: Array) -> Array:
	var n: int = ranks.size()
	var grid: Array = []
	for s in n:
		var row: Array = []
		for r in n:
			row.append(r == int(ranks[s]))
		grid.append(row)
	return grid


## How many claims of a note step contradict the real melody.
func _step_lies(step: Dictionary, melody: Array) -> int:
	var lies: int = 0
	for t in step["must_ticks"]:
		if int(melody[int(t) - 1]) != int(step["star"]):
			lies += 1
	for t2 in step["cannot_ticks"]:
		if int(melody[int(t2) - 1]) == int(step["star"]):
			lies += 1
	return lies


## "" when a Count / Extreme sentence's group wording fits how often its
## connected stars really repeat (`counts`), else what is wrong with it.
func _group_verb_problem(text: String, kind: String, counts: Array) -> String:
	var any_repeat: bool = false
	var any_once: bool = false
	for c in counts:
		if int(c) > 0:
			any_repeat = true
		else:
			any_once = true
	if any_repeat and any_once:
		return "built over a group where some stars repeat and some do not"
	var says_first: bool
	if kind == "ordinal_count_before":
		says_first = text.contains("connected stars first fire before")
		if not says_first and not text.contains("connected stars fire before"):
			return "unrecognised Count wording"
	else:
		says_first = text.contains("going by each star's first note")
	if says_first != any_repeat:
		return "says %s of a group that %s" % ["'first'" if says_first else "the plain verb",
			"all repeat" if any_repeat else "never repeats"]
	return ""


func run() -> void:
	print("=== 1. the verb is counted, and only says what the sentence says ===")
	var verb_facts: int = 0
	var verb_false: int = 0
	var wording_mismatch: Array = []
	var clues_with_verb: int = 0
	var shipped: Array = []
	for cid in [0, 2]:
		var made: Array = _beginner_puzzle(cid, 11)
		var g = made[0]
		await g.generate_clues_forms()
		ok(g.gate_passed, "c%d: passes the ship gate with the verb counted" % cid)
		shipped.append(made)
		for cl in g.chosen_form_clues:
			var says_repeats: int = 0
			var here: int = 0
			for d in (cl["disclosures"] as Array):
				if not (d is Dictionary) or not bool((d as Dictionary).get("from_verb", false)):
					continue
				here += 1
				verb_facts += 1
				var real: int = int(g.repeat_count[int(d["star"])])
				var claims_repeat: bool = int(d["lo"]) >= 1
				if claims_repeat != (real >= 1) or (not claims_repeat and int(d["hi"]) != 0):
					verb_false += 1
				if claims_repeat:
					says_repeats += 1
			if here > 0:
				clues_with_verb += 1
			var text: String = str(cl["text"])
			# Wording that presupposes a star firing more than once: the "first"
			# forms, and (2026-10-12) a Firing Relation's "one of the firings of"
			# / "the first|last|second firing of" -- a star that fires once reads
			# "the only firing of" there instead. (2026-10-14: a sentence may now open
			# with it -- "The second firing of X is..." -- hence either capital.)
			var plural_firing: bool = text.contains("firings of") \
				or RegEx.create_from_string("[Tt]he (first|last|second|third|fourth|fifth|sixth) firing of").search(text) != null
			var has_first: bool = text.contains("first fire") or text.contains("first-firing") or text.contains("first note") or plural_firing
			if says_repeats > 0 and not has_first:
				wording_mismatch.append("credited 'repeats' with no 'first' wording: %s" % text)
		var pins: int = 0
		for cl2 in g.chosen_form_clues:
			if RegEx.create_from_string(" fires on note \\d+\\.$").search(str(cl2["text"])):
				pins += 1
		print("    c%d: %d clues, %d repeat notes, %d pins shipped" % [cid, g.chosen_form_clues.size(), g._repeat_ticks().size(), pins])
	print("    %d verb facts on %d clues" % [verb_facts, clues_with_verb])
	ok(verb_facts >= 10, "the shipped puzzles carry verb facts to check (%d)" % verb_facts)
	ok(verb_false == 0, "every one is true of the real melody (%d false)" % verb_false)
	ok(wording_mismatch.is_empty(), "none credits 'repeats' to a sentence without 'first' wording (%d) %s" % [wording_mismatch.size(), str(wording_mismatch.slice(0, 2))])
	var pub: Array = _beginner_puzzle(0, 11, false)
	await pub[0].generate_clues_forms()
	var pub_verbs: int = 0
	for cl3 in pub[0].chosen_form_clues:
		for d2 in (cl3["disclosures"] as Array):
			if d2 is Dictionary and bool((d2 as Dictionary).get("from_verb", false)):
				pub_verbs += 1
	ok(pub_verbs == 0, "with the old public-shape switch on, no verb fact is emitted (%d)" % pub_verbs)

	print("\n=== 1b. over a GROUP the verb is true of every member, or the clue is not built ===")
	# Reported from a live Phial puzzle 2026-10-11: "Exactly 3 of Eosyos's
	# connected stars first fire before it", where one of Eosyos's connected
	# stars fires only once. "first fire" may be said of a group only when ALL
	# of it repeats, the plain verb only when NONE does; a mixed group gets no
	# such clue. Checked on unpruned puzzles (more Count / Extreme clues), from
	# each clue's own fact (who the connected stars are) and the real melody.
	var group_clues: int = 0
	var group_bad: Array = []
	for cid2 in [4, 0, 1]:
		var gm = _beginner_puzzle(cid2, 11)[0]
		gm.prune_enabled = false
		await gm.generate_clues_forms()
		for cl4 in gm.chosen_form_clues:
			for d3 in (cl4["disclosures"] as Array):
				var kind: String = str((d3 as Dictionary).get("kind", ""))
				if kind != "ordinal_count_before" and kind != "ordinal_extreme":
					continue
				var counts: Array = []
				for nb in (d3["neighbors"] as Array):
					counts.append(int(gm.repeat_count[int(nb)]))
				group_clues += 1
				var why: String = _group_verb_problem(str(cl4["text"]), kind, counts)
				if why != "":
					group_bad.append("c%d: %s -- %s" % [cid2, why, str(cl4["text"])])
	print("    %d Count / Extreme clues checked" % group_clues)
	ok(group_clues >= 6, "enough group clues to mean something (%d)" % group_clues)
	ok(group_bad.is_empty(), "none says 'first fire' of a star that fires once, or 'fire' of one that repeats (%d bad) %s" % [group_bad.size(), str(group_bad.slice(0, 2))])
	ok(_group_verb_problem("Exactly 3 of Eosyos's connected stars first fire before it.", "ordinal_count_before", [1, 0, 5]) != "",
		"the reported sentence (connected stars repeating 1, 0 and 5 times) is flagged by this check")
	ok(_group_verb_problem("Exactly 3 of Eosyos's connected stars first fire before it.", "ordinal_count_before", [1, 2, 5]) == "",
		"and the same sentence over stars that all repeat is accepted")

	print("\n=== 2a. note steps on a hand-built board ===")
	# 4 stars, notes -> positions [1,2,2,3,4,1]: note 3 repeats Beta, note 6 Alpha.
	var host = await _small_host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var w = host._widgets
	var solver = d._hint_solver_for(4)
	var pin_clue: Dictionary = {"text": "Beta fires on note 3.", "cells": [], "search_terms": ["N:Beta"],
		"disclosures": [{"kind": "firing_position", "s": 1, "sel": {"kind": "count", "lo": 3, "hi": 3}, "lo": 1, "hi": 1}]}
	var once_clue: Dictionary = {"text": "Gamma fires earlier than Delta.", "cells": [], "search_terms": ["N:Gamma", "N:Delta"],
		"disclosures": [{"kind": "repeat_count_range", "star": 2, "lo": 0, "hi": 0, "negated": false, "from_verb": true}]}
	var ticks: Dictionary = d._player_tick_board()
	ok(ticks.keys().size() == 2 and ticks[3] == [1, 2] and ticks[6] == [1, 2, 3, 4], "the untouched board: note 3 is position 1 or 2, note 6 any of four (got %s)" % str(ticks))
	var blank: Array = []
	for s in 4:
		blank.append([true, true, true, true])
	ok(d._hint_note_steps([pin_clue], solver, blank, ticks).is_empty(), "no step while the star's own position is unknown")
	var seq: Array = _truth_seq_grid([0, 1, 2, 3])
	var steps: Array = d._hint_note_steps([pin_clue], solver, seq, ticks)
	ok(steps.size() == 1 and steps[0]["must_ticks"] == [3] and (steps[0]["cannot_ticks"] as Array).is_empty() and int(steps[0]["star"]) == 1,
		"'Beta fires on note 3' with Beta's position known: note 3 must be Beta (got %s)" % str(steps))
	if steps.size() == 1:
		ok(w._step_sentence(steps[0]) == "With what you know, note 3 must be Beta firing again.", "worded: '%s'" % w._step_sentence(steps[0]))
	var steps2: Array = d._hint_note_steps([once_clue], solver, seq, ticks)
	ok(steps2.size() == 1 and steps2[0]["cannot_ticks"] == [6] and int(steps2[0]["star"]) == 2,
		"'Gamma fires' (once): the only later note open to Gamma, note 6, cannot be Gamma (got %s)" % str(steps2))
	if steps2.size() == 1:
		ok(w._step_sentence(steps2[0]) == "With what you know, note 6 cannot be Gamma firing again.", "worded: '%s'" % w._step_sentence(steps2[0]))
		d._apply_step_to_boards(steps2[0], {"ticks": ticks})
		ok(ticks[6] == [1, 2, 4], "applying the step takes position 3 off note 6 (got %s)" % str(ticks[6]))
		ok(d._hint_note_steps([once_clue], solver, seq, ticks).is_empty(), "and the same step is not offered twice")
	var all_steps: Array = d.hint_next_steps([pin_clue], {"seq": seq, "ticks": d._player_tick_board()})
	var note_in_all: bool = false
	for st in all_steps:
		if str(st["axis"]) == "note":
			note_in_all = true
	ok(note_in_all, "hint_next_steps offers the note step alongside the other kinds")
	ok(_step_lies({"star": 1, "must_ticks": [6], "cannot_ticks": []}, [0, 1, 1, 2, 3, 0]) == 1
		and _step_lies({"star": 1, "must_ticks": [3], "cannot_ticks": []}, [0, 1, 1, 2, 3, 0]) == 0,
		"the soundness check below does flag a wrong step and pass a right one")

	print("\n=== 2c. the reverse link: the player's own Repeats mark settles a note ===")
	ok(d._hint_note_steps([], solver, seq, d._player_tick_board()).is_empty(), "no marks, no clue: no step")
	d._load_match_records([{"name": "Gamma", "seq_lo": 3, "seq_hi": 3, "repeat_states": {0: 1}}])
	d._full_propagation_refresh()
	var rsteps: Array = d._hint_note_steps([], solver, seq, d._player_tick_board())
	ok(rsteps.size() == 1 and rsteps[0]["cannot_ticks"] == [6] and int(rsteps[0]["clue_index"]) == -1 and str(rsteps[0]["descriptor"]) == "Gamma",
		"Gamma marked 'never repeats': note 6, the only one open to it, cannot be Gamma (got %s)" % str(rsteps))
	d._load_match_records([{"name": "Delta", "seq_lo": 4, "seq_hi": 4, "repeat_states": {1: 1, 0: 2}}])
	d._full_propagation_refresh()
	rsteps = d._hint_note_steps([], solver, seq, d._player_tick_board())
	ok(rsteps.size() == 1 and rsteps[0]["must_ticks"] == [6] and bool(rsteps[0]["resolved"]),
		"Delta marked 'repeats once' with one note open to it: note 6 must be Delta (got %s)" % str(rsteps))
	if rsteps.size() == 1:
		ok(w._step_sentence(rsteps[0]) == "With what you know, note 6 must be Delta firing again.", "worded: '%s'" % w._step_sentence(rsteps[0]))
	d._load_match_records([{"name": "Beta", "seq_lo": 2, "seq_hi": 2, "repeat_states": {1: 1}}])
	d._full_propagation_refresh()
	ok(d._hint_note_steps([], solver, seq, d._player_tick_board()).is_empty(),
		"Beta marked 'repeats once' with TWO notes open to it settles neither: no step")
	# A count the ENGINE derived (not the player's mark) must not drive this hint.
	d._load_match_records([{"name": "Gamma", "seq_lo": 3, "seq_hi": 3}])
	d._full_propagation_refresh()
	ok(not d._repeat_marks_say_something(d._player_repeat_marks_for_rank(3)), "a record with no Repeats mark of the player's own says nothing")
	# The mark also narrows a CLUE's step: 'Beta fires on note 3' plus 'Beta
	# repeats once' leaves note 6 unable to be Beta.
	d._load_match_records([{"name": "Beta", "seq_lo": 2, "seq_hi": 2, "repeat_states": {1: 1}}])
	d._full_propagation_refresh()
	var csteps: Array = d._hint_note_steps([pin_clue], solver, seq, d._player_tick_board())
	var both: bool = false
	for cs in csteps:
		if int(cs["clue_index"]) == 0 and cs["must_ticks"] == [3] and cs["cannot_ticks"] == [6]:
			both = true
	ok(both, "with the mark, the pin clue's step also rules note 6 out for Beta (got %s)" % str(csteps))
	d._load_match_records([])
	d._full_propagation_refresh()

	print("\n=== 3. notes placed bound the Repeats marks ===")
	var beta: int = d._get_or_create_match_record_for_name("Beta")
	d.record_at(beta)["seq_lo"] = 2
	d.record_at(beta)["seq_hi"] = 2
	d._full_propagation_refresh()
	var buckets: Array = d._get_repeat_bucket_values()
	print("    repeat buckets on this board: %s" % str(buckets))
	ok(buckets.has(0) and buckets.has(1), "the board offers repeat counts 0 and 1")
	ok(d._effective_repeat_state(beta, 0) == 0, "before any note is placed, 'Beta never repeats' is still open")
	await w._on_staff_identity_select(3, 2)
	beta = d._get_or_create_match_record_for_name("Beta")
	ok(d._seq_pos_for_melody_tick(3) == 2, "note 3 placed on Beta's position")
	ok(d._effective_repeat_state(beta, 0) == 2, "now 'Beta never repeats' is ruled out (state %d)" % d._effective_repeat_state(beta, 0))
	# Only the counts that occur are offered (author, 2026-10-11: Listen shows
	# every star's count, so a count no star has must not be a button). Here
	# that is 0 and 1, the engine's domain is the same list, and so with 0
	# ruled out the one count left on screen is confirmed.
	ok(d._repeat_values_shown() == [0, 1] and d._repeat_count_domain() == [0, 1],
		"the counts shown, and the engine's domain, are the ones that occur: 0 and 1 (got %s / %s)" % [str(d._repeat_values_shown()), str(d._repeat_count_domain())])
	ok(d._effective_repeat_state(beta, 1) == 1, "with 'never' ruled out, the only count left on screen, 'once', is confirmed (state %d)" % d._effective_repeat_state(beta, 1))
	var too_many: bool = true
	for bv in buckets:
		if int(bv) > 2 and d._effective_repeat_state(beta, int(bv)) != 2:
			too_many = false   # only notes 3 and 6 could be Beta's
	ok(too_many, "and any count above the two notes that could be Beta's is ruled out")
	w._on_staff_identity_undo(3)
	beta = d._get_or_create_match_record_for_name("Beta")
	ok(d._effective_repeat_state(beta, 0) == 0, "letting the note go takes that back (state %d)" % d._effective_repeat_state(beta, 0))
	host.queue_free()
	await process_frame

	print("\n=== 4. a count clue is a NAME deduction once the stars are Listened ===")
	# "Alpha is one of the stars that repeat once." True counts: stars 0 and 1
	# repeat once, stars 2 and 3 never. Listen gives each star's count, so
	# marking 'repeats once' on Alpha's row must leave only stars 0 and 1 for it.
	var hn = await _small_host([1, 2, 2, 3, 4, 1])
	var dn = hn._deduction
	var alpha: int = dn._get_or_create_match_record_for_name("Alpha")
	dn._propagate_repeat_confirmed_same_record(alpha, 1)
	dn._full_propagation_refresh()
	alpha = dn._get_or_create_match_record_for_name("Alpha")
	ok(dn._candidate_stars_for_record(alpha).size() == 4, "before any Listen the mark rules no star out for Alpha (%s)" % str(dn._candidate_stars_for_record(alpha)))
	await hn._on_pitch_listen_star_clicked(2)
	alpha = dn._get_or_create_match_record_for_name("Alpha")
	ok(dn._candidate_stars_for_record(alpha) == [0, 1, 3], "Listening to star 2 (never repeats) rules it out for Alpha (%s)" % str(dn._candidate_stars_for_record(alpha)))
	for s_l in [0, 1, 3]:
		await hn._on_pitch_listen_star_clicked(s_l)
	alpha = dn._get_or_create_match_record_for_name("Alpha")
	ok(dn._candidate_stars_for_record(alpha) == [0, 1], "with every star Listened, Alpha can only be a star that repeats once (%s)" % str(dn._candidate_stars_for_record(alpha)))
	var gamma_n: int = dn._get_or_create_match_record_for_name("Gamma")
	dn._full_propagation_refresh()
	ok(dn._candidate_stars_for_record(dn._get_or_create_match_record_for_name("Gamma")).size() == 4, "a name with no Repeats mark keeps every star (record %d)" % gamma_n)
	hn.queue_free()
	await process_frame

	print("\n=== 2b. soundness of note steps on real puzzles ===")
	var total_steps: int = 0
	var total_lies: int = 0
	for made2 in shipped:
		var g2 = made2[0]
		var h2 = await _host_for(g2, made2[1], int(made2[2]))
		var d2 = h2._deduction
		var solver2 = d2._hint_solver_for(g2.star_count)
		var clues: Array = g2.chosen_form_clues
		var seq2: Array = _truth_seq_grid(g2.sequence_rank_solution)
		var ticks2: Dictionary = d2._player_tick_board()
		var open_before: int = 0
		for t in ticks2:
			if (ticks2[t] as Array).size() > 1:
				open_before += 1
		var chain: int = 0
		for _i in 200:
			var found: Array = d2._hint_note_steps(clues, solver2, seq2, ticks2)
			if found.is_empty():
				break
			for st2 in found:
				total_lies += _step_lies(st2, g2.melody_star_sequence)
			total_steps += found.size()
			d2._apply_step_to_boards(found[0], {"ticks": ticks2})
			chain += 1
		var settled: int = 0
		var wrong: int = 0
		for t2 in ticks2:
			var cands: Array = ticks2[t2]
			var true_rank: int = int(g2.sequence_rank_solution[int(g2.melody_star_sequence[int(t2) - 1])]) + 1
			if not cands.has(true_rank):
				wrong += 1
			if cands.size() == 1:
				settled += 1
		print("    c%d: %d repeat notes open; a chain of %d single-clue steps settles %d of them" % [int(made2[2]), open_before, chain, settled])
		ok(wrong == 0, "c%d: the true star is never ruled out for any note" % int(made2[2]))
		ok(chain > 0, "c%d: at least one note step is found from positions alone" % int(made2[2]))
		h2.queue_free()
		await process_frame
	ok(total_steps >= 5, "enough steps examined to mean something (%d)" % total_steps)
	ok(total_lies == 0, "no step contradicts the real melody (%d claims wrong)" % total_lies)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
