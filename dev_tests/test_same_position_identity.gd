extends "res://dev_tests/test_base.gd"
# A record narrowed to ONE sequence position, and the Staff popup for that
# position, are the same star — and nothing used to connect them.
#
# Sequence is alldiff, so this is a proof, not a heuristic. But it cannot
# drive a merge: the narrowing is DERIVED, merges are destructive, and the
# derived layer is wiped every refresh. So the two records share their facts
# through the derived layer instead, and the sharing dies with its cause.
#
# Three symptoms of the one gap, all reported live (Chroneeia/6,
# Keraides/14):
#   * the Staff popup kept offering a magenta "still possible" pair that the
#     Sort:Name row had already resolved,
#   * the second name never promoted to a confirm even though every other
#     name was ruled out or taken,
#   * the Sort:Name row never received the popup's own pitch eliminations.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	# _ready() is DEFERRED in --script mode: _widgets/_deduction are still
	# null until a frame has passed, and touching one aborts _init silently.
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33, 622.25]
	host._star_pitch_index = [0, 1, 2, 3, 4, 5]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	var d = host._deduction
	var w = host._widgets
	host._widgets.clear_pitch_caches()

	# ── 1. the narrowing is recorded even when the position is "taken" ──
	# _settle_singleton_sequences used to refuse to record a derived pin when
	# _find_match_record_by_exact_seq already returned some other record.
	# That guard fired precisely when the Staff popup for the position
	# existed — the one case where the two records need to find each other —
	# and left the narrowing invisible to every cross-record reader.
	print("\n=== 1. a derived position pin survives a popup owning that slot ===")
	d._load_match_records([])
	var pyr: int = d._get_or_create_match_record_for_name("Pyrios")
	d._match_records[pyr]["seq_candidates"] = [3, 5]
	var pop5: int = d._get_or_create_match_record_for_seq(5)
	var hel: int = d._get_or_create_match_record_for_name("Helios")
	d._match_records[hel]["seq_lo"] = 3
	d._match_records[hel]["seq_hi"] = 3
	d._full_propagation_refresh()

	ok(d._effective_seq_candidates(pyr) == [5],
		"Pyrios narrows to position 5 (got %s)" % str(d._effective_seq_candidates(pyr)))
	ok(d._seq_candidate_set_for(pyr) == [5],
		"and the pin is VISIBLE to other records (got %s)" % str(d._seq_candidate_set_for(pyr)))

	# ── 2. facts flow both ways between the two same-position records ──
	print("\n=== 2. the name row and the position popup share what they know ===")
	ok(d._effective_name_state(pop5, "Pyrios") == 1,
		"the position-5 popup now shows Pyrios confirmed")
	var others_gone: bool = true
	for n in host._star_names:
		if str(n) != "Pyrios" and d._effective_name_state(pop5, str(n)) != 2:
			others_gone = false
	ok(others_gone, "and every other name on that popup is ruled out")

	print("\n=== 3. and the popup's own marks reach the name row ===")
	var note: String = str(w._note_name_for_star(1))   # a note nobody has claimed
	d._match_records[pop5]["pitch_states"] = {note: 2}
	d._full_propagation_refresh()
	ok(d._effective_pitch_state(pyr, note) == 2,
		"%s eliminated on the popup shows up on the Sort:Name row" % note)

	# ── 4. release ──
	print("\n=== 4. the sharing dies with the narrowing that justified it ===")
	d._match_records[hel]["seq_lo"] = 0
	d._match_records[hel]["seq_hi"] = 0
	d._full_propagation_refresh()
	ok(d._effective_seq_candidates(pyr).size() > 1,
		"Pyrios is open again (got %s)" % str(d._effective_seq_candidates(pyr)))
	ok(d._effective_name_state(pop5, "Pyrios") != 1,
		"the popup no longer claims Pyrios")
	ok(d._effective_pitch_state(pyr, note) == 0,
		"and the borrowed pitch elimination is gone from the name row")

	# ── 4b. the popup OPENED AFTER the refresh, which is the live order ──
	# Everything above creates the popup record BEFORE
	# _full_propagation_refresh(), so the fixpoint sees both records and
	# wires them together. THE GAME DOES THE OPPOSITE: the refresh has
	# already run, and _open_staff_popup then calls
	# _get_or_create_match_record_for_seq, which appends a record and calls
	# only _sync_derived_size(). Nothing runs the fixpoint in between.
	#
	# Reported 2026-08-27:
	#   "Player has locked Keriion down as Sequence 8, and also an A4 star
	#    which means it's either yellow or red, but that did not propagate
	#    to the Staff popup for sequence 8. It DOES show up correctly on
	#    Keriion's Name tab slot entries for Color."
	#
	# _find_match_record_by_exact_seq read the record's OWN seq_lo/seq_hi, so
	# a DERIVED pin was invisible to it and a second, empty record was
	# created for that position — a blank popup beside a correct Name tab,
	# for the same star. The same mistake _seq_singleton_owners had already
	# fixed once and this site kept.
	print("\n=== 4b. a popup opened after the refresh finds the derived pin ===")
	d._load_match_records([])
	var ker: int = d._get_or_create_match_record_for_name("Keriion")
	d._match_records[ker]["seq_candidates"] = [3, 5]
	var sel: int = d._get_or_create_match_record_for_name("Selion")
	d._match_records[sel]["seq_lo"] = 5
	d._match_records[sel]["seq_hi"] = 5
	d._match_records[ker]["color_states"] = {1: 2}
	d._full_propagation_refresh()
	ok(d._seq_candidate_set_for(ker) == [3],
		"Keriion is pinned to position 3 by DERIVATION, not by seq_lo (own seq_lo=%s)"
			% str(d._match_records[ker]["seq_lo"]))
	ok(d._effective_color_state(ker, 1) == 2,
		"and its own row knows colour 1 is out — the Name-tab surface that worked")
	var n_before: int = d._match_records.size()
	var pop3: int = d._get_or_create_match_record_for_seq(3)
	ok(pop3 == ker,
		"the popup for position 3 resolves to Keriion's record (got %d, want %d)" % [pop3, ker])
	ok(d._match_records.size() == n_before,
		"no duplicate record for a position already pinned (%d -> %d)"
			% [n_before, d._match_records.size()])
	ok(d._effective_color_state(pop3, 1) == 2,
		"so the Staff popup sees the colour elimination (got %d)"
			% d._effective_color_state(pop3, 1))

	# ── 5. cross-record name exclusion feeds the singleton promotion ──
	# _settle_singleton_names counted through _effective_name_state, which
	# knows nothing about a name another record has already claimed. A popup
	# showing the player exactly one remaining name still counted two.
	print("\n=== 5. last-name-standing counts names taken elsewhere ===")
	d._load_match_records([])
	var pop2: int = d._get_or_create_match_record_for_seq(2)
	d._match_records[pop2]["name_states"] = {
		"Keriion": 2, "Selion": 2, "Pyrios": 2, "Helios": 2,
	}
	var eos: int = d._get_or_create_match_record_for_name("Eos")
	d._match_records[eos]["seq_lo"] = 4
	d._match_records[eos]["seq_hi"] = 4
	d._full_propagation_refresh()
	ok(d._records_provably_distinct(pop2, eos),
		"sanity: the two records are provably different stars")
	ok(d._effective_name_state(pop2, "Eos") == 2,
		"Eos is ruled out on the popup because another record holds it")
	ok(d._effective_name_state(pop2, "Zeta") == 1,
		"so the one name left standing is confirmed (this never fired before)")

	# ── 6. a disagreeing pair is never absorbed by the sharing ──
	# Two records raw-pinned to one position both carry an "S:<pos>" identity
	# token, so they go through the merge pass first. A value clash makes it
	# refuse, and both survive — still sitting on the same position. The
	# sharing pass must not then quietly finish the job the merge declined.
	print("\n=== 6. sharing refuses a pair the merge already refused ===")
	d._load_match_records([])
	var one_a: int = d._get_or_create_match_record_for_seq(1)
	d._match_records[one_a]["color_states"] = {1: 1}
	var one_b: int = d._get_or_create_match_record_for_name("Keriion")
	d._match_records[one_b]["seq_lo"] = 1
	d._match_records[one_b]["seq_hi"] = 1
	d._match_records[one_b]["color_states"] = {1: 2}
	var before: int = d.record_count()
	d._full_propagation_refresh()

	ok(d.record_count() == before,
		"both records survive the refused merge (%d -> %d)" % [before, d.record_count()])
	ok(d._records_provably_distinct(one_a, one_b),
		"sanity: they are provably different stars")
	ok(d._seq_candidate_set_for(one_a) == [1] and d._seq_candidate_set_for(one_b) == [1],
		"sanity: and both are still on position 1")
	ok(d._effective_color_state(one_a, 1) == 1 and d._effective_color_state(one_b, 1) == 2,
		"neither colour mark was absorbed by the other")
	ok(d._effective_name_state(one_a, "Keriion") != 1,
		"and the position record did not adopt the other's name")
	var reported: bool = false
	for c in d._contradictions:
		if str((c as Dictionary).get("axis", "")) == "merge":
			reported = true
			print("      %s" % str((c as Dictionary).get("text", "")))
	ok(reported, "the disagreement is still reported")

	# ── 7. no leak out of a bare star-widget record ──
	# Every star gets a star_idx-bound record the moment its widget is drawn,
	# and that star_idx is unearned — every _effective_*_state reads ground
	# truth off it. Such a record must never be a sharing SOURCE.
	#
	# Tested by calling the sharing directly. A bare stub has no sequence
	# information at all, so it cannot reach the pass through the normal
	# route — the guard is there for the day something gives it some.
	print("\n=== 7. an unlistened star-widget record leaks nothing ===")
	d._load_match_records([])
	var pop6: int = d._get_or_create_match_record_for_seq(6)
	var stub: int = d._get_or_create_match_record_for_star_idx(3)
	ok(d._record_is_unconfirmed_star_widget_stub(stub),
		"sanity: the star-widget record is an unconfirmed stub")
	ok(not bool(d.record_at(stub).get("pitch_revealed", false)),
		"sanity: and Listen has not revealed it")
	d._share_derived_facts(stub, pop6)
	var leaked: Array[String] = []
	for n2 in w._distinct_note_names():
		if d._effective_pitch_state(pop6, str(n2)) != 0:
			leaked.append(str(n2))
	ok(leaked.is_empty(), "no pitch was copied out of it (got %s)" % str(leaked))
	var col_leaked: Array[int] = []
	for ci in host.COLOR_NAME_LABELS.size():
		if d._effective_color_state(pop6, int(ci)) != 0:
			col_leaked.append(int(ci))
	ok(col_leaked.is_empty(), "nor its colour (got %s)" % str(col_leaked))
	ok(d._effective_star_idx(pop6) < 0,
		"and the popup was not bound to that star (got %d)" % d._effective_star_idx(pop6))

	# The same record IS a legitimate sharing target, though.
	d._match_records[pop6]["name_states"] = {"Eos": 1}
	d._share_derived_facts(pop6, stub)
	ok(d._effective_name_state(stub, "Eos") == 1,
		"but sharing INTO a stub still works")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
