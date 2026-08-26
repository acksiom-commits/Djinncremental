extends "res://dev_tests/test_base.gd"
# VALUE_FACT_KINDS must list every non-Sequence fact kind.
#
# `disclosures` merges solver_facts (Sequence CSP input) and value_facts
# (Name closure input) into one array. _seq_facts_from_clues rebuilds the
# Sequence fact list after pruning by EXCLUDING everything in
# VALUE_FACT_KINDS -- so a kind missing from that list is silently handed
# to _solve() as an unknown Sequence fact.
#
# That failure is quiet in the worst way: _solve() ignores kinds it does
# not recognise, so the puzzle still generates and still passes its
# uniqueness gate. The only symptom is that pruning measures against a
# subtly different fact set than generation did.
#
# Two checks:
#   1. every kind in NAME_POSITION_PRED_KINDS is in VALUE_FACT_KINDS --
#      these two lists were introduced together and must stay in sync
#   2. every kind actually EMITTED as a value_fact by a real generated
#      puzzle is in VALUE_FACT_KINDS -- catches a new emitter added
#      without registering its kind, which check 1 cannot see
#
# Check 2 states its own denominator: "0 unregistered kinds" is also what
# a run that emitted no value_facts at all would report.

const SEED := 11
const CONSTELLATION := 0

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var puz = load("res://constellation_logic_puzzle.gd")

	var declared: Array = puz.VALUE_FACT_KINDS
	var predicate_kinds: Array = puz.NAME_POSITION_PRED_KINDS
	print("  VALUE_FACT_KINDS declares %d kinds" % declared.size())

	var missing_pred: Array = []
	for k in predicate_kinds:
		if not declared.has(k):
			missing_pred.append(k)
	ok(missing_pred.is_empty(),
		"every NAME_POSITION_PRED_KINDS entry is registered (missing: %s)" % str(missing_pred))

	# Generate one real puzzle and look at what actually got emitted.
	var cdef: Dictionary = cd.get_constellation_def(CONSTELLATION)
	var scn: int = int(cdef["star_count"])
	var g = puz.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, SEED, CONSTELLATION, cdef.get("name_theme", {}),
		cd.get_note_assignment(CONSTELLATION), cd.get_note_freqs(CONSTELLATION), null)
	await g._generate_clues_forms_attempt()

	# A value_fact is anything the Sequence solver has no branch for. The
	# Sequence kinds are exactly the ordinal_* family (see _solve's match
	# and _validate_sequence_fact), so anything NOT ordinal_* that shows up
	# in disclosures is a value fact and must be registered.
	var seen: Dictionary = {}
	var unregistered: Array = []
	var value_fact_total: int = 0
	for clue in g.chosen_form_clues:
		for f in (clue.get("disclosures", []) as Array):
			if not (f is Dictionary):
				continue
			var kind: String = str((f as Dictionary).get("kind", ""))
			if kind == "" or kind.begins_with("ordinal_"):
				continue
			value_fact_total += 1
			seen[kind] = int(seen.get(kind, 0)) + 1
			if not declared.has(kind) and not unregistered.has(kind):
				unregistered.append(kind)

	var kinds_seen: Array = seen.keys()
	kinds_seen.sort()
	print("  value-fact kinds emitted by a real puzzle: %s" % str(kinds_seen))
	print("  value facts emitted in total: %d" % value_fact_total)

	# Non-vacuity: 0 unregistered means nothing if 0 were emitted.
	ok(value_fact_total > 0,
		"the puzzle actually emitted value facts (%d) — otherwise the next check is vacuous" % value_fact_total)
	ok(unregistered.is_empty(),
		"every emitted value-fact kind is registered in VALUE_FACT_KINDS (unregistered: %s)" % str(unregistered))

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
