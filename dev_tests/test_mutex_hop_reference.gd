extends "res://dev_tests/test_base.gd"
# A Mutual Exclusion that names "every star N hops from <Ref>" (2026-10-20,
# author) reads as <Ref> being none of its other elements. Drawn on six Beginner
# maps: <Ref> is never inside another element (before: in a colour group in 171
# of 953 hop draws), and every Colour/Pitch element beside a hop carries the
# fact "<Ref> is not in that group", so the hints and the proof read it too.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const Cat = preload("res://constellation_logic_puzzle.gd").Category


var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var draws: int = 0
	var with_hop: int = 0
	var bad: int = 0
	var shown: int = 0
	var ref_facts_seen: int = 0
	var ref_groups: int = 0
	for cid in [0, 1, 2, 3, 4, 5]:
		for seed in [11, 23, 37]:
			var cd = load("res://constellation_data.gd").new()
			var gc = load("res://game_context.gd").new()
			cd._game_context = gc
			gc.constellation_difficulty[cid] = "easy"
			cd.player_seed = seed
			var def: Dictionary = cd.get_constellation_def(cid)
			var eng = load("res://click_sequence_puzzle_engine.gd").new()
			eng.set_constellation(cid, cd, gc)
			var g = PuzzleScript.new()
			g.difficulty = "easy"
			g.setup(int(def["star_count"]), def["line_pairs"], eng.get_correct_star_sequence(cid), seed, cid, def.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
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
				var chars: Array = r["chars"]
				var ref: int = -1
				for ch in chars:
					if int(ch["cat"]) == Cat.DISTANCE:
						ref = int(ch["ref"])
				var cats: Array = []
				for ch0 in chars:
					cats.append(int(ch0["cat"]))
				if shown < 2 and cats.has(Cat.NAME) and cats.has(Cat.SEQUENCE):
					var kinds: Array = []
					for f in (r["solver_facts"] as Array) + (r["value_facts"] as Array):
						kinds.append(str(f["kind"]))
					print("PROBE  facts of: %s\nPROBE     -> %s" % [r["text"], str(kinds)])
					shown += 1
				if ref < 0:
					continue
				with_hop += 1
				for ch2 in chars:
					var c: int = int(ch2["cat"])
					var s: int = int(ch2["star"])
					var hit: bool = false
					match c:
						Cat.NAME, Cat.SEQUENCE:
							hit = s == ref
						Cat.COLOR:
							hit = g.star_colors[s] == g.star_colors[ref]
						Cat.PITCH:
							hit = g._freq_for_star(s) == g._freq_for_star(ref)
					if hit:
						bad += 1
					if c == Cat.COLOR or c == Cat.PITCH:
						ref_groups += 1
				for f2 in (r["value_facts"] as Array):
					if str(f2["kind"]) == "descriptor_not_in_group" and int(f2["cat"]) == Cat.NAME and int(f2["star"]) == ref:
						ref_facts_seen += 1
	print("    %d draws, %d with a hop, %d with the reference inside another element; reference-vs-group facts %d for %d group elements beside a hop" % [
		draws, with_hop, bad, ref_facts_seen, ref_groups])
	ok(with_hop >= 200, "enough hop draws to judge (%d)" % with_hop)
	ok(ref_groups >= 100, "enough Colour/Pitch elements beside a hop to judge (%d)" % ref_groups)
	ok(bad == 0, "the hop's reference is never inside another element (%d)" % bad)
	ok(ref_facts_seen == ref_groups, "every Colour/Pitch element beside a hop says the reference is not in it (%d of %d)" % [ref_facts_seen, ref_groups])
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
