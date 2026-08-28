extends "res://dev_tests/test_base.gd"
# Covers the raw-vs-effective reader class: every UI-facing reader must see
# facts that arrive via ground truth (star_idx), slot labels, or derived
# narrowing — none of which land in the raw state dicts.
#
# Includes the reported Pyrios repro: a name record with two colours
# eliminated must rule itself out on those stars' name checklists.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
    if c: print("  PASS  ", s)
    else: print("  FAIL  ", s); fails += 1


func run() -> void:
    var host = OverlayScene.instantiate()
    root.add_child(host)
    await process_frame

    # 4 stars, one per colour, one note each (all singleton notes).
    host._constellation_id = 0
    host._star_count = 4
    host._star_names = ["Pyrios", "Beta", "Gamma", "Delta"]
    host._star_colors = [0, 3, 1, 2]        # Blue, Red, White, Yellow
    host._star_degrees = [2, 2, 3, 1]
    host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
    host._star_pitch_index = [0, 1, 2, 3]
    host._sequence_rank_solution = [0, 1, 2, 3]
    var d = host._deduction
    var w = host._widgets
    w.clear_pitch_caches()
    var WHITE: int = 1
    var YELLOW: int = 2
    var white_star: int = 2
    var yellow_star: int = 3

    # ---------------------------------------------------------------
    print("\n=== REPORTED CASE: name record with 2 colours eliminated ===")
    d._load_match_records([])
    for s in host._star_count:
        d._get_or_create_match_record_for_star_idx(s)     # widget stubs
    var pyrios: int = d._get_or_create_match_record_for_name("Pyrios")
    d._match_records[pyrios]["color_states"] = {WHITE: 2, YELLOW: 2}

    ok(d._star_elim_state(white_star, "Pyrios") != 2,
        "precondition: not yet ruled out before a refresh")
    d._full_propagation_refresh()
    ok(d._star_elim_state(white_star, "Pyrios") == 2,
        "white star's checklist now rules out Pyrios")
    ok(d._star_elim_state(yellow_star, "Pyrios") == 2,
        "yellow star's checklist now rules out Pyrios")
    ok(d._star_elim_state(0, "Pyrios") != 2,
        "blue star (still possible) NOT ruled out")

    # Releasing the eliminations must release the marks again.
    d._match_records[d._find_match_record_by_name("Pyrios")]["color_states"] = {}
    d._full_propagation_refresh()
    ok(d._star_elim_state(white_star, "Pyrios") != 2,
        "un-eliminating the colours releases the star marks")

    # ---------------------------------------------------------------
    print("\n=== generalised beyond colour: DEGREE narrowing reaches it too ===")
    d._load_match_records([])
    for s2 in host._star_count:
        d._get_or_create_match_record_for_star_idx(s2)
    var beta: int = d._get_or_create_match_record_for_name("Beta")
    # Degree 3 belongs only to star 2; eliminating it must rule star 2 out.
    d._match_records[beta]["degree_states"] = {3: 2}
    d._full_propagation_refresh()
    ok(d._star_elim_state(2, "Beta") == 2,
        "degree elimination reaches the star checklist (was colour-only)")

    # ---------------------------------------------------------------
    print("\n=== display readers see ground-truth / derived facts ===")
    d._load_match_records([])
    # A record pinned to star 0 at sequence position 1, pitch Listen-revealed.
    var rec: int = d._get_or_create_match_record_for_star_idx(0)
    d._match_records[rec]["pitch_revealed"] = true
    d._match_records[rec]["seq_lo"] = 1
    d._match_records[rec]["seq_hi"] = 1
    var true_note: String = w._note_name_for_star(0)

    var marker: Dictionary = d._melody_marker_for_position(1)
    ok(bool(marker["pitch_known"]) and str(marker["note_name"]) == true_note,
        "melody staff shows a Listen-revealed pitch (raw pitch_states is empty)")
    ok(d._known_color_for_seq_position(1) == host._star_colors[0],
        "melody staff colour resolves from star_idx ground truth")
    ok(d._display_color_for_record(rec) == host.STAR_COLORS_BY_IDX[host._star_colors[0]],
        "row tint resolves from star_idx ground truth")
    ok(w._confirmed_pitch_str_for_star(0) == true_note,
        "star tag shows the Listen-revealed pitch")
    ok(w._confirmed_sequence_str(0) == "1",
        "star tag shows the sequence position")
    # NAME IS THE HIDDEN AXIS, so a record bound to a star_idx with a
    # revealed pitch must NOT surrender its name — _effective_name_state
    # refuses the star_idx shortcut on purpose (a Pitch slot once showed an
    # unconfirmed star's true name because of it). The staff's name row
    # inherits that guard, and this asserts it before asserting the display.
    ok(d._known_name_for_seq_position(1) == "",
        "staff shows NO name for a star-bound record the player never identified (got '%s')"
            % d._known_name_for_seq_position(1))
    d._match_records[rec]["name"] = str(host._star_names[0])
    ok(d._known_name_for_seq_position(1) == str(host._star_names[0]),
        "and shows it once identity IS confirmed (got '%s')"
            % d._known_name_for_seq_position(1))

    # ---------------------------------------------------------------
    # A position pinned by DEDUCTION, not typed. All three staff readouts
    # ask _record_is_at_seq, which reads the effective candidate set; they
    # used to match on the record's own seq_lo/seq_hi and so drew "?" and an
    # uncoloured numeral over a position the player had solved. Same class
    # as d27d9c4's _find_match_record_by_exact_seq, found while adding the
    # name row that would have inherited it.
    print("\n=== staff readouts see a DERIVED position, not just a typed one ===")
    d._load_match_records([])
    var dr: int = d._get_or_create_match_record_for_star_idx(0)
    d._match_records[dr]["pitch_revealed"] = true
    d._match_records[dr]["seq_candidates"] = [1, 2]
    var other: int = d._get_or_create_match_record_for_star_idx(1)
    d._match_records[other]["seq_lo"] = 2
    d._match_records[other]["seq_hi"] = 2
    d._full_propagation_refresh()
    ok(int(d._match_records[dr]["seq_lo"]) == 0,
        "precondition: the pin is DERIVED — own seq_lo is still 0")
    ok(d._seq_candidate_set_for(dr) == [1],
        "precondition: and it resolves to position 1 (got %s)"
            % str(d._seq_candidate_set_for(dr)))
    var dmark: Dictionary = d._melody_marker_for_position(1)
    ok(bool(dmark["has_position"]), "the staff sees a position there at all")
    ok(bool(dmark["pitch_known"]), "and its pitch, rather than drawing '?'")
    ok(d._known_color_for_seq_position(1) == host._star_colors[0],
        "and its colour, so the numeral is tinted rather than left unknown")
    d._match_records[dr]["name"] = str(host._star_names[0])
    ok(d._known_name_for_seq_position(1) == str(host._star_names[0]),
        "and its name, once identity is confirmed (got '%s')"
            % d._known_name_for_seq_position(1))

    # ---------------------------------------------------------------
    print("\n=== leak guard still holds: un-listened stub must stay hidden ===")
    d._load_match_records([])
    var stub: int = d._get_or_create_match_record_for_star_idx(1)   # no pitch_revealed
    ok(d._displayable_pitch_for_record(stub) == "",
        "un-listened star-widget stub exposes no pitch")
    ok(w._confirmed_pitch_str_for_star(1) == "?",
        "star tag shows ? rather than leaking an un-earned pitch")

    print("")
    if fails == 0:
        print("=== ALL PASSED ===")
        quit(0)
    else:
        print("=== %d FAILED ===" % fails)
        quit(1)
    finish()
