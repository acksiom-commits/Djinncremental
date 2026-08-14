extends "res://dev_tests/test_base.gd"
# Exercises today's deduction changes against the REAL production classes:
# the record factory + save/load round-trip, identity unification, the
# general cardinality exclusion rule, the sync-merge conflict guard, and
# cell-model coverage including the negation case.
#
# No assert() (a failing one hangs the headless runner), no manual .free()
# on RefCounted, no NOTIFICATION_WM_CLOSE_REQUEST.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0

func ok(cond: bool, label: String) -> void:
    if cond:
        print("  PASS  ", label)
    else:
        print("  FAIL  ", label)
        fails += 1


func run() -> void:
    var host = OverlayScene.instantiate()
    root.add_child(host)
    # _ready() is DEFERRED in --script mode: without this the composed
    # _widgets/_deduction are still null and every call below aborts _init
    # before quit(), hanging the runner.
    await process_frame

    # 4-star constellation. Blue x2 (shared), White x1, Yellow x1.
    # Notes: star0 unique, stars 1+2 share, star3 unique.
    host._constellation_id = 0
    host._star_count = 4
    host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
    host._star_colors = [0, 0, 1, 2]
    host._star_degrees = [2, 2, 3, 1]
    host._pitch_freqs = [440.0, 493.88, 523.25]
    host._star_pitch_index = [0, 1, 1, 2]
    host._pitch_rank_solution = [0, 1, 2, 3]

    var d = host._deduction
    var w = host._widgets
    print("star_count=%d  notes=%s" % [host._star_count, str(w._distinct_note_names())])

    # ---------------------------------------------------------------
    print("\n=== 1. record factory + save/load round-trip ===")
    var i_name: int = d._get_or_create_match_record_for_name("Alpha")
    var i_seq: int  = d._get_or_create_match_record_for_seq(3)
    var i_star: int = d._get_or_create_match_record_for_star_idx(2)
    var expected_keys: Array = d._new_match_record().keys()
    ok(d._match_records[i_name].keys().size() == expected_keys.size(),
        "factory-built name record has the full field set")
    ok(str(d._match_records[i_name]["name"]) == "Alpha", "name override applied")
    ok(int(d._match_records[i_seq]["seq_lo"]) == 3 and int(d._match_records[i_seq]["seq_hi"]) == 3,
        "seq override applied")
    ok(int(d._match_records[i_star]["star_idx"]) == 2, "star_idx override applied")

    d._match_records[i_name]["name_states"] = {"Beta": 2}
    var saved: Array = d._save_match_records()
    d._load_match_records(saved)
    ok(d._match_records.size() == 3, "round-trip preserved record count")
    var reloaded: Dictionary = d._match_records[0]
    ok(reloaded.keys().size() == expected_keys.size(), "round-trip preserved full field set")
    ok(int((reloaded.get("name_states", {}) as Dictionary).get("Beta", 0)) == 2,
        "round-trip preserved a nested state value")
    # A save written before a field existed must come back with its default.
    var stripped: Array = [{"name": "Solo"}]
    d._load_match_records(stripped)
    ok(d._match_records[0].keys().size() == expected_keys.size(),
        "legacy save missing fields is backfilled with defaults")

    # ---------------------------------------------------------------
    print("\n=== 2. identity unification via singleton pitch (Helios/C#5 case) ===")
    d._load_match_records([])
    var note0: String = w._note_name_for_star(0)      # unique to star 0
    var note1: String = w._note_name_for_star(1)      # shared by stars 1 and 2
    ok(d._pitch_star_count(note0) == 1, "sanity: %s is a singleton note" % note0)
    ok(d._pitch_star_count(note1) == 2, "sanity: %s is shared by two stars" % note1)

    var by_name: int = d._get_or_create_match_record_for_name("Alpha")
    d._match_records[by_name]["pitch_states"] = {note0: 1}      # player assigned
    var by_star: int = d._get_or_create_match_record_for_star_idx(0)
    d._match_records[by_star]["pitch_revealed"] = true          # Listen revealed
    ok(d._records_provably_identical(by_name, by_star),
        "name-record and Listen-revealed star-record recognised as the same star")

    # CHANGED 2026-08-14. This used to assert the two records FUSED into one
    # (_match_records.size() == 1). That mechanism is gone on this path:
    # _settle_identical_records no longer folds anything into an
    # auto-created star-widget stub, because a merge is destructive and
    # permanent while this pass is the engine INFERRING identity — so an
    # inference the player can retract produced a consequence they could
    # not. (Reported 2026-08-14: naming a Sort:Pitch slot permanently
    # identified its star on the map, and UNDO could not take it back.)
    #
    # The CAPABILITY this section protects is unchanged and is what is
    # asserted now: the engine still recognises the two as one star, and
    # the name record still resolves to that star. Only the destructive
    # fusion is gone — the identity rides in the derived layer, where it
    # releases when its premise does.
    #
    # The player's own confirm path still merges, deliberately:
    # _confirm_match_record_identity calls _merge_match_records directly.
    d._settle_identical_records()
    ok(d._match_records.size() == 2, "the inferring pass does NOT destroy either record")
    d._full_propagation_refresh()
    ok(d._effective_star_idx(by_name) == 0,
        "the name record still resolves to star 0 (eff_star=%d)" % d._effective_star_idx(by_name))
    ok(str(d._match_records[by_name]["name"]) == "Alpha",
        "and it still carries its name")

    # Shared note must NOT prove identity.
    d._load_match_records([])
    var n_b: int = d._get_or_create_match_record_for_name("Beta")
    d._match_records[n_b]["pitch_states"] = {note1: 1}
    var s_c: int = d._get_or_create_match_record_for_star_idx(1)
    d._match_records[s_c]["pitch_revealed"] = true
    ok(not d._records_provably_identical(n_b, s_c),
        "a SHARED note does not prove identity")

    # ---------------------------------------------------------------
    print("\n=== 3. cardinality exclusion beyond k=1 (the Blue/G4+A#4 case) ===")
    d._load_match_records([])
    # Two distinct records both confirm the shared note -> both carriers
    # accounted for -> excluded from a third, distinct record.
    var r1: int = d._get_or_create_match_record_for_name("Alpha")
    var r2: int = d._get_or_create_match_record_for_name("Beta")
    var r3: int = d._get_or_create_match_record_for_name("Gamma")
    d._match_records[r1]["pitch_states"] = {note1: 1}
    d._match_records[r2]["pitch_states"] = {note1: 1}
    d._clear_deduction_caches()
    var excl: Array = d._compute_excluded_pitches_for(r3)
    ok(excl.has(note1),
        "shared note (incidence 2) excluded once 2 distinct records confirm it")

    # With only ONE confirmer it must NOT be excluded.
    d._load_match_records([])
    var q1: int = d._get_or_create_match_record_for_name("Alpha")
    var q3: int = d._get_or_create_match_record_for_name("Gamma")
    d._match_records[q1]["pitch_states"] = {note1: 1}
    d._clear_deduction_caches()
    ok(not d._compute_excluded_pitches_for(q3).has(note1),
        "one confirmer of a 2-star note excludes nothing (still unsound)")

    # Same rule on Colour: Blue has 2 stars.
    d._load_match_records([])
    var c1: int = d._get_or_create_match_record_for_name("Alpha")
    var c2: int = d._get_or_create_match_record_for_name("Beta")
    var c3: int = d._get_or_create_match_record_for_name("Gamma")
    d._match_records[c1]["color_states"] = {0: 1}
    d._match_records[c2]["color_states"] = {0: 1}
    d._clear_deduction_caches()
    ok(d._compute_excluded_colors_for(c3).has(0),
        "Blue (incidence 2) excluded once both Blue slots are spoken for")

    # ---------------------------------------------------------------
    print("\n=== 4. sync-merge conflict guard ===")
    d._load_match_records([])
    var m1: int = d._get_or_create_match_record_for_name("Alpha")
    var m2: int = d._get_or_create_match_record_for_name("Beta")
    d._match_records[m1]["seq_lo"] = 2; d._match_records[m1]["seq_hi"] = 2
    d._match_records[m2]["seq_lo"] = 2; d._match_records[m2]["seq_hi"] = 2
    var kinds: Array = d._merge_conflict_kinds(m1, m2)
    ok(kinds.has("name"), "conflicting names reported by _merge_conflict_kinds")
    ok(d._records_have_merge_conflict(m1, m2), "delegate agrees with the kinds list")
    var before: int = d._match_records.size()
    d._merge_match_records(m1, m2, false)   # must refuse, must not suspend
    ok(d._match_records.size() == before,
        "allow_await=false refuses a conflicting merge instead of suspending")

    # ---------------------------------------------------------------
    print("\n=== 5. cell-model coverage, including negation ===")
    d._load_match_records([])
    var SEQ: int = ConstellationLogicPuzzle.Category.SEQUENCE
    var NAME: int = ConstellationLogicPuzzle.Category.NAME
    # "Neither Alpha nor Beta fires 3rd"  ->  two is_true=false cells.
    var neg_cells: Array = [
        {"cat_a": NAME, "star_a": 0, "cat_b": SEQ, "star_b": 2, "is_true": false},
        {"cat_a": NAME, "star_a": 1, "cat_b": SEQ, "star_b": 2, "is_true": false},
    ]
    ok(d._clue_coverage_fraction(neg_cells) == 0.0, "negation clue starts uncovered")

    # Star 2's true rank is 2 -> player-facing slot 3. X both names there.
    var slot: int = d._get_or_create_match_record_for_seq(3)
    d._match_records[slot]["name_states"] = {"Alpha": 2, "Beta": 2}
    d._clear_deduction_caches()
    ok(d._clue_coverage_fraction(neg_cells) == 1.0,
        "recording the two ELIMINATIONS fully covers the negation clue")

    print("")
    if fails == 0:
        print("=== ALL CHECKS PASSED ===")
        quit(0)
    else:
        print("=== %d CHECK(S) FAILED ===" % fails)
        quit(1)
    finish()
