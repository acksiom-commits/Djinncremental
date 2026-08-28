extends "res://dev_tests/test_base.gd"
# The rendered SENTENCE must agree with the puzzle's ground truth.
#
# WHY THIS EXISTS: the Adjacency Form rendered every clue backwards for its
# entire life, and every gate in the project passed it. From a live save:
#
#     "Eosaara fires immediately after Nyxaos."
#      Eosaara fires at position 5, Nyxaos at 6 -- Eosaara is EARLIER.
#
# Its ordinal_adjacent fact was correct; only the sentence was inverted.
# Nothing noticed because nothing compares the two. The solver reads facts,
# the uniqueness gate solves from facts, pruning measures with facts, and
# _validate_sequence_fact validates facts. The in-game deduction engine
# reads facts too -- so a player who correctly followed that sentence got
# their own board flagged as contradictory. The TEXT had exactly one
# consumer, the player, and no test stood where the player stands.
#
# So this test reads ONLY the sentence. It re-derives each claim from the
# English and checks it against the real solution, deliberately ignoring
# the disclosure encodings. Checking the facts instead would reproduce the
# original blind spot exactly: a Form can hold a true fact and print a lie.
#
# IT STATES ITS OWN DENOMINATOR. Every sentence shape needs its own parser,
# so the report prints judged/seen PER FORM. An earlier version counted
# only what it judged, and Distance Existential showed "18" while 54
# existed -- a Form covered at one third looked fully covered. Any sentence
# a parser matched but could not resolve is now counted and sampled, so
# partial coverage is visible instead of flattering.
#
# Unpruned (prune_enabled = false) for sample size: Adjacency is ~1% of a
# pruned puzzle, so a pruned fixture would test almost nothing while
# looking green. Same note as test_distance_disclosure.gd.

const SEEDS := [11, 4242, 31337]
const CONSTELLATIONS := [0, 2]

var fails: int = 0
var checked: int = 0
var wrong: int = 0
var by_form: Dictionary = {}      # judged sentences per Form
var seen_forms: Dictionary = {}   # every clue seen per Form
var examples: Array = []
var unjudged: Array = []

var _g = null

var _re_gap: RegEx
var _re_cmp: RegEx
var _re_off: RegEx
var _re_btw: RegEx
var _re_chain: RegEx
var _re_range: RegEx
var _re_extr: RegEx
var _re_count: RegEx
var _re_gorder: RegEx
var _re_bridge: RegEx
var _re_member: RegEx
var _re_same: RegEx
var _re_diff: RegEx
var _re_not: RegEx
var _re_neither: RegEx
var _re_hop: RegEx
var _re_conn: RegEx
var _re_dextr: RegEx
var _re_gcmp: RegEx
var _re_either: RegEx
var _re_only: RegEx
var _re_ident: RegEx
var _re_stag: RegEx
var _re_distinct: RegEx
var _re_none: RegEx


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _rx(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r


func _compile() -> void:
	_re_gap     = _rx("(.+) fires immediately (after|before) (.+)\\.$")
	_re_off     = _rx("(.+?) (?:fires|is pitched|is) exactly (\\d+) (?:steps?|pitch ranks?) (later|earlier|higher|lower) than (.+)\\.$")
	_re_cmp     = _rx("(.+?) (?:fires|is pitched|is) (later|earlier|higher|lower) than (.+)\\.$")
	_re_btw     = _rx("(.+?) (?:fires|is pitched) between (.+) and (.+)\\.$")
	_re_chain   = _rx("(.+?) (?:fires|is pitched) (before|after|higher than|lower than) (.+), which (?:fires|is pitched) (?:before|after|higher than|lower than) (.+)\\.$")
	_re_range   = _rx("(.+) is among the (first|last) (\\d+)\\.$")
	_re_extr    = _rx("(.+) is the (earliest|latest) to fire among its connected stars\\.$")
	_re_count   = _rx("^Exactly (\\d+) of (.+)'s connected stars fire before it\\.$")
	_re_bridge  = _rx("^Among (the .+), the (earliest|latest)-firing one is (.+)\\.$")
	# Group Order renders its group as "every yellow star" / "every star that
	# plays A#4" (_group_noun_phrase with plural=true), NOT "the ...".
	_re_gorder  = _rx("(.+?) (precedes|follows) ((?:every|the) .+)\\.$")
	# Pseudo-True Pair (Staggered) states three conjuncts at once; it must be
	# tried BEFORE _re_cmp, whose "fires earlier than" would otherwise claim
	# the sentence and then fail to resolve its overlong left side.
	_re_stag    = _rx("^(.+?) can be (.+?) or (.+?), (.+?) can be (.+?) or (.+?), and (.+?) fires (earlier|later) than (.+)\\.$")
	_re_member  = _rx("(.+?) is (one of|not one of) (the .+)\\.$")
	_re_same    = _rx("(.+) and (.+) have the same (pitch|color|colour)\\.$")
	_re_diff    = _rx("(.+) all have different (pitches|colors|colours)\\.$")
	_re_distinct = _rx("(.+) are all different stars\\.$")
	_re_hop     = _rx("(.+?) is (\\d+) hops? from (.+)\\.$")
	_re_conn    = _rx("(.+?) is not connected to (.+)\\.$")
	# Distance Extreme. Added 2026-08-27 after this test FAILED on a true
	# sentence: "The star that fires 1st note is the farthest star to
	# Oryides." was claimed by the greedy _re_ident below, which reads
	# "X is Y" as an identity and so demanded the two labels name the SAME
	# star -- while this Form guarantees they are DIFFERENT by construction.
	# Exactly the collision _re_ident's own comment warns about; this Form's
	# shape had simply never been given a branch.
	#
	# It went unseen for the Form's whole life because Distance Extreme is
	# ~0.2% of clues and had never once landed in a sample. The generator
	# changes of 2026-08-26/27 shifted the RNG stream and drew one in. A
	# pre-existing gap, surfaced rather than caused.
	_re_dextr   = _rx("^(.+?) is the (closest|farthest) star to (.+)\\.$")
	_re_gcmp    = _rx("(.+?) has a (higher|lower) (sequence position|frequency|color rank) than (.+)\\.$")
	_re_either  = _rx("(.+?) is either (.+?) or (.+)\\.$")
	_re_only    = _rx("(.+?) and (.+?) can only be (.+?) or (.+)\\.$")
	# Mutual Exclusion's negation phrasing (2026-08-19) and Dual Negation
	# share these two shapes. The tail is either a LABEL ("is Helios") or a
	# PREDICATE ("plays B4", "is blue", "fires 3rd note"), so the verb is
	# captured and _predicate_star resolves whichever it turns out to be.
	_re_none    = _rx("^None of (.+) (is|plays|fires) (.+)\\.$")
	# Second group GREEDY on purpose. Labels themselves contain the verbs
	# ("the star that FIRES 12th note"), so a non-greedy group stops at the
	# first one inside the label and shreds the sentence -- it silently cut
	# Dual Negation from 506 judged to ~0. Greedy backtracks to the LAST
	# verb, which is the actual predicate.
	_re_neither = _rx("^Neither (.+?) nor (.+) (is|plays|fires) (.+)\\.$")
	_re_not     = _rx("(.+?) is not (.+)\\.$")
	_re_ident   = _rx("^(.+) is (.+)\\.$")


# ── ground-truth readers ────────────────────────────────────────────────
func _seq(s: int) -> int:
	return int(_g.sequence_rank_solution[s])


func _pitch(s: int) -> int:
	return int(_g._pitch_freq_rank[_g.star_pitch_index[s]])


func _axis_val(s: int, axis: String) -> int:
	return _pitch(s) if axis == "pitch" else _seq(s)


## label -> star, for every characteristic this clue rendered.
func _label_map(clue: Dictionary) -> Dictionary:
	var m: Dictionary = {}
	for ch in (clue.get("chars", []) as Array):
		# Keyed lowercase, because _stars_in matches case-insensitively
		# (a label is capitalised when it opens a sentence).
		var lbl: String = str(_g._characteristic_label(ch)).to_lower()
		if lbl != "":
			m[lbl] = int((ch as Dictionary)["star"])
	return m


## Stars whose label appears in `frag`. Longest label first, blanking each
## match as it is consumed, so "Helios" cannot also match inside "Helioseia".
func _stars_in(frag: String, m: Dictionary) -> Array:
	var labels: Array = m.keys()
	labels.sort_custom(func(a, b): return str(a).length() > str(b).length())
	# Case-insensitive: a label is rendered lowercase ("the star that fires
	# 9th note") but is capitalised when it opens a sentence. Matching
	# case-sensitively silently dropped a THIRD of all sentences -- every
	# clue whose subject was a descriptor rather than a name.
	var work: String = frag.to_lower()
	var out: Array = []
	for l in labels:
		var ls: String = str(l).to_lower()
		if work.contains(ls):
			work = work.replace(ls, "")
			var st: int = int(m[ls])
			if not out.has(st):
				out.append(st)
	return out


## Like _stars_in but KEEPS duplicates, so a sentence asserting that N
## labels are all different stars can be caught when two of them are not.
func _stars_in_dup(frag: String, m: Dictionary) -> Array:
	var labels: Array = m.keys()
	labels.sort_custom(func(a, b): return str(a).length() > str(b).length())
	var work: String = frag.to_lower()
	var out: Array = []
	for l in labels:
		var ls: String = str(l)
		while work.contains(ls):
			work = work.replace(ls, "")
			out.append(int(m[ls]))
	return out


## Every star a predicate covers, as a GROUP: "is blue" -> all blue stars.
## Group Negation (Form 24) negates against a whole Colour/Pitch group, so
## its tail names many stars where Dual Negation's names exactly one. A
## negation is satisfied when NO listed subject is in the set, which is the
## same test either way — so both shapes share one checker, with this
## returning the full set and _predicate_star the singleton case.
## Also handles "is blue or plays A4" by unioning the two halves.
func _predicate_stars(verb: String, rest: String) -> Array:
	var out: Array = []
	var parts: Array = [rest]
	var split_at: int = rest.find(" or ")
	if split_at >= 0:
		parts = [rest.substr(0, split_at), rest.substr(split_at + 4)]
	for p in parts:
		var frag: String = str(p).strip_edges()
		var v: String = verb
		# The second half carries its own verb ("... or plays A4").
		for cand in ["is ", "plays ", "fires "]:
			if frag.begins_with(cand):
				v = cand.strip_edges()
				frag = frag.substr(cand.length())
				break
		var one: int = _predicate_star(v, frag)
		if one >= 0:
			if not out.has(one):
				out.append(one)
			continue
		# Not a singleton — try it as a whole Colour/Pitch group.
		var low: String = frag.strip_edges().to_lower()
		for ci in range(_g.COLOR_NAMES.size()):
			if str(_g.COLOR_NAMES[ci]).to_lower() == low:
				for s in _g.star_count:
					if int(_g.star_colors[s]) == ci and not out.has(s):
						out.append(s)
		for s2 in _g.star_count:
			if str(_g.note_name_for_freq(_g._freq_for_star(s2))).to_lower() == low and not out.has(s2):
				out.append(s2)
	return out


## The star a PREDICATE denotes: "plays B4", "is blue", "is Helios",
## "fires 3rd note". Resolved from ground truth rather than from the clue's
## own chars, so a predicate naming the wrong star is caught rather than
## quietly agreeing with itself. Returns -1 if it names no single star.
func _predicate_star(verb: String, rest: String) -> int:
	var r: String = rest.strip_edges().to_lower()
	match verb:
		"plays":
			var hit: int = -1
			for s in _g.star_count:
				if str(_g.note_name_for_freq(_g._freq_for_star(s))).to_lower() == r:
					if hit >= 0:
						return -1   # ties: the predicate is not a unique reference
					hit = s
			return hit
		"fires":
			var digits: String = ""
			for ch in r:
				if ch >= "0" and ch <= "9":
					digits += ch
				elif digits != "":
					break
			if digits == "":
				return -1
			var pos: int = int(digits) - 1
			for s2 in _g.star_count:
				if _seq(s2) == pos:
					return s2
			return -1
		"is":
			for ci in range(_g.COLOR_NAMES.size()):
				if str(_g.COLOR_NAMES[ci]).to_lower() == r:
					var chit: int = -1
					for s3 in _g.star_count:
						if int(_g.star_colors[s3]) == ci:
							if chit >= 0:
								return -1
							chit = s3
					return chit
			for s4 in _g.star_count:
				if str(_g.star_names[s4]).to_lower() == r:
					return s4
	return -1


func _one_star(frag: String, m: Dictionary) -> int:
	var f: Array = _stars_in(frag, m)
	return int(f[0]) if f.size() == 1 else -1


## "a star 2 hops from Theryis" -> EVERY star at that distance.
##
## Must be tried before _one_star on a distinctness element. The clue's
## chars carry the DISTANCE node, so _label_map resolves that exact phrase
## to the element's single representative — which would check disjointness
## against one star when the element actually covers the whole ring, a
## strictly weaker test than the builder's own guarantee.
func _hop_phrase_stars(frag: String) -> Array:
	var r := RegEx.new()
	r.compile("stars? (\\d+) hops? from (.+)$")
	var mm := r.search(frag.strip_edges().trim_suffix("."))
	if mm == null:
		return []
	var h: int = int(mm.get_string(1))
	var refname: String = mm.get_string(2).strip_edges().to_lower()
	for s in _g.star_count:
		if str(_g.star_names[s]).to_lower() != refname:
			continue
		var out: Array = []
		for t in _g.star_count:
			if int(_g._distances[s][t]) == h:
				out.append(t)
		return out
	return []


## Stars named by a collective phrase: "the blue stars", "a white star",
## "the star that plays C#5". Resolved off the visible map, as a player would.
func _group_stars(phrase: String) -> Array:
	var out: Array = []
	var p: String = phrase.to_lower()
	for ci in range(_g.COLOR_NAMES.size()):
		if p.contains(str(_g.COLOR_NAMES[ci]).to_lower()):
			for s in _g.star_count:
				if int(_g.star_colors[s]) == ci:
					out.append(s)
			return out
	if p.contains("play"):
		for s in _g.star_count:
			var note: String = str(_g.note_name_for_freq(_g._freq_for_star(s))).to_lower()
			if p.ends_with(note) or p.contains(note + " ") or p.contains(note + ","):
				out.append(s)
	return out


func _judge(form: String, text: String, holds: bool, detail: String) -> void:
	checked += 1
	by_form[form] = int(by_form.get(form, 0)) + 1
	if not holds:
		wrong += 1
		if examples.size() < 10:
			examples.append("%s | %s | %s" % [form, text, detail])


## Returns only after judging, or falling through every parser. The caller
## detects "matched but unresolved" by watching by_form, so every early exit
## here is still accounted for.
func _try_parse(clue: Dictionary, text: String, form: String) -> void:
	var m: Dictionary = _label_map(clue)
	var mm: RegExMatch

	# Staggered pair: "A can be P or Q, B can be R or S, and A fires earlier
	# than B." All three conjuncts are checkable, so all three are checked.
	mm = _re_stag.search(text)
	if mm:
		var g1: int = _one_star(mm.get_string(1), m)
		var ga: int = _one_star(mm.get_string(2), m)
		var gb2: int = _one_star(mm.get_string(3), m)
		var g2: int = _one_star(mm.get_string(4), m)
		var gc: int = _one_star(mm.get_string(5), m)
		var gd: int = _one_star(mm.get_string(6), m)
		var l3: int = _one_star(mm.get_string(7), m)
		var r3: int = _one_star(mm.get_string(9), m)
		if g1 >= 0 and ga >= 0 and gb2 >= 0 and g2 >= 0 and gc >= 0 and gd >= 0 \
				and l3 >= 0 and r3 >= 0:
			var first_ok: bool = g1 == ga or g1 == gb2
			var second_ok: bool = g2 == gc or g2 == gd
			var ord_ok: bool = (_seq(l3) < _seq(r3)) if mm.get_string(8) == "earlier" \
				else (_seq(l3) > _seq(r3))
			_judge(form, text, first_ok and second_ok and ord_ok,
				"options %s / order %s" % [str(first_ok and second_ok), str(ord_ok)])
		return

	# ── two labels + a direction ────────────────────────────────────────
	mm = _re_gap.search(text)
	if mm:
		var a1: int = _one_star(mm.get_string(1), m)
		var b1: int = _one_star(mm.get_string(3), m)
		if a1 >= 0 and b1 >= 0:
			var want: int = 1 if mm.get_string(2) == "after" else -1
			_judge(form, text, _seq(a1) - _seq(b1) == want,
				"positions %d vs %d" % [_seq(a1), _seq(b1)])
		return

	mm = _re_off.search(text)
	if mm:
		var a2: int = _one_star(mm.get_string(1), m)
		var b2: int = _one_star(mm.get_string(4), m)
		var w2: String = mm.get_string(3)
		var ax2: String = "pitch" if (w2 == "higher" or w2 == "lower") else "seq"
		if a2 >= 0 and b2 >= 0:
			var d2: int = _axis_val(a2, ax2) - _axis_val(b2, ax2)
			var n2: int = int(mm.get_string(2))
			var exp2: int = n2 if (w2 == "later" or w2 == "higher") else -n2
			_judge(form, text, d2 == exp2, "%s delta %d, sentence says %d" % [ax2, d2, exp2])
		return

	# BEFORE _re_cmp: a chain sentence ("A is pitched lower than B, which is
	# pitched lower than C") also matches the plain comparison pattern, whose
	# right-hand side would then swallow ", which is pitched lower than C"
	# and resolve to two stars instead of one.
	mm = _re_chain.search(text)
	if mm:
		var c1: int = _one_star(mm.get_string(1), m)
		var c2: int = _one_star(mm.get_string(3), m)
		var c3: int = _one_star(mm.get_string(4), m)
		var wc: String = mm.get_string(2)
		var axc: String = "pitch" if (wc.begins_with("higher") or wc.begins_with("lower")) else "seq"
		if c1 >= 0 and c2 >= 0 and c3 >= 0:
			var desc: bool = wc == "after" or wc.begins_with("higher")
			var v1: int = _axis_val(c1, axc)
			var v2: int = _axis_val(c2, axc)
			var v3: int = _axis_val(c3, axc)
			var holdc: bool = (v1 > v2 and v2 > v3) if desc else (v1 < v2 and v2 < v3)
			_judge(form, text, holdc, "%s chain %d,%d,%d" % [axc, v1, v2, v3])
		return

	# "A, B, C and D are all different stars" -- distinctness of IDENTITY,
	# not of a Colour/Pitch value like the "all have different pitches"
	# phrasing below. Duplicates matter here, so this counts label
	# occurrences rather than the de-duplicated star set.
	mm = _re_distinct.search(text)
	if mm:
		# Elements are a MIX now: bijective labels ("Theraion") denote one
		# star, group phrases ("a yellow star") denote a whole set. The
		# claim that all are different holds exactly when no element's set
		# overlaps another's -- which for two singletons is the old
		# "distinct stars" test, and for a group is the non-overlap
		# condition the builder enforces.
		var sets_d: Array = []
		for part in mm.get_string(1).replace(", and ", "|").replace(" and ", "|").split("|"):
			var frag_d: String = str(part).strip_edges().trim_suffix(",")
			for piece in frag_d.split(","):
				var pf: String = str(piece).strip_edges()
				if pf == "":
					continue
				var hop_d: Array = _hop_phrase_stars(pf)
				if not hop_d.is_empty():
					sets_d.append(hop_d)
					continue
				var one_d: int = _one_star(pf, m)
				if one_d >= 0:
					sets_d.append([one_d])
					continue
				var grp_d: Array = _group_stars(pf)
				if not grp_d.is_empty():
					sets_d.append(grp_d)
		if sets_d.size() >= 2:
			var disjoint: bool = true
			for i_d in sets_d.size():
				for j_d in range(i_d + 1, sets_d.size()):
					for x_d in (sets_d[i_d] as Array):
						if (sets_d[j_d] as Array).has(x_d):
							disjoint = false
			_judge(form, text, disjoint,
				"%d elements, two of them can be the same star" % sets_d.size())
		return

	mm = _re_cmp.search(text)
	if mm:
		var a3: int = _one_star(mm.get_string(1), m)
		var b3: int = _one_star(mm.get_string(3), m)
		var w3: String = mm.get_string(2)
		var ax3: String = "pitch" if (w3 == "higher" or w3 == "lower") else "seq"
		if a3 >= 0 and b3 >= 0:
			var gt3: bool = (w3 == "later" or w3 == "higher")
			var hold3: bool = (_axis_val(a3, ax3) > _axis_val(b3, ax3)) if gt3 \
				else (_axis_val(a3, ax3) < _axis_val(b3, ax3))
			_judge(form, text, hold3,
				"%s %d vs %d" % [ax3, _axis_val(a3, ax3), _axis_val(b3, ax3)])
		return

	# ── three labels ────────────────────────────────────────────────────
	mm = _re_btw.search(text)
	if mm:
		var mid: int = _one_star(mm.get_string(1), m)
		var e1: int = _one_star(mm.get_string(2), m)
		var e2: int = _one_star(mm.get_string(3), m)
		var axb: String = "pitch" if text.contains("is pitched") else "seq"
		if mid >= 0 and e1 >= 0 and e2 >= 0:
			var lo: int = mini(_axis_val(e1, axb), _axis_val(e2, axb))
			var hi: int = maxi(_axis_val(e1, axb), _axis_val(e2, axb))
			var mv: int = _axis_val(mid, axb)
			_judge(form, text, mv > lo and mv < hi,
				"%s mid %d not inside (%d,%d)" % [axb, mv, lo, hi])
		return

	# ── one label + a computed property ─────────────────────────────────
	mm = _re_range.search(text)
	if mm:
		var sr: int = _one_star(mm.get_string(1), m)
		if sr >= 0:
			var n: int = int(mm.get_string(3))
			var r: int = _seq(sr)
			var holdr: bool = (r < n) if mm.get_string(2) == "first" \
				else (r >= _g.star_count - n)
			_judge(form, text, holdr, "position %d, window %s %d" % [r, mm.get_string(2), n])
		return

	mm = _re_extr.search(text)
	if mm:
		var se: int = _one_star(mm.get_string(1), m)
		if se >= 0:
			var lowest: bool = mm.get_string(2) == "earliest"
			var holde: bool = true
			for nb in _g.proximity[se]:
				if lowest and _seq(int(nb)) < _seq(se):
					holde = false
				if not lowest and _seq(int(nb)) > _seq(se):
					holde = false
			_judge(form, text, holde, "position %d among neighbours" % _seq(se))
		return

	mm = _re_count.search(text)
	if mm:
		var sc2: int = _one_star(mm.get_string(2), m)
		if sc2 >= 0:
			var k: int = 0
			for nb2 in _g.proximity[sc2]:
				if _seq(int(nb2)) < _seq(sc2):
					k += 1
			_judge(form, text, k == int(mm.get_string(1)), "really %d neighbours before it" % k)
		return

	# ── subject vs a collective group ───────────────────────────────────
	mm = _re_bridge.search(text)
	if mm:
		var sb: int = _one_star(mm.get_string(3), m)
		var gb: Array = _group_stars(mm.get_string(1))
		if sb >= 0 and not gb.is_empty():
			var lowb: bool = mm.get_string(2) == "earliest"
			var holdb: bool = gb.has(sb)
			for gs in gb:
				if lowb and _seq(int(gs)) < _seq(sb):
					holdb = false
				if not lowb and _seq(int(gs)) > _seq(sb):
					holdb = false
			_judge(form, text, holdb, "subject position %d, group of %d" % [_seq(sb), gb.size()])
		return

	mm = _re_gorder.search(text)
	if mm:
		var sg: int = _one_star(mm.get_string(1), m)
		var gg: Array = _group_stars(mm.get_string(3))
		if sg >= 0 and not gg.is_empty():
			var prec: bool = mm.get_string(2) == "precedes"
			var holdg: bool = true
			for gs2 in gg:
				if int(gs2) == sg:
					continue
				if prec and _seq(int(gs2)) < _seq(sg):
					holdg = false
				if not prec and _seq(int(gs2)) > _seq(sg):
					holdg = false
			_judge(form, text, holdg, "subject position %d vs %d members" % [_seq(sg), gg.size()])
		return

	mm = _re_member.search(text)
	if mm:
		var sm: int = _one_star(mm.get_string(1), m)
		var gm: Array = _group_stars(mm.get_string(3))
		if sm >= 0 and not gm.is_empty():
			var pos_m: bool = mm.get_string(2) == "one of"
			_judge(form, text, gm.has(sm) == pos_m,
				"member=%s, sentence says %s" % [str(gm.has(sm)), mm.get_string(2)])
		return

	# ── equality / distinctness ─────────────────────────────────────────
	mm = _re_same.search(text)
	if mm:
		var q1: int = _one_star(mm.get_string(1), m)
		var q2: int = _one_star(mm.get_string(2), m)
		var axq: String = "pitch" if mm.get_string(3) == "pitch" else "color"
		if q1 >= 0 and q2 >= 0:
			var holdq: bool = (_pitch(q1) == _pitch(q2)) if axq == "pitch" \
				else (int(_g.star_colors[q1]) == int(_g.star_colors[q2]))
			_judge(form, text, holdq, "%s values differ" % axq)
		return

	mm = _re_diff.search(text)
	if mm:
		var members: Array = _stars_in(mm.get_string(1), m)
		var axd: String = "pitch" if mm.get_string(2).begins_with("pitch") else "color"
		if members.size() >= 2:
			var holdd: bool = true
			for i in range(members.size()):
				for j in range(i + 1, members.size()):
					var x: int = int(members[i])
					var y: int = int(members[j])
					var same: bool = (_pitch(x) == _pitch(y)) if axd == "pitch" \
						else (int(_g.star_colors[x]) == int(_g.star_colors[y]))
					if same:
						holdd = false
			_judge(form, text, holdd, "%d listed, a %s value repeats" % [members.size(), axd])
		return

	# ── map topology ────────────────────────────────────────────────────
	# EXISTENTIAL: "X is 3 hops from a white star" claims SOME member of the
	# group sits at exactly that distance, not that all of them do. Checking
	# it as a for-all would fail every true clue with a multi-member group.
	mm = _re_hop.search(text)
	if mm:
		var sh: int = _one_star(mm.get_string(1), m)
		var gh: Array = _group_stars(mm.get_string(3))
		if sh >= 0 and not gh.is_empty():
			var hop: int = int(mm.get_string(2))
			var found: bool = false
			for gs3 in gh:
				if int(gs3) != sh and int(_g._distances[sh][int(gs3)]) == hop:
					found = true
			_judge(form, text, found, "no member of that group is exactly %d hop(s) away" % hop)
		return

	mm = _re_conn.search(text)
	if mm:
		var k1: int = _one_star(mm.get_string(1), m)
		var k2: int = _one_star(mm.get_string(2), m)
		if k1 >= 0 and k2 >= 0:
			_judge(form, text, int(_g._distances[k1][k2]) != 1, "they ARE 1 hop apart")
		return

	# "X is the closest/farthest star to Y" — judged on the CLAIM, not just
	# on the two labels being distinct. "THE farthest" asserts three things:
	# the pair differ, X sits at the extreme hop distance from Y, and that
	# extreme is UNIQUE (otherwise the definite article lies). Unreachable
	# stars (-1) are excluded from the comparison, matching how the Form
	# itself skips them.
	mm = _re_dextr.search(text)
	if mm:
		var dt: int = _one_star(mm.get_string(1), m)
		var dr: int = _one_star(mm.get_string(3), m)
		if dt >= 0 and dr >= 0:
			var want_min: bool = mm.get_string(2) == "closest"
			var ext: int = -1
			var ties: int = 0
			for s4 in _g.star_count:
				if s4 == dr:
					continue
				var d4: int = int(_g._distances[dr][s4])
				if d4 == -1:
					continue
				if ext == -1 or (want_min and d4 < ext) or (not want_min and d4 > ext):
					ext = d4
					ties = 1
				elif d4 == ext:
					ties += 1
			var claimed: int = int(_g._distances[dr][dt])
			_judge(form, text, dt != dr and claimed == ext and ties == 1,
				"claimed %d hops, %s is %d (ties %d)"
					% [claimed, mm.get_string(2), ext, ties])
		return

	# ── subject vs an explicit list ─────────────────────────────────────
	mm = _re_gcmp.search(text)
	if mm:
		var sgc: int = _one_star(mm.get_string(1), m)
		var listed: Array = _stars_in(mm.get_string(4), m)
		var axgc: String = "pitch" if mm.get_string(3) == "frequency" else "seq"
		if sgc >= 0 and not listed.is_empty() and mm.get_string(3) != "color rank":
			var hi_gc: bool = mm.get_string(2) == "higher"
			var holdgc: bool = true
			for ls in listed:
				if int(ls) == sgc:
					continue
				var cmp_ok: bool = (_axis_val(sgc, axgc) > _axis_val(int(ls), axgc)) if hi_gc \
					else (_axis_val(sgc, axgc) < _axis_val(int(ls), axgc))
				if not cmp_ok:
					holdgc = false
			_judge(form, text, holdgc,
				"%s subject %d vs %d listed" % [axgc, _axis_val(sgc, axgc), listed.size()])
		return

	# ── set-valued identity claims ──────────────────────────────────────
	mm = _re_only.search(text)
	if mm:
		var p1: int = _one_star(mm.get_string(1), m)
		var p2: int = _one_star(mm.get_string(2), m)
		var v1: int = _one_star(mm.get_string(3), m)
		var v2: int = _one_star(mm.get_string(4), m)
		if p1 >= 0 and p2 >= 0 and v1 >= 0 and v2 >= 0:
			var lhs: Array = [p1, p2]
			lhs.sort()
			var rhs: Array = [v1, v2]
			rhs.sort()
			_judge(form, text, lhs == rhs, "pair %s vs options %s" % [str(lhs), str(rhs)])
		return

	mm = _re_either.search(text)
	if mm:
		var se2: int = _one_star(mm.get_string(1), m)
		var o1: int = _one_star(mm.get_string(2), m)
		var o2: int = _one_star(mm.get_string(3), m)
		if se2 >= 0 and o1 >= 0 and o2 >= 0:
			_judge(form, text, se2 == o1 or se2 == o2, "subject is neither option")
		return

	# "None of A, B, or C plays B4." — every listed star must differ from
	# the one the predicate names. Before _re_ident, which would otherwise
	# claim the "... is blue" variant.
	mm = _re_none.search(text)
	if mm:
		var listed_n: Array = _stars_in(mm.get_string(1), m)
		var tgt_set: Array = []
		var one_n: int = _one_star(mm.get_string(3), m)
		if one_n >= 0:
			tgt_set = [one_n]
		else:
			tgt_set = _predicate_stars(mm.get_string(2), mm.get_string(3))
		if listed_n.size() >= 2 and not tgt_set.is_empty():
			var clean_n: bool = true
			for ls_n in listed_n:
				if tgt_set.has(int(ls_n)):
					clean_n = false
			_judge(form, text, clean_n,
				"a listed star IS in the negated set (%d listed, %d negated)"
					% [listed_n.size(), tgt_set.size()])
		return

	mm = _re_neither.search(text)
	if mm:
		var n1: int = _one_star(mm.get_string(1), m)
		var n2b: int = _one_star(mm.get_string(2), m)
		# Tail is a label for Dual Negation ("is Helios") and a predicate
		# for Mutual Exclusion ("plays B4"); try the label first so the
		# older shape keeps resolving through the clue's own chars.
		# Tail is a single star for Dual Negation / Mutual Exclusion, and a
		# whole Colour/Pitch group (possibly two, joined by "or") for Group
		# Negation. Same satisfaction test: no subject may be in the set.
		var set3: Array = []
		var one3: int = _one_star(mm.get_string(4), m)
		if one3 >= 0:
			set3 = [one3]
		else:
			set3 = _predicate_stars(mm.get_string(3), mm.get_string(4))
		if n1 >= 0 and n2b >= 0 and not set3.is_empty():
			_judge(form, text, not set3.has(n1) and not set3.has(n2b),
				"a negated subject IS in the set (%d negated)" % set3.size())
		return

	mm = _re_not.search(text)
	if mm:
		var x1: int = _one_star(mm.get_string(1), m)
		var x2: int = _one_star(mm.get_string(2), m)
		if x1 >= 0 and x2 >= 0:
			_judge(form, text, x1 != x2, "both labels denote star %d" % x1)
		return

	# Exact Identity, LAST: "X is Y" asserts two labels name the same star.
	# Deliberately greedy, so it must run only after every other "... is ..."
	# shape above has claimed its own sentences.
	mm = _re_ident.search(text)
	if mm:
		var y1: int = _one_star(mm.get_string(1), m)
		var y2: int = _one_star(mm.get_string(2), m)
		if y1 >= 0 and y2 >= 0:
			_judge(form, text, y1 == y2, "labels denote different stars %d and %d" % [y1, y2])
		return


func run() -> void:
	_compile()
	var cd = load("res://constellation_data.gd").new()

	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in SEEDS:
			_g = load("res://constellation_logic_puzzle.gd").new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			_g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
			_g.prune_enabled = false
			await _g.generate_clues_forms()

			for clue in _g.chosen_form_clues:
				var text: String = str(clue.get("text", ""))
				var form: String = str(clue.get("form_name", "?"))
				seen_forms[form] = int(seen_forms.get(form, 0)) + 1
				var before: int = int(by_form.get(form, 0))
				_try_parse(clue, text, form)
				if int(by_form.get(form, 0)) == before and unjudged.size() < 14:
					unjudged.append("%s | %s" % [form, text])

	# ── report ──────────────────────────────────────────────────────────
	var forms: Array = seen_forms.keys()
	forms.sort()
	var total_seen: int = 0
	var unverified: Array = []
	print("\n  sentences judged against ground truth: %d\n" % checked)
	print("    %-30s %8s" % ["FORM", "judged/seen"])
	for f in forms:
		var sn: int = int(seen_forms[f])
		var jd: int = int(by_form.get(f, 0))
		total_seen += sn
		if jd == 0:
			unverified.append(str(f))
		print("    %-30s %5d/%-5d %s" % [str(f), jd, sn, "  <-- NO PARSER" if jd == 0 else ""])
	print("\n  overall: %d judged of %d sentences (%.0f%%)"
		% [checked, total_seen, 100.0 * float(checked) / float(maxi(1, total_seen))])
	if not unjudged.is_empty():
		print("  unjudged samples (parser missing, or labels unresolvable):")
		for u in unjudged:
			print("      %s" % str(u))
	for e in examples:
		print("    CONTRADICTS ITS OWN PUZZLE: %s" % str(e))

	# Non-vacuity first: "0 wrong" is also what parsing nothing looks like.
	ok(checked > 0,
		"sentences were actually parsed (%d) — otherwise the next check is vacuous" % checked)
	ok(by_form.has("Adjacency"),
		"Adjacency is represented (%d) — the Form this test was written for"
			% int(by_form.get("Adjacency", 0)))
	ok(unverified.is_empty(),
		"every Form that appeared has at least one judged sentence (unverified: %s)"
			% ("none" if unverified.is_empty() else ", ".join(unverified)))
	ok(wrong == 0,
		"every judged sentence agrees with the real solution (%d contradict it)" % wrong)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
