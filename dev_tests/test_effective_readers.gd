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
