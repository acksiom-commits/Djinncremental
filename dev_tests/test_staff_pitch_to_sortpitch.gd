extends "res://dev_tests/test_base.gd"
# Repro: confirming a SINGLETON note on the Staff popup for sequence slot N
# should show up on that note's Sort:Pitch slot row.
#
# Covers BOTH orderings, because they take different code paths:
#   A. staff-check first, Sort:Pitch opened after  -> adopt path in
#      _get_or_create_match_record_for_pitch_slot
#   B. Sort:Pitch opened first (blank placeholder), staff-check after ->
#      must be rescued by _settle_identical_records
# and checks the RENDERED result, not just the record linkage, since a
# correct merge with a blank Sequence field looks identical to the player.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0

func ok(cond: bool, label: String) -> void:
    if cond:
        print("  PASS  ", label)
    else:
        print("  FAIL  ", label)
        fails += 1


func setup_host():
    var host = OverlayScene.instantiate()
    root.add_child(host)
    return host


func configure(host) -> void:
    # 4 stars, 4 distinct notes -> every note is a singleton, matching The
    # Archon (star_count == note_freqs.size() gives a 1:1 bijection).
    host._constellation_id = 0
    host._star_count = 4
    host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
    host._star_colors = [0, 1, 2, 3]
    host._star_degrees = [2, 2, 3, 1]
    host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
    host._star_pitch_index = [0, 1, 2, 3]
    host._sequence_rank_solution = [0, 1, 2, 3]


func report(d, w, target_note: String, slot_rec: int, label: String) -> void:
    print("    slot_record=%d  name='%s'  seq=%d..%d  pitch_label='%s'" % [
        slot_rec,
        str(d._match_records[slot_rec].get("name", "")),
        int(d._match_records[slot_rec].get("seq_lo", 0)),
        int(d._match_records[slot_rec].get("seq_hi", 0)),
        str(d._match_records[slot_rec].get("pitch_slot_label", "")),
    ])
    var bounds: Array = d._effective_seq_bounds(slot_rec)
    print("    effective bounds -> lo=%d hi=%d   (records total=%d)" % [
        int(bounds[0]), int(bounds[1]), d._match_records.size()])
    ok(int(d._match_records[slot_rec].get("seq_lo", 0)) == 4,
        "%s: Sort:Pitch %s row carries sequence 4" % [label, target_note])
    ok(int(bounds[0]) == 4 and int(bounds[1]) == 4,
        "%s: effective bounds render as the exact pin 4" % label)


func run() -> void:
    var host = setup_host()
    await process_frame
    configure(host)
    var d = host._deduction
    var w = host._widgets
    var note: String = w._note_name_for_star(3)   # star 3, true rank 3 -> slot 4
    print("target note = %s   singleton? %s" % [note, str(d._pitch_star_count(note) == 1)])
    var freq: float = w._freq_for_note_name(note)

    # ---- ORDER A: staff-check first, then open Sort:Pitch ----
    print("\n=== A. staff popup first, Sort:Pitch opened after ===")
    d._load_match_records([])
    var seq_rec_a: int = d._get_or_create_match_record_for_seq(4)
    w._on_staff_pitch_check(seq_rec_a, note, null)
    var slot_a: int = d._get_or_create_match_record_for_pitch_slot(freq, 0)
    report(d, w, note, slot_a, "A")

    # ---- ORDER B: Sort:Pitch opened first, then staff-check ----
    print("\n=== B. Sort:Pitch opened first (blank placeholder), staff-check after ===")
    d._load_match_records([])
    var slot_b0: int = d._get_or_create_match_record_for_pitch_slot(freq, 0)
    print("    blank placeholder created at idx %d" % slot_b0)
    var seq_rec_b: int = d._get_or_create_match_record_for_seq(4)
    ok(seq_rec_b != slot_b0, "sanity: staff slot made a separate record")
    w._on_staff_pitch_check(seq_rec_b, note, null)
    var slot_b: int = d._get_or_create_match_record_for_pitch_slot(freq, 0)
    report(d, w, note, slot_b, "B")

    print("")
    if fails == 0:
        print("=== ALL CHECKS PASSED ===")
        quit(0)
    else:
        print("=== %d CHECK(S) FAILED ===" % fails)
        quit(1)
    finish()
