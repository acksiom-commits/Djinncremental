extends "res://dev_tests/test_base.gd"
# ============================================================================
#  THE MATRIX-UP LINT.
#
#  This module exists because one specific mistake has been made over and
#  over across weeks of work on this puzzle, has been pointed out by the user
#  every single time, and has never once been caught by anything automatic:
#
#      Reasoning DOWN from stars and their characteristics, instead of UP
#      from the cell matrix.
#
#  It is not a style preference. Every instance shipped a real bug:
#    * display-only exclusions on four separate axes
#    * hop clues scoring "Used Up" on a barely-started board
#    * then the same clues stuck OUT of Used Up, the mirror error
#    * both identity passes silently unable to bind anything at all
#
#  Memory notes did not stop it. Comments did not stop it. A lint that fails
#  the suite does, because the suite runs before every commit.
#
#  WHAT IT CHECKS, and the matrix-up answer in each case:
#
#  A. COLUMN SCANS BY HAND. A function that takes a star/position and walks
#     _match_records to work out what could be there is re-deriving a grid
#     lookup. Use _stars_possible_for_descriptor(cat, value) — the descriptor
#     row — or the column loop in _settle_identity_from_value_columns.
#
#  B. STUB BLINDNESS. Every star gets a star_idx-bound record the instant its
#     widget renders. Any loop reading _effective_star_idx across records
#     without consulting _record_is_unconfirmed_star_widget_stub is treating
#     those placeholders as player knowledge. This exact blindness caused
#     three separate shipped bugs.
#
#  TRIAGE AT THE USE SITE, NOT THE FUNCTION. This lint reports FUNCTION
#  names because that is what it can see; the bugs live at individual USE
#  SITES. On 2026-08-13 _detect_contradictions was flagged, one of its two
#  _effective_star_idx sites was examined, and the whole function was
#  cleared as sound — while the actual bug sat in the second site forty
#  lines further down, and shipped. When clearing a function, check EVERY
#  site inside it and say which ones you looked at.
#
#  HOW TO RESPOND WHEN IT FAILS — read this before touching the allowlist:
#
#    1. FIRST assume the new function is the mistake, not the lint. That has
#       been true every time so far.
#    2. Ask what the matrix-native form is. Usually the question is already
#       answerable by an existing primitive.
#    3. ONLY if the function is genuinely a legitimate exception, add its
#       name below WITH a one-line reason. Adding a name silently defeats
#       the entire purpose of this file.
# ============================================================================

const SOURCE := "res://constellation_puzzle_deduction.gd"

# ── A: hand-rolled column scans. Each entry needs a reason. ────────────────
const ALLOW_COLUMN_SCAN := {
	"_records_bound_to_star":
		"IS the column primitive for the LOCATED tier; one scan, many callers",
	"_records_identifying_star":
		"IS the column primitive for the DENOTES tier; one scan, many callers",
	"_records_holding_descriptor":
		"IS the write-side primitive; extracted BECAUSE this lint found it open-coded",
	"_record_descriptor_state":
		"per-record reader by design — the row/column builders are built FROM it",
	"_stars_possible_for_descriptor":
		"the matrix-up primitive itself; scanning records is how it reads the grid",
	"_descriptor_term":
		"pure value lookup, takes no record at all",
	"_find_match_record_by_star_idx":
		"exact-field lookup on a stored key, not a deduction",
	"_player_knows_star_pitch":
		"builds a cache of listened stars once; gates on pitch_revealed, not identity",
}

# ── B: loops that read _effective_star_idx across records. ─────────────────
const ALLOW_STUB_BLIND := {
	"_occupied_positions":
		"filters stubs — this is the function that fixed the blindness",
	"_records_bound_to_star":
		"filters stubs explicitly",
	"_records_identifying_star":
		"delegates to _records_bound_to_star, which filters",
	"_stars_possible_for_descriptor":
		"reads candidate sets, never star_idx directly",
	"_settle_star_identity_from_candidates":
		"occupancy comes from _occupied_positions; its own skip is of BOUND records",
	"_settle_identity_from_value_columns":
		"same — occupancy from _occupied_positions",
	"_player_knows_star_pitch":
		"gates on pitch_revealed, which a stub never has",
	"_effective_star_idx":
		"the accessor itself",
	"_find_match_record_by_star_idx":
		"exact-field lookup used BY the stub machinery",
	"_debug_dump_records":
		"diagnostic output, asserts nothing",
	"_settle_same_star_identity":
		"includes stubs ON PURPOSE — the star map's record IS a stub, and it "
		+ "was the surface that never learned anything. Grouping by star is "
		+ "sound because a stub's star_idx is its widget's POSITION, which is "
		+ "definitional rather than a claim. Safe because it shares via "
		+ "_share_player_marks, which reads only each record's OWN dicts and "
		+ "never an _effective_* reader, so no ground-truth tier can leak "
		+ "out of a stub regardless of what it is grouped with",

	# ── Triaged 2026-08-13, all three measured rather than reasoned. ──────
	"_detect_contradictions":
		"BOTH sites checked (2026-08-14, after clearing it on one site alone "
		+ "let a bug ship). Site 1, marks-vs-own-star: a widget record's "
		+ "POSITION is not a claim needing proof, the widget IS that map star, "
		+ "and stub-ness withholds Name/Pitch but never position. Site 2, "
		+ "records-sharing-a-star: now gated on _same_star_value_clash, which "
		+ "reads only each record's OWN fields, so stubs and ground truth "
		+ "cannot mask or fake a clash",
	"_settle_derived_exclusions_for_axis":
		"FIXED: now unskips stubs, whose Name axis is genuinely unknown "
		+ "(measured: 15/15 names open on a star-7 stub)",
	"_settle_derived_eliminations":
		"skip is harmless: a stub's candidates are [pinned], so Colour/Degree "
		+ "derive only what _effective_color_state already gives, and Pitch is "
		+ "separately gated on all_pitches_known",
	"_settle_group_sequence_bounds":
		"requires star_idx >= 0 and reads only VISIBLE groups (colour, degree) "
		+ "plus a pitch group gated on _player_knows_star_pitch",
}

# ── PRE-EXISTING DEBT, found when this lint was introduced (2026-08-13). ───
#
# NOT the same thing as an allowlist. These are hits that were already in the
# file, have NOT been reviewed, and may well be real bugs — two of the four
# stub-blind ones sit in settle passes where the equivalent blindness had
# just been proved to disable the pass entirely.
#
# They are quarantined rather than allowlisted so the lint can be green for
# NEW code without pretending these are fine. The list is printed in full on
# every run and is asserted NOT to grow. Moving one out means either fixing
# it or promoting it to a real allowlist entry with a reason.
const KNOWN_UNTRIAGED_COLUMN := {}

const KNOWN_UNTRIAGED_STUB := {}

## What a POSITION may not be turned into, IN PLAYER-SIDE CODE. NAME and the
## SEQUENCE solution are the two things the player is solving FOR.
##
## Only star_colors is absent, and only because colour is drawn on the map:
## every position's colour is known at first glance, so reading it off a
## position is observation. PITCH IS NOT IN THAT CATEGORY — it is gated
## behind LISTEN and tracked per record as "pitch_revealed", so reading a
## frequency the player has not listened to is as much a leak as reading a
## name. An earlier draft of this rule wrongly exempted it.
const IDENTITY_GROUND_TRUTH := ["star_names[", "pitch_rank_solution["]

## name -> reason. A function that legitimately bridges position and
## identity (there should be very few, and each is a place the puzzle is
## being ANSWERED rather than posed).
const ALLOW_POSITION_NAMING := {}

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## Splits the source into {name, body} per function, so a match can be
## attributed to something the reader can go and look at.
func _functions_of(src: String) -> Array:
	var out: Array = []
	var lines: PackedStringArray = src.split("\n")
	var cur_name: String = ""
	var cur: PackedStringArray = PackedStringArray()
	for raw in lines:
		var line: String = raw
		if line.begins_with("func "):
			if cur_name != "":
				out.append({"name": cur_name, "body": "\n".join(cur)})
			var after: String = line.substr(5)
			var paren: int = after.find("(")
			cur_name = after.substr(0, paren).strip_edges() if paren > 0 else after.strip_edges()
			cur = PackedStringArray()
		cur.append(line)
	if cur_name != "":
		out.append({"name": cur_name, "body": "\n".join(cur)})
	return out


## Everything to the right of a `#` is prose, and prose must not be able to
## satisfy — or silence — a rule.
##
## Found 2026-08-14 by the user asking whether this lint was actually
## working: _settle_same_star_identity sweeps _match_records and reads
## _effective_star_idx with no stub check, exactly what rule B exists to
## flag, and the lint was GREEN on it — because a comment two lines away
## happened to mention _record_is_unconfirmed_star_widget_stub. Writing
## about the guard was silencing the check for the guard.
func _code_only(body: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for raw in body.split("\n"):
		var line: String = raw
		var hash_at: int = line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		out.append(line)
	return "\n".join(out)


## Does this body loop over VALUES without a RECORD loop enclosing it?
##
## That is the discriminator rule C needs, and two cheaper guesses at it were
## both wrong before this one — worth recording, because each looked obviously
## right:
##
##   "a top-level (depth-1) value loop"  — the loops in
##      _settle_identity_from_value_columns sit at depth 2, inside the
##      CATEGORY loop. Not record-driven, but not depth 1 either.
##   "a line starting with one tab"      — the scanned game files indent with
##      FOUR SPACES; only these dev_tests files use tabs, so it matched
##      nothing at all.
##
## What actually matters is enclosure: a value loop inside a record loop is
## record-driven (it can only reach records that already exist), while one
## that is not can conclude something about a descriptor with NO record.
## So track the open `for` stack by indent width and ask whether any still-open
## enclosing loop iterates _match_records.
func _has_unenclosed_value_loop(body: String) -> bool:
	var stack: Array = []          # [indent_width, is_record_loop]
	for raw in body.split("\n"):
		var stripped: String = raw.strip_edges()
		if stripped == "":
			continue
		# Tabs count as one level; the scanned files use 4 spaces per level.
		var ind: int = 0
		for i in raw.length():
			var ch: String = raw[i]
			if ch == "\t":
				ind += 4
			elif ch == " ":
				ind += 1
			else:
				break
		while not stack.is_empty() and int((stack[stack.size() - 1] as Array)[0]) >= ind:
			stack.remove_at(stack.size() - 1)
		if not stripped.begins_with("for "):
			continue
		if stripped.contains("_host._star_count"):
			var enclosed: bool = false
			for fr in stack:
				if bool((fr as Array)[1]):
					enclosed = true
					break
			if not enclosed:
				return true
		stack.append([ind, stripped.contains("_match_records")])
	return false


func _iterates_records(body: String) -> bool:
	return body.contains("in _match_records")


func run() -> void:
	var src: String = FileAccess.get_file_as_string(SOURCE)
	ok(src != "", "read %s (%d bytes)" % [SOURCE, src.length()])
	if src == "":
		print("\nFAILURES (%d failures)" % fails)
		finish()
		return

	var funcs: Array = _functions_of(src)
	print("  scanned %d functions" % funcs.size())
	ok(funcs.size() > 100, "found a plausible number of functions (%d)" % funcs.size())

	# ── A ──────────────────────────────────────────────────────────────────
	var col_hits: Array = []
	for f in funcs:
		var fn: Dictionary = f
		var name: String = str(fn["name"])
		var body: String = _code_only(str(fn["body"]))
		if ALLOW_COLUMN_SCAN.has(name) or KNOWN_UNTRIAGED_COLUMN.has(name):
			continue
		if not _iterates_records(body):
			continue
		# Signature only — a `star` local inside a row-shaped function is
		# ordinary; a star PARAMETER plus a record sweep is the column shape.
		var sig: String = body.substr(0, body.find(")") + 1) if body.find(")") > 0 else body
		if sig.contains("star: int") or sig.contains("star_idx: int") \
				or sig.contains("position: int"):
			col_hits.append(name)

	if not col_hits.is_empty():
		print("\n  --- A: hand-rolled column scans ---")
		for n in col_hits:
			print("    %s  takes a star and sweeps _match_records" % str(n))
		print("    Matrix-up answer: _stars_possible_for_descriptor(cat, value),")
		print("    or the column loop in _settle_identity_from_value_columns.")
		print("    Read this file's header before allowlisting anything.")
	ok(col_hits.is_empty(),
		"no NEW function answers a star-shaped question by sweeping records (%d)" % col_hits.size())

	# ── B ──────────────────────────────────────────────────────────────────
	var stub_hits: Array = []
	for f2 in funcs:
		var fn2: Dictionary = f2
		var name2: String = str(fn2["name"])
		var body2: String = _code_only(str(fn2["body"]))
		if ALLOW_STUB_BLIND.has(name2) or KNOWN_UNTRIAGED_STUB.has(name2):
			continue
		if not _iterates_records(body2):
			continue
		if not body2.contains("_effective_star_idx"):
			continue
		if body2.contains("_record_is_unconfirmed_star_widget_stub"):
			continue
		stub_hits.append(name2)

	if not stub_hits.is_empty():
		print("\n  --- B: stub-blind record sweeps ---")
		for n2 in stub_hits:
			print("    %s  reads _effective_star_idx across records, never checks for a stub" % str(n2))
		print("    Every star has a star_idx-bound record the moment its widget renders.")
		print("    Treating those as player knowledge has shipped three separate bugs.")
	ok(stub_hits.is_empty(),
		"no NEW record sweep is blind to auto-created star stubs (%d)" % stub_hits.size())

	# ── C: value-iterating passes must store on VALUES ────────────────────
	#
	# Added 2026-08-14 after a full sweep found THREE bugs of one shape that
	# rules A and B structurally cannot see — they look for record SWEEPS,
	# and every one of these was about where a conclusion is STORED.
	#
	# The distinction that makes it checkable: a pass that iterates RECORDS
	# can only ever conclude something about a record it already has, and
	# _stars_possible_for_descriptor derives a descriptor's row FROM records,
	# so a record write reaches the row for free. A pass that iterates VALUES
	# can conclude something about a descriptor with NO record at all — and
	# then a record-only write has nowhere to land and the fact is DISCARDED.
	#
	# So: a top-level `for … in _host._star_count` (indent depth 1 — a nested
	# one is inside a record loop and is record-driven) plus a conclusion
	# write means the pass MUST also go through _narrow_descriptor_row.
	#
	# This rule would have caught all three: _apply_distance_side (shipped,
	# reported from a live game), _settle_alldiff_position_exclusions, and
	# _settle_identity_from_value_columns.
	var store_hits: Array = []
	for f3 in funcs:
		var fn3: Dictionary = f3
		var name3: String = str(fn3["name"])
		var body3: String = _code_only(str(fn3["body"]))
		if not (name3.begins_with("_settle_") or name3.begins_with("_apply_")):
			continue
		if not _has_unenclosed_value_loop(body3):
			continue
		if not (body3.contains("_add_derived_state") or body3.contains("_derived[")):
			continue   # iterates values but concludes nothing
		if body3.contains("_narrow_descriptor_row"):
			continue   # stores on the value, as it must
		store_hits.append(name3)

	if not store_hits.is_empty():
		print("\n  --- C: value-iterating passes that store only on records ---")
		for n3 in store_hits:
			print("    %s  concludes about VALUES but writes only to records" % str(n3))
		print("    A descriptor with no record has nowhere for that write to land,")
		print("    so the conclusion is DISCARDED, not merely undisplayed.")
		print("    Route it through _narrow_descriptor_row.")
	ok(store_hits.is_empty(),
		"every value-iterating pass stores its conclusion on the VALUE (%d do not)"
			% store_hits.size())

	# ── D: a POSITION must not read IDENTITY off ground truth ─────────────
	#
	# Added 2026-08-16, ahead of the position-axis migration, because the
	# hazard it guards is invisible by construction: this codebase says
	# "star" for BOTH the map location and the named entity, and the new
	# POSITION axis makes them the SAME INTEGER. So
	#
	#     func _something(star: int) -> String:
	#         return star_names[star]
	#
	# reads as obviously correct while silently crossing from a position the
	# player is still solving to an identity only the generator knows. That
	# is characteristic-down in its purest form and no existing rule sees it,
	# because there is no record sweep and no value loop — just a subscript.
	#
	# The convention that makes it CHECKABLE is the whole point of the
	# convention: position-axis variables are named `pos`, never `star`.
	# Same integers, different word. Two halves, because one without the
	# other is trivially evaded:
	#
	#   D1 safety     — a `pos` parameter must not touch identity ground truth
	#   D2 convention — a POSITION-axis function must not call it `star`,
	#                   which is what would make D1 unenforceable
	#
	# SCOPE: this file ONLY — the player-side deduction engine. The first
	# draft also scanned the generator, and that was a TIER error, caught by
	# the user asking for a matrix-up review of the rule itself. The
	# generator holds 38 reads of these arrays against the deduction
	# engine's 8, and it MUST: it constructs the answer. A rule that fired
	# there would be allowlisted into silence, which this file's own header
	# calls being defeated rather than satisfied. The invariant is not
	# "positions must not read names" — it is "PLAYER-SIDE code must not read
	# ground truth", and that boundary is the FILE boundary.
	#
	# Only star_colors is exempt as observable; see IDENTITY_GROUND_TRUTH for
	# why pitch is NOT (LISTEN-gated), which the first draft also got wrong.
	#
	# KNOWN LIMIT, stated rather than hidden: keying on a parameter NAME is a
	# readability aid promoted to a check. The genuinely matrix-up rule is
	# about a PLANE — does this write into POSITION x NAME from something
	# other than clue closure — and that needs the closure to exist first.
	# Until then D is a tripwire, not a proof; REPLACE it when Phase 2 lands
	# rather than extending it.
	#
	# Both halves are INERT until the migration lands — there is no `pos:`
	# parameter and no Category.POSITION today. Rule C shipped inert TWICE on
	# two different wrong discriminators, so both halves here were verified by
	# planting a violation of each and confirming this file went red.
	var pos_hits: Array = []
	var naming_hits: Array = []
	for f4 in funcs:
		var fn4: Dictionary = f4
		var name4: String = str(fn4["name"])
		if ALLOW_POSITION_NAMING.has(name4):
			continue
		var body4: String = _code_only(str(fn4["body"]))
		var close: int = body4.find(")")
		var sig4: String = body4.substr(0, close + 1) if close > 0 else body4
		if sig4.contains("pos: int") or sig4.contains("pos_a: int") \
				or sig4.contains("pos_b: int"):
			for g2 in IDENTITY_GROUND_TRUTH:
				if body4.contains(str(g2)):
					pos_hits.append("%s  reads %s" % [name4, str(g2)])
					break
		if body4.contains("Category.POSITION") \
				and (sig4.contains("star: int") or sig4.contains("star_idx: int")):
			naming_hits.append(name4)

	if not pos_hits.is_empty():
		print("\n  --- D1: a position read an identity off ground truth ---")
		for n4 in pos_hits:
			print("    %s" % str(n4))
		print("    POSITION x NAME is what the PLAYER solves. A function that")
		print("    subscripts it from a position has answered the puzzle from")
		print("    the answer key. Colour is fine — it is drawn on the map.")
		print("    PITCH IS NOT: it is gated behind LISTEN (pitch_revealed).")
	ok(pos_hits.is_empty(),
		"no function turns a position into an identity via ground truth (%d)" % pos_hits.size())

	if not naming_hits.is_empty():
		print("\n  --- D2: POSITION-axis function calls its parameter `star` ---")
		for n5 in naming_hits:
			print("    %s" % str(n5))
		print("    Rename it `pos`. Same integer, different word — it is what")
		print("    lets D1, and a human reader, see the position/identity line.")
	ok(naming_hits.is_empty(),
		"every POSITION-axis function names its parameter `pos` (%d do not)" % naming_hits.size())

	# The allowlists are the load-bearing part of this file. If one grows
	# without its reason, the lint has been defeated rather than satisfied.
	var unreasoned: int = 0
	for k in ALLOW_COLUMN_SCAN:
		if str(ALLOW_COLUMN_SCAN[k]).strip_edges() == "":
			unreasoned += 1
	for k2 in ALLOW_STUB_BLIND:
		if str(ALLOW_STUB_BLIND[k2]).strip_edges() == "":
			unreasoned += 1
	for k5 in ALLOW_POSITION_NAMING:
		if str(ALLOW_POSITION_NAMING[k5]).strip_edges() == "":
			unreasoned += 1
	ok(unreasoned == 0, "every allowlist entry carries a reason (%d bare)" % unreasoned)

	# ── The debt, printed every run so it cannot fade into the background ──
	print("\n  --- OUTSTANDING, not reviewed (%d) ---"
		% (KNOWN_UNTRIAGED_COLUMN.size() + KNOWN_UNTRIAGED_STUB.size()))
	for k3 in KNOWN_UNTRIAGED_COLUMN:
		print("    [column] %s — %s" % [str(k3), str(KNOWN_UNTRIAGED_COLUMN[k3])])
	for k4 in KNOWN_UNTRIAGED_STUB:
		print("    [stub]   %s — %s" % [str(k4), str(KNOWN_UNTRIAGED_STUB[k4])])
	# Frozen at the count found when the lint was written. Growing it means
	# new debt was quarantined instead of fixed, which is the failure this
	# whole file exists to prevent.
	# Ratcheted down as items are triaged: 1 column / 4 stub when the lint was
	# written, then 1 / 0, now 0 / 0 — the backlog is CLEAR. Any future hit
	# must be fixed or promoted to a reasoned allowlist entry; it can no
	# longer be parked here.
	ok(KNOWN_UNTRIAGED_COLUMN.size() <= 0 and KNOWN_UNTRIAGED_STUB.size() <= 0,
		"the untriaged backlog has not grown (%d column, %d stub)"
			% [KNOWN_UNTRIAGED_COLUMN.size(), KNOWN_UNTRIAGED_STUB.size()])

	print("\nALL PASS (0 failures)" if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
