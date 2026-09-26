extends "res://dev_tests/test_base.gd"
# Cheap structural validation of a cached puzzle (critical-pass review item 3).
#
# from_cache_dict() coerced every field's TYPE but accepted anything of the
# right shape, so a rank list that was not a permutation, per-star arrays of
# the wrong length, duplicate names or a clue pointing at a nonexistent star
# all "loaded successfully". validate_cache_dict() now checks those, cheaply,
# without re-proving uniqueness.
#
# TWO opposite failure modes are tested, because either is expensive:
#   - a FALSE REJECTION silently regenerates a player's puzzle and wipes their
#     notes, so every real cache must pass -- including after the JSON
#     round-trip a save goes through, which turns every int into a float;
#   - a MISSED corruption defeats the point, so each invariant is broken on
#     purpose, one at a time, from a known-good control, and must be caught.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const RootUiScript = preload("res://root_ui.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _roundtrip(d: Dictionary) -> Dictionary:
	# What a save/load does: JSON turns every int into a float.
	return JSON.parse_string(JSON.stringify(d))


## `mutate` corrupts a deep copy of `good`; the result must be rejected with a
## reason containing `expect`, while the untouched control still passes.
func _reject(good: Dictionary, label: String, expect: String, mutate: Callable) -> void:
	var bad: Dictionary = good.duplicate(true)
	mutate.call(bad)
	var reason: String = PuzzleScript.validate_cache_dict(bad)
	ok(reason != "" and reason.contains(expect),
		"%s is rejected (reason: \"%s\")" % [label, reason])


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var caches: Array = []   # [constellation_id, dict]

	print("=== no false rejections: every real cache, before AND after a JSON round-trip ===")
	for cid in range(7):
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		var g = PuzzleScript.new()
		var sq: Array = []
		for i in range(scn):
			sq.append(i)
		g.setup(scn, cdef["line_pairs"], sq, 11, cid, cdef.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		await g.generate_clues_forms()
		var raw: Dictionary = g.to_cache_dict()
		var reason_raw: String = PuzzleScript.validate_cache_dict(raw)
		var reason_rt: String = PuzzleScript.validate_cache_dict(_roundtrip(raw))
		print("    c%d: %d stars, %d clues -> direct \"%s\", after JSON \"%s\"" % [cid, scn, g.chosen_form_clues.size(), reason_raw, reason_rt])
		ok(g.gate_passed, "c%d generated a puzzle that passes its gate (else this proves nothing)" % cid)
		ok(reason_raw == "", "c%d: a freshly generated cache is valid" % cid)
		ok(reason_rt == "", "c%d: and stays valid after the JSON round-trip (ints become floats)" % cid)
		var g2 = PuzzleScript.new()
		g2.setup(scn, cdef["line_pairs"], sq, 11, cid, cdef.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		ok(g2.from_cache_dict(_roundtrip(raw)), "c%d: from_cache_dict accepts the round-tripped cache" % cid)
		caches.append([cid, raw])
	ok(caches.size() >= 3, "several constellations were checked (%d) -- otherwise this proves little" % caches.size())
	if caches.is_empty():
		finish()
		return

	# Corrupt copies of one real cache, one invariant at a time.
	var good: Dictionary = _roundtrip(caches[0][1])
	var n: int = int(good["star_count"])
	print("\n=== each invariant, broken on purpose, is caught (control: the untouched cache passes) ===")
	ok(PuzzleScript.validate_cache_dict(good) == "", "control: the unmodified cache is valid")

	_reject(good, "a stale version", "version", func(d): d["version"] = 1)
	_reject(good, "a missing version", "version", func(d): d.erase("version"))
	_reject(good, "star_count of 0", "star_count", func(d): d["star_count"] = 0)
	_reject(good, "an absurd star_count", "star_count", func(d): d["star_count"] = 500)
	_reject(good, "a string star_count", "star_count", func(d): d["star_count"] = "many")
	_reject(good, "an incomplete generation", "generation_complete", func(d): d["generation_complete"] = false)

	_reject(good, "star_colors one entry short", "star_colors", func(d): d["star_colors"].pop_back())
	_reject(good, "a colour outside the range", "colour range", func(d): d["star_colors"][0] = 9)
	_reject(good, "a negative colour", "colour range", func(d): d["star_colors"][0] = -1)
	_reject(good, "a degree beyond the star count", "star_degrees", func(d): d["star_degrees"][0] = n + 3)
	_reject(good, "star_degrees one entry long", "star_degrees", func(d): d["star_degrees"].append(0))

	_reject(good, "a repeated star name", "repeats", func(d): d["star_names"][1] = d["star_names"][0])
	_reject(good, "an empty star name", "empty", func(d): d["star_names"][0] = "  ")
	_reject(good, "a numeric star name", "non-string", func(d): d["star_names"][0] = 7)
	_reject(good, "star_names one short", "star_names", func(d): d["star_names"].pop_back())

	_reject(good, "a repeated rank (not a permutation)", "permutation", func(d): d["pitch_rank_solution"][1] = d["pitch_rank_solution"][0])
	_reject(good, "a rank beyond the star count", "pitch_rank_solution", func(d): d["pitch_rank_solution"][0] = n)
	_reject(good, "a rank list one short", "pitch_rank_solution", func(d): d["pitch_rank_solution"].pop_back())

	_reject(good, "pitch_count of 0", "pitch_count", func(d): d["pitch_count"] = 0)
	_reject(good, "pitch_freq_rank of the wrong length", "pitch_freq_rank", func(d): d["pitch_freq_rank"].append(0))
	_reject(good, "a pitch rank out of range", "pitch_freq_rank", func(d): d["pitch_freq_rank"][0] = 999)

	_reject(good, "no clues at all", "chosen_form_clues", func(d): d["chosen_form_clues"] = [])
	_reject(good, "clues that are not an array", "chosen_form_clues", func(d): d["chosen_form_clues"] = "nope")
	_reject(good, "a clue that is not a dictionary", "not a dictionary", func(d): d["chosen_form_clues"][0] = 5)
	_reject(good, "an unknown Form id", "form_id", func(d): d["chosen_form_clues"][0]["form_id"] = 99)
	_reject(good, "a clue with empty text", "text", func(d): d["chosen_form_clues"][0]["text"] = "")
	_reject(good, "a chars entry pointing at a missing star", "chars entry", func(d):
		var ch: Array = d["chosen_form_clues"][0]["chars"]
		ch[0]["star"] = n + 5)
	_reject(good, "a chars entry with a bad category", "category", func(d):
		var ch: Array = d["chosen_form_clues"][0]["chars"]
		ch[0]["cat"] = 42)
	_reject(good, "a disclosure with no kind", "no kind", func(d): d["chosen_form_clues"][0]["disclosures"].append({"s": 1}))

	# A cell-carrying clue, since not every clue has cells.
	var cell_clue: int = -1
	for i in (good["chosen_form_clues"] as Array).size():
		if not ((good["chosen_form_clues"][i]["cells"]) as Array).is_empty():
			cell_clue = i
			break
	ok(cell_clue >= 0, "the real cache has a clue with cells to corrupt (else the next two checks are vacuous)")
	if cell_clue >= 0:
		_reject(good, "a cells entry pointing at a missing star", "cells entry", func(d): d["chosen_form_clues"][cell_clue]["cells"][0]["star_a"] = n + 5)
		_reject(good, "a cells entry with a non-bijective category", "non-bijective", func(d): d["chosen_form_clues"][cell_clue]["cells"][0]["cat_a"] = 4)

	print("\n=== a rejected cache leaves the puzzle untouched ===")
	var cdef0: Dictionary = cd.get_constellation_def(int(caches[0][0]))
	var g3 = PuzzleScript.new()
	var sq3: Array = []
	for i in range(int(cdef0["star_count"])):
		sq3.append(i)
	g3.setup(int(cdef0["star_count"]), cdef0["line_pairs"], sq3, 11, int(caches[0][0]), cdef0.get("name_theme", {}),
		cd.get_note_assignment(int(caches[0][0])), cd.get_note_freqs(int(caches[0][0])), null)
	var names_before: Array = g3.star_names.duplicate()
	var ranks_before: Array = g3.sequence_rank_solution.duplicate()
	var bad: Dictionary = good.duplicate(true)
	bad["pitch_rank_solution"][1] = bad["pitch_rank_solution"][0]
	ok(not g3.from_cache_dict(bad), "from_cache_dict rejects a corrupt cache")
	ok(g3.star_names == names_before and g3.sequence_rank_solution == ranks_before and g3.chosen_form_clues.is_empty(),
		"and did not half-overwrite the puzzle it was called on (validation runs BEFORE any field is assigned)")

	print("\n=== root_ui: discard a corrupt cache, keep a merely stale one ===")
	ok(RootUiScript._invalid_cache_reason(good) == "", "a valid cache is kept")
	var stale: Dictionary = good.duplicate(true)
	stale["version"] = 1
	ok(RootUiScript._invalid_cache_reason(stale) == "",
		"a stale-VERSION cache is kept (still a playable puzzle; regeneration can be refused)")
	var corrupt: Dictionary = good.duplicate(true)
	corrupt["pitch_rank_solution"][1] = corrupt["pitch_rank_solution"][0]
	ok(RootUiScript._invalid_cache_reason(corrupt) != "", "a corrupt cache is discarded")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
