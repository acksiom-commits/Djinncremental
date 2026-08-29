extends "res://dev_tests/test_base.gd"
# COPY writes a checklist's still-open values into the Notes tab.
#
# Per user direction 2026-08-27: a copy button on tab slots and popups takes
# "the still-unexcluded items", makes a pastable string, and puts it in the
# Notes tab, "with the header being whatever tab slot or popup section the
# information was taken from". Destination, filter and granularity were
# confirmed: straight into Notes (not the OS clipboard), drop hard-X AND
# soft-eliminated, one button per section.
#
# THE FILTER IS THE PART WORTH PINNING. State 2 is a hard X and state 3 is
# soft-eliminated (a sibling on the row is protected) — both mean "ruled
# out", so both are dropped. 0 neutral, 1 confirmed and 4 protected all
# stay. Getting 3 wrong is the silent failure: the list would look right
# while offering values the engine has already derived as impossible.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
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
	w.clear_pitch_caches()

	# A record with NO confirmed name. _get_or_create_match_record_for_name
	# sets r["name"], which _effective_name_state treats as a confirmed
	# identity and so rules out every other name — a perfectly correct
	# collapse, and useless for testing a filter. A position record is both
	# the realistic case (the player is staring at a Staff popup) and the one
	# where several names are genuinely still open.
	print("=== the filter: 2 (hard X) and 3 (soft) are dropped, 0/1/4 kept ===")
	d._load_match_records([])
	var rec: int = d._get_or_create_match_record_for_seq(2)
	# NO confirmed name in this case, deliberately. State 1 is an identity
	# confirmation: the engine promotes it to the record's `name` and every
	# other name correctly collapses to 2. So "confirmed" cannot coexist
	# with "still open" — asserting both in one list tests a board that
	# cannot exist. Confirmation gets its own case below.
	d._match_records[rec]["name_states"] = {
		"Selion": 2,   # hard X    -> dropped
		"Pyrios": 3,   # soft-elim -> dropped
		"Helios": 4,   # protected -> kept
	}                  # Keriion/Eos/Zeta stay 0 -> kept
	d._full_propagation_refresh()
	d._note_entries.clear()
	w._on_staff_copy(rec, "name")

	ok(d._note_entries.size() == 1,
		"one Notes entry was written (got %d)" % d._note_entries.size())
	var entry: String = str(d._note_entries[0]) if not d._note_entries.is_empty() else ""
	print("    entry: %s" % entry)
	ok(entry.begins_with("Note 2 — Name:"),
		"header names the source — the slot and the section (got '%s')" % entry)
	ok(not entry.contains("Selion"), "a hard-X name (2) is absent")
	ok(not entry.contains("Pyrios"),
		"a SOFT-eliminated name (3) is absent too — the rule most easily got wrong")
	ok(entry.contains("Helios"), "a protected name (4) is kept")
	ok(entry.contains("Zeta"), "an untouched name (0) is kept")

	print("\n=== a confirmed identity copies as itself alone ===")
	d._load_match_records([])
	var conf: int = d._get_or_create_match_record_for_name("Keriion")
	d._full_propagation_refresh()
	d._note_entries.clear()
	w._on_staff_copy(conf, "name")
	var ec: String = str(d._note_entries[0]) if not d._note_entries.is_empty() else ""
	print("    entry: %s" % ec)
	ok(ec == "Keriion — Name: Keriion",
		"a confirmed record copies one name, headed by it (got '%s')" % ec)

	print("\n=== a name another record has claimed is excluded too ===")
	# The popups fold in a cross-record exclusion AFTER reading state: a
	# value a provably-different record has confirmed is X'd here, even
	# though nothing about it lives in THIS record's own state dict. The
	# copy has to reproduce that second step, or it lists values the popup
	# beside it is drawing as struck out.
	d._load_match_records([])
	var mine: int = d._get_or_create_match_record_for_seq(2)
	var theirs: int = d._get_or_create_match_record_for_name("Zeta")
	d._match_records[theirs]["seq_lo"] = 5
	d._match_records[theirs]["seq_hi"] = 5
	d._full_propagation_refresh()
	ok(d._records_provably_distinct(mine, theirs),
		"precondition: the two records are provably different stars")
	ok(d._compute_excluded_names_for(mine).has("Zeta"),
		"precondition: so Zeta is cross-record excluded here")
	d._note_entries.clear()
	w._on_staff_copy(mine, "name")
	var ex: String = str(d._note_entries[0]) if not d._note_entries.is_empty() else ""
	print("    entry: %s" % ex)
	ok(not ex.contains("Zeta"),
		"a name taken by another record is absent from the copy (got '%s')" % ex)

	print("\n=== a position with no name yet is headed by its NOTE number ===")
	d._load_match_records([])
	var pos: int = d._get_or_create_match_record_for_seq(3)
	d._full_propagation_refresh()
	d._note_entries.clear()
	w._on_staff_copy(pos, "color")
	var e2: String = str(d._note_entries[0]) if not d._note_entries.is_empty() else ""
	print("    entry: %s" % e2)
	ok(e2.begins_with("Note 3 — Color:"),
		"an unidentified slot is headed by its sequence position (got '%s')" % e2)

	print("\n=== everything ruled out still records a line ===")
	d._load_match_records([])
	var rec3: int = d._get_or_create_match_record_for_seq(4)
	var all_out: Dictionary = {}
	for n in host._star_names:
		all_out[str(n)] = 2
	d._match_records[rec3]["name_states"] = all_out
	d._full_propagation_refresh()
	d._note_entries.clear()
	w._on_staff_copy(rec3, "name")
	var e3: String = str(d._note_entries[0]) if not d._note_entries.is_empty() else ""
	print("    entry: %s" % e3)
	ok(d._note_entries.size() == 1,
		"a fully-eliminated list still writes an entry rather than silently doing nothing")
	ok(e3.contains("(none left)"),
		"and says so explicitly — that state means the board contradicts itself (got '%s')" % e3)

	print("\n=== the copy is a real note: it persists and can be removed ===")
	d._save_puzzle_notes()
	var before: int = d._note_entries.size()
	d.remove_note_entry(0)
	ok(d._note_entries.size() == before - 1,
		"a copied entry is removable exactly like a typed one (%d -> %d)"
			% [before, d._note_entries.size()])

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
