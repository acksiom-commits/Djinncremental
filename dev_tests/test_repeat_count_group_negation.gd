extends "res://dev_tests/test_base.gd"
# Repeat Count — Form 24 (Group Negation), the third LIVE clue-generation
# user of Category.REPEAT (see planned_repeat_count_axis_design.md). Same
# rigor as Forms 12/23's own test modules.
#
# What must hold, and why each case exists:
#  - _build_form_group_negation must actually build a group with
#    group_cat == Category.REPEAT sometimes (only possible on a
#    non-degenerate constellation) -- otherwise every check below is
#    vacuous.
#  - Every such clue's text must render real words, never "?", and must
#    use the "repeats N times" predicate phrasing (never the "never
#    repeats" noun-phrase wording, which would read as a confusing double
#    negative inside "Neither X nor Y ___").
#  - The claim ("Neither/None of ... repeats N times [or ...]") must be
#    TRUE against ground truth: every named subject's repeat_count must
#    differ from the negated group's repeat_count value, checked
#    independently via the clue's own descriptor_not_in_group value_facts.
#  - The group's repeat_count value (group_key) must never be the -1
#    never-fires sentinel -- that would mean the group was defined by a
#    star whose note never actually repeats in the melody at all.
#  - A real end-to-end generated puzzle must still ship cleanly.
#  - A hard-mode (degenerate repeat_count) puzzle must never draw REPEAT
#    for this Form either.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
    if c:
        print("  PASS  ", s)
    else:
        print("  FAIL  ", s)
        fails += 1


func run() -> void:
    var cd = load("res://constellation_data.gd").new()
    var gc = load("res://game_context.gd").new()
    cd._game_context = gc
    gc.constellation_difficulty[0] = "easy"

    cd.player_seed = 11
    var def: Dictionary = cd.get_constellation_def(0)
    var scn: int = int(def["star_count"])
    var overlay_engine = load("res://click_sequence_puzzle_engine.gd").new()
    overlay_engine.set_constellation(0, cd, gc)
    var sq: Array = overlay_engine.get_correct_star_sequence(0)
    var g = PuzzleScript.new()
    g.difficulty = "easy"
    g.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
        cd.get_note_assignment(0), cd.get_note_freqs(0), null)
    g._build_record_array()
    g._build_matrix()

    print("=== drawing Group Negation directly, many times, matrix never committed ===")
    var repeat_facts: Array = []   # descriptor_not_in_group facts whose group_cat == REPEAT
    var repeat_clue_texts: Array = []
    var total_drawn: int = 0
    for i in 500:
        var clue: Dictionary = g._build_form_group_negation({})
        if clue.is_empty():
            continue
        total_drawn += 1
        var vf: Array = clue.get("value_facts", [])
        var hit: bool = false
        for f in vf:
            var fd: Dictionary = f
            if str(fd.get("kind", "")) == "descriptor_not_in_group" and int(fd.get("group_cat", -1)) == PuzzleScript.Category.REPEAT:
                repeat_facts.append(fd)
                hit = true
        if hit:
            repeat_clue_texts.append(str(clue.get("text", "")))
    ok(total_drawn > 0, "sanity: Group Negation actually produced some clues (got %d of 500 draws)" % total_drawn)
    ok(repeat_facts.size() > 0, "at least one draw built a REPEAT group (got %d descriptor_not_in_group facts) -- otherwise every check below is vacuous" % repeat_facts.size())

    print("\n=== every Repeat-group negation fact is well-formed and TRUE ===")
    var bad_truth: int = 0
    var bad_sentinel: int = 0
    for f2 in repeat_facts:
        var fd2: Dictionary = f2
        var subj_star: int = int(fd2.get("star", -1))
        var group_key: int = int(fd2.get("group_key", -999))
        if group_key < 0:
            bad_sentinel += 1
            print("    used the never-fires sentinel as the group's repeat value: group_key=%d" % group_key)
        if int(g.repeat_count[subj_star]) == group_key:
            bad_truth += 1
            print("    FALSE claim: subject star %d has repeat_count=%d, equal to the negated group's value %d" % [subj_star, g.repeat_count[subj_star], group_key])
    ok(bad_truth == 0, "every Repeat-group negation fact is actually true against ground truth (%d false of %d)" % [bad_truth, repeat_facts.size()])
    ok(bad_sentinel == 0, "no Repeat-group is ever defined by the -1 never-fires sentinel (%d bad of %d)" % [bad_sentinel, repeat_facts.size()])

    print("\n=== every clue text that used a REPEAT group is well-formed ===")
    var bad_text: int = 0
    var missing_phrase: int = 0
    for t in repeat_clue_texts:
        var text: String = str(t)
        if text.strip_edges() == "" or text.contains("?"):
            bad_text += 1
            print("    bad text: '%s'" % text)
        if not text.contains("repeats") or text.contains("never repeats"):
            missing_phrase += 1
            print("    missing/wrong predicate phrasing: '%s'" % text)
    ok(bad_text == 0, "no Repeat-group clue's text is blank or contains '?' (%d bad of %d)" % [bad_text, repeat_clue_texts.size()])
    ok(missing_phrase == 0, "every Repeat-group clue uses the 'repeats N times' phrasing, never 'never repeats' (%d bad of %d)" % [missing_phrase, repeat_clue_texts.size()])
    if not repeat_clue_texts.is_empty():
        print("    sample: %s" % str(repeat_clue_texts[0]))

    print("\n=== a real end-to-end generated puzzle still ships cleanly ===")
    var g2 = PuzzleScript.new()
    g2.difficulty = "easy"
    g2.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
        cd.get_note_assignment(0), cd.get_note_freqs(0), null)
    await g2.generate_clues_forms()
    ok(g2.gate_passed and not g2.chosen_form_clues.is_empty(),
        "a real puzzle still ships (gate_passed=%s, %d clues)" % [g2.gate_passed, g2.chosen_form_clues.size()])
    var broken: int = 0
    for c2 in g2.chosen_form_clues:
        var t2: String = str((c2 as Dictionary).get("text", ""))
        if t2.strip_edges() == "" or t2.strip_edges() == "?" or t2.contains(" ? "):
            broken += 1
            print("    broken clue text: '%s'" % t2)
    ok(broken == 0, "no clue anywhere in a real generated puzzle rendered as broken '?' text (got %d)" % broken)

    print("\n=== a hard-mode (degenerate repeat_count) puzzle never draws REPEAT ===")
    var cd3 = load("res://constellation_data.gd").new()
    cd3.player_seed = 11
    var def3: Dictionary = cd3.get_constellation_def(0)   # no GameContext -> hard mode
    var sq3: Array = []
    for i3 in range(int(def3["star_count"])):
        sq3.append(i3)
    var g3 = PuzzleScript.new()
    g3.setup(int(def3["star_count"]), def3["line_pairs"], sq3, 11, 0, def3.get("name_theme", {}),
        cd3.get_note_assignment(0), cd3.get_note_freqs(0), null)
    g3._build_record_array()
    g3._build_matrix()
    ok(g3._repeat_count_is_degenerate(), "sanity: hard-mode Archon's repeat_count is degenerate (all-zero)")
    var hard_repeat_draws: int = 0
    for i4 in 500:
        var clue3: Dictionary = g3._build_form_group_negation({})
        if clue3.is_empty():
            continue
        var vf3: Array = clue3.get("value_facts", [])
        for f3 in vf3:
            var fd3: Dictionary = f3
            if str(fd3.get("kind", "")) == "descriptor_not_in_group" and int(fd3.get("group_cat", -1)) == PuzzleScript.Category.REPEAT:
                hard_repeat_draws += 1
    ok(hard_repeat_draws == 0, "hard mode never draws Category.REPEAT for Group Negation (got %d of 500)" % hard_repeat_draws)

    if fails == 0:
        print("\nALL PASS (0 failures)")
    else:
        print("\nFAILURES (%d failures)" % fails)
    finish()
