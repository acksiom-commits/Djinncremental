extends "res://dev_tests/test_base.gd"
# THE JOINT NAME-AND-NOTE PROOF (_solve_joint, 2026-10-14).
#
# To the player, which map star each NAME is and who fires on each NOTE are
# both unknown; colour, pitch, map distances and (by Listen) how often each
# star fires are given. A puzzle must have exactly ONE answer for the two
# together (author: guessing or two valid endings is never acceptable).
# Measured before this proof existed: 3 of 12 Beginner puzzles had a second
# answer, one checked by hand against every clue.
#
# This file holds an INDEPENDENT reader of the clues. It shares no code with
# the generator's joint proof: it reads how a clue names each star from the
# clue's search terms and chars (not from the generator's "ents"), reads
# pitch comparisons from the sentence, and searches names and notes itself.
# A note label "the star that first fires on note T" is whoever owns note T,
# and T is that star's first note; "the star N hops from X" is resolved
# through whichever star X is.
#
#  1. Shipped Beginner puzzles: the real answer satisfies every clue as read
#     here (the reader is not wrong about the answer); with the names fixed
#     to their real stars the reader finds exactly the real melody (the
#     control); and with names unknown it finds exactly one answer.
#  2. The generator's joint proof and this reader count the same answers
#     (capped at 2) with each clue removed in turn, and "more than one"
#     occurs, so the comparison can fail.
#  3. Puzzles the proof before this one shipped (names read as their real
#     stars, names_honoured = false) include ones with a second answer,
#     and the joint proof finds it too: the thing that changed is tested.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const C = PuzzleScript.Category
const INNER_BUDGET: int = 3000000
const PI_BUDGET: int = 400000

var g
var lbl_of_rank: Array = []
var _nodes: int = 0
var _hit: bool = false
var unresolved_fields: int = 0
var link_constraints: int = 0
var unread_clues: Array = []
var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner(cid: int, seed: int):
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var p = PuzzleScript.new()
	p.difficulty = "easy"
	p.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	return p


func _lbl(x: int) -> int:
	return int(lbl_of_rank[int(g.sequence_rank_solution[x])])


## A descriptor as an entity: {"name": x} (pi[x]), {"note": T} (owner of T),
## or {"star": x} (visible).
func _ent(cat: int, x: int) -> Dictionary:
	if cat == C.NAME:
		return {"name": x}
	if cat == C.SEQUENCE:
		return {"note": _lbl(x)}
	return {"star": x}


func _fixed_group(cat: int, key: int) -> Array:
	var out: Array = []
	for s in g.star_count:
		if g._name_group_key(cat, s) == key:
			out.append(s)
	return out


## How a seq/value fact's star field is named in its clue.
func _field_ent(terms: Array, fd: Dictionary, field: String, outer: Array, chars: Array) -> Dictionary:
	var x: int = int(fd[field])
	var lr: Dictionary = fd.get("label_refs", {})
	if lr.has(field):
		return {"note": int(lr[field])}
	var named: bool = terms.has("N:%s" % str(g.star_names[x]))
	var fixed: bool = (terms.has("C:%s" % PuzzleScript.COLOR_NAMES[int(g.star_colors[x])]) and g._group_size(C.COLOR, x) <= 1) \
		or (terms.has("P:%s" % PuzzleScript.note_name_for_freq(g._freq_for_star(x))) and g._group_size(C.PITCH, x) <= 1)
	if named and fixed:
		link_constraints += 1
		outer.append({"kind": "link", "name": x, "star": x})   # the clue ties the name to the visible star
		return {"star": x}
	if named:
		return {"name": x}
	if not fixed:
		# Described as "the star N hops from <name>": the clue's chars record it.
		for ch in chars:
			if int(ch["cat"]) == C.DISTANCE and int(ch["star"]) == x and ch.has("ref"):
				return {"hop": int(ch["ref"]), "hops": int(g._distances[int(ch["ref"])][x])}
		unresolved_fields += 1
	return {"star": x}


const STAR_FIELDS := {
	"ordinal_exact": ["s"], "ordinal_neg": ["s"], "ordinal_either_or": ["s"], "ordinal_range": ["s"],
	"ordinal_extreme": ["s"], "ordinal_count_before": ["s"], "firing_position": ["s"],
	"ordinal_cmp": ["a", "b"], "ordinal_adjacent": ["a", "b"], "ordinal_offset": ["a", "b"],
	"firing_relation": ["a", "b"], "values_same": ["a", "b"], "ordinal_chain": ["a", "mid", "b"],
	"repeat_count_range": ["star"],
}


## Every clue as {inner: [facts with entity refs], outer: [constraints on pi alone]}.
func _compile_all(clues: Array) -> Dictionary:
	var inner: Array = []
	var outer: Array = []
	var notes_named: Dictionary = {}
	for cl in clues:
		var terms: Array = cl.get("search_terms", [])
		# Pitch comparisons store no facts (the generator's proofs never read
		# them); read them off the sentence. Entities: the clue's first chars,
		# in the order the sentence names them.
		var text: String = str(cl["text"])
		var chars: Array = cl.get("chars", [])
		var read_any: bool = false
		if text.contains(" is pitched "):
			# The stars it names are its first chars (stored lowest pitch first,
			# not in sentence order). A TRUE clue states their real pitch order:
			# "between" states only which is in the middle, a pitch step states
			# the exact difference in steps.
			var k: int = 3 if (text.contains(", which is pitched") or text.contains(" is pitched between ")) else 2
			var ents: Array = []
			var true_stars: Array = []
			for ch in chars.slice(0, k):
				ents.append(_ent(int(ch["cat"]), int(ch["star"])))
				true_stars.append(int(ch["star"]))
			var mode: String = "order"
			if text.contains(" is pitched between "):
				mode = "between"
			elif text.contains(" is pitched exactly "):
				mode = "step"
			var refs3: Dictionary = {}
			for i in ents.size():
				refs3["e%d" % i] = ents[i]
			inner.append({"kind": "pitch_pattern", "f": {"mode": mode, "true_stars": true_stars}, "refs": refs3})
		elif (cl["disclosures"] as Array).is_empty():
			unread_clues.append(text)
		for d0 in cl["disclosures"]:
			if not (d0 is Dictionary):
				continue
			var d: Dictionary = d0
			var k: String = str(d.get("kind", ""))
			match k:
				"name_group", "name_group_neg":
					var cat: int = int(d["cat"])
					if cat == C.SEQUENCE:
						inner.append({"kind": "ordinal_exact" if k == "name_group" else "ordinal_neg", "f": {"r": int(d["group_key"])},
							"refs": {"s": {"name": int(d["name_star"])}}})
						notes_named[int(lbl_of_rank[int(d["group_key"])])] = true
					else:
						outer.append({"kind": "in" if k == "name_group" else "out", "a": {"name": int(d["name_star"])},
							"set": _fixed_group(cat, int(d["group_key"]))})
				"descriptor_either_or":
					var a: Dictionary = _ent(int(d["cat_a"]), int(d["star_a"]))
					var o1: Dictionary = _ent(int(d["cat_b"]), int(d["s1"]))
					var o2: Dictionary = _ent(int(d["cat_b"]), int(d["s2"]))
					inner.append({"kind": "eq_any", "f": {}, "refs": {"a": a, "o1": o1, "o2": o2}})
				"descriptor_not_in_group":
					var e: Dictionary = _ent(int(d["cat"]), int(d["star"]))
					inner.append({"kind": "not_in", "f": {"set": _fixed_group(int(d["group_cat"]), int(d["group_key"]))}, "refs": {"a": e}})
				"distance_hop":
					inner.append({"kind": "dist", "f": {"hops": int(d["hops"]), "negated": bool(d.get("negated", false))},
						"refs": {"a": _ent(int(d["ref_cat"]), int(d["ref"])), "b": _ent(int(d["target_cat"]), int(d["target"]))}})
				"name_rank_range":
					inner.append({"kind": "ordinal_range", "f": {"lo": int(d["lo"]), "hi": int(d["hi"])}, "refs": {"s": {"name": int(d["name_star"])}}})
				"name_nbr_count":
					inner.append({"kind": "nbr_count", "f": {"k": int(d["k"])}, "refs": {"s": {"name": int(d["name_star"])}}})
				"name_nbr_extreme":
					inner.append({"kind": "nbr_extreme", "f": {"want_lowest": bool(d["want_lowest"])}, "refs": {"s": {"name": int(d["name_star"])}}})
				"name_same_group", "name_different_group":
					inner.append({"kind": "same_key" if k == "name_same_group" else "diff_key", "f": {"cat": int(d["cat"])},
						"refs": {"a": {"name": int(d["name_star_a"])}, "b": {"name": int(d["name_star_b"])}}})
				_:
					if not STAR_FIELDS.has(k):
						continue
					if k == "values_same" and int(d.get("cat", -1)) == C.SEQUENCE:
						continue
					var refs: Dictionary = {}
					for field in STAR_FIELDS[k]:
						refs[field] = _field_ent(terms, d, field, outer, chars)
						if refs[field].has("note"):
							notes_named[int(refs[field]["note"])] = true
					if k == "ordinal_exact" or k == "ordinal_neg":
						notes_named[int(lbl_of_rank[int(d["r"])])] = true
					if k == "ordinal_either_or":
						notes_named[int(lbl_of_rank[int(d["r1"])])] = true
						notes_named[int(lbl_of_rank[int(d["r2"])])] = true
					var ff: Dictionary = d.duplicate()
					if k == "ordinal_extreme" or k == "ordinal_count_before":
						ff["neighbors"] = d["neighbors"]
					inner.append({"kind": k, "f": ff, "refs": refs})
		for f2 in inner:
			for r in (f2["refs"] as Dictionary).values():
				if (r as Dictionary).has("note"):
					notes_named[int(r["note"])] = true
	return {"inner": inner, "outer": outer, "notes_named": notes_named}


# ── pi: which map star each name is ────────────────────────────────────────

func _ent_star(e: Dictionary, pi: Array, owners: Array) -> int:
	if e.has("name"):
		return int(pi[int(e["name"])])
	if e.has("note"):
		return int(owners[int(e["note"]) - 1]) if owners.size() >= int(e["note"]) else -1
	if e.has("hop"):
		# "the star 2 hops from X": only one star may be meant; with several
		# the reader cannot point at it, and the fact is read as no constraint.
		var from: int = int(pi[int(e["hop"])])
		if from < 0:
			return -1
		var at: Array = []
		for s in g.star_count:
			if int(g._distances[from][s]) == int(e["hops"]):
				at.append(s)
		return int(at[0]) if at.size() == 1 else -1
	return int(e["star"])


## Outer constraints whose entities are all names or visible stars.
func _outer_ok(c: Dictionary, pi: Array) -> bool:
	match str(c["kind"]):
		"link":
			return int(pi[int(c["name"])]) == int(c["star"])
		"in":
			return (c["set"] as Array).has(_ent_star(c["a"], pi, []))
		"out":
			return not (c["set"] as Array).has(_ent_star(c["a"], pi, []))
	return true


func _enum_pi(outer: Array, inner: Array, cap: int) -> Array:
	# Candidate stars per name from the unary constraints.
	var n: int = g.star_count
	var cand: Array = []
	for nm in n:
		var ok_set: Array = []
		for s in n:
			var pi_try: Array = []
			pi_try.resize(n)
			pi_try.fill(-1)
			pi_try[nm] = s
			var good: bool = true
			for c in outer:
				if int(c.get("name", c.get("a", {}).get("name", -1))) == nm and not _outer_ok(c, pi_try):
					good = false
					break
			if good:
				ok_set.append(s)
		cand.append(ok_set)
	# Inner facts about names and visible stars only (no notes) also prune pi.
	var pi_only: Array = []
	for f in inner:
		var has_note: bool = false
		for r in (f["refs"] as Dictionary).values():
			if (r as Dictionary).has("note"):
				has_note = true
		if not has_note and str(f["kind"]) in ["eq_any", "not_in", "dist", "same_key", "diff_key", "pitch_rel", "pitch_between", "pitch_pattern"]:
			pi_only.append(f)
	var out: Array = []
	var pi: Array = []
	pi.resize(n)
	pi.fill(-1)
	var used: Dictionary = {}
	_pi_dfs(0, n, cand, pi, used, pi_only, out, cap)
	return out


func _pi_dfs(i: int, n: int, cand: Array, pi: Array, used: Dictionary, pi_only: Array, out: Array, cap: int) -> void:
	if out.size() >= cap:
		return
	if i == n:
		for f in pi_only:
			if not _identity_ok(f, pi, []):
				return
		out.append(pi.duplicate())
		return
	for s in cand[i]:
		if used.has(s):
			continue
		pi[i] = s
		used[s] = true
		_pi_dfs(i + 1, n, cand, pi, used, pi_only, out, cap)
		used.erase(s)
		pi[i] = -1


## Facts that depend only on WHICH stars the entities are.
func _identity_ok(f: Dictionary, pi: Array, owners: Array) -> bool:
	var refs: Dictionary = f["refs"]
	for r0 in refs.values():
		if _ent_star(r0, pi, owners) < 0:
			return true   # not assigned yet, or a hop that names no single star
	match str(f["kind"]):
		"eq_any":
			var a: int = _ent_star(refs["a"], pi, owners)
			return a == _ent_star(refs["o1"], pi, owners) or a == _ent_star(refs["o2"], pi, owners)
		"not_in":
			return not (f["f"]["set"] as Array).has(_ent_star(refs["a"], pi, owners))
		"dist":
			var d: int = int(g._distances[_ent_star(refs["a"], pi, owners)][_ent_star(refs["b"], pi, owners)])
			return (d == int(f["f"]["hops"])) != bool(f["f"]["negated"])
		"same_key":
			return g._name_group_key(int(f["f"]["cat"]), _ent_star(refs["a"], pi, owners)) == g._name_group_key(int(f["f"]["cat"]), _ent_star(refs["b"], pi, owners))
		"diff_key":
			return g._name_group_key(int(f["f"]["cat"]), _ent_star(refs["a"], pi, owners)) != g._name_group_key(int(f["f"]["cat"]), _ent_star(refs["b"], pi, owners))
		"pitch_pattern":
			# Same relative pitch order as the real stars the clue names.
			var ts: Array = f["f"]["true_stars"]
			var now: Array = []
			for i in ts.size():
				now.append(_ent_star(refs["e%d" % i], pi, owners))
			var mode: String = str(f["f"]["mode"])
			if mode == "step":
				return _pitch_step(now[0]) - _pitch_step(now[1]) == _pitch_step(int(ts[0])) - _pitch_step(int(ts[1]))
			var tf: Array = []
			var nf: Array = []
			for i2 in ts.size():
				tf.append(g._freq_for_star(int(ts[i2])))
				nf.append(g._freq_for_star(int(now[i2])))
			if mode == "between":
				var mid: int = 0
				for i3 in 3:
					if tf[i3] > minf(minf(tf[0], tf[1]), tf[2]) and tf[i3] < maxf(maxf(tf[0], tf[1]), tf[2]):
						mid = i3
				var o1: int = (mid + 1) % 3
				var o2: int = (mid + 2) % 3
				return nf[mid] > minf(nf[o1], nf[o2]) and nf[mid] < maxf(nf[o1], nf[o2])
			for i4 in ts.size():
				for j4 in ts.size():
					if (tf[i4] < tf[j4]) != (nf[i4] < nf[j4]):
						return false
			return true
		"pitch_rel":
			var pa: float = g._freq_for_star(_ent_star(refs["a"], pi, owners))
			var pb: float = g._freq_for_star(_ent_star(refs["b"], pi, owners))
			return pa > pb if bool(f["f"]["up"]) else pa < pb
		"pitch_between":
			var px: float = g._freq_for_star(_ent_star(refs["a"], pi, owners))
			var p1: float = g._freq_for_star(_ent_star(refs["b"], pi, owners))
			var p2: float = g._freq_for_star(_ent_star(refs["c"], pi, owners))
			return px > minf(p1, p2) and px < maxf(p1, p2)
	return true


# ── O: who fires on each note, for one pi ───────────────────────────────────

func _first(notes: Array, s: int) -> int:
	return int((notes[s] as Array)[0]) if not (notes[s] as Array).is_empty() else 999


const FIRST_KINDS := ["ordinal_cmp", "ordinal_chain", "ordinal_extreme", "ordinal_count_before", "ordinal_range",
	"ordinal_exact", "ordinal_neg", "ordinal_either_or", "nbr_count", "nbr_extreme"]
const IDENTITY_KINDS := ["eq_any", "not_in", "dist", "same_key", "diff_key", "values_same", "repeat_count_range", "pitch_rel", "pitch_between", "pitch_pattern"]


## Inner fact against the assignment so far. False only when certainly broken.
func _check(f: Dictionary, pi: Array, owners: Array, notes: Array, need: Array, full: bool) -> bool:
	var refs: Dictionary = f["refs"]
	var who: Dictionary = {}
	for field in refs:
		var w: int = _ent_star(refs[field], pi, owners)
		if w < 0:
			return true
		who[field] = w
	var kind: String = str(f["kind"])
	var fd: Dictionary = f["f"]
	if IDENTITY_KINDS.has(kind):
		if kind == "values_same":
			if int(fd.get("cat", -1)) == C.REPEAT:
				return int(need[int(who["a"])]) == int(need[int(who["b"])])
			return g._name_group_key(int(fd["cat"]), int(who["a"])) == g._name_group_key(int(fd["cat"]), int(who["b"]))
		if kind == "repeat_count_range":
			var reps: int = int(need[int(who["star"])]) - 1
			return (reps >= int(fd["lo"]) and reps <= int(fd["hi"])) != bool(fd.get("negated", false))
		return _identity_ok(f, pi, owners)
	var nbrs: Array = []
	if kind == "ordinal_extreme" or kind == "ordinal_count_before":
		# "X's connected stars": the neighbours of whichever map star X is.
		nbrs = fd["neighbors"] if (refs["s"] as Dictionary).has("star") else g.proximity[int(who["s"])]
	elif kind == "nbr_count" or kind == "nbr_extreme":
		nbrs = g.proximity[int(who["s"])]
	if not full:
		if FIRST_KINDS.has(kind):
			if who.has("s"):
				if (notes[int(who["s"])] as Array).is_empty():
					return true
			else:
				var begun: int = 0
				for field2 in who:
					if not (notes[int(who[field2])] as Array).is_empty():
						begun += 1
				if begun == 0 or begun < who.size() - 1:
					return true
		elif kind == "firing_position":
			if (notes[int(who["s"])] as Array).size() < int(need[int(who["s"])]):
				return true
		elif kind == "firing_relation":
			if (notes[int(who["a"])] as Array).size() < int(need[int(who["a"])]) or (notes[int(who["b"])] as Array).size() < int(need[int(who["b"])]):
				return true
		else:
			return true
	match kind:
		"ordinal_exact":
			return _first(notes, int(who["s"])) == int(lbl_of_rank[int(fd["r"])])
		"ordinal_neg":
			return _first(notes, int(who["s"])) != int(lbl_of_rank[int(fd["r"])])
		"ordinal_either_or":
			var fe: int = _first(notes, int(who["s"]))
			return fe == int(lbl_of_rank[int(fd["r1"])]) or fe == int(lbl_of_rank[int(fd["r2"])])
		"ordinal_range":
			var f0: int = _first(notes, int(who["s"]))
			if int(fd["lo"]) > 0 and f0 < int(lbl_of_rank[int(fd["lo"])]):
				return false
			if int(fd["hi"]) < g.star_count - 1 and f0 > int(lbl_of_rank[int(fd["hi"])]):
				return false
			return true
		"ordinal_cmp":
			return (_first(notes, int(who["a"])) > _first(notes, int(who["b"]))) == bool(fd["a_gt_b"])
		"ordinal_chain":
			return _first(notes, int(who["a"])) < _first(notes, int(who["mid"])) and _first(notes, int(who["mid"])) < _first(notes, int(who["b"]))
		"ordinal_extreme", "nbr_extreme":
			for nb in nbrs:
				if (_first(notes, int(who["s"])) < _first(notes, int(nb))) != bool(fd["want_lowest"]):
					return false
			return true
		"ordinal_count_before", "nbr_count":
			var before: int = 0
			for nb2 in nbrs:
				if _first(notes, int(nb2)) < _first(notes, int(who["s"])):
					before += 1
			return before == int(fd["k"])
		"ordinal_adjacent", "ordinal_offset":
			var ranks: Array = g._ranks_from_owners(owners)
			return int(ranks[int(who["a"])]) == int(ranks[int(who["b"])]) + int(fd.get("offset", 1))
		"firing_position":
			var v: int = g._firing_value(notes[int(who["s"])], fd["sel"])
			return v >= 0 and v >= int(fd["lo"]) and v <= int(fd["hi"])
		"firing_relation":
			return g._firing_rel_holds(g._firing_pick_notes(notes[int(who["a"])], fd["pick_a"]),
				g._firing_pick_notes(notes[int(who["b"])], fd["pick_b"]), fd["spec"])
	return true


func _solve_o(pi: Array, inner: Array, must_begin: Dictionary, cap: int) -> Array:
	var n: int = g.melody_star_sequence.size()
	var need: Array = []
	for s in g.star_count:
		need.append(g._star_ticks(s).size())
	# facts to re-check when a star gets a note / a note is assigned
	var by_star: Array = []
	for _s in g.star_count:
		by_star.append([])
	var by_note: Array = []
	for _t in n + 1:
		by_note.append([])
	var always: Array = []
	for f in inner:
		var placed: bool = false
		for r in (f["refs"] as Dictionary).values():
			if (r as Dictionary).has("note"):
				(by_note[int(r["note"])] as Array).append(f)
			else:
				var rs: int = _ent_star(r, pi, [])
				if rs >= 0:
					(by_star[rs] as Array).append(f)
				else:
					always.append(f)
			placed = true
		var k: String = str(f["kind"])
		if (k == "ordinal_extreme" or k == "ordinal_count_before") and (f["refs"]["s"] as Dictionary).has("star"):
			for nb in f["f"]["neighbors"]:
				(by_star[int(nb)] as Array).append(f)
		elif k == "nbr_count" or k == "nbr_extreme" or k == "ordinal_extreme" or k == "ordinal_count_before":
			var center: Dictionary = f["refs"]["s"]
			if not center.has("note") and _ent_star(center, pi, []) >= 0:
				for nb2 in g.proximity[_ent_star(center, pi, [])]:
					(by_star[int(nb2)] as Array).append(f)
			else:
				always.append(f)
		if not placed:
			always.append(f)
	var owners: Array = []
	owners.resize(n)
	owners.fill(-1)
	var notes: Array = []
	for _s2 in g.star_count:
		notes.append([])
	var sols: Array = []
	_nodes = 0
	_hit = false
	var st: Dictionary = {"pi": pi, "need": need, "by_star": by_star, "by_note": by_note, "always": always, "inner": inner,
		"must_begin": must_begin, "free": g.star_count - must_begin.size(), "free_used": 0}
	_dfs(1, n, owners, notes, st, sols, cap)
	return sols


func _dfs(t: int, n: int, owners: Array, notes: Array, st: Dictionary, sols: Array, cap: int) -> void:
	if sols.size() >= cap or _hit:
		return
	var pi: Array = st["pi"]
	var need: Array = st["need"]
	if t > n:
		for f in st["inner"]:
			if not _check(f, pi, owners, notes, need, true):
				return
		sols.append(owners.duplicate())
		return
	for s in g.star_count:
		if (notes[s] as Array).size() >= int(need[s]):
			continue
		var begins: bool = (notes[s] as Array).is_empty()
		var mb: bool = (st["must_begin"] as Dictionary).has(t)
		if mb and not begins:
			continue
		if begins and not mb and int(st["free_used"]) >= int(st["free"]):
			continue
		_nodes += 1
		if _nodes > INNER_BUDGET:
			_hit = true
			return
		owners[t - 1] = s
		(notes[s] as Array).append(t)
		if begins and not mb:
			st["free_used"] = int(st["free_used"]) + 1
		var good: bool = true
		var to_check: Array = (st["by_star"][s] as Array) + (st["by_note"][t] as Array) + (st["always"] as Array)
		for held in notes[s]:
			if int(held) != t:
				to_check += st["by_note"][int(held)]
		for f in to_check:
			if not _check(f, pi, owners, notes, need, false):
				good = false
				break
		if good:
			_dfs(t + 1, n, owners, notes, st, sols, cap)
		if begins and not mb:
			st["free_used"] = int(st["free_used"]) - 1
		(notes[s] as Array).pop_back()
		owners[t - 1] = -1
		if sols.size() >= cap or _hit:
			return


func _names_str(pi: Array) -> String:
	var parts: Array = []
	for nm in pi.size():
		if int(pi[nm]) != nm:
			parts.append("%s is really the %s star" % [str(g.star_names[nm]), PuzzleScript.note_name_for_freq(g._freq_for_star(int(pi[nm])))])
	return "; ".join(parts) if not parts.is_empty() else "(names as in the real answer)"


## Answers this reader finds for `clues` with names unknown, up to `cap`:
## {"count", "inconclusive", "second": [names, notes] of a non-real one}.
func _reader_count(clues: Array, cap: int) -> Dictionary:
	unresolved_fields = 0
	unread_clues = []
	var comp: Dictionary = _compile_all(clues)
	var truth: Array = g.melody_star_sequence
	var ident: Array = []
	for i in g.star_count:
		ident.append(i)
	var pis: Array = _enum_pi(comp["outer"], comp["inner"], PI_BUDGET)
	var count: int = 0
	var inconclusive: bool = pis.size() >= PI_BUDGET
	var second: Array = []
	for pi in pis:
		var os: Array = _solve_o(pi, comp["inner"], comp["notes_named"], cap - count)
		if _hit:
			inconclusive = true
		for o in os:
			count += 1
			if second.is_empty() and (pi != ident or o != truth):
				second = [pi, o]
		if count >= cap:
			break
	return {"count": count, "inconclusive": inconclusive and count < cap, "second": second}


func run() -> void:
	print("=== 1. shipped Beginner puzzles have exactly one answer, names unknown ===")
	var puzzles: Array = []
	for pair in [[2, 23], [4, 11], [1, 23], [5, 11]]:
		g = _beginner(int(pair[0]), int(pair[1]))
		await g.generate_clues_forms()
		lbl_of_rank = g._first_fire_ticks()
		var tag: String = "c%d s%d" % [int(pair[0]), int(pair[1])]
		ok(g.gate_passed and g.names_honoured, "%s: passes the ship gate with the joint proof on" % tag)
		var comp: Dictionary = _compile_all(g.chosen_form_clues)
		ok(unread_clues.is_empty(), "%s: every clue is read (%s)" % [tag, str(unread_clues)])
		var ident: Array = []
		for i in g.star_count:
			ident.append(i)
		var truth: Array = g.melody_star_sequence.duplicate()
		var tnotes: Array = []
		for _s in g.star_count:
			tnotes.append([])
		for t in truth.size():
			(tnotes[int(truth[t])] as Array).append(t + 1)
		var need0: Array = []
		for s in g.star_count:
			need0.append(g._star_ticks(s).size())
		var bad: Array = []
		for c in comp["outer"]:
			if not _outer_ok(c, ident):
				bad.append(str(c))
		for f in comp["inner"]:
			if not _check(f, ident, truth, tnotes, need0, true):
				bad.append("%s %s" % [str(f["kind"]), str(f["refs"])])
		ok(bad.is_empty(), "%s: the real answer satisfies every clue as read here (%d facts; broken: %s)" % [tag, comp["inner"].size() + comp["outer"].size(), str(bad.slice(0, 3))])
		var ctl: Array = _solve_o(ident, comp["inner"], comp["notes_named"], 2)
		ok(ctl.size() == 1 and not _hit and ctl[0] == truth, "%s: control -- with the real names, exactly the real melody (%d found)" % [tag, ctl.size()])
		var rc: Dictionary = _reader_count(g.chosen_form_clues, 2)
		ok(int(rc["count"]) == 1 and not bool(rc["inconclusive"]),
			"%s: with names unknown, exactly one answer (%d found%s)" % [tag, int(rc["count"]), ", inconclusive" if bool(rc["inconclusive"]) else ""])
		if not (rc["second"] as Array).is_empty():
			print("    second answer, names %s, notes %s" % [str(rc["second"][0]), str(rc["second"][1])])
		puzzles.append(g)

	print("\n=== 2. the joint proof and this reader agree, one clue removed at a time ===")
	var compared: int = 0
	var agree: int = 0
	var seen_not_unique: int = 0

	for gp in puzzles.slice(0, 2):
		g = gp
		lbl_of_rank = g._first_fire_ticks()
		var all_clues: Array = g.chosen_form_clues.duplicate()
		for drop in all_clues:
			var rest: Array = []
			var rest_seq: Array = []
			for cl in all_clues:
				if cl != drop:
					rest.append(cl)
			for cl2 in rest:
				for d in cl2["disclosures"]:
					if d is Dictionary and not g.VALUE_FACT_KINDS.has(str(d.get("kind", ""))):
						rest_seq.append(d)
			var rc2: Dictionary = _reader_count(rest, 2)
			g.names_honoured = true
			var sols: Array = await g._solve_notes(rest_seq, 2, rest)
			var gen_inconclusive: bool = g._last_solve_inconclusive
			compared += 1
			if not gen_inconclusive and not bool(rc2["inconclusive"]) and sols.size() == int(rc2["count"]):
				agree += 1
			else:
				print("    DISAGREE without '%s': reader %d%s, joint proof %d%s" % [str(drop["text"]), int(rc2["count"]),
					" (inconclusive)" if bool(rc2["inconclusive"]) else "", sols.size(), " (inconclusive)" if gen_inconclusive else ""])
			if int(rc2["count"]) > 1:
				seen_not_unique += 1
	ok(compared >= 30, "enough removals compared to mean something (%d)" % compared)
	ok(agree == compared, "the joint proof and this reader report the same number of answers every time (%d of %d)" % [agree, compared])
	ok(seen_not_unique > 0, "'more than one answer' actually occurred (%d times), so the comparison can fail" % seen_not_unique)

	print("\n=== 3. what changed: puzzles proven by reading names as their real stars ===")
	# Built with names_honoured = false, the proof before the joint one. On
	# 2026-10-14 this reader found a second answer for these two (verified by
	# hand for The Archon); the joint proof must see it too.
	var caught: int = 0
	var old_tried: int = 0
	for pair2 in [[0, 11], [2, 11]]:
		g = _beginner(int(pair2[0]), int(pair2[1]))
		g.names_honoured = false
		# The Easy settings of the day those second answers were found: no spare
		# clues, historical pruning order (the later Easy extras happen to make
		# these two seeds unique even under the old proof).
		g.spare_note_pins_override = 0
		g.spare_first_pins_override = 0
		g.spare_name_ties_override = 0
		g.prune_first_forms = [-1]
		g.seq_chain_len_override = 3
		await g.generate_clues_forms()
		lbl_of_rank = g._first_fire_ticks()
		var tag2: String = "c%d s%d" % [int(pair2[0]), int(pair2[1])]
		if not g.gate_passed:
			continue
		old_tried += 1
		var rc3: Dictionary = _reader_count(g.chosen_form_clues, 2)
		g.names_honoured = true
		var jsols: Array = await g._solve_notes(g._seq_facts_from_clues(), 2)
		print("    %s (old proof's puzzle): reader %d answer(s), joint proof %d" % [tag2, int(rc3["count"]), jsols.size()])
		if int(rc3["count"]) > 1 and jsols.size() > 1:
			caught += 1
	ok(old_tried > 0 and caught > 0, "the old proof shipped puzzles with a second answer, and the joint proof sees it (%d of %d)" % [caught, old_tried])

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()


## A star's pitch as a step among the map's distinct pitches, lowest = 0.
func _pitch_step(s: int) -> int:
	var fr: Array = []
	for x in g.star_count:
		var v: float = g._freq_for_star(x)
		if not fr.has(v):
			fr.append(v)
	fr.sort()
	return fr.find(g._freq_for_star(s))
