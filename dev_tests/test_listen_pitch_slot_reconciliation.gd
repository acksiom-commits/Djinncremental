extends "res://dev_tests/test_base.gd"
# Repro (reported 2026-08-29): two stars share one note. The player listens
# to star A first — its colour shows up fine on the Sort:Pitch tab. Later
# the player opens that tab (creating a blank "note B" placeholder for the
# still-unheard star B), then goes back and Listens to star B. Star B's
# colour never shows up on ITS Sort:Pitch slot, even though its pitch and
# star identity are both now fully known.
#
# Root cause: _reconcile_unique_pitch_slot only ever merged a freshly-
# confirmed Listen record into the Sort:Pitch tab when the WHOLE note was
# a singleton (_pitch_star_count == 1) — a shared note skipped
# reconciliation unconditionally, even in the case checked here where, by
# the time star B is heard, star A's slot is already resolved and star B's
# blank slot is the only remaining candidate for the merge.
#
# Covers both the case the fix should now catch (exactly one blank slot
# left) and the case it must still decline (two blank slots, genuinely
# ambiguous), so a future change can't "fix" the second case by silently
# guessing which star is which.

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
    # 4 stars, 3 distinct notes: stars 0 and 1 both play note index 0
    # ("A4"), so that note is shared by exactly two stars — the case
    # _reconcile_unique_pitch_slot used to refuse outright.
    host._constellation_id = 0
    host._star_count = 4
    host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
    host._star_colors = [0, 1, 2, 3]
    host._star_degrees = [2, 2, 3, 1]
    host._pitch_freqs = [440.0, 493.88, 523.25]
    host._star_pitch_index = [0, 0, 1, 2]
    host._sequence_rank_solution = [0, 1, 2, 3]


## Mirrors _on_pitch_listen_star_clicked's deduction-side sequence exactly
## (constellation_study_overlay.gd) without the UI/synth scaffolding around
## it, since that sequence — not the click plumbing — is what's under test.
func listen_to_star(d, w, star_idx: int, note: String) -> int:
    var record_idx: int = d._get_or_create_match_record_for_star_idx(star_idx)
    d._propagate_pitch_confirmed_same_record(record_idx, note)
    d.record_at(record_idx)["pitch_revealed"] = true
    record_idx = await d._reconcile_unique_pitch_slot(record_idx, note)
    return record_idx


func run() -> void:
    var host = setup_host()
    await process_frame
    configure(host)
    var d = host._deduction
    var w = host._widgets
    var note: String = w._note_name_for_star(0)   # shared by stars 0 and 1
    var freq: float = w._freq_for_note_name(note)
    ok(d._pitch_star_count(note) == 2, "sanity: %s is shared by two stars" % note)

    print("\n=== the rescued case: star A resolved first, star B is the LAST blank slot ===")
    d._load_match_records([])

    # Star A heard before the Sort:Pitch tab is ever opened — nothing to
    # reconcile against yet.
    var rec_a: int = await listen_to_star(d, w, 0, note)
    ok(d._known_color_for_record(rec_a) == 0, "star A's own record already knows its colour")

    # Tab opened: slot A ADOPTS star A's already-confirmed record; slot B
    # is created blank, since star B hasn't been heard yet.
    var slot_a: int = d._get_or_create_match_record_for_pitch_slot(freq, 0)
    var slot_b_before: int = d._get_or_create_match_record_for_pitch_slot(freq, 1)
    ok(slot_a == rec_a, "slot A adopted star A's record on tab-open, not a fresh blank")
    ok(d._known_color_for_record(slot_a) == 0, "Sort:Pitch slot A shows star A's colour")
    ok(d._known_color_for_record(slot_b_before) == -1, "sanity: slot B starts blank with no colour")

    # Star B heard later — the reported scenario. Slot B is now the ONLY
    # blank slot left for this note, so the merge is sound.
    var rec_b: int = await listen_to_star(d, w, 1, note)
    var slot_b_after: int = d._get_or_create_match_record_for_pitch_slot(freq, 1)
    ok(rec_b == slot_b_before, "star B's Listen record merged into the existing blank slot B")
    ok(slot_b_after == rec_b, "re-fetching slot B by label now returns the merged record")
    ok(d._known_color_for_record(slot_b_after) == 1,
        "THE BUG: Sort:Pitch slot B now shows star B's colour")
    ok(d._match_records.size() == 2, "the merge actually removed the orphan (2 records total, not 3)")

    print("\n=== the still-declined case: two blank slots, genuinely ambiguous ===")
    d._load_match_records([])

    # Tab opened FIRST, before either star is heard: both slots start blank.
    var slot_x: int = d._get_or_create_match_record_for_pitch_slot(freq, 0)
    var slot_y: int = d._get_or_create_match_record_for_pitch_slot(freq, 1)
    ok(d._known_color_for_record(slot_x) == -1 and d._known_color_for_record(slot_y) == -1,
        "sanity: both slots start blank")

    var rec_x: int = await listen_to_star(d, w, 0, note)
    ok(rec_x != slot_x and rec_x != slot_y,
        "star heard while TWO blank slots remain does not merge into either — still ambiguous")
    ok(d._known_color_for_record(rec_x) == 0,
        "the star's OWN record still knows its colour even though no slot linked to it yet")

    print("")
    if fails == 0:
        print("ALL PASS (0 failures)")
        quit(0)
    else:
        print("FAILURES (%d failures)" % fails)
        quit(1)
    finish()
