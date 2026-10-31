extends "res://dev_tests/test_base.gd"
# No two star names in one puzzle are easy to mistake for each other (author,
# 2026-10-31). Reported on The Phial: Keraeara entered where the clue said
# Keryara, the board's only contradiction.
#
#  - Every prefix goes round once before any repeats, so a board shares a
#    prefix only when it has more stars than the theme has prefixes.
#  - Any two names are at least MIN_NAME_DISTANCE edits apart.
#  - Every pool is still full, unique, deterministic, and a Beginner board's
#    names are the first names of that constellation's Hard board.
#  - A theme too small for the rule still returns its names, and never hangs.
#
# Every built-in constellation on both layouts: names are seeded by
# constellation_id alone, so no other seed can give a different pool.

const Namer = preload("res://constellation_star_namer.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _prefix_of(nm: String, prefixes: Array) -> String:
	var best: String = ""
	for p in prefixes:
		if nm.begins_with(str(p)) and str(p).length() > best.length():
			best = str(p)
	return best


func run() -> void:
	await process_frame
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc

	var pools: int = 0
	var pairs: int = 0
	var close: Array = []
	var prefix_excess: Array = []
	var bad_pool: Array = []
	var not_subset: Array = []
	for cid in range(7):
		var beginner: Array = []
		for diff in ["easy", "hard"]:
			gc.constellation_difficulty[cid] = diff
			var def: Dictionary = cd.get_constellation_def(cid)
			var n: int = int(def.get("star_count", 0))
			if n <= 0:
				continue
			var theme: Dictionary = def.get("name_theme", {})
			var prefixes: Array = theme.get("prefixes", Namer.DEFAULT_THEME["prefixes"])
			var names: Array = Array(Namer.generate_names(n, cid, theme))
			pools += 1
			var uniq: Dictionary = {}
			for nm in names:
				uniq[nm] = true
				if str(nm).begins_with("Star-"):
					bad_pool.append("c%d %s fell back to %s" % [cid, str(diff), str(nm)])
			if names.size() != n or uniq.size() != n:
				bad_pool.append("c%d %s: %d names, %d unique, %d stars" % [cid, str(diff), names.size(), uniq.size(), n])
			if names != Array(Namer.generate_names(n, cid, theme)):
				bad_pool.append("c%d %s is not deterministic" % [cid, str(diff)])
			var shared: int = 0
			for i in names.size():
				for j in range(i + 1, names.size()):
					pairs += 1
					if Namer._edit_distance(str(names[i]), str(names[j])) < Namer.MIN_NAME_DISTANCE:
						close.append("c%d %s/%s" % [cid, str(names[i]), str(names[j])])
					if _prefix_of(str(names[i]), prefixes) == _prefix_of(str(names[j]), prefixes):
						shared += 1
			# One extra pair per star beyond the prefix count, no more: that is
			# what "least used first" gives.
			var allowed: int = maxi(0, n - prefixes.size())
			if shared != allowed:
				prefix_excess.append("c%d %s: %d stars, %d shared-prefix pairs, want %d" % [cid, str(diff), n, shared, allowed])
			if str(diff) == "easy":
				beginner = names
			elif names.size() >= beginner.size() and names.slice(0, beginner.size()) != beginner:
				not_subset.append("c%d" % cid)

	ok(pools == 14, "every constellation on both layouts judged (%d pools, %d name pairs)" % [pools, pairs])
	ok(bad_pool.is_empty(), "every pool is full, unique and deterministic (%s)" % str(bad_pool))
	ok(close.is_empty(), "no two names within %d edits (%d of %d pairs: %s)"
		% [Namer.MIN_NAME_DISTANCE - 1, close.size(), pairs, str(close)])
	ok(prefix_excess.is_empty(), "a prefix repeats only past the theme's size (%s)" % str(prefix_excess))
	ok(not_subset.is_empty(), "a Beginner board's names lead its Hard board's (%s)" % str(not_subset))

	# The reported pair and the three others that would pass one half of the rule.
	var phial: Array = Array(Namer.generate_names(6, 4, {}))
	ok(not (phial.has("Keraeara") and phial.has("Keryara")), "The Phial no longer has both Keraeara and Keryara (%s)" % str(phial))
	ok(Namer._edit_distance("Theraion", "Theryis") >= Namer.MIN_NAME_DISTANCE,
		"Theraion/Theryis passes the distance alone, so the prefix half is needed")
	ok(Namer._edit_distance("Helios", "Selion") < Namer.MIN_NAME_DISTANCE,
		"Helios/Selion passes the prefix alone, so the distance half is needed")

	print("\n=== a theme too small for the rule ===")
	var tiny: Dictionary = {"prefixes": ["Ka"], "mids": ["a"], "suffixes": ["b", "c", "d"]}
	var got: Array = Array(Namer.generate_names(3, 9, tiny))
	var uniq2: Dictionary = {}
	for nm2 in got:
		uniq2[nm2] = true
	ok(got.size() == 3 and uniq2.size() == 3, "the rule gives way rather than a name (%s)" % str(got))
	var over: Array = Array(Namer.generate_names(5, 9, tiny))
	ok(over.size() == 5 and str(over[4]).begins_with("Star-"), "past the pool it still falls back to Star-N (%s)" % str(over))

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
