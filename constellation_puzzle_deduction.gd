class_name ConstellationPuzzleDeduction
extends RefCounted

# ── BEFORE EDITING THIS FILE ────────────────────────────────────────────
# A PreToolUse hook (.claude/settings.json) injects the MATRIX-UP CHECKPOINT
# into context on every edit to this file. It is there because reasoning
# DOWN from stars instead of UP from the cell matrix has produced a bug
# every single time, across weeks, and memory notes / comments / a lint all
# failed to stop it — each of them required the author to remember to look.
# The hook does not.
#
# The five questions, in short: what UNIT is this reasoning over; where does
# the conclusion get STORED; which TIER am I reading through; do I need
# guards (if so, suspect the unit); and is the fix a MISSING rule.
# See dev_tests/test_matrix_up_lint.gd for the mechanical half.

# Deduction-engine half of the Constellation Study Overlay split (see
# docs/early_game_architecture_overview.md, §4, and the refactor plan this
# executes). Owns _match_records and everything that reads/mutates it —
# get-or-create lookups, elimination propagation, merge/conflict logic,
# save/load. Depends on nothing but data: reads ground-truth arrays and
# node-independent config off _host (star names/colors/counts, pitch
# tables, etc. — none of that is deduction's own state, so it stays on the
# host rather than being duplicated here), and the one place it needs to
# put something on screen mid-computation (the conflict-choice dialog) goes
# through the injected _conflict_dialog_fn Callable instead of reaching
# into the widgets file directly.
#
# Being built up incrementally, one independently headless-boot-verified
# slice at a time, same pattern as constellation_puzzle_widgets.gd.
# Progress: Slice A (ownership wiring + 4 scattered functions) in progress.

var _host: ConstellationStudyOverlay = null

# Shared puzzle-state color palette — see puzzle_state_colors.gd.
const STATE_COLORS: PuzzleStateColors = preload("res://puzzle_state_colors.tres")

# Deduction code (_merge_match_records/_confirm_match_record_identity) asks
# for a conflict choice through this instead of calling the widgets file's
# _show_conflict_choice directly — keeps this file's only "put something on
# screen" dependency behind one injected seam.
var _conflict_dialog_fn: Callable = Callable()

# The star widget's own per-star name checklist used to keep its protect
# and manual-block flags in two GLOBAL dicts keyed "star_idx:name",
# separate from the identical per-record fields every other surface uses
# (protected_staff_names / manual_name_blocks). That wasn't just
# duplication: because they were keyed by star and lived outside
# _match_records, _merge_match_records never merged them, so those flags
# sat entirely outside propagation, save-merging, and every settle pass.
# They now live on the star's own record, where the keying is identical
# (by name) and the existing merge/save paths pick them up for free.
# See _star_name_flags_record() below.

# Match records — one per set of facts the player has asserted belong to the same star.
# Each record: {
#   "name": String,              # "" if unknown
#   "seq_lo": int, "seq_hi": int, # 0 if unknown; exact position known when seq_lo == seq_hi > 0
#   "seq_candidates": Array,      # explicit narrowed set of possible sequence slots, if any
#   "color_states": Dictionary,   # {color_idx(int): state(int)} 0=neutral, 1=confirmed, 2=eliminated
#   "pitch_states": Dictionary,   # {note_name(String): state(int)}
#   "degree_states": Dictionary,  # {degree(int): state(int)}
#   "name_states": Dictionary,    # {name(String): state(int)}
#   "repeat_states": Dictionary,  # {repeat_count_value(int): state(int)} -- NEW
#                                 # axis (2026-09-29), same 0/1/2/3/4 vocabulary,
#                                 # but NOT alldiff: multiple records can validly
#                                 # confirm the SAME value (most stars share 0).
#                                 # See planned_repeat_count_axis_design.md.
#   "manual_name_blocks": Dictionary,   # {name(String): true} — names the player
#   "manual_pitch_blocks": Dictionary,  # X'd directly, as opposed to state-2
#   "manual_color_blocks": Dictionary,  # entries that are fallout from confirming
#   "manual_repeat_blocks": Dictionary, # a sibling value. Lets the Undo row tell
#                                        # "Undo selects" (revert sibling-clearing
#                                        # fallout only) apart from "Undo blocks"
#                                        # (revert the player's own X clicks only).
#   "protected_pitch_notes": Dictionary,  # {note_name(String): true} — right-click
#   "protected_color_idxs": Dictionary,   # "still possible" flags, one dict per
#   "protected_staff_names": Dictionary,  # category; cosmetic hints, not hard facts.
#   "protected_repeat_values": Dictionary,# same, for repeat_states.
#   "pitch_revealed": bool,       # true once the record's pitch has been shown to the player
#   "star_elim": Dictionary,      # {star_idx(int): state(int)} — which stars are ruled out for THIS record
#   "star_idx": int,              # -1 until resolvable from seq_lo==seq_hi or map-widget confirm
#   "color_slot_label": String,   # "" unless bound to a Sort:Color grid slot (e.g. "Blue A")
#   "pitch_slot_label": String,   # "" unless bound to a Sort:Pitch grid slot
#   "degree_slot_label": String,  # "" unless bound to a Sort:Sequence grid slot
#   "melody_ticks": Array,         # raw melody note-event indices (1-indexed)
#                                  # this record has been opened FROM on the staff --
#                                  # NEVER seeded from ground truth (see
#                                  # _get_or_create_match_record_for_melody_tick's
#                                  # own comment); grows by UNION when two tick-
#                                  # anchored records merge because the PLAYER's
#                                  # own marks proved them the same star.
# }
var _match_records: Array[Dictionary] = []


# ── THE RECORD BOUNDARY (Phase 0) ────────────────────────────────────────
# Nothing outside this file indexes _match_records. Widgets and the overlay
# go through record_count() and record_at() instead — 79 direct reaches
# replaced, and test_record_boundary fails the build if a new one appears,
# since GDScript has no way to actually enforce privacy.
#
# The point is NOT encapsulation for its own sake. Phase 3 needs derived
# identity, which needs records to ALIAS each other (record 13 resolving to
# record 11) instead of being destructively merged — and an alias is only
# possible if every "record at index i" question goes through one function
# that can redirect it. Today record_at() is a plain lookup; that is the
# whole point of doing this as its own phase, with no behaviour change to
# hide a mistake in.
#
# What this deliberately does NOT do: record_at() hands back the live
# Dictionary, so callers can still mutate through it. Sealing MUTATION too
# would mean defensive copies on a path that runs per-widget per-refresh,
# and it is not what Phase 3 is blocked on. Index resolution is.
#
# Bounds behaviour is also left exactly as it was — record_at() indexes
# directly and will still fault on a bad index rather than quietly
# returning an empty Dictionary, because a silent no-op write is a worse
# failure than a loud one, and changing it here would break the "pure
# refactor" contract that lets this land without a playtest.

## How many records exist. Replaces external `_match_records.size()`.
func record_count() -> int:
    return _match_records.size()


## The record at `idx` — the single place an index becomes a record, and
## the hook Phase 3's aliasing will need. Returns the live Dictionary.
func record_at(idx: int) -> Dictionary:
    return _match_records[idx]

## Bumped every time _match_records is cleared/rebuilt (see
## _load_match_records()). _merge_match_records() and
## _confirm_match_record_identity() both hold indices/Dictionary
## references across `await _conflict_dialog_fn.call(...)` — a real,
## reachable window, since root_ui.gd re-invokes show_for_constellation()
## (which rebuilds _match_records from scratch) on the SAME constellation
## a study overlay already has open, whenever that constellation's puzzle
## regenerates. Capturing this counter at entry and checking it after an
## await lets those functions detect "the array was rebuilt out from under
## me" and abort cleanly instead of writing to an orphaned Dictionary or
## bracket-indexing a stale/now-out-of-range index.
var _match_records_generation: int = 0


# ==================================================
# THE DERIVED LAYER  (migration Phase 2, 2026-08-10)
#
# _match_records now holds ONLY what the player asserted. Everything the
# engine concludes lives here instead, in a parallel array indexed the same
# way, and is thrown away and rebuilt from scratch on every
# _full_propagation_refresh(). It is never saved.
#
# WHY THIS EXISTS. Every derived pass used to write its conclusions into
# the same dicts as player input, which made "whose fact is this?"
# unanswerable — so each pass grew its own ownership-mark dict to try to
# tell them apart on the way back out. That scheme produced a long line of
# bugs, all the same shape:
#   * a derived elimination re-justifying itself from its own previous
#     output, so undoing its cause never released it (the three-strand
#     star_elim -> colour -> candidates loop);
#   * _recompute_color_star_elim adopting the player's own X's as
#     engine-owned and then "releasing" them (the Keriion/Selion report);
#   * derived sequence pins and derived star_idx bindings written with NO
#     mark at all, hence unreleasable forever.
#
# Separation kills the whole class by construction rather than by guard:
#   * a derived fact cannot outlive its cause, because the layer is wiped
#     every refresh and only re-derived if its premises still hold;
#   * a derived pass cannot damage player input, because it does not have
#     a handle to write to it;
#   * no ownership marks are needed, so derived_value_elim_marks,
#     color_star_elim_marks and the honour_derived parameter are all gone.
#
# WHY READING DERIVED FACTS DURING DERIVATION IS SAFE. Within one refresh
# this is a monotone fixpoint: passes only ADD facts, and only ever from
# premises already present. A fact that could justify itself is therefore
# never introduced in the first place — the self-sustaining loop needed
# last refresh's output to survive into this one, which is exactly what
# the wipe prevents. That is why honour_derived could be deleted outright
# instead of being threaded through more call sites.
#
# NOT IN THIS PHASE: derived IDENTITY. _settle_star_identity_from_candidates
# still writes star_idx into the record, because a derived identity is only
# useful once the two records MERGE, and merging is destructive and cannot
# be rolled back when the derived layer is wiped. Making that safe needs
# non-destructive aliasing (union-find) and a sweep of every cross-record
# reader — Phase 3. See [[deduction-grid-migration-scope]].
#
# Entry shape mirrors the record's own keys so the readers can consult one
# then the other with no translation:
#   {"color_states": {}, "degree_states": {}, "pitch_states": {},
#    "name_states": {}, "star_elim": {}, "seq_candidates": []}
var _derived: Array[Dictionary] = []


func _blank_derived_entry() -> Dictionary:
    # Every states_key _add_derived_state/_derived_state can be called with
    # (via _axis_states_key) needs its own sub-dict here, or _add_derived_
    # state's `_derived[record_idx][states_key]` reads back null for a
    # missing key, gets coerced into a fresh, DISCONNECTED empty Dictionary
    # by the typed `var d: Dictionary` it assigns into, and the write that
    # follows lands in that orphaned dict and vanishes — _add_derived_state
    # still returns true, so nothing LOOKS wrong at the call site. Caught
    # exactly this way when Axis.REPEAT was wired in (2026-09-29):
    # _settle_derived_exclusions_for_axis computed every condition for
    # elimination correctly and _add_derived_state reported success, but
    # _effective_repeat_state never saw it, because repeat_states was
    # missing here.
    return {
        "color_states":  {},
        "degree_states": {},
        "pitch_states":  {},
        "name_states":   {},
        "repeat_states": {},
        "star_elim":     {},
        "seq_candidates": [],
        # Phase 3. A record the engine has concluded IS some star, without
        # writing that into the record's own star_idx. See
        # _effective_star_idx for why the two must stay separate.
        "star_idx":      -1,
    }


## Throws the whole derived layer away. Called at the top of every
## _full_propagation_refresh(), and any time _match_records changes shape
## (load, create, merge) so the two arrays can never drift out of
## alignment — a derived entry read against the wrong record would be a
## silent wrong answer rather than a crash.
func _reset_derived() -> void:
    _derived.clear()
    for _i in _match_records.size():
        _derived.append(_blank_derived_entry())
    _seq_singleton_built = false
    # Once per refresh, not once per fixpoint round — see the note in
    # _clear_deduction_caches_all(). A constellation switch reaches this too,
    # so a previous puzzle's constraints cannot survive one.
    _distance_constraints_built = false
    _distance_constraints_cache = []
    # Derived facts about VALUES rather than records — same lifetime as the
    # derived layer itself, so they are rebuilt each refresh and release
    # when their premise does. Deliberately NOT cleared by
    # _clear_deduction_caches: that drops caches mid-fixpoint, and these are
    # conclusions, not a cache.
    _derived_descriptor_stars.clear()


## Grows the layer to match _match_records without discarding what is
## already derived. Used by the record-creation paths, which can run
## mid-refresh.
func _sync_derived_size() -> void:
    while _derived.size() < _match_records.size():
        _derived.append(_blank_derived_entry())
    while _derived.size() > _match_records.size():
        _derived.remove_at(_derived.size() - 1)
    _seq_singleton_built = false


# ── CONTRADICTION DETECTION ──────────────────────────────────────────────
# A record with every option ruled out on some axis is not a hard position,
# it is an IMPOSSIBLE one: some mark behind it must be wrong. The engine
# could always compute this — _candidate_stars_for_record returning [] says
# it outright — but nothing ever asked, so the board just sat there quietly
# unsolvable.
#
# Found the hard way (2026-08-10): a G4 elimination on a record whose star
# genuinely plays G4 emptied that record's candidate set completely. The
# save had been in that state for a whole session. Nothing flagged it, and
# the wrongness surfaced as a clue that "must be contradictory" — the clue
# was fine.
#
# Rebuilt every refresh off the derived layer and never persisted: a
# contradiction is a conclusion, so it must not outlive the marks that
# caused it. Fixing the offending mark makes it disappear on the next
# refresh with no extra bookkeeping.
#
# Deliberately NOT phrased as "this mark is wrong" — the engine knows the
# set is empty, not which of the marks is the mistake, and pointing at the
# wrong one would be worse than pointing at none. It also must never leak
# ground truth: it says "every star is ruled out", never which star was
# right.
#
# FORMER GAP, NOW CLOSED — contradictions that get absorbed before this
# runs. If a record's marks identify a star UNIQUELY, _settle_identical_records
# merges it into that star's record, and every axis then reads ground truth,
# which overrides the offending mark. The impossible state used to disappear
# instead of being reported, and the player's wrong mark silently vanished
# with it. Found while testing this: a fixture whose confirmed colour had
# exactly one star merged and reported nothing, and only stopped doing so
# once the colour covered two.
#
# Both halves are now handled below: _marks_contradicting_star compares a
# settled record's own marks against its star's ground truth (the confirmed
# half), and _settle_identical_records refuses a merge whose records clash
# (_merge_value_clashes, recorded in _merge_refusals) so the detector can
# report the pair (the merge half).
var _contradictions: Array[Dictionary] = []


func _detect_contradictions() -> void:
    _contradictions.clear()
    var all_notes: Array = _host._widgets._distinct_note_names()

    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var who: String = _record_display_name(i)

        # MORE NOTES THAN IT FIRES (2026-10-16). A row can reach this by entries
        # being joined to it (naming them, "Same star as note"), which the
        # row's own buttons cannot stop. Reported: Dobraan on five notes at R3.
        var held_notes: int = (r.get("melody_ticks", []) as Array).size()
        var fires_n: int = _known_fire_count_for_record(i)
        if fires_n > 0 and held_notes > fires_n:
            _contradictions.append({
                "record": i, "axis": "notes",
                "text": "%s is entered on %d notes, but fires only %d time%s." % [who, held_notes, fires_n, "" if fires_n == 1 else "s"],
            })

        # Candidate stars is the strongest single check — it already
        # intersects colour, degree and listened pitch, so it catches
        # combinations no per-axis check would.
        if _candidate_stars_for_record(i).is_empty():
            _contradictions.append({
                "record": i, "axis": "star",
                "text": "%s can't be any star — every star is ruled out." % who,
            })
            continue   # the per-axis findings below would all be the same fault

        # A record whose identity is settled reads its axes off ground
        # truth, so an all-eliminated axis is unreachable there — but a
        # player mark that CONTRADICTS that ground truth is reachable, and
        # it is exactly what the detector used to miss.
        #
        # In practice this only ever fires for a CONFIRMED identity. A mark
        # that rules a star out also removes it from the candidate set, so
        # the engine could never have DERIVED that binding — the reachable
        # case is the player pinning a star on the map while an older mark
        # of their own says it cannot be that star. Before this, ground
        # truth just overruled the mark in silence.
        #
        # That is the confirmed half of the merge-absorption hole from
        # d4bebd5. The merge half is closed separately: the merge pass
        # refuses a merge whose records clash (_merge_value_clashes), so no
        # mark is dropped by a union, and the refused pair is reported
        # through _merge_refusals further down this function.
        var eff_star: int = _effective_star_idx(i)
        if eff_star >= 0:
            var clash: Array = _marks_contradicting_star(i, eff_star)
            if not clash.is_empty():
                _contradictions.append({
                    "record": i, "axis": "ground-truth",
                    "text": "%s is settled as a star that its own %s rules out." % [
                        who, " and ".join(clash)],
                })
            continue

        if str(r.get("name", "")) == "" and _all_eliminated(i, "name", _host._star_names):
            _contradictions.append({
                "record": i, "axis": "name",
                "text": "%s has every name ruled out." % who,
            })
        if _all_eliminated(i, "pitch", all_notes):
            _contradictions.append({
                "record": i, "axis": "pitch",
                "text": "%s has every pitch ruled out." % who,
            })
        var colour_vals: Array = []
        for ci in _host.COLOR_NAME_LABELS.size():
            colour_vals.append(int(ci))
        if _all_eliminated(i, "colour", colour_vals):
            _contradictions.append({
                "record": i, "axis": "colour",
                "text": "%s has every colour ruled out." % who,
            })

    # Pairs the merge pass refused because their marks clash. Provably the
    # same entity, yet one confirms what the other rules out — so it is the
    # pair that is impossible, not either record alone, and neither would
    # be caught by any of the per-record checks above.
    for ref in _merge_refusals:
        var ra: int = int(ref["a"])
        var rb: int = int(ref["b"])
        if ra >= _match_records.size() or rb >= _match_records.size():
            continue
        # The two records usually share a name — that is often WHY they are
        # provably the same — so naming both would read "Pyrios and Pyrios",
        # which tells the player nothing about where to look. Fall back to
        # whatever actually distinguishes them.
        var na: String = _record_display_name(ra)
        var nb: String = _record_display_name(rb)
        var subject: String = "%s and %s" % [na, nb]
        if na == nb:
            var qa: String = _record_qualifier(ra)
            var qb: String = _record_qualifier(rb)
            subject = "Two entries for %s (%s and %s)" % [na, qa, qb] \
                if qa != "" and qb != "" and qa != qb \
                else "Two entries for %s" % na
        _contradictions.append({
            "record": ra, "axis": "merge",
            "text": "%s must be the same star, but disagree about %s." % [
                subject, " and ".join(ref["clashes"])],
        })

    # Two records claiming the same NAME.
    #
    # Reported because the second claim is otherwise completely inert.
    # _propagate_name_states_confirmed_same_record refuses to promote a
    # confirmed name into r["name"] when another record already holds it —
    # correctly, since that would mint a duplicate identity — so the claim
    # stays in name_states and nothing downstream sees it.
    # _find_match_record_by_name returns the FIRST holder, which is what
    # the star map reads through, so the newer assertion never reaches the
    # map at all. The old comment said it "surfaces on the next explicit
    # Sort:Name-tab interaction"; in practice the player has no reason to
    # go there and just sees their input do nothing.
    #
    # Deliberately says nothing about which claim is right. Unlike colour,
    # degree and listened pitch, a star's NAME is the hidden thing the
    # puzzle is about — comparing it against ground truth here would hand
    # over the answer. This is purely a conflict between two of the
    # player's own entries, which is why it can be reported at all. For the
    # same reason _marks_contradicting_star does not check the name axis.
    var name_claims: Dictionary = {}
    for i in _match_records.size():
        var r2: Dictionary = _match_records[i]
        var claimed: String = str(r2.get("name", ""))
        if claimed == "":
            for k in (r2.get("name_states", {}) as Dictionary):
                if int((r2["name_states"] as Dictionary)[k]) == 1:
                    claimed = str(k)
                    break
        if claimed == "":
            continue
        if not name_claims.has(claimed):
            name_claims[claimed] = []
        (name_claims[claimed] as Array).append(i)

    for nm in name_claims:
        var idxs: Array = name_claims[nm]
        if idxs.size() < 2:
            continue
        # Skip when the merge pass already reported this exact pair. Since
        # a name confirm now produces an identity token, most duplicate
        # claims either merge away or come back as a refusal — saying the
        # same thing twice in the banner just makes it look like two
        # separate mistakes.
        var already: bool = false
        for ref2 in _merge_refusals:
            if idxs.has(int(ref2["a"])) and idxs.has(int(ref2["b"])):
                already = true
                break
        if already:
            continue
        var wheres: Array[String] = []
        for idx in idxs:
            var q: String = _record_qualifier(int(idx))
            wheres.append(q if q != "" else "an unplaced entry")
        # Where the two claimants also disagree about a VALUE, say so —
        # that is the actionable part, and it is the reason they can never
        # reconcile into one entry. Still only compares the player's marks
        # against each other, never against the answer.
        var why: Array[String] = _merge_value_clashes(int(idxs[0]), int(idxs[1]))
        var tail: String = ""
        if not why.is_empty():
            tail = ", and they disagree about %s" % " and ".join(why)
        _contradictions.append({
            "record": int(idxs[0]), "axis": "name-claim",
            "text": "%s is claimed by %d entries (%s)%s — only one can be right." % [
                str(nm), idxs.size(), ", ".join(wheres), tail],
        })

    # Two records on one star is impossible ONLY when the two are provably
    # DIFFERENT stars. On its own it is ordinary and expected: a record is a
    # view, not a star, and the same star is routinely held by a Sort:Name
    # row, a Sort:Pitch slot, a Staff position and a map widget at once.
    # That is the entire reason _records_provably_identical and the merge
    # path exist.
    #
    # Reported from a live game 2026-08-13: "Slot C#5 A and The star that
    # fires 4th are both set to the same star" on a board where C#5 really
    # WAS the 4th note. Reproduced with those two records not provably
    # distinct, i.e. nothing said they were different stars — the engine had
    # simply worked out, correctly, that they were the same one.
    #
    # It became reachable when the identity passes were unblocked (54d71d9):
    # merging deliberately runs against an EMPTY derived layer, so a
    # co-identification the engine DERIVES cannot be folded away, and every
    # such correct conclusion was being reported as a broken board.
    #
    # The star-shaped reading — "a star may hold at most one record" — is
    # what made this look like a conflict. Matrix-up, the constraint is on
    # the star's identity, and many views of one star agreeing about it is
    # agreement, not collision. Only two views that CANNOT be the same star
    # are a contradiction.
    var by_star: Dictionary = {}
    for i in _match_records.size():
        var si: int = _effective_star_idx(i)
        if si < 0:
            continue
        if not by_star.has(si):
            by_star[si] = []
        (by_star[si] as Array).append(i)
    for si2 in by_star:
        var here: Array = by_star[si2]
        if here.size() < 2:
            continue
        for a in here.size():
            for b in range(a + 1, here.size()):
                var clash: Array[String] = _same_star_value_clash(int(here[a]), int(here[b]))
                if clash.is_empty():
                    continue   # same star, seen twice — agreement, not conflict
                _contradictions.append({
                    "record": int(here[b]), "axis": "identity",
                    "text": "%s and %s are both set to the same star, but disagree about %s." % [
                        _record_display_name(int(here[a])), _record_display_name(int(here[b])),
                        " and ".join(clash)],
                })

    # NO same-position check here, deliberately — see
    # _settle_same_position_identity, which is the pass that would need one.
    # Two provably-different records cannot both END UP on one position:
    # _compute_excluded_positions_for already removes a position owned by a
    # provably-distinct record, so nothing can be DERIVED onto a taken one.
    # The only way to reach the state is for both to be raw-pinned there,
    # and a raw pin puts an "S:<pos>" token in both identity signatures — so
    # that pair goes through _settle_identical_records and is already
    # reported as a merge refusal above. A check here could only ever
    # duplicate that message.


## Which of the player's OWN marks on this record rule out being `star`.
## Reads the raw state dicts, never the _effective_* readers — those
## consult the ground-truth tier, which is the very thing being checked,
## and would report agreement with itself every time.
##
## Only hard eliminations count (state 2). A confirm on some other value is
## not listed separately: it is the sibling-clearing eliminations it
## produced that actually do the ruling out, and naming both would blame
## one mistake twice.
func _marks_contradicting_star(record_idx: int, star: int) -> Array:
    var out: Array = []
    if record_idx < 0 or record_idx >= _match_records.size():
        return out
    if star < 0 or star >= _host._star_count:
        return out
    var r: Dictionary = _match_records[record_idx]

    var sc: int = int(_host._star_colors[star]) if star < _host._star_colors.size() else -1
    if sc >= 0 and int((r.get("color_states", {}) as Dictionary).get(sc, 0)) == 2:
        out.append("%s colour mark" % str(_host.COLOR_NAME_LABELS[sc]))

    var sd: int = int(_host._star_degrees[star]) if star < _host._star_degrees.size() else -1
    if sd >= 0 and int((r.get("degree_states", {}) as Dictionary).get(sd, 0)) == 2:
        out.append("degree-%d mark" % sd)

    # Pitch only where the player could legitimately know it — an unheard
    # star's note must not be implied by a warning either.
    if _player_knows_star_pitch(star):
        var nn: String = _host._widgets._note_name_for_star(star)
        if nn != "?" and int((r.get("pitch_states", {}) as Dictionary).get(nn, 0)) == 2:
            out.append("%s pitch mark" % nn)

    if int((r.get("star_elim", {}) as Dictionary).get(star, 0)) == 2:
        out.append("X on that star")

    return out


## True when every value on `axis` reads eliminated. An empty value list
## means "nothing to rule out" and is never a contradiction.
func _all_eliminated(record_idx: int, axis: String, values: Array) -> bool:
    if values.is_empty():
        return false
    for v in values:
        var st: int = 0
        match axis:
            "name":   st = _effective_name_state(record_idx, str(v))
            "pitch":  st = _effective_pitch_state(record_idx, str(v))
            "colour": st = _effective_color_state(record_idx, int(v))
        if st != 2:
            return false
    return true


## How a record should be referred to in a warning: its name if it has one,
## otherwise whichever slot it belongs to, so the player can find the thing
## being complained about.
func _record_display_name(record_idx: int) -> String:
    if record_idx < 0 or record_idx >= _match_records.size():
        return "A record"
    var r: Dictionary = _match_records[record_idx]
    var nm: String = str(r.get("name", ""))
    if nm != "":
        return nm
    for key in ["color_slot_label", "pitch_slot_label", "degree_slot_label"]:
        var lbl: String = str(r.get(key, ""))
        if lbl != "":
            return "Slot %s" % lbl
    var lo: int = int(r.get("seq_lo", 0))
    var hi: int = int(r.get("seq_hi", 0))
    if lo > 0 and lo == hi:
        var phrase: String = _seq_noun(lo)
        return phrase.substr(0, 1).to_upper() + phrase.substr(1)
    var si: int = _effective_star_idx(record_idx)
    if si >= 0 and si < _host._star_names.size():
        return str(_host._star_names[si])
    return "An unnamed entry"


## What distinguishes a record from another of the same name — the slot it
## belongs to, or its sequence position. "" when nothing does, in which
## case the caller should not pretend otherwise.
func _record_qualifier(record_idx: int) -> String:
    if record_idx < 0 or record_idx >= _match_records.size():
        return ""
    var r: Dictionary = _match_records[record_idx]
    for key in ["color_slot_label", "pitch_slot_label", "degree_slot_label"]:
        var lbl: String = str(r.get(key, ""))
        if lbl != "":
            return "slot %s" % lbl
    var lo: int = int(r.get("seq_lo", 0))
    if lo > 0 and lo == int(r.get("seq_hi", 0)):
        return "position %d" % lo
    var si: int = int(r.get("star_idx", -1))
    if si >= 0:
        return "the star map"
    return ""


func _ordinal(n: int) -> String:
    var suffix: String = "th"
    if n % 100 < 11 or n % 100 > 13:
        match n % 10:
            1: suffix = "st"
            2: suffix = "nd"
            3: suffix = "rd"
    return "%d%s" % [n, suffix]


# ── DERIVED IDENTITY (Phase 3) ───────────────────────────────────────────
# "This record IS star N", concluded rather than asserted.
#
# It used to be written straight into r["star_idx"], a player-input field,
# with no way to take it back — eliminate every colour but one, and the
# binding stuck even after the eliminations were cleared. That was the last
# member of the derived-facts-outlive-their-causes family Phase 2 killed
# everywhere else.
#
# The reason it was left behind is that identity is not just another fact.
# Two records agreeing on a star is what triggers _merge_match_records,
# which DESTROYS one of them — and a destroyed record cannot come back when
# the derived layer is wiped on the next refresh. So the split here is
# sharper than for any other axis:
#
#   * STATE RESOLUTION reads the effective identity. A derived binding
#     resolves colour, degree and (once listened) pitch through the
#     ground-truth tier, exactly as a confirmed one does, and releases the
#     moment its cause does.
#   * IDENTITY AND PERSISTENCE read the OWN field only — merging,
#     _identity_signature, _records_provably_identical, the conflict
#     dialog, and save/load. Nothing destructive or durable may rest on a
#     fact that evaporates every frame.
#
# _player_knows_star_pitch also stays on the own field deliberately: you
# only know a pitch you actually listened to, and listening attaches to a
# star the player confirmed. Letting a derived binding claim that knowledge
# would leak unheard pitches into deduction.
func _effective_star_idx(record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var own: int = int(_match_records[record_idx].get("star_idx", -1))
    if own >= 0:
        return own
    if record_idx >= _derived.size():
        return -1
    return int(_derived[record_idx].get("star_idx", -1))


## Total derived facts across every record. The fixpoint loop compares this
## before and after a round: unchanged means nothing new was concluded and
## the frame has settled. Cheap enough to call per round (a handful of
## small dicts) and far more robust than having every pass remember to
## report whether it changed anything.
func _derived_fact_count() -> int:
    var n: int = 0
    for d in _derived:
        n += (d["color_states"] as Dictionary).size()
        n += (d["degree_states"] as Dictionary).size()
        n += (d["pitch_states"] as Dictionary).size()
        n += (d["name_states"] as Dictionary).size()
        n += (d["star_elim"] as Dictionary).size()
        # Sequence is a NARROWING, so its array shrinks as more is learned.
        # Counted as positions ruled out so this total only ever rises —
        # a measure that could fall might match a previous round's value
        # while the state had in fact changed, and stop the loop early.
        var seq: Array = d["seq_candidates"]
        if not seq.is_empty():
            n += maxi(0, _host._star_count - seq.size())
        if int(d.get("star_idx", -1)) >= 0:
            n += 1
    return n


func _derived_state(record_idx: int, states_key: String, value_key) -> int:
    if record_idx < 0 or record_idx >= _derived.size():
        return 0
    return int((_derived[record_idx][states_key] as Dictionary).get(value_key, 0))


## Adds a derived fact. Refuses to overwrite an existing one, so a pass
## cannot flip another pass's conclusion — a genuine contradiction between
## two derivations means a rule is wrong, and silently letting the last
## writer win would hide it. Returns true if the fact was newly added,
## which the fixpoint loop uses to decide whether to iterate again.
func _add_derived_state(record_idx: int, states_key: String, value_key, state: int) -> bool:
    if record_idx < 0 or record_idx >= _derived.size():
        return false
    var d: Dictionary = _derived[record_idx][states_key]
    if int(d.get(value_key, 0)) != 0:
        return false
    d[value_key] = state
    return true


func setup(host: ConstellationStudyOverlay, conflict_dialog_fn: Callable) -> void:
    _host = host
    _conflict_dialog_fn = conflict_dialog_fn


# ==================================================
# TYPE COERCION — _load_match_records() is the one place untrusted,
# save-derived data enters _match_records. Every other function in this
# file that reads a record field (there are dozens, e.g. `int(r.get(
# "seq_lo", 0))` throughout) trusts that value is already the right type
# — true for records built by normal gameplay (literal ints/strings), but
# not for a corrupted-but-parseable save. Fully sanitizing every field
# here, once, means none of those downstream reads need their own guard:
# a wrong-typed value assigned into a typed variable, or passed to the
# global int()/bool() constructors, hangs the engine rather than raising
# a catchable error (confirmed repeatedly this session, bool() included).
# str() is safe for any input type (also confirmed) — the many str(...)
# calls elsewhere in this file don't need this treatment.
# ==================================================
func _coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


# For coercing DICTIONARY KEYS that are semantically ints (color/star/degree
# indices), not values. JSON.stringify()/JSON.parse_string() — exactly what
# save_manager.gd's atomic write/read does to the whole save file — silently
# turns every int Dictionary key into a String (confirmed directly: {1:"a"}
# round-trips to {"1":"a"}). _coerce_int() alone only accepts already-typed
# int/float, so applying it straight to a key coming out of a real save
# reload returns `default` for every single key — collapsing an entire
# dict like color_states down to one entry, silently, on every normal
# save/load cycle, not just a corrupted one. This was the actual bug;
# range-clamping alone (added first, kept below) wasn't enough on its own.
func _coerce_int_key(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    if typeof(val) == TYPE_STRING and (val as String).is_valid_int():
        return int(val)
    return default


func _coerce_bool(val, default: bool) -> bool:
    if typeof(val) == TYPE_BOOL:
        return val
    return default


func _coerce_dict(val, default: Dictionary) -> Dictionary:
    if typeof(val) == TYPE_DICTIONARY:
        return val
    return default


func _coerce_array(val, default: Array) -> Array:
    if typeof(val) == TYPE_ARRAY:
        return val
    return default


# ==================================================
# MELODY BAR SCORE — piano-roll style summary of confirmed Sequence×Pitch
# information. Purely a rendering query over _match_records: no ground
# truth is ever read here. A position only gets a notehead if the player
# has confirmed BOTH the exact sequence slot AND a pitch on that same
# record; a confirmed slot with unconfirmed pitch gets a "?" at neutral
# height; a wholly unconfirmed slot draws nothing.
# ==================================================
## The note a record can legitimately DISPLAY, or "" — the shared guard for
## every pitch-showing surface. Uses _effective_pitch_state so a pitch known
## through Listen (which lives in ground truth via star_idx, not in
## pitch_states) is shown, while refusing to read ground truth off a bare
## auto-created star-widget stub, which would hand over an un-earned answer.
func _displayable_pitch_for_record(record_idx: int) -> String:
    if record_idx < 0 or record_idx >= _match_records.size():
        return ""
    var r: Dictionary = _match_records[record_idx]
    if _record_is_unconfirmed_star_widget_stub(record_idx) \
            and not bool(r.get("pitch_revealed", false)):
        return ""
    for note in _host._widgets._distinct_note_names():
        if _effective_pitch_state(record_idx, str(note)) == 1:
            return str(note)
    return ""


func _melody_marker_for_position(seq_pos: int) -> Dictionary:
    # Reads the EFFECTIVE pitch, not raw pitch_states: a Listen-revealed
    # note lives in ground truth via star_idx and never lands in that dict,
    # so the staff used to show "?" for positions whose pitch was fully
    # known. Same bypass-the-effective-layer class as _known_color_for_
    # seq_position and _display_color_for_record below.
    # ALSO the effective POSITION, for the same reason. Matching on the
    # record's own seq_lo/seq_hi missed every position the player pinned by
    # DEDUCTION rather than by typing — those live in the derived layer and
    # deliberately never touch those fields — so the staff drew "?" over a
    # position that was actually solved. Third instance of the mistake
    # _seq_singleton_owners documents and d27d9c4 fixed in
    # _find_match_record_by_exact_seq; see _record_at_seq_position.
    var has_position: bool = false
    for i in _match_records.size():
        if not _record_is_at_seq(i, seq_pos):
            continue
        has_position = true
        var note: String = _displayable_pitch_for_record(i)
        if note != "":
            return {"has_position": true, "pitch_known": true, "note_name": note}
    return {"has_position": has_position, "pitch_known": false, "note_name": ""}


## Is this record THIS sequence position, by any route the player has?
##
## Reads the effective candidate set, so a derived pin counts exactly like a
## typed one. The staff's three per-position readouts (pitch, name, the
## numeric's colour) all ask this, and all three used to ask it of
## seq_lo/seq_hi and get "no" for a position the player had solved.
func _record_is_at_seq(record_idx: int, seq_pos: int) -> bool:
    var s: Array = _seq_candidate_set_for(record_idx)
    return s.size() == 1 and int(s[0]) == seq_pos


## The name at a sequence position, or "" if it is not yet determined.
##
## Same "resolves by elimination" rule _known_color_for_seq_position uses: a
## directly-recorded name counts, and so does the last name standing once
## every other has been ruled out.
func _known_name_for_seq_position(seq_pos: int) -> String:
    for i in _match_records.size():
        if not _record_is_at_seq(i, seq_pos):
            continue
        var found: String = _known_name_for_record(i)
        if found != "":
            return found
    return ""


## One record's name by the same rule, or "". Also what the staff shows for a
## repeat note the player has not placed on a position yet: such a note has
## no position to look up, only its own record.
func _known_name_for_record(record_idx: int) -> String:
    if record_idx < 0 or record_idx >= _match_records.size():
        return ""
    var own: String = str(_match_records[record_idx].get("name", ""))
    if own != "":
        return own
    var confirmed: String = ""
    var eliminated_count: int = 0
    var remaining: String = ""
    for n in _host._star_names:
        var nm: String = str(n)
        var st: int = _effective_name_state(record_idx, nm)
        if st == 1:
            confirmed = nm
        elif st == 2:
            eliminated_count += 1
        else:
            remaining = nm
    if confirmed != "":
        return confirmed
    if eliminated_count == _host._star_names.size() - 1 and remaining != "":
        return remaining
    return ""


## One record's colour (confirmed, or the last one standing), or -1. Not
## _known_color_for_record below, which reads only the record's own confirm.
func _resolved_color_for_record(record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var confirmed: int = -1
    var eliminated_count: int = 0
    var remaining: int = -1
    for ci in _host.COLOR_NAME_LABELS.size():
        var state: int = _effective_color_state(record_idx, ci)
        if state == 1:
            confirmed = ci
        elif state == 2:
            eliminated_count += 1
        else:
            remaining = ci
    if confirmed >= 0:
        return confirmed
    if eliminated_count == _host.COLOR_NAME_LABELS.size() - 1 and remaining >= 0:
        return remaining
    return -1


## The staff's pitch readout for one record (see _melody_marker_for_position).
func _melody_marker_for_record(record_idx: int) -> Dictionary:
    var note: String = _displayable_pitch_for_record(record_idx)
    return {"has_position": false, "pitch_known": note != "", "note_name": note}


func _known_color_for_seq_position(seq_pos: int) -> int:
    # A position's color counts as "known" either because the player
    # directly confirmed one, or because elimination (from here or
    # propagated in from a Sort: tab) has narrowed it down to the single
    # remaining candidate — that's the same "resolves by elimination"
    # pattern already used for identity anchors elsewhere in this panel.
    # EFFECTIVE colour, not raw color_states — a colour known because the
    # record is pinned to a star, or because it wears a "Blue A" slot label,
    # never lands in that dict. Colour is a given axis (painted on the map),
    # so reading its ground-truth tier leaks nothing.
    # Effective POSITION too — see _record_is_at_seq. This matched on
    # seq_lo/seq_hi and so left the numeric uncoloured for any position the
    # player had pinned by deduction rather than by typing.
    for i in _match_records.size():
        if not _record_is_at_seq(i, seq_pos):
            continue
        var found: int = _resolved_color_for_record(i)
        if found >= 0:
            return found
    return -1


func _propagate_pitch_confirmed_same_record(record_idx: int, confirmed_note: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var pitch_states: Dictionary = r.get("pitch_states", {})
    for f in _host._pitch_freqs:
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        if note_name != confirmed_note:
            pitch_states[note_name] = 2
    pitch_states[confirmed_note] = 1
    r["pitch_states"] = pitch_states
    # A confirm supersedes any earlier manual X on the same note (edge case:
    # player X'd a note, then later confirmed that same note some other way)
    # — otherwise "Undo blocks" would later wipe out this now-confirmed value.
    var manual_pitch: Dictionary = r.get("manual_pitch_blocks", {})
    if manual_pitch.has(confirmed_note):
        manual_pitch.erase(confirmed_note)
        r["manual_pitch_blocks"] = manual_pitch
    # Same staleness fix as _sync_color_states_from_star_idx: a
    # pitch_slot_label naming a DIFFERENT note than what was just confirmed
    # is now wrong. _effective_pitch_state checks the label BEFORE raw
    # pitch_states, so an unfixed stale label here would keep showing the
    # superseded note as confirmed instead of this one.
    var label: String = str(r.get("pitch_slot_label", ""))
    if label != "" and not label.begins_with(confirmed_note):
        r["pitch_slot_label"] = ""


## Same shape as _propagate_pitch_confirmed_same_record — see there. Iterates
## the current Sort:Repeats bucket list rather than a fixed puzzle-wide
## domain like _host._pitch_freqs, since that list is player-driven (see
## _repeat_bucket_values' own comment) and grows over the course of a
## puzzle; a value added to the tab AFTER this record last confirmed
## something is still a real sibling to clear here.
func _propagate_repeat_confirmed_same_record(record_idx: int, confirmed_value: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var repeat_states: Dictionary = r.get("repeat_states", {})
    for v in _repeat_values_all():
        var value: int = int(v)
        if value != confirmed_value:
            repeat_states[value] = 2
    repeat_states[confirmed_value] = 1
    r["repeat_states"] = repeat_states
    var manual_repeat: Dictionary = r.get("manual_repeat_blocks", {})
    if manual_repeat.has(confirmed_value):
        manual_repeat.erase(confirmed_value)
        r["manual_repeat_blocks"] = manual_repeat
    # Same staleness fix as pitch's: a repeat_slot_label naming a DIFFERENT
    # value than what was just confirmed here (this record was reached via
    # some OTHER tab's "Repeats:" checklist, not by being placed in a
    # bucket) is now wrong, and _effective_repeat_state checks the label
    # before raw repeat_states.
    var label: String = str(r.get("repeat_slot_label", ""))
    if label != "" and not label.begins_with("R%d " % confirmed_value):
        r["repeat_slot_label"] = ""


## Clue texts the player has right-clicked into Notes, as reference material
## rather than a "done" marker — Used Up (2026-08-14 to 2026-08-24) was the
## same gesture but meant "I am finished with this clue"; Notes means "I
## want this clue in front of me while I work," which is why it sits next
## to freeform text (_note_entries below) instead of a separate tab. Player
## state, so it round-trips through the save; reversible, so a misclick
## costs nothing.
var _noted_clue_refs: Dictionary = {}

## Freeform lines the player has typed into the Notes tab's entry box.
## Ordered (Array, not Dictionary) — unlike clue refs, entry order is
## meaningful; the player is building a running scratchpad, not a set.
var _note_entries: Array[String] = []

## Sort:Repeats bucket bookkeeping. Unlike Color/Degree/Pitch, whose
## Sort:tab group sizes come straight from ground truth (those axes are
## given/observable, so the true count is no leak), Repeat Count's true
## per-value incidence IS the secret the design doc explicitly withholds
## ("no free tier for this axis" — see planned_repeat_count_axis_design.md).
## So the bucket LIST and each bucket's SLOT COUNT are player-driven state,
## not derived from _host._repeat_count: the player starts with buckets
## 0/1/2 (a universal, puzzle-independent range — same kind of safe
## structural fact as Sequence's 1..star_count, not this puzzle's answer)
## and grows either dimension themselves as clues imply more is needed.
## Persisted per-puzzle (_save_puzzle_notes() / the load block in
## constellation_study_overlay.gd), same isolation as _noted_clue_refs.
var _repeat_bucket_values: Array = []
var _repeat_bucket_slot_counts: Dictionary = {}


func is_clue_noted(text: String) -> bool:
    return _noted_clue_refs.has(text)


## Lazily seeds the starting buckets on first use rather than at
## declaration time, so a fresh puzzle (nothing loaded yet) and a loaded
## save with an explicit empty list are indistinguishable — both want the
## same default, and seeding at declaration would also fire before a real
## loaded list has had a chance to land.
func _ensure_repeat_buckets_seeded() -> void:
    if _repeat_bucket_values.is_empty():
        _repeat_bucket_values = [0, 1, 2]


func _get_repeat_bucket_values() -> Array:
    _ensure_repeat_buckets_seeded()
    return _repeat_bucket_values.duplicate()


## Appends the next integer not already a bucket — always the current
## maximum plus one, so buckets stay a contiguous 0..N run (matching the
## axis's own real shape: a repeat count of N implies 0..N-1 are at least
## conceivable too) rather than letting gaps accumulate from repeated
## presses landing on the same next value.
func _add_repeat_bucket() -> void:
    _ensure_repeat_buckets_seeded()
    var next_value: int = 0
    for v in _repeat_bucket_values:
        next_value = max(next_value, int(v) + 1)
    _repeat_bucket_values.append(next_value)
    _save_puzzle_notes()


func _repeat_bucket_slot_count(value: int) -> int:
    return int(_repeat_bucket_slot_counts.get(value, 1))


func _add_repeat_bucket_slot(value: int) -> void:
    _repeat_bucket_slot_counts[value] = _repeat_bucket_slot_count(value) + 1
    _save_puzzle_notes()


## Floored at 1 rather than letting a bucket go to zero rows — a bucket
## with no rows at all has no way back into view (nothing left to click
## "add slot" on). Never deletes the record a hidden slot pointed to: slot
## records are found by LABEL STRING equality (see
## _get_or_create_match_record_for_repeat_slot), so a slot removed here and
## re-added later reunites with the exact same record and everything the
## player had already filled in in it, rather than losing it.
func _remove_repeat_bucket_slot(value: int) -> void:
    var cur: int = _repeat_bucket_slot_count(value)
    if cur <= 1:
        return
    _repeat_bucket_slot_counts[value] = cur - 1
    _save_puzzle_notes()


## Shared wording for a repeat-count value — the Sort:Repeats bucket header
## and this axis's own clue text (_characteristic_label's REPEAT branch,
## constellation_logic_puzzle.gd) should read as the same fact in different
## places, not two independently-phrased claims about the same number.
func _repeat_value_label(value: int) -> String:
    if value == 0:
        return "Never repeats"
    if value == 1:
        return "Repeats once"
    if value == 2:
        return "Repeats twice"
    return "Repeats %d times" % value


## Same "adopt an existing confirmed record, else create a blank one" shape
## as _get_or_create_match_record_for_color_slot/_degree_slot — see those
## for the general pattern. Placing a record here is itself the confirm
## (see _effective_repeat_state's slot-label tier), not a separate step.
func _get_or_create_match_record_for_repeat_slot(value: int, position_in_group: int) -> int:
    var label: String = "R%d %s" % [value, _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("repeat_slot_label", "")) == label:
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("repeat_slot_label", "")) != "":
            continue
        if int(r.get("repeat_states", {}).get(value, 0)) == 1:
            r["repeat_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"repeat_slot_label": label}))
    _sync_derived_size()
    return _match_records.size() - 1


func _compute_excluded_repeats_for(record_idx: int) -> Array[int]:
    var out: Array[int] = []
    for v in _compute_excluded_for_axis(Axis.REPEAT, record_idx):
        out.append(int(v))
    return out


## Returns the new state, so the caller can rebuild without re-querying.
func toggle_clue_noted(text: String) -> bool:
    if text == "":
        return false
    if _noted_clue_refs.has(text):
        _noted_clue_refs.erase(text)
    else:
        _noted_clue_refs[text] = true
    _save_puzzle_notes()
    return _noted_clue_refs.has(text)


## Appends one freeform note. Trimmed and rejected if blank, so a stray
## Enter-press on an empty box doesn't litter the list with nothing rows.
func add_note_entry(text: String) -> void:
    var trimmed: String = text.strip_edges()
    if trimmed == "":
        return
    _note_entries.append(trimmed)
    _save_puzzle_notes()


func remove_note_entry(index: int) -> void:
    if index < 0 or index >= _note_entries.size():
        return
    _note_entries.remove_at(index)
    _save_puzzle_notes()


## Every descriptor value the PLAYER has personally marked, as rendered
## terms ("N:Heleai", "C:Blue", "P:C#5", "S:5") — the same vocabulary the
## SEARCH tab and each clue's search_terms use, so a clue can be matched
## against it by what its text visibly says.
##
## "Personally marked" is the load-bearing part, and it is narrower than
## "has a non-zero state". Confirming one name calls
## _propagate_name_states_confirmed_same_record, which sets name_states to 2
## for every OTHER name on that record — counting those would turn nearly
## every clue magenta on the player's first click. Only a confirmation
## (state == 1) or a mark the player made by hand (the manual_*_blocks
## dicts, which exist precisely to tell those apart) counts here.
func player_marked_terms() -> Dictionary:
    var out: Dictionary = {}
    for r in _match_records:
        var rec: Dictionary = r
        for n in (rec.get("name_states", {}) as Dictionary):
            if int((rec.get("name_states", {}) as Dictionary)[n]) == 1 \
                    or (rec.get("manual_name_blocks", {}) as Dictionary).has(n):
                out["N:" + str(n)] = true

        # A record already bound to a star had its colour_states WRITTEN
        # from ground truth by _sync_color_states_from_star_idx, so a
        # "confirmed" colour there is not a player deduction — and it could
        # not be one anyway, since that star's colour is painted on the map.
        # Only a hand-placed block counts.
        var color_given: bool = int(rec.get("star_idx", -1)) >= 0
        for ci in (rec.get("color_states", {}) as Dictionary):
            var c_ok: bool = (rec.get("manual_color_blocks", {}) as Dictionary).has(ci)
            if not c_ok and not color_given:
                c_ok = int((rec.get("color_states", {}) as Dictionary)[ci]) == 1
            if c_ok:
                var idx: int = int(ci)
                if idx >= 0 and idx < _host.COLOR_NAME_LABELS.size():
                    out["C:" + str(_host.COLOR_NAME_LABELS[idx])] = true

        # Same for pitch, and this is the reported case: LISTEN calls
        # _propagate_pitch_confirmed_same_record, which writes
        # pitch_states[note] = 1 exactly as a player confirm would. Using a
        # reveal mechanic is not entering information, so listening to a
        # star must not turn clues magenta. Once the note is revealed, a
        # confirmation on that axis tells us nothing the reveal did not.
        var pitch_given: bool = bool(rec.get("pitch_revealed", false))
        for note in (rec.get("pitch_states", {}) as Dictionary):
            var p_ok: bool = (rec.get("manual_pitch_blocks", {}) as Dictionary).has(note)
            if not p_ok and not pitch_given:
                p_ok = int((rec.get("pitch_states", {}) as Dictionary)[note]) == 1
            if p_ok:
                out["P:" + str(note)] = true
        # Sequence has no per-value state dict; an exact pin IS the mark.
        var lo: int = int(rec.get("seq_lo", 0))
        if lo > 0 and lo == int(rec.get("seq_hi", 0)):
            out["S:%d" % lo] = true
    return out


func _save_puzzle_notes() -> void:
    # Every mutation path calls this, so it's the reliable choke point for
    # invalidating the derived caches — see _clear_deduction_caches().
    _clear_deduction_caches()
    if not _host._cd or _host._constellation_id < 0:
        return
    var notes: Dictionary = {}
    notes["match_records"] = _save_match_records()
    # WIRE KEY STAYS "retired_clues" — renamed to _noted_clue_refs in code
    # 2026-08-24 (Used Up became Notes), but every save on disk already uses
    # this key, and a save clues had filed away under the old "done" meaning
    # carry forward as Notes references under the new one, which is the
    # right outcome: nothing the player filed is lost, it just lives under
    # a tab with a clearer purpose now. Keyed by clue TEXT rather than
    # index, because clue order is not a stable identifier across a cache
    # regeneration.
    notes["retired_clues"] = _noted_clue_refs.keys()
    # Freeform notes. New field, no legacy key to preserve.
    notes["note_text_entries"] = _note_entries.duplicate()
    # protected_names / user_blocks are gone as separate note fields — the
    # star widget's protect and manual-block flags now live on each star's
    # own record, so they round-trip inside match_records above.
    # Sort:Repeats bucket shape — player-driven state, not derivable from
    # match_records alone (an empty bucket the player added but hasn't
    # filled a slot in yet would otherwise vanish on reload). New fields,
    # no legacy key to preserve.
    notes["repeat_bucket_values"] = _repeat_bucket_values.duplicate()
    notes["repeat_bucket_slot_counts"] = _repeat_bucket_slot_counts.duplicate()
    _host._cd.set_player_puzzle_notes(_host._constellation_id, notes)

# ==================================================
# DEDUCTION ENGINE CORE — record lookups, elimination
# propagation, merge/conflict logic, save/load
# ==================================================
func _clear_protected_names_for_star(star_idx: int) -> void:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        _match_records[idx]["protected_staff_names"] = {}




# ==================================================
# NAME-PROPAGATION HELPERS
# ==================================================
func _propagate_name_confirmed(confirmed_star: int, star_name: String) -> void:
    # A name belongs to exactly one star in the WHOLE constellation. Now that
    # star_elim lives on _match_records instead of a separate per-star array,
    # this one write is visible from every display surface that reads the
    # same record — the map widgets, and any future Sort: tab that shows
    # name/star candidates — with nothing left to fall out of sync.
    var this_record: int = _get_or_create_match_record_for_name(star_name)
    var this_elim: Dictionary = _match_records[this_record].get("star_elim", {})
    for j in _host._star_count:
        this_elim[j] = 1 if j == confirmed_star else 2
    _match_records[this_record]["star_elim"] = this_elim

    # The cross-record broadcast that used to live here is GONE (2026-08-13).
    # It wrote star_elim=2 into every OTHER name record's own dict, which is
    # the player-input layer — so "no other name is this star", an inference,
    # became indistinguishable from an X the player drew by hand. Measured:
    # undo the binding and those marks survived, released by nothing. That is
    # the non-releasable-state failure the derived layer was built to end,
    # and it had simply been reintroduced on this one path.
    #
    # _settle_alldiff_position_exclusions now derives the identical
    # conclusion every refresh, from the position's own collapsed row rather
    # than from this event, so it releases when its premise does and also
    # fires for positions the player never explicitly confirmed. Deleting
    # the broadcast without that pass would have LOST the deduction — it was
    # verified to be load-bearing, not merely redundant.
    #
    # The writes above, onto the confirming record itself, stay: those are a
    # faithful record of what the player actually asserted.
    _save_puzzle_notes()


# ==================================================
# RECORD IDENTITY LOOKUPS
# ==================================================

func _find_match_record_by_name(name_str: String) -> int:
    if name_str == "":
        return -1
    for i in _match_records.size():
        if _match_records[i]["name"] == name_str:
            return i
    return -1


func _star_elim_state(star_idx: int, name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx < 0:
        return 0
    var r: Dictionary = _match_records[idx]
    if _effective_star_idx(idx) == star_idx:
        return 1
    var own: int = int(r.get("star_elim", {}).get(star_idx, 0))
    if own != 0:
        return own      # the player's own X or check always wins
    return _derived_state(idx, "star_elim", star_idx)



## The record that owns a star's own per-star name-checklist flags. Same
## record the star widget already binds to, so its protect/manual-block
## state now merges, saves, and propagates like every other record field
## (see the note where _protected_names/_user_blocks used to be declared).
func _star_name_flags_record(star_idx: int) -> int:
    if star_idx < 0 or star_idx >= _host._star_count:
        return -1
    return _get_or_create_match_record_for_star_idx(star_idx)


func _is_name_protected(star_idx: int, name_str: String) -> bool:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return false
    return (_match_records[idx].get("protected_staff_names", {}) as Dictionary).has(name_str)


func _set_name_protected(star_idx: int, name_str: String, on: bool) -> void:
    var idx: int = _star_name_flags_record(star_idx)
    if idx < 0:
        return
    var protected: Dictionary = _match_records[idx].get("protected_staff_names", {})
    if on:
        protected[name_str] = true
    else:
        protected.erase(name_str)
    _match_records[idx]["protected_staff_names"] = protected


func _is_star_name_user_blocked(star_idx: int, name_str: String) -> bool:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return false
    return (_match_records[idx].get("manual_name_blocks", {}) as Dictionary).has(name_str)


func _set_star_name_user_blocked(star_idx: int, name_str: String, on: bool) -> void:
    var idx: int = _star_name_flags_record(star_idx)
    if idx < 0:
        return
    var manual: Dictionary = _match_records[idx].get("manual_name_blocks", {})
    if on:
        manual[name_str] = true
    else:
        manual.erase(name_str)
    _match_records[idx]["manual_name_blocks"] = manual


## Every name this star's row has a manual block on — replaces scanning a
## global dict's "star:name" keys with a straight read of that star's own
## record.
func _user_blocked_names_for_star(star_idx: int) -> Array[String]:
    var out: Array[String] = []
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return out
    for k in (_match_records[idx].get("manual_name_blocks", {}) as Dictionary):
        out.append(str(k))
    return out


func _clear_star_name_user_blocks(star_idx: int) -> void:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        _match_records[idx]["manual_name_blocks"] = {}


func _star_has_any_protected(star_idx: int, all_names_for_star: Array) -> bool:
    # Ignores stale protect flags on names that got hard-decided by some
    # other means since being protected (e.g. a later color elimination) —
    # only a name still sitting at neutral counts toward "protected."
    for n in all_names_for_star:
        var name_str: String = str(n)
        if _is_name_protected(star_idx, name_str) and _star_elim_state(star_idx, name_str) == 0:
            return true
    return false


func _effective_name_display_state(star_idx: int, name_str: String, all_names_for_star: Array) -> int:
    var base: int = _star_elim_state(star_idx, name_str)
    if base != 0:
        return base   # hard confirm (1) or hard eliminate (2) always wins
    if not _star_has_any_protected(star_idx, all_names_for_star):
        return 0       # neutral, nobody's protected anything yet in this row
    return 4 if _is_name_protected(star_idx, name_str) else 3


func _record_value_protected(record_idx: int, protect_key: String, value_key) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    var r: Dictionary = _match_records[record_idx]
    var protected: Dictionary = r.get(protect_key, {})
    return protected.has(value_key)


func _record_any_protected(record_idx: int, protect_key: String) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    var r: Dictionary = _match_records[record_idx]
    var protected: Dictionary = r.get(protect_key, {})
    return not protected.is_empty()


func _record_effective_state(record_idx: int, states_key: String, protect_key: String, value_key) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var base: int = int(states.get(value_key, 0))
    if base != 0:
        return base
    # Player input first, then the derived layer, then the soft
    # protect/"still possible" tier. Derived outranks protect because a
    # derived elimination is a hard conclusion while protect is only a
    # relative hint about the rest of the row.
    var der: int = _derived_state(record_idx, states_key, value_key)
    if der != 0:
        return der
    if not _record_any_protected(record_idx, protect_key):
        return 0
    return 4 if _record_value_protected(record_idx, protect_key, value_key) else 3




# ── Record-level Undo engine ──────────────────────────────────────────
# Mirrors the star widget's Undo selects/blocks/all row (_on_undo_name_*
# above), scoped to a single record's own states dict instead of a star's
# cross-record star_elim. "Selects" reverts the fallout of the record's
# OWN most recent confirm (sibling-clearing set every other value to
# eliminated); "blocks" reverts only the values the player X'd directly,
# tracked in the manual_*_blocks dicts added alongside name_states/
# pitch_states/color_states. The two are independent so they compose:
# a value the player X'd, that ALSO happened to be swept by a later
# confirm's sibling-clearing, stays flagged manual and survives
# "Undo selects" — only "Undo blocks" (or "Undo all") clears it.
func _undo_category_selects(record_idx: int, states_key: String, manual_key: String, protect_key: String, all_values: Array) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var manual: Dictionary = r.get(manual_key, {})
    for v in all_values:
        var cur: int = int(states.get(v, 0))
        if cur == 1 or (cur == 2 and not manual.has(v)):
            states[v] = 0
    r[states_key] = states
    # "still possible" protects only mean something relative to a
    # selection that no longer exists once that selection is undone —
    # same reasoning as _clear_protected_names_for_star.
    r[protect_key] = {}

    # Undo has to be the INVERSE of the confirm, and the confirm does two
    # things: it writes name_states, and it PROMOTES the name into r["name"]
    # (see _propagate_name_states_confirmed_same_record). Clearing only the
    # states left the promoted field standing, and _effective_name_state
    # reads that field — so the name still came back confirmed and the
    # button looked dead. Reported 2026-08-14 on a Sort:Pitch slot's name
    # checklist: select "Heleai", press UNDO SELECTS, nothing happens.
    #
    # _on_slot_name_check's toggle-off path already cleared r["name"] for
    # exactly this reason; the undo path was simply never updated when the
    # promotion was added, so the two ways of retracting a name disagreed.
    #
    # Only for a record whose identity rests on something ELSE. A Sort:Name
    # row's r["name"] is its DEFINING field, not a promotion — clearing that
    # would delete the row itself, turning an undo of some marks into the
    # destruction of the thing being marked.
    if states_key == "name_states":
        var promoted: String = str(r.get("name", ""))
        var defined_elsewhere: bool = str(r.get("pitch_slot_label", "")) != "" \
            or str(r.get("color_slot_label", "")) != "" \
            or str(r.get("degree_slot_label", "")) != "" \
            or int(r.get("star_idx", -1)) >= 0 \
            or (int(r.get("seq_lo", 0)) > 0 and int(r.get("seq_lo", 0)) == int(r.get("seq_hi", 0)))
        if promoted != "" and defined_elsewhere and int(states.get(promoted, 0)) != 1:
            r["name"] = ""


func _undo_category_blocks(record_idx: int, states_key: String, manual_key: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var manual: Dictionary = r.get(manual_key, {})
    for v in manual.keys():
        states[v] = 0
    r[states_key] = states
    r[manual_key] = {}




func _recompute_color_star_elim(record_idx: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Rules out every star OUTSIDE this record's candidate set, so the
    # star-map name checklists see the same closure the rest of the engine
    # uses: colour, degree, and Listen-revealed pitch all narrow it.
    # (Generalised 2026-08-07 from a colour-only version, which left a
    # reported hole — a name record with two colours eliminated stopped
    # being a candidate internally, but the widgets read star_elim and kept
    # offering that name on those stars.)
    #
    # PHASE 2. This used to write into the record's own star_elim and keep a
    # color_star_elim_marks dict so it could tell its output from the
    # player's on the way back out. That bookkeeping is what produced the
    # Keriion/Selion report — every non-candidate star got claimed as
    # engine-owned, including ones the player had X'd by hand, and the next
    # refresh that widened the candidate set "released" their input.
    #
    # Now the conclusion goes to the derived layer, which is wiped and
    # rebuilt every refresh. There is nothing to own, nothing to release,
    # and no way to touch player input from here — the whole mechanism is
    # gone rather than guarded. The honour_derived argument went with it:
    # reading derived state back is safe now, because a fact can only be
    # present if this refresh re-derived it from premises that still hold.
    var r: Dictionary = _match_records[record_idx]
    if str(r.get("name", "")) == "":
        return   # star_elim means "which stars can't be THIS NAME"
    if _effective_star_idx(record_idx) >= 0:
        return   # identity already pinned; ground truth governs
    var cands: Array = _candidate_stars_for_record(record_idx)
    if cands.is_empty() or cands.size() >= _host._star_count:
        return   # nothing known well enough to rule anything out
    var cand_set: Dictionary = {}
    for c in cands:
        cand_set[int(c)] = true
    for s in _host._star_count:
        if cand_set.has(s):
            continue
        _add_derived_state(record_idx, "star_elim", s, 2)


func _slot_letter(idx: int) -> String:
    return char(65 + idx) if idx < 26 else str(idx + 1)


func _anonymous_star_label(star_idx: int) -> String:
    var color_idx: int = _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else 1
    var color_name: String = _host.COLOR_NAME_LABELS[clamp(color_idx, 0, _host.COLOR_NAME_LABELS.size() - 1)]
    var ordinal: int = 0
    for s in _host._star_count:
        var sc: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
        if sc == color_idx and s < star_idx:
            ordinal += 1
    return "%s star %s" % [color_name, _slot_letter(ordinal)]




func _known_color_for_record(record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = _effective_star_idx(record_idx)
    if star_idx >= 0:
        # Clamped, not just bounds-checked against array size — _star_colors
        # is int-coerced but not range-clamped on load (constellation_study_
        # overlay.gd), so a corrupted/stale puzzle-cache entry could put an
        # out-of-range value here. The three callers in constellation_puzzle_
        # widgets.gd (_build_pitch_group_row) bracket-index the 4-element
        # STAR_COLORS_BY_IDX with this return value with no clamp of their
        # own — every OTHER _star_colors consumer in that file already
        # clamps to 0-3 before indexing the same array; this closes the one
        # path that routed through here instead and skipped it.
        return clamp(_host._star_colors[star_idx], 0, 3) if star_idx < _host._star_colors.size() else -1
    var cs: Dictionary = r.get("color_states", {})
    for ci in _host.COLOR_NAME_LABELS.size():
        if int(cs.get(ci, 0)) == 1:
            return ci
    return -1


func _sync_color_states_from_star_idx(record_idx: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    # OWN identity only, never effective. This function WRITES ground truth
    # into color_states, which is player-input storage — legitimate when the
    # player confirmed the identity, and a Phase 2 violation if a derived
    # binding could trigger it. A derived binding needs no write at all: the
    # ground-truth tier in _effective_color_state reads through
    # _effective_star_idx and reaches the same answer without touching the
    # record.
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx < 0 or star_idx >= _host._star_colors.size():
        return
    var true_color: int = clamp(_host._star_colors[star_idx], 0, 3)
    for ci in _host.COLOR_NAME_LABELS.size():
        r["color_states"][ci] = 1 if ci == true_color else 2
    # A color_slot_label ("Blue A") only means something while the record's
    # color is still ambiguous — once star_idx pins it to ground truth, a
    # label naming a DIFFERENT color is stale and would leave that slot's
    # Sort:Color row pointing at a record that no longer belongs there.
    var label: String = str(r.get("color_slot_label", ""))
    if label != "" and not label.begins_with(_host.COLOR_NAME_LABELS[true_color]):
        r["color_slot_label"] = ""


## Single source of truth for a match record's field set. The full literal
## used to be written out SIX times (once per _get_or_create_match_record_
## for_* function) with _save_match_records()/_load_match_records() carrying
## their own hand-maintained copies of the same field list on top — eight
## places to keep in sync, every one of them by hand. Adding or removing one
## field meant eight correct edits or a silently-dropped value; proven live
## when a field added for one experiment had to be threaded through all
## eight and then unpicked from all eight again.
##
## `overrides` sets whatever the specific creation site needs; everything
## else takes the default below. Load also starts from this, so a save
## written before a field existed comes back with that field's default
## rather than missing entirely.
func _new_match_record(overrides: Dictionary = {}) -> Dictionary:
    var r: Dictionary = {
        "name": "",
        "seq_lo": 0, "seq_hi": 0,
        # DISPLAY ONLY: the staff note numbers the player typed into the
        # lower / upper Sequence boxes, so a box can keep showing what was
        # typed. The bound itself lives in seq_lo / seq_hi (rank space); these
        # are shown only while they still agree with it (see
        # _exclusive_display_lo / _hi). 0 = nothing typed.
        "seq_tick_lo": 0, "seq_tick_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "degree_states": {},
        "name_states": {},
        "repeat_states": {},
        "manual_name_blocks": {},
        "manual_pitch_blocks": {},
        "manual_color_blocks": {},
        "manual_repeat_blocks": {},
        "protected_pitch_notes": {},
        "protected_color_idxs": {},
        "protected_staff_names": {},
        "protected_repeat_values": {},
        "pitch_revealed": false,
        "star_elim": {},
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": "",
        "repeat_slot_label": "",
        "melody_ticks": [],
        # The player's own "this star does NOT fire on that note" marks, by
        # staff note (2026-10-12: every note is on the Sequence row). Only
        # repeat notes ever go here; a first note is ruled out through the
        # position set above. A record holding one of these notes is then
        # provably a different star (_compute_records_provably_distinct).
        "seq_note_blocks": [],
    }
    for k in overrides:
        r[k] = overrides[k]
    return r


## TEST SEAM: true = the behaviour before 2026-10-13, where a colour slot could
## adopt a map star's own widget record. Only so a test can show the fault.
var color_slot_adopts_star_widgets: bool = false


func _get_or_create_match_record_for_color_slot(color_idx: int, position_in_group: int) -> int:
    var label: String = "%s %s" % [_host.COLOR_NAME_LABELS[color_idx], _slot_letter(position_in_group)]
    # A SLOT OF A SHARED COLOUR IS NEVER A MAP STAR'S OWN WIDGET RECORD
    # (reported 2026-10-13: "Color Slots are being assigned to specific stars
    # again"). "Blue A" is anonymous -- a row for SOME blue star -- and the
    # adoption below ("a record already known to be blue takes a blue slot")
    # was handing it the record the Star Map keeps for one particular blue
    # star. That record came to look "known to be blue" on 2026-10-12, when
    # placing a note on a star's widget started merging the note's record into
    # it: every merge ends by writing the star's true colour into the target
    # (_sync_color_states_from_star_idx). The slot then WAS that star, and
    # another blue star's data entered into it clashed with the first star's
    # pitch and count.
    #
    # So such a record is neither adopted nor, if an earlier session already
    # labelled it, kept as the slot: the label comes off and the slot gets a
    # fresh anonymous record. With only ONE star of the colour the slot is
    # that star by definition, and nothing changes.
    var shared: bool = _color_star_count(color_idx) > 1 and not color_slot_adopts_star_widgets
    for i in _match_records.size():
        if str(_match_records[i].get("color_slot_label", "")) == label:
            if shared and _record_is_unconfirmed_star_widget_stub(i):
                _match_records[i]["color_slot_label"] = ""
                continue
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("color_slot_label", "")) != "":
            continue
        if shared and _record_is_unconfirmed_star_widget_stub(i):
            continue
        if int(r.get("color_states", {}).get(color_idx, 0)) == 1:
            r["color_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"color_slot_label": label}))
    _sync_derived_size()
    return _match_records.size() - 1


func _get_or_create_match_record_for_pitch_slot(pitch_freq: float, position_in_group: int) -> int:
    var pitch_name: String = ConstellationLogicPuzzle.note_name_for_freq(pitch_freq)
    var label: String = "%s %s" % [pitch_name, _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("pitch_slot_label", "")) == label:
            return i
    var note_name: String = pitch_name
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("pitch_slot_label", "")) != "":
            continue
        if int(r.get("pitch_states", {}).get(note_name, 0)) == 1:
            r["pitch_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"pitch_slot_label": label}))
    _sync_derived_size()
    return _match_records.size() - 1


func _reconcile_unique_pitch_slot(record_idx: int, note_name: String) -> int:
    # _get_or_create_match_record_for_pitch_slot's "adopt an existing
    # confirmed record" path only runs at the moment a slot label is
    # FIRST created — if the Sort:Pitch tab was opened (creating blank
    # placeholder records, e.g. "G4 A" and "G4 B") before every star
    # sharing this note had been listened to, whichever placeholder is
    # still blank at that point is permanently locked in from then on by
    # the label-match lookup that always runs first: a LATER listen
    # confirming one of those stars never gets linked to it. Reported
    # 2026-08-29 as "listened to a star, its colour never showed up on
    # its Sort:Pitch slot" — that slot's record has a pitch_slot_label
    # (so _effective_pitch_state already reads it as confirmed) but no
    # star_idx, and colour reads star_idx, not the pitch label, so the
    # slot's colour stays unknown forever even though the star it
    # belongs to is now fully known.
    #
    # Safe to merge into a blank slot exactly when there is only ONE
    # candidate left for this confirm to be: every OTHER record already
    # wearing a pitch_slot_label for this note that has no star_idx of
    # its own. Zero means nothing is orphaned yet — either every slot
    # already resolved, or the tab was never opened, in which case the
    # ADOPT path above will still catch this record whenever a slot for
    # it IS first created. More than one is genuinely ambiguous: which
    # blank letter this star belongs to is arbitrary discovery order,
    # unrecoverable from a single confirm, so merging would be unsound —
    # this is the general form of the old star-count==1-only rule (one
    # slot total for the whole note, so at most one can ever be blank).
    # Called only from the Listen click handler (a deliberate, low-
    # frequency player action), never from the passive
    # _full_propagation_refresh path, so this is the one place in the
    # merge-vs-query tradeoff explored earlier where a merge is both safe
    # and necessary — there's no live-query equivalent that can make a
    # blank slot record's OWN star_idx exist.
    var label_prefix: String = note_name + " "
    var blank_slots: Array = []
    for i in _match_records.size():
        if i == record_idx:
            continue
        var r: Dictionary = _match_records[i]
        if not str(r.get("pitch_slot_label", "")).begins_with(label_prefix):
            continue
        if int(r.get("star_idx", -1)) < 0:
            blank_slots.append(i)
    if blank_slots.size() != 1:
        return record_idx
    var slot_idx: int = int(blank_slots[0])
    record_idx = await _merge_match_records(record_idx, slot_idx)
    return record_idx


func _get_or_create_match_record_for_name(name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx >= 0:
        return idx
    _match_records.append(_new_match_record({"name": name_str}))
    _sync_derived_size()
    return _match_records.size() - 1


func _get_or_create_match_record_for_seq(slot: int) -> int:
    var idx: int = _find_match_record_by_exact_seq(slot)
    if idx >= 0:
        return idx
    _match_records.append(_new_match_record({"seq_lo": slot, "seq_hi": slot}))
    _sync_derived_size()
    return _match_records.size() - 1


## Melody TICK identity (raw playback position, 1-indexed), never a resolved
## rank -- see melody_ticks' own field comment for why this exists as a
## SEPARATE keying scheme from _get_or_create_match_record_for_seq above,
## which that function's own `{"seq_lo": slot, "seq_hi": slot}` creation
## dict makes unsafe for this purpose: seeding a brand-new record with the
## TRUE rank the instant a tick is clicked writes ground truth into
## player-visible storage before the player has done anything (2026-09-28,
## found when the user pointed out the staff's melody replay -- and by
## extension its repeat pattern -- is the reward for solving, not a free
## tool, which invalidated this session's earlier "it's audible anyway"
## justification for the shared-record shortcut). A record created here
## starts with seq_lo/seq_hi at 0 (fully unknown), exactly like every other
## fresh record; it only gains a real Sequence pin through the player's own
## Name/Colour/Pitch/Seq. actions, same as any other record. Two different
## ticks that turn out to be the same star still end up sharing one record —
## but only once the player's OWN marks prove it, via the ordinary identity-
## merge machinery (_merge_match_records unions their melody_ticks), never
## because a click silently looked up the answer.
func _find_match_record_by_melody_tick(tick: int) -> int:
    for i in _match_records.size():
        if (_match_records[i].get("melody_ticks", []) as Array).has(tick):
            return i
    return -1


func _get_or_create_match_record_for_melody_tick(tick: int) -> int:
    # One note, one record. Notes are never grouped on the click (2026-10-10:
    # repeats are earned, see _seq_pos_for_melody_tick). Two notes come to
    # share a record only through the ordinary identity merge, once the
    # player's own marks say they are the same star -- naming both, or placing
    # a repeat note on a position (the Staff popup's "Same star as note" row).
    var found: int = _find_match_record_by_melody_tick(tick)
    if found >= 0:
        return found
    _match_records.append(_new_match_record({"melody_ticks": [tick]}))
    _sync_derived_size()
    return _match_records.size() - 1


## Lets go of a staff note that an identity merge attached to a NAMED record.
## Merging unions melody_ticks and nothing ever takes them back out, so once a
## note had been named (and so merged into that star's Sort row) the Staff
## popup's Name Undo cleared the name marks but left the note on the record:
## still labelled with the star, still deriving its position, so Undo looked
## like it did nothing.
##
## Moves THIS note (and only this one: every other note on the record got there
## by the player's own proof and is not this Undo's to take back) onto a fresh,
## unmarked record and leaves everything else on the named record, which is
## the Sort row's, as it was.
## Marks the player entered on the note itself before the merge cannot be told
## apart from the row's, so they stay with the row; the note starts clean.
## Returns the fresh record's index, or -1 when there was nothing to detach
## (the record is not named, or the note is not on it).
func _detach_melody_ticks_from_named_record(tick: int, record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var rec: Dictionary = _match_records[record_idx]
    if str(rec.get("name", "")) == "" and int(rec.get("star_idx", -1)) < 0:
        return -1
    return _detach_melody_tick(tick, record_idx)


## The move itself, with no condition on what the record is: used by the Name
## Undo above and by the Staff popup's "Same star as note" Undo, which lets a
## repeat note go from whatever record the player had placed it on.
func _detach_melody_tick(tick: int, record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var rec: Dictionary = _match_records[record_idx]
    var have: Array = rec.get("melody_ticks", [])
    if not have.has(tick):
        return -1
    var kept: Array = []
    for t in have:
        if int(t) != tick:
            kept.append(t)
    rec["melody_ticks"] = kept
    _match_records.append(_new_match_record({"melody_ticks": [tick]}))
    _sync_derived_size()
    return _match_records.size() - 1


func _get_or_create_match_record_for_star_idx(star_idx: int) -> int:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        return idx
    _match_records.append(_new_match_record({"star_idx": star_idx}))
    _sync_derived_size()
    return _match_records.size() - 1


func _get_or_create_match_record_for_degree_slot(degree: int, position_in_group: int) -> int:
    # Label carries the degree VALUE ("Conn3 A"), not a bare "Conn A". The
    # old format collided across groups: the degree-2 group's "A" slot and
    # the degree-3 group's "A" slot produced the identical string, so any
    # label-equality check treated two records for provably DIFFERENT stars
    # as the same slot — including _records_provably_identical's slot-label
    # branch, which would have merged them outright. Also what blocked
    # Degree from participating in group/member propagation at all, since
    # the group couldn't be identified from the label.
    var label: String = "Conn%d %s" % [degree, _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("degree_slot_label", "")) == label:
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("degree_slot_label", "")) != "":
            continue
        if int(r.get("degree_states", {}).get(degree, 0)) == 1:
            r["degree_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"degree_slot_label": label}))
    _sync_derived_size()
    return _match_records.size() - 1


## Which record IS this position, if one already is.
##
## READS THE EFFECTIVE CANDIDATE SET, not seq_lo/seq_hi. A position the
## player established by DEDUCTION lives in the derived layer and
## deliberately never touches those fields (see test_derived_layer:
## "...WITHOUT writing into the player's own seq_lo"), so the old own-field
## test could not see it. Reported live:
##
##   "Player has locked Keriion down as Sequence 8, and also an A4 star
##    which means it's either yellow or red, but that did not propagate to
##    the Staff popup for sequence 8. It DOES show up on Keriion's Name tab."
##
## Keriion's pin was derived, so this returned -1, and
## _get_or_create_match_record_for_seq appended a SECOND, empty record for
## position 8. The popup read that one — hence a blank popup beside a
## correct Name tab, for the same star.
##
## THE EXACT MISTAKE _seq_singleton_owners ALREADY FIXED, still standing
## here: "Reading seq_lo == seq_hi alone stopped seeing derived pins the
## moment they moved into the derived layer, which silently dropped every
## exclusion cascade." One instance was corrected; this one was missed.
##
## Every caller is a UI path (popup open, widget build), never the
## fixpoint, so scanning the effective set here costs nothing per refresh.
func _find_match_record_by_exact_seq(seq: int) -> int:
    for i in _match_records.size():
        var s: Array = _seq_candidate_set_for(i)
        if s.size() == 1 and int(s[0]) == seq:
            return i
    return -1


## THE SAME MISTAKE _find_match_record_by_exact_seq's own header describes
## as "still standing here" -- read the raw own field, not
## _effective_star_idx(). _settle_identical_records() deliberately never
## merges an unconfirmed star-widget stub into the "real" record it
## matches (see that function's header: a merge would make the engine's
## inference unretractable) -- instead it writes the shared star onto the
## REAL record's DERIVED layer only, leaving the stub's own star_idx
## field as the sole remaining owner of the raw value. A raw-field-only
## scan therefore always finds the stub -- the one record that, by
## definition (_record_is_unconfirmed_star_widget_stub), never gets a
## name or a collapsed Sequence range -- while the fully-resolved record
## for the exact same physical star sits right beside it, invisible to
## this lookup. Reported live: Helios/C#5 correct on the Staff line and
## the Pitch tab (both read through _effective_*/derived-aware paths),
## still "4,7,12" on the star's own Star Map popup (built from whatever
## _get_or_create_match_record_for_star_idx hands it).
##
## Fix: scan by _effective_star_idx (own field OR derived fallback), and
## when more than one record matches the same physical star (a stub AND
## its now-linked real record both effectively point at it), prefer the
## non-stub one — the informative record is what a UI lookup wants,
## while _settle_identical_records's own refusal to merge is untouched.
func _find_match_record_by_star_idx(star_idx: int) -> int:
    if star_idx < 0:
        return -1
    var stub_idx: int = -1
    for i in _match_records.size():
        if _effective_star_idx(i) != star_idx:
            continue
        if not _record_is_unconfirmed_star_widget_stub(i):
            return i
        if stub_idx < 0:
            stub_idx = i
    return stub_idx




## allow_await=false is for SYNCHRONOUS callers (currently
## _settle_identical_records, which runs inside the non-async
## _full_propagation_refresh). A coroutine suspended mid-merge would
## silently abandon the rest of the refresh, so in that mode this function
## refuses any merge that would need a conflict dialog and leaves the pair
## for the explicit commit paths, which can await properly.
##
## Two layers keep that honest: the _merge_conflict_kinds() check below —
## the SINGLE place conflicts are detected, shared with
## _records_have_merge_conflict() so the two can't drift — and a fail-safe
## `if not allow_await: return` at every dialog site, so a future conflict
## added without updating the kinds list degrades to an abandoned merge
## rather than a suspended refresh.
func _merge_match_records(target_idx: int, source_idx: int, allow_await: bool = true) -> int:
    if target_idx == source_idx:
        return target_idx
    if target_idx < 0 or target_idx >= _match_records.size() \
            or source_idx < 0 or source_idx >= _match_records.size():
        return target_idx
    if not allow_await and not _merge_conflict_kinds(target_idx, source_idx).is_empty():
        return target_idx
    # A confirm/eliminate clash refuses the merge on BOTH paths, unlike the
    # confirm-vs-confirm kinds above, which have conflict dialogs and are
    # only gated on the non-await path. There is nothing to ask the player
    # here: the two marks cannot both be right, the union would resolve it
    # by destroying one, and a destroyed mark cannot be reported later
    # because the evidence is what got destroyed. Refusing keeps both
    # records and both marks alive, and _detect_contradictions surfaces the
    # pair on this very refresh.
    if not _merge_value_clashes(target_idx, source_idx).is_empty():
        return target_idx
    var entry_generation: int = _match_records_generation
    var target: Dictionary = _match_records[target_idx]
    var source: Dictionary = _match_records[source_idx]

    # Tracks a name that lost the "Keep: X / Keep: Y" conflict below, so it can
    # be explicitly re-eliminated for the resolved star after its own record
    # gets deleted by this merge — otherwise that elimination is lost entirely
    # and the checklist row comes back up neutral next rebuild.
    var discarded_name: String = ""

    if target["name"] == "" and source["name"] != "":
        target["name"] = source["name"]
    elif target["name"] != "" and source["name"] != "" and target["name"] != source["name"]:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var kept_name: String = await _conflict_dialog_fn.call("name", target["name"], source["name"])
        discarded_name = source["name"] if kept_name == target["name"] else target["name"]
        target["name"] = kept_name

    # Intersect both sides' bounds (0 = unconstrained on that side) instead
    # of branching on seq_lo alone. The old branch only ever checked
    # seq_lo>0 to decide whether source had "real" sequence info — a
    # hi-only exclusive bound (seq_lo==0, seq_hi>0, e.g. "not the last
    # position") carries real information too, but was silently DROPPED
    # whenever it merged into a target with no lo of its own (neither
    # branch matched), and silently OVERWRITTEN by whichever side merged in
    # second otherwise — losing exactly the kind of fact
    # _records_provably_distinct's sequence check now depends on.
    var t_lo: int = int(target["seq_lo"])
    var t_hi: int = int(target["seq_hi"])
    var s_lo: int = int(source["seq_lo"])
    var s_hi: int = int(source["seq_hi"])
    var t_exact: bool = t_lo > 0 and t_lo == t_hi
    var s_exact: bool = s_lo > 0 and s_lo == s_hi
    if t_exact and s_exact and t_lo != s_lo:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_seq: int = int(await _conflict_dialog_fn.call(
            "sequence position", str(t_lo), str(s_lo)))
        target["seq_lo"] = winning_seq
        target["seq_hi"] = winning_seq
    elif t_lo > 0 or t_hi > 0 or s_lo > 0 or s_hi > 0:
        var new_lo: int = max(t_lo, s_lo)
        var hi_candidates: Array = []
        if t_hi > 0: hi_candidates.append(t_hi)
        if s_hi > 0: hi_candidates.append(s_hi)
        var new_hi: int = hi_candidates.min() if not hi_candidates.is_empty() else 0
        if new_lo > 0 and new_hi > 0 and new_lo > new_hi:
            # The two partial bounds contradict once intersected (shouldn't
            # arise from sound player input) — keep target's own prior
            # bounds rather than write an inverted, meaningless range.
            new_lo = t_lo
            new_hi = t_hi
        target["seq_lo"] = new_lo
        target["seq_hi"] = new_hi
    # The typed-note memory belongs to ONE record's own entry; two merged
    # records' bounds were just intersected, so neither typed value is known
    # to describe the result. Forget both and let the boxes show the bound.
    target["seq_tick_lo"] = 0
    target["seq_tick_hi"] = 0

    var target_cand: Array = target.get("seq_candidates", [])
    var source_cand: Array = source.get("seq_candidates", [])
    if target_cand.is_empty() and not source_cand.is_empty():
        target["seq_candidates"] = source_cand.duplicate()
    elif not target_cand.is_empty() and not source_cand.is_empty():
        var merged_cand: Array = []
        for v in target_cand:
            if source_cand.has(v):
                merged_cand.append(v)
        target["seq_candidates"] = merged_cand

    # Same conflict-detection shape as the pitch merge just below — two
    # DIFFERENT hard-confirmed colors on either side of a merge is a real
    # contradiction, not something a blind key-by-key union should paper
    # over. This was missing here even though the pitch logic right below
    # already did it correctly — exactly the same failure class as the
    # star-identity/color bug already fixed elsewhere in this file.
    var target_confirmed_color: int = -1
    for ck0 in target["color_states"]:
        if int(target["color_states"][ck0]) == 1:
            target_confirmed_color = int(ck0)
            break
    var source_confirmed_color: int = -1
    for ck1 in source["color_states"]:
        if int(source["color_states"][ck1]) == 1:
            source_confirmed_color = int(ck1)
            break
    if target_confirmed_color >= 0 and source_confirmed_color >= 0 and target_confirmed_color != source_confirmed_color:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_color: String = await _conflict_dialog_fn.call(
            "confirmed color", _host.COLOR_NAME_LABELS[target_confirmed_color], _host.COLOR_NAME_LABELS[source_confirmed_color])
        if winning_color == _host.COLOR_NAME_LABELS[source_confirmed_color]:
            target["color_states"][target_confirmed_color] = 0
            target_confirmed_color = source_confirmed_color
        else:
            source["color_states"][source_confirmed_color] = 0
            source_confirmed_color = -1

    for ck in source["color_states"]:
        var sv: int = int(source["color_states"][ck])
        var tv: int = int(target["color_states"].get(ck, 0))
        if int(ck) == source_confirmed_color and target_confirmed_color >= 0 and int(ck) != target_confirmed_color:
            continue
        if sv == 1 or tv == 1:
            target["color_states"][ck] = 1
        elif sv == 2 or tv == 2:
            target["color_states"][ck] = 2

    # Same fix, degree axis.
    var target_confirmed_degree: int = -1
    for dk0 in target["degree_states"]:
        if int(target["degree_states"][dk0]) == 1:
            target_confirmed_degree = int(dk0)
            break
    var source_confirmed_degree: int = -1
    for dk1 in source["degree_states"]:
        if int(source["degree_states"][dk1]) == 1:
            source_confirmed_degree = int(dk1)
            break
    if target_confirmed_degree >= 0 and source_confirmed_degree >= 0 and target_confirmed_degree != source_confirmed_degree:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_degree: String = await _conflict_dialog_fn.call(
            "confirmed degree", str(target_confirmed_degree), str(source_confirmed_degree))
        if winning_degree == str(source_confirmed_degree):
            target["degree_states"][target_confirmed_degree] = 0
            target_confirmed_degree = source_confirmed_degree
        else:
            source["degree_states"][source_confirmed_degree] = 0
            source_confirmed_degree = -1

    for dk in source["degree_states"]:
        var sv_d: int = int(source["degree_states"][dk])
        var tv_d: int = int(target["degree_states"].get(dk, 0))
        if int(dk) == source_confirmed_degree and target_confirmed_degree >= 0 and int(dk) != target_confirmed_degree:
            continue
        if sv_d == 1 or tv_d == 1:
            target["degree_states"][dk] = 1
        elif sv_d == 2 or tv_d == 2:
            target["degree_states"][dk] = 2

    var target_confirmed_note: String = ""
    for pk0 in target["pitch_states"]:
        if int(target["pitch_states"][pk0]) == 1:
            target_confirmed_note = str(pk0)
            break
    var source_confirmed_note: String = ""
    for pk1 in source["pitch_states"]:
        if int(source["pitch_states"][pk1]) == 1:
            source_confirmed_note = str(pk1)
            break
    if target_confirmed_note != "" and source_confirmed_note != "" and target_confirmed_note != source_confirmed_note:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_note: String = await _conflict_dialog_fn.call(
            "confirmed pitch", target_confirmed_note, source_confirmed_note)
        if winning_note == source_confirmed_note:
            target["pitch_states"][target_confirmed_note] = 0
            target_confirmed_note = source_confirmed_note
        else:
            source["pitch_states"][source_confirmed_note] = 0
            source_confirmed_note = ""

    for pk in source["pitch_states"]:
        var sv2: int = int(source["pitch_states"][pk])
        var tv2: int = int(target["pitch_states"].get(pk, 0))
        if pk == source_confirmed_note and target_confirmed_note != "" and pk != target_confirmed_note:
            continue
        if sv2 == 1 or tv2 == 1:
            target["pitch_states"][pk] = 1
        elif sv2 == 2 or tv2 == 2:
            target["pitch_states"][pk] = 2

    if bool(source.get("pitch_revealed", false)):
        target["pitch_revealed"] = true

    # Same conflict-detection shape as color/degree/pitch above. Found while
    # building the Sort:Repeats tab (2026-09-30): this whole function is
    # explicit field-by-field with no generic fallback (see this function's
    # own "anything not copied over here is gone for good" comment below),
    # and repeat_states had no entry at all — a Repeats confirm on either
    # side of a Name/Colour/Pitch-proven merge would have been silently
    # discarded the instant the merge ran.
    var target_confirmed_repeat: int = -1
    for rk0 in target["repeat_states"]:
        if int(target["repeat_states"][rk0]) == 1:
            target_confirmed_repeat = int(rk0)
            break
    var source_confirmed_repeat: int = -1
    for rk1 in source["repeat_states"]:
        if int(source["repeat_states"][rk1]) == 1:
            source_confirmed_repeat = int(rk1)
            break
    if target_confirmed_repeat >= 0 and source_confirmed_repeat >= 0 and target_confirmed_repeat != source_confirmed_repeat:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_repeat: String = await _conflict_dialog_fn.call(
            "confirmed repeat count", str(target_confirmed_repeat), str(source_confirmed_repeat))
        if winning_repeat == str(source_confirmed_repeat):
            target["repeat_states"][target_confirmed_repeat] = 0
            target_confirmed_repeat = source_confirmed_repeat
        else:
            source["repeat_states"][source_confirmed_repeat] = 0
            source_confirmed_repeat = -1

    for rk in source["repeat_states"]:
        var sv_r: int = int(source["repeat_states"][rk])
        var tv_r: int = int(target["repeat_states"].get(rk, 0))
        if int(rk) == source_confirmed_repeat and target_confirmed_repeat >= 0 and int(rk) != target_confirmed_repeat:
            continue
        if sv_r == 1 or tv_r == 1:
            target["repeat_states"][rk] = 1
        elif sv_r == 2 or tv_r == 2:
            target["repeat_states"][rk] = 2

    var target_elim: Dictionary = target.get("star_elim", {})
    var source_elim: Dictionary = source.get("star_elim", {})
    for sk in source_elim:
        var sv3: int = int(source_elim[sk])
        var tv3: int = int(target_elim.get(sk, 0))
        if sv3 == 1 or tv3 == 1:
            target_elim[sk] = 1
        elif sv3 == 2 or tv3 == 2:
            target_elim[sk] = 2
    target["star_elim"] = target_elim

    # source gets deleted at the end of this function — anything not copied
    # over here is gone for good. name_states was being silently dropped
    # (union merge, same shape as star_elim above — a genuinely conflicting
    # pair of confirmed names is already caught by the "name" field's own
    # dialog-protected merge near the top of this function, so this doesn't
    # need its own dialog). The three protected_* dicts are just "still
    # possible" cosmetic hints, not hard facts, so a plain union is enough.
    var target_name_states: Dictionary = target.get("name_states", {})
    var source_name_states: Dictionary = source.get("name_states", {})
    for nk in source_name_states:
        var snv: int = int(source_name_states[nk])
        var tnv: int = int(target_name_states.get(nk, 0))
        if snv == 1 or tnv == 1:
            target_name_states[nk] = 1
        elif snv == 2 or tnv == 2:
            target_name_states[nk] = 2
    target["name_states"] = target_name_states

    for protect_key in ["protected_pitch_notes", "protected_color_idxs", "protected_staff_names", "protected_repeat_values", "manual_name_blocks", "manual_pitch_blocks", "manual_color_blocks", "manual_repeat_blocks"]:
        var target_protect: Dictionary = target.get(protect_key, {})
        var source_protect: Dictionary = source.get(protect_key, {})
        for pk in source_protect:
            target_protect[pk] = true
        target[protect_key] = target_protect

    if int(target["star_idx"]) < 0 and int(source["star_idx"]) >= 0:
        target["star_idx"] = source["star_idx"]

    # UNION, not overwrite: once two tick-anchored records are proven to be
    # the same star (via a Name/Colour/Pitch confirm shared between them —
    # see melody_ticks' own comment), the merged record needs to answer to
    # EVERY tick either one did, so re-clicking any of them still finds it.
    var target_ticks: Array = target.get("melody_ticks", [])
    for t in source.get("melody_ticks", []):
        if not target_ticks.has(t):
            target_ticks.append(t)
    target["melody_ticks"] = target_ticks

    # The same star's "does not fire on note N" marks, from either record.
    var target_blocks: Array = target.get("seq_note_blocks", [])
    for bt in source.get("seq_note_blocks", []):
        if not target_blocks.has(bt):
            target_blocks.append(bt)
    target["seq_note_blocks"] = target_blocks

    var target_label: String = str(target.get("color_slot_label", ""))
    var source_label: String = str(source.get("color_slot_label", ""))
    if target_label == "" and source_label != "":
        target["color_slot_label"] = source_label
    elif target_label != "" and source_label != "" and target_label != source_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["color_slot_label"] = await _conflict_dialog_fn.call("color slot label", target_label, source_label)

    var target_pitch_label: String = str(target.get("pitch_slot_label", ""))
    var source_pitch_label: String = str(source.get("pitch_slot_label", ""))
    if target_pitch_label == "" and source_pitch_label != "":
        target["pitch_slot_label"] = source_pitch_label
    elif target_pitch_label != "" and source_pitch_label != "" and target_pitch_label != source_pitch_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["pitch_slot_label"] = await _conflict_dialog_fn.call("pitch slot label", target_pitch_label, source_pitch_label)

    var target_degree_label: String = str(target.get("degree_slot_label", ""))
    var source_degree_label: String = str(source.get("degree_slot_label", ""))
    if target_degree_label == "" and source_degree_label != "":
        target["degree_slot_label"] = source_degree_label
    elif target_degree_label != "" and source_degree_label != "" and target_degree_label != source_degree_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["degree_slot_label"] = await _conflict_dialog_fn.call("degree slot label", target_degree_label, source_degree_label)

    var target_repeat_label: String = str(target.get("repeat_slot_label", ""))
    var source_repeat_label: String = str(source.get("repeat_slot_label", ""))
    if target_repeat_label == "" and source_repeat_label != "":
        target["repeat_slot_label"] = source_repeat_label
    elif target_repeat_label != "" and source_repeat_label != "" and target_repeat_label != source_repeat_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["repeat_slot_label"] = await _conflict_dialog_fn.call("repeats slot label", target_repeat_label, source_repeat_label)

    # _match_records may have been cleared/rebuilt by one of the awaits
    # above (see _match_records_generation's own comment) — target_idx/
    # source_idx and the target/source Dictionary references could now
    # point at nothing, or at unrelated records in a freshly-rebuilt
    # array. Abort here rather than let remove_at()/the bracket-indexing
    # below act on stale indices.
    if _match_records_generation != entry_generation:
        return target_idx

    _sync_color_states_from_star_idx(target_idx)
    _match_records.remove_at(source_idx)
    # Drop the SAME index, not the tail: the two arrays are positional, and
    # truncating the end after removing from the middle would silently shift
    # every derived entry past source_idx onto the wrong record.
    if source_idx < _derived.size():
        _derived.remove_at(source_idx)
    if source_idx < target_idx:
        target_idx -= 1

    # The name that lost the conflict above no longer has any record of its own —
    # whichever side it came from was just deleted. Re-create a blank record for
    # it now and immediately mark it eliminated for the star this merged record
    # ended up representing, so the checklist row stays darkened instead of
    # reverting to a fresh, unmarked neutral candidate on the next rebuild.
    if discarded_name != "" and int(_match_records[target_idx]["star_idx"]) >= 0:
        var resolved_star: int = int(_match_records[target_idx]["star_idx"])
        var loser_record_idx: int = _get_or_create_match_record_for_name(discarded_name)
        if loser_record_idx != target_idx:
            var loser_elim: Dictionary = _match_records[loser_record_idx].get("star_elim", {})
            loser_elim[resolved_star] = 2
            _match_records[loser_record_idx]["star_elim"] = loser_elim

    return target_idx


func _confirm_match_record_identity(record_idx: int, star_idx: int, star_name: String) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1  # callers already treat a negative return as "abort"
    # See _match_records_generation's comment — this function holds
    # record_idx/Dictionary references across three separate awaits
    # (including one that calls _merge_match_records, which does its own
    # rebuild-during-await work). Checked after each one below.
    var entry_generation: int = _match_records_generation
    # Color contradiction check FIRST, before any merge — every star widget
    # auto-creates a blank star_idx-bound record just by rendering, so the
    # merge below runs almost every time a name gets confirmed onto a star.
    # _merge_match_records ends with its own unconditional
    # _sync_color_states_from_star_idx(target_idx) call, which silently
    # resyncs color_states from star_idx — checking for a contradiction
    # AFTER that merge would just find the record already rewritten to
    # agree with itself. Ground truth (_host._star_colors) doesn't need the
    # record to have merged anything first, so this check can and must run
    # before the merge touches anything.
    var true_color: int = clamp(_host._star_colors[star_idx] if star_idx < _host._star_colors.size() else 1, 0, 3)
    var r0: Dictionary = _match_records[record_idx]
    var prior_confirmed_color: int = -1
    for ci in _host.COLOR_NAME_LABELS.size():
        if int(r0["color_states"].get(ci, 0)) == 1:
            prior_confirmed_color = ci
            break
    if prior_confirmed_color >= 0 and prior_confirmed_color != true_color:
        var old_color_label: String = "%s (previous)" % _host.COLOR_NAME_LABELS[prior_confirmed_color]
        var new_color_label: String = "%s (%s's true color)" % [_host.COLOR_NAME_LABELS[true_color], star_name]
        var color_winner: String = await _conflict_dialog_fn.call(
            "color for '%s'" % star_name, old_color_label, new_color_label)
        if color_winner == old_color_label:
            return -1
        if _match_records_generation != entry_generation:
            return -1

    var existing_by_star: int = _find_match_record_by_star_idx(star_idx)
    if existing_by_star >= 0 and existing_by_star != record_idx:
        record_idx = await _merge_match_records(record_idx, existing_by_star)
        if _match_records_generation != entry_generation \
                or record_idx < 0 or record_idx >= _match_records.size():
            return -1

    var r: Dictionary = _match_records[record_idx]
    if int(r["star_idx"]) >= 0 and int(r["star_idx"]) != star_idx:
        var old_label: String = "%s (current)" % _anonymous_star_label(int(r["star_idx"]))
        var new_label: String = "%s (just checked)" % _anonymous_star_label(star_idx)
        var winner: String = await _conflict_dialog_fn.call(
            "star identity for '%s'" % star_name, old_label, new_label)
        if winner == old_label:
            return -1
        if _match_records_generation != entry_generation:
            return -1

    if str(r["name"]) == "":
        r["name"] = star_name
    r["star_idx"] = star_idx
    _sync_color_states_from_star_idx(record_idx)

    var elim: Dictionary = r.get("star_elim", {})
    for j in _host._star_count:
        elim[j] = 1 if j == star_idx else 2
    r["star_elim"] = elim

    return record_idx


func _save_match_records() -> Array:
    # Deep-copies whatever the record actually holds instead of restating
    # the field list a third time. The old per-field version had to be kept
    # in sync with _new_match_record() and _load_match_records() by hand,
    # and a field missing from THIS list was written to disk as gone —
    # silent, and invisible until the next load. Values are already
    # correctly typed in memory (creation goes through _new_match_record,
    # load coerces on the way in), so no per-field coercion is needed here;
    # the int-key-becomes-String hazard of a JSON round-trip is handled on
    # the load side by _coerce_int_key, which is where it actually happens.
    var out: Array = []
    for r in _match_records:
        out.append((r as Dictionary).duplicate(true))
    return out


func _load_match_records(data: Array) -> void:
    _match_records.clear()
    _match_records_generation += 1
    _clear_deduction_caches()
    for entry in data:
        if not entry is Dictionary:
            continue
        var e: Dictionary = entry

        var raw_color_states: Dictionary = _coerce_dict(e.get("color_states"), {})
        var color_states: Dictionary = {}
        for ck in raw_color_states:
            var color_idx: int = _coerce_int_key(ck, -1)
            # Unlike pitch/name/degree_states (string or open-ended int keys,
            # never used to index a fixed-size array), color_states keys DO
            # get bracket-indexed straight into the 4-entry COLOR_NAME_LABELS/
            # STAR_COLORS_BY_IDX arrays elsewhere (_display_color_for_record,
            # _merge_match_records) with no bounds check at the read site —
            # a corrupted/hand-edited save with an out-of-range key would
            # crash there. Dropped here rather than clamped: clamping a KEY
            # (unlike clamping a scalar value elsewhere in this file) risks
            # silently colliding with — and overwriting — a different,
            # already-valid color's real state.
            if color_idx < 0 or color_idx >= _host.COLOR_NAME_LABELS.size():
                continue
            color_states[color_idx] = _coerce_int(raw_color_states[ck], 0)

        var raw_pitch_states: Dictionary = _coerce_dict(e.get("pitch_states"), {})
        var pitch_states: Dictionary = {}
        for pk in raw_pitch_states:
            pitch_states[str(pk)] = _coerce_int(raw_pitch_states[pk], 0)

        var raw_star_elim: Dictionary = _coerce_dict(e.get("star_elim"), {})
        var star_elim: Dictionary = {}
        for sk in raw_star_elim:
            var star_key: int = _coerce_int_key(sk, -1)
            if star_key < 0:
                continue
            star_elim[star_key] = _coerce_int(raw_star_elim[sk], 0)

        # color_star_elim_marks / derived_value_elim_marks are deliberately
        # NOT read back. They were ownership bookkeeping for derived facts
        # written into player fields; Phase 2 moved those facts to the
        # derived layer, which is rebuilt from scratch every refresh and
        # never saved. Old saves still carry both keys — dropping them here
        # is the migration, and costs nothing, since everything they
        # described gets re-derived on the first refresh anyway.
        var raw_name_states: Dictionary = _coerce_dict(e.get("name_states"), {})
        var name_states: Dictionary = {}
        for nk in raw_name_states:
            name_states[str(nk)] = _coerce_int(raw_name_states[nk], 0)

        var manual_name_blocks: Dictionary = {}
        for mnk in _coerce_dict(e.get("manual_name_blocks"), {}):
            manual_name_blocks[str(mnk)] = true

        var manual_pitch_blocks: Dictionary = {}
        for mpk in _coerce_dict(e.get("manual_pitch_blocks"), {}):
            manual_pitch_blocks[str(mpk)] = true

        var manual_color_blocks: Dictionary = {}
        for mck in _coerce_dict(e.get("manual_color_blocks"), {}):
            var mc_idx: int = _coerce_int_key(mck, -1)
            if mc_idx < 0 or mc_idx >= _host.COLOR_NAME_LABELS.size():
                continue
            manual_color_blocks[mc_idx] = true

        var raw_degree_states: Dictionary = _coerce_dict(e.get("degree_states"), {})
        var degree_states: Dictionary = {}
        for dk in raw_degree_states:
            var degree_key: int = _coerce_int_key(dk, -1)
            if degree_key < 0:
                continue
            degree_states[degree_key] = _coerce_int(raw_degree_states[dk], 0)

        # Missing from this function was the exact gotcha this file's own
        # comment on _blank_derived_entry() warns about for a new axis:
        # Category.REPEAT existed as a live clue axis for days before this
        # was added, and nothing round-tripped a player's repeat_states mark
        # through save/load until now -- a Sort:Repeats confirm would have
        # silently reverted to unknown on the very next reload.
        var raw_repeat_states: Dictionary = _coerce_dict(e.get("repeat_states"), {})
        var repeat_states: Dictionary = {}
        for rk in raw_repeat_states:
            var repeat_key: int = _coerce_int_key(rk, -1)
            if repeat_key < 0:
                continue
            repeat_states[repeat_key] = _coerce_int(raw_repeat_states[rk], 0)

        var manual_repeat_blocks: Dictionary = {}
        for mrk in _coerce_dict(e.get("manual_repeat_blocks"), {}):
            var mr_idx: int = _coerce_int_key(mrk, -1)
            if mr_idx < 0:
                continue
            manual_repeat_blocks[mr_idx] = true

        var protected_repeat_values: Dictionary = {}
        for prk in _coerce_dict(e.get("protected_repeat_values"), {}):
            var pr_idx: int = _coerce_int_key(prk, -1)
            if pr_idx < 0:
                continue
            protected_repeat_values[pr_idx] = true

        var protected_pitch_notes: Dictionary = {}
        for ppk in _coerce_dict(e.get("protected_pitch_notes"), {}):
            protected_pitch_notes[str(ppk)] = true

        var protected_color_idxs: Dictionary = {}
        for pck in _coerce_dict(e.get("protected_color_idxs"), {}):
            var pc_idx: int = _coerce_int_key(pck, -1)
            if pc_idx < 0 or pc_idx >= _host.COLOR_NAME_LABELS.size():
                continue
            protected_color_idxs[pc_idx] = true

        var protected_staff_names: Dictionary = {}
        for psnk in _coerce_dict(e.get("protected_staff_names"), {}):
            protected_staff_names[str(psnk)] = true

        var seq_candidates: Array = []
        for v in _coerce_array(e.get("seq_candidates"), []):
            seq_candidates.append(_coerce_int(v, 0))

        var melody_ticks: Array = []
        for v in _coerce_array(e.get("melody_ticks"), []):
            melody_ticks.append(_coerce_int(v, 0))

        var seq_note_blocks: Array = []
        for v in _coerce_array(e.get("seq_note_blocks"), []):
            seq_note_blocks.append(_coerce_int(v, 0))

        # Built on _new_match_record() rather than as its own literal, so a
        # save written before some field existed comes back carrying that
        # field's current default instead of missing it entirely — and so
        # adding a field never again means remembering to edit this list.
        _match_records.append(_new_match_record({
            "name": str(e.get("name", "")),
            "seq_lo": _coerce_int(e.get("seq_lo"), 0), "seq_hi": _coerce_int(e.get("seq_hi"), 0),
            "seq_tick_lo": _coerce_int(e.get("seq_tick_lo"), 0), "seq_tick_hi": _coerce_int(e.get("seq_tick_hi"), 0),
            "seq_candidates": seq_candidates,
            "color_states": color_states,
            "pitch_states": pitch_states,
            "degree_states": degree_states,
            "name_states": name_states,
            "repeat_states": repeat_states,
            "manual_name_blocks": manual_name_blocks,
            "manual_pitch_blocks": manual_pitch_blocks,
            "manual_color_blocks": manual_color_blocks,
            "manual_repeat_blocks": manual_repeat_blocks,
            "protected_pitch_notes": protected_pitch_notes,
            "protected_color_idxs": protected_color_idxs,
            "protected_staff_names": protected_staff_names,
            "protected_repeat_values": protected_repeat_values,
            "pitch_revealed": _coerce_bool(e.get("pitch_revealed"), false),
            "star_elim": star_elim,
            "star_idx": _coerce_int(e.get("star_idx"), -1),
            "color_slot_label": str(e.get("color_slot_label", "")),
            "pitch_slot_label": str(e.get("pitch_slot_label", "")),
            "degree_slot_label": str(e.get("degree_slot_label", "")),
            "repeat_slot_label": str(e.get("repeat_slot_label", "")),
            "melody_ticks": melody_ticks,
            "seq_note_blocks": seq_note_blocks,
        }))
    # Sized against the now-FULLY-populated _match_records, not the
    # transiently-empty one right after .clear() above — _reset_derived()
    # used to run before this loop, so _derived came back sized 0 against
    # a real non-empty load (masked for years by every test either loading
    # 0 real records or never asserting the size match at all; see
    # test_constellation_switch_isolation.gd's "derived layer matches
    # record count after switch" check, the first to catch it).
    _reset_derived()


func _display_color_for_record(record_idx: int) -> Color:
    if record_idx < 0 or record_idx >= _match_records.size():
        return STATE_COLORS.unresolved_fallback
    # EFFECTIVE colour — see _known_color_for_seq_position. Reading raw
    # color_states left every row that knows its colour through star_idx or
    # a slot label stuck on the unresolved fallback tint.
    for ci in _host.COLOR_NAME_LABELS.size():
        if _effective_color_state(record_idx, ci) == 1:
            return _host.STAR_COLORS_BY_IDX[ci]
    return STATE_COLORS.unresolved_fallback


## TEMPORARY DIAGNOSTIC (added 2026-08-07, remove once the Staff-popup ->
## Sort:Pitch report is resolved). Dumps every match record that touches a
## given note, plus the ground truth needed to interpret them, so the
## actual in-game state can be compared against what the headless repro
## produces — six scenarios of that repro pass, so the trigger is something
## about live state rather than the linkage logic itself.
## Bound to SHIFT+D in constellation_study_overlay.gd's _input().
func _debug_dump_pitch_records(note_name: String) -> void:
    print("")
    print("========= PITCH RECORD DUMP: '%s' =========" % note_name)
    print("  incidence (_pitch_star_count) = %d   [1 = singleton, linkage expected]"
        % _pitch_star_count(note_name))
    var carriers: Array = []
    for s in _host._star_count:
        if _host._widgets._note_name_for_star(s) == note_name:
            carriers.append(s)
    print("  stars actually carrying it   = %s" % str(carriers))
    for s2 in carriers:
        print("    star %d: name='%s' colour=%d degree=%d true_rank(1-based)=%d" % [
            int(s2),
            str(_host._star_names[int(s2)]) if int(s2) < _host._star_names.size() else "?",
            int(_host._star_colors[int(s2)]) if int(s2) < _host._star_colors.size() else -1,
            int(_host._star_degrees[int(s2)]) if int(s2) < _host._star_degrees.size() else -1,
            (int(_host._sequence_rank_solution[int(s2)]) + 1) if int(s2) < _host._sequence_rank_solution.size() else -1,
        ])
    print("  --- records mentioning this note ---")
    var shown: int = 0
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var raw: int = int((r.get("pitch_states", {}) as Dictionary).get(note_name, 0))
        var eff: int = _effective_pitch_state(i, note_name)
        var label: String = str(r.get("pitch_slot_label", ""))
        # Only the interesting ones: anything asserting/denying this note,
        # anything wearing its slot label, and anything pinned to a carrier.
        if raw == 0 and eff == 0 and label == "" and not carriers.has(int(r.get("star_idx", -1))):
            continue
        shown += 1
        print("    [%d] name='%s' star_idx=%d seq=%d..%d cand=%s" % [
            i, str(r.get("name", "")), int(r.get("star_idx", -1)),
            int(r.get("seq_lo", 0)), int(r.get("seq_hi", 0)),
            str(r.get("seq_candidates", []))])
        print("         raw_pitch=%d effective_pitch=%d pitch_revealed=%s" % [
            raw, eff, str(bool(r.get("pitch_revealed", false)))])
        print("         labels: pitch='%s' colour='%s' degree='%s'" % [
            label, str(r.get("color_slot_label", "")), str(r.get("degree_slot_label", ""))])
        print("         stub?=%s  candidate_stars=%s" % [
            str(_record_is_unconfirmed_star_widget_stub(i)),
            str(_candidate_stars_for_record(i))])
    if shown == 0:
        print("    (no record mentions this note at all)")
    # Why any two of them did or didn't unify — the actual question.
    print("  --- pairwise identity/conflict among those records ---")
    for i2 in _match_records.size():
        for j2 in range(i2 + 1, _match_records.size()):
            var same: bool = _records_provably_identical(i2, j2)
            var distinct: bool = _records_provably_distinct(i2, j2)
            if not same and not distinct:
                continue
            print("    [%d]x[%d] identical=%s distinct=%s conflicts=%s" % [
                i2, j2, str(same), str(distinct), str(_merge_conflict_kinds(i2, j2))])
    print("=========================================")
    print("")


func _debug_dump_named_records() -> void:
    for watch_name in ["Eosaara", "Pyrios"]:
        var idx: int = _find_match_record_by_name(watch_name)
        if idx < 0:
            print("[DEBUG] record for '%s': NOT FOUND" % watch_name)
            continue
        var r: Dictionary = _match_records[idx]
        print("[DEBUG] record for '%s': star_idx=%d color_slot_label='%s' color_states=%s" %
            [watch_name, int(r.get("star_idx", -1)), str(r.get("color_slot_label", "")), str(r.get("color_states", {}))])




func _confirm_color_against_ground_truth(record_idx: int, color_idx: int, asserting_true: bool) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false  # matches this function's own "false means abort" contract
    # Returns false if the caller should abort. Only meaningful once
    # star_idx is resolved to real ground truth (_host._star_colors) — before
    # that there's nothing to check against. This is what catches a
    # misclick on a Sort:tab or staff-popup color button overwriting a
    # color that's already pinned by a resolved star identity — same
    # failure class as the star-identity confirm bug fixed elsewhere in
    # this file, just reachable directly instead of through a merge.
    var star_idx: int = _effective_star_idx(record_idx)
    if star_idx < 0 or star_idx >= _host._star_colors.size():
        return true
    var true_color: int = clamp(_host._star_colors[star_idx], 0, 3)
    var contradicts: bool = (asserting_true and color_idx != true_color) or (not asserting_true and color_idx == true_color)
    if not contradicts:
        return true
    var claim: String = "%s (your click)" % _host.COLOR_NAME_LABELS[color_idx]
    var truth: String = "%s (this star's true color)" % _host.COLOR_NAME_LABELS[true_color]
    var winner: String = await _conflict_dialog_fn.call("color for this star", claim, truth)
    return winner == claim


func _color_star_count(color_idx: int) -> int:
    var count: int = 0
    for s in _host._star_count:
        var sc: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
        if sc == color_idx:
            count += 1
    return count


func _degree_star_count(degree: int) -> int:
    # Same shape as _color_star_count/_pitch_star_count, keyed by Degree
    # (per-star connection count) — gates _compute_excluded_degrees_for the
    # same way, since a degree value is only safe to exclude elsewhere when
    # exactly one star has it.
    var count: int = 0
    for s in _host._star_count:
        var d: int = int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0
        if d == degree:
            count += 1
    return count


func _repeat_count_star_count(value: int) -> int:
    # Same shape again, keyed by Repeat Count. This is the CAPACITY the
    # group-elimination rule (_settle_derived_exclusions_for_axis via
    # Axis.REPEAT) checks against — unlike Colour/Degree this axis is
    # hidden, so this ground-truth count is read only by the SOLVER'S own
    # incidence/clique bookkeeping, never displayed to the player directly.
    var count: int = 0
    for s in _host._star_count:
        var rc: int = int(_host._repeat_count[s]) if s < _host._repeat_count.size() else -1
        if rc == value:
            count += 1
    return count


func _pitch_star_count(note_name: String) -> int:
    # Same shape as _color_star_count, keyed by note name instead of color
    # index — ground-truth incidence count, used to gate
    # _compute_excluded_pitches_for below (a note can have more than one
    # star, unlike Sequence/Name, so exclusion is only sound when exactly
    # one star has it). Also the canonical version of the incidence-count
    # loop widgets.gd previously duplicated inline in two places.
    var count: int = 0
    for s in _host._star_count:
        if s >= _host._star_pitch_index.size():
            continue
        var p: int = int(_host._star_pitch_index[s])
        if p < 0 or p >= _host._pitch_freqs.size():
            continue
        if ConstellationLogicPuzzle.note_name_for_freq(_host._pitch_freqs[p]) == note_name:
            count += 1
    return count


func _confirm_color_against_cap(record_idx: int, color_idx: int) -> bool:
    # ADDED 2026-07-27 — color has a fixed, always-visible ground-truth
    # count per constellation (e.g. exactly 4 Blue stars, from the star map
    # the player can already see). _confirm_color_against_ground_truth above
    # only catches a contradiction once THIS record's own star identity is
    # resolved (star_idx >= 0) — but most Sort:tab records don't have one
    # yet during normal solving, so nothing else stopped more records than
    # actually exist from independently confirming the same color (found via
    # playtesting: 5+ records confirmed Blue when only 4 stars are Blue).
    # This catches that broader, cross-record case.
    var cap: int = _color_star_count(color_idx)
    var already_confirmed: int = 0
    for i in _match_records.size():
        if i == record_idx:
            continue
        if int(_match_records[i].get("color_states", {}).get(color_idx, 0)) == 1:
            already_confirmed += 1
    if already_confirmed < cap:
        return true
    var color_name: String = _host.COLOR_NAME_LABELS[color_idx]
    var claim: String = "%s here (your click)" % color_name
    var truth: String = "the existing %d confirmed elsewhere (the max for this constellation)" % already_confirmed
    var winner: String = await _conflict_dialog_fn.call("color count for this constellation", claim, truth)
    return winner == claim


func _propagate_color_confirmed_same_record(record_idx: int, confirmed_color_idx: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Confirming one color on a record means every OTHER color is
    # automatically eliminated on that SAME record — a slot/name/star can
    # only be one color.
    var r: Dictionary = _match_records[record_idx]
    for ci in _host.COLOR_NAME_LABELS.size():
        if ci != confirmed_color_idx:
            r["color_states"][ci] = 2
    # A confirm supersedes any earlier manual X on the same color — see the
    # matching comment in _propagate_pitch_confirmed_same_record.
    var manual_color: Dictionary = r.get("manual_color_blocks", {})
    if manual_color.has(confirmed_color_idx):
        manual_color.erase(confirmed_color_idx)
        r["manual_color_blocks"] = manual_color
    # Same staleness fix as _sync_color_states_from_star_idx: a
    # color_slot_label naming a DIFFERENT color than what was just
    # confirmed is now wrong and would leave that slot's Sort:Color row
    # pointing at a record that no longer belongs there.
    var label: String = str(r.get("color_slot_label", ""))
    if label != "" and not label.begins_with(_host.COLOR_NAME_LABELS[confirmed_color_idx]):
        r["color_slot_label"] = ""






func _propagate_degree_confirmed_same_record(record_idx: int, confirmed_degree: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Same rule as color/pitch: confirming one degree value means every
    # OTHER possible degree is eliminated on that SAME record. Degree had
    # no equivalent to _propagate_color_confirmed_same_record/
    # _propagate_pitch_confirmed_same_record before this — two different
    # degrees could end up simultaneously marked confirmed on one record.
    var r: Dictionary = _match_records[record_idx]
    var degree_states: Dictionary = r.get("degree_states", {})
    var degrees_set: Dictionary = {}
    for i in _host._star_count:
        degrees_set[int(_host._star_degrees[i]) if i < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        if int(deg) != confirmed_degree:
            degree_states[deg] = 2
    degree_states[confirmed_degree] = 1
    r["degree_states"] = degree_states


func _propagate_name_states_confirmed_same_record(record_idx: int, confirmed_name: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Same rule as color/pitch/degree: confirming one name on a record
    # means every OTHER name is eliminated on that SAME record. This is
    # the record-level name_states field (staff popup NAME section, Sort:tab
    # name checklist popup) — distinct from _propagate_name_confirmed,
    # which is the unrelated star_elim mechanism for binding a name to a
    # star. name_states never got sibling-clearing when color/pitch/degree
    # did — confirming a name here previously left every other name sitting
    # at neutral instead of showing eliminated.
    var r: Dictionary = _match_records[record_idx]
    var name_states: Dictionary = r.get("name_states", {})
    for n in _host._star_names:
        var name_str: String = str(n)
        if name_str != confirmed_name:
            name_states[name_str] = 2
    name_states[confirmed_name] = 1
    r["name_states"] = name_states
    # A confirm supersedes any earlier manual X on the same name — see the
    # matching comment in _propagate_pitch_confirmed_same_record.
    var manual_name: Dictionary = r.get("manual_name_blocks", {})
    if manual_name.has(confirmed_name):
        manual_name.erase(confirmed_name)
        r["manual_name_blocks"] = manual_name

    # Promote into the real identity field (r["name"]), same reasoning as
    # _settle_singleton_sequences promoting a narrowed-to-one Sequence
    # range into seq_lo==seq_hi. Without this, every caller of this
    # function (_on_staff_name_check, _on_slot_name_check, and this file's
    # own _settle_singleton_names) only ever wrote name_states — never
    # r["name"], the ONLY field _find_match_record_by_name/
    # _get_or_create_match_record_for_name ever look at. Checking a name
    # off via the Staff popup or the NameChecklistPopup therefore never
    # linked that record to the one the Sort:Name tab creates/reuses for
    # the same name — two permanently separate records for the same star,
    # exactly the same failure shape as the Sequence propagation bug this
    # file's _records_provably_distinct fix addressed, just on the write
    # side instead of the read side. Skips promotion (same rule
    # _settle_singleton_sequences already uses) when a DIFFERENT record
    # already owns this name — a real contradiction needing a conflict
    # dialog, which this function can't await; it surfaces on the next
    # explicit Sort:Name-tab interaction with that name instead.
    if str(r.get("name", "")) == "":
        var existing_idx: int = _find_match_record_by_name(confirmed_name)
        if existing_idx < 0 or existing_idx == record_idx:
            r["name"] = confirmed_name



## The list is melody TICK numbers: the FIRST note of every star still
## possible, compressed into ranges. A candidate's later notes are not listed:
## they are not given (see _seq_pos_for_melody_tick). "No info" (blank) is
## judged in RANK space (every rank still open).
func _compressed_possible_positions_str(record_idx: int) -> String:
    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return ""
    if candidates.size() == _host._star_count:
        return ""
    var ticks: Array = []
    for c in candidates:
        ticks.append(_first_tick_for_rank(int(c)))
    ticks.sort()
    if ticks.size() == 1:
        return str(ticks[0])

    var segments: Array = []
    var seg_start: int = ticks[0]
    var prev: int = ticks[0]
    for idx in range(1, ticks.size()):
        var c: int = ticks[idx]
        if c == prev + 1:
            prev = c
        else:
            segments.append([seg_start, prev])
            seg_start = c
            prev = c
    segments.append([seg_start, prev])

    var parts: Array = []
    for seg in segments:
        parts.append(str(seg[0]) if seg[0] == seg[1] else "%d-%d" % [seg[0], seg[1]])
    return ",".join(parts)




# ── collapse_soft: the LOGIC/DISPLAY split ───────────────────────────────
# The three readers below serve two different callers with one body.
#
# Deduction needs a hard answer, so by default the soft protect tier is
# COLLAPSED: 3 (soft-eliminated, because a sibling value on this record was
# right-clicked "still possible") reads as 2, and 4 (protected) reads as 0,
# since "still possible" is a hint, never a confirmation. Every candidate
# set, distinctness test and exclusion sweep depends on that.
#
# Popup rows need the opposite. staff_popup_row.gd and the Sort:Colour
# toggle both already paint 3 dimmer and 4 magenta — that styling was
# simply never reachable, because the collapse happened before the state
# ever got to them. Only the star-map name checklist showed magenta, and
# only because it goes through _effective_name_display_state(), which is a
# hand-written fourth copy of this same tier for the star_elim axis.
#
# collapse_soft=false returns the uncollapsed 0-4 for display. Callers must
# still let a HARD cross-record exclusion win over a soft 3/4 — see the
# popup call sites, which apply that overlay when the state is 0 or 4.
func _effective_color_state(record_idx: int, color_idx: int, collapse_soft: bool = true) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Four sources of "known color" for a record, checked in order of
    # certainty: ground-truth visible color (star-anchored), the slot label
    # itself (a "Blue A" row is structurally Blue even though nothing ever
    # writes that into color_states), the player's raw toggled state, and —
    # same fold-in as _effective_pitch_state, see that function's comment —
    # the staff popup's right-click "still possible" protect set, so a
    # narrowed color set can also prove cross-record distinctness.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = _effective_star_idx(record_idx)
    if star_idx >= 0:
        var true_color: int = _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else -1
        return 1 if true_color == color_idx else 2

    var label: String = str(r.get("color_slot_label", ""))
    if label != "":
        var label_color: int = _host.COLOR_NAME_LABELS.find(label.get_slice(" ", 0))
        if label_color >= 0:
            return 1 if label_color == color_idx else 2

    var soft: int = _record_effective_state(record_idx, "color_states", "protected_color_idxs", color_idx)
    if not collapse_soft:
        return soft
    match soft:
        3: return 2   # soft-eliminated (a sibling color is protected) counts as eliminated
        4: return 0   # protected ("still possible") is not a confirmation — stays neutral
        _: return soft


func _effective_pitch_state(record_idx: int, note_name: String, collapse_soft: bool = true) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Same three tiers as _effective_color_state (ground truth, slot label,
    # raw toggled state), plus a fourth: the staff popup's right-click
    # "still possible" protect set. Narrowing that set to a few notes is the
    # player asserting "every other note is eliminated for this record" —
    # folding the *derived* soft-eliminated/protected states in here (rather
    # than writing them into the real, right-click-guarded pitch_states
    # dict) is what lets that assertion prove cross-record distinctness
    # without the right-click guard locking out the very next note the
    # player wants to also mark "still possible" the moment the first click
    # would otherwise hard-eliminate everything else.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = _effective_star_idx(record_idx)
    # GATED on pitch_revealed (Listen). Pitch is designed to be Listen-
    # revealed, not read off a star the player has merely identified: the
    # star popup shows a "PITCH" placeholder until that click
    # (constellation_puzzle_widgets.gd), and _axis_confirms /
    # _displayable_pitch_for_record already refuse un-Listened stubs. This
    # tier used to skip the gate, so the pitch checklist popup showed an
    # identity-confirmed but un-Listened star's true note as confirmed
    # (and ruled out every other note) while the star's own popup still
    # said "PITCH" -- and every deduction pass reading this state inherited
    # the un-earned answer. Colour/Degree are "given" axes and keep their
    # ungated star_idx tier.
    if star_idx >= 0 and (bool(r.get("pitch_revealed", false)) or _pitch_earned_for_star(star_idx)):
        var true_note: String = _host._widgets._note_name_for_star(star_idx)
        return 1 if true_note == note_name else 2

    var label: String = str(r.get("pitch_slot_label", ""))
    if label != "":
        var label_note: String = label.get_slice(" ", 0)
        return 1 if label_note == note_name else 2

    var soft: int = _record_effective_state(record_idx, "pitch_states", "protected_pitch_notes", note_name)
    if not collapse_soft:
        return soft
    match soft:
        3: return 2   # soft-eliminated (a sibling note is protected) counts as eliminated
        4: return 0   # protected ("still possible") is not a confirmation — stays neutral
        _: return soft


func _effective_name_state(record_idx: int, name_str: String, collapse_soft: bool = true) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Deliberately does NOT shortcut via star_idx the way
    # _effective_pitch_state/_effective_color_state do (see those
    # functions) — a record's star_idx gets set by things that are NOT a
    # legitimate name confirmation: _build_star_widgets_impl() auto-
    # creates a star_idx-bound record for every star merely by rendering
    # its floating widget, and _get_or_create_match_record_for_pitch_slot
    # can go on to ADOPT that same record as a Sort:Pitch-tab row once the
    # listen mechanic legitimately confirms its pitch — which reveals
    # PITCH, never identity. r["name"] is the safe signal instead: it's
    # ONLY ever set by a genuine player identity confirmation
    # (_confirm_match_record_identity always sets it together with
    # star_idx), never by auto-creation — so this isn't losing any real
    # coverage the star_idx tier had, just the leak it caused. Found via a
    # singleton Pitch slot showing an unconfirmed star's true name as
    # already selected on a puzzle that had barely started — the adopted
    # record's leftover star_idx (from mere widget rendering) was being
    # read as "the player knows this star's identity."
    var r: Dictionary = _match_records[record_idx]
    var rn: String = str(r.get("name", ""))
    if rn != "":
        return 1 if rn == name_str else 2

    var soft: int = _record_effective_state(record_idx, "name_states", "protected_staff_names", name_str)
    # THE NAME'S ROW IS FULL (2026-10-16). Reported: the player confirmed
    # "Dobraan" on the entries of notes 6, 9 and 14 one at a time; each joined
    # Dobraan's row, which ended up on five notes for a star that fires four
    # times, and nothing objected. A name whose row already holds as many notes
    # as it fires (or would go over by taking this entry's notes) cannot be
    # this entry -- unless the entry is already that row.
    if soft == 0 and _name_row_too_full_for(record_idx, name_str):
        return 2
    if not collapse_soft:
        return soft
    match soft:
        3: return 2
        4: return 0
        _: return soft


## Would joining note entry `record_idx` to `name_str`'s row put that row over
## the number of times it fires? Only for an entry that holds notes; false
## when the count is not known or the entry already is that row.
func _name_row_too_full_for(record_idx: int, name_str: String) -> bool:
    var mine: Array = _match_records[record_idx].get("melody_ticks", [])
    if mine.is_empty():
        return false
    var nr: int = _find_match_record_by_name(name_str)
    if nr < 0 or nr == record_idx:
        return false
    var fires: int = _known_fire_count_for_record(nr)
    if fires <= 0:
        return false
    var theirs: Array = _match_records[nr].get("melody_ticks", [])
    var together: int = theirs.size()
    for t in mine:
        if not theirs.has(t):
            together += 1
    return together > fires


func _effective_degree_state(record_idx: int, degree: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Three tiers, not two. Degree genuinely has no staff-popup
    # protect/right-click mechanism (_on_record_degree_toggle/_eliminate
    # write degree_states directly, unconditionally, with no
    # soft-eliminated/protected layer to fold in) — that part of the old
    # comment was correct. But it wrongly concluded from that that there was
    # "no derived state to consult" at all, and skipped straight from raw
    # player input to ground truth. The DERIVED layer is a separate thing
    # from the protect tier: _settle_singleton_degrees has been writing a
    # derived confirm via _add_derived_state since Degree got its
    # singleton-promotion pass, and nothing ever read it back — that
    # promotion has been dead code the whole time this function skipped
    # straight to ground truth. Found 2026-08-12 while adding
    # _settle_derived_degree_exclusions: its writes landed in the derived
    # layer exactly as designed and were just as invisible.
    #
    # Deliberately still skips degree_slot_label — that label is just "Conn
    # <letter>" with no degree number embedded, so two different
    # degree-value groups' "A" slot collide on the same label; ground truth
    # + raw + derived is sufficient and safe here.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = _effective_star_idx(record_idx)
    if star_idx >= 0 and star_idx < _host._star_degrees.size():
        return 1 if int(_host._star_degrees[star_idx]) == degree else 2
    var raw: int = int(r.get("degree_states", {}).get(degree, 0))
    if raw != 0:
        return raw
    return _derived_state(record_idx, "degree_states", degree)


## Repeat Count has NO ground-truth/star_idx shortcut tier at all — unlike
## Colour/Pitch/Degree (given axes, freely observable) and unlike even Name
## (which has r["name"] as a promoted overall-identity field), a record's
## repeat-count is genuinely just another axis value with no "look it up"
## fallback. It is narrowed the exact same way any other Sort-tab checklist
## is: raw player marks, then the derived layer, then the soft protect tier
## — same three-tier fold _effective_color_state/_effective_pitch_state use.
## The repeat count Listen has given for this record's star, or -1: the record
## is bound to a star (its own star_idx, or one the engine has settled for it)
## AND the player has Listened to that star. Every surface that shows or edits
## a record's Repeats entry asks this, so a given count is shown the same way
## and cannot be overwritten on any of them.
func _repeat_given_for_record(record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var star_idx: int = _effective_star_idx(record_idx)
    if star_idx < 0 or star_idx >= _host._repeat_count.size() or not _player_knows_star_pitch(star_idx):
        return -1
    return int(_host._repeat_count[star_idx])


## Makes sure the player's bucket list reaches `value`, so a count Listen has
## just given has a row to show on. Buckets stay a contiguous 0..N run.
func _ensure_repeat_bucket_for(value: int) -> void:
    _ensure_repeat_buckets_seeded()
    var top: int = -1
    for v in _repeat_bucket_values:
        top = maxi(top, int(v))
    while top < value:
        top += 1
        _repeat_bucket_values.append(top)


func _effective_repeat_state(record_idx: int, value: int, collapse_soft: bool = true) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Slot-label tier, same as _effective_color_state's "a 'Blue A' row is
    # structurally Blue even though nothing ever writes that into
    # color_states": placing a record into the Sort:Repeats tab's "R0 A"
    # bucket IS the player's confirm, not a separate step. Unlike Colour
    # this is the record's OWN assertion rather than a ground-truth fact —
    # but the effect on this axis's state is identical either way, so it
    # reads the same way here.
    # LISTEN GIVES THE COUNT (author ruling 2026-10-11). Once the player has
    # Listened to a star, how often it repeats is known along with its pitch,
    # so a record that IS that star reads the true count -- the one
    # ground-truth tier this axis has, gated on Listen exactly as the pitch
    # tier is, so a star the player has merely identified gives nothing away.
    var given: int = _repeat_given_for_record(record_idx)
    if given >= 0:
        return 1 if given == value else 2
    var label: String = str(_match_records[record_idx].get("repeat_slot_label", ""))
    if label != "":
        var label_value: int = int(label.get_slice(" ", 0).substr(1))
        return 1 if label_value == value else 2
    var soft: int = _record_effective_state(record_idx, "repeat_states", "protected_repeat_values", value)
    if not collapse_soft:
        return soft
    match soft:
        3: return 2   # soft-eliminated (a sibling value is protected) counts as eliminated
        4: return 0   # protected ("still possible") is not a confirmation — stays neutral
        _: return soft


func _effective_star_state(record_idx: int, star_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # System A: the star widget's own per-star name checklist. A record
    # confirmed to BE a specific star (star_idx resolved) or one that has
    # explicitly X'd that star via star_elim (written by _on_name_check/
    # _on_name_x on the *name*-identified record, keyed by star_idx) is just
    # as solid a distinctness proof as a confirmed/eliminated Color or
    # Pitch — this was the primary, actually-used name-elimination path,
    # and it wasn't feeding _records_provably_distinct at all before.
    var r: Dictionary = _match_records[record_idx]
    var rs: int = _effective_star_idx(record_idx)
    if rs >= 0:
        return 1 if rs == star_idx else 2
    return int(r.get("star_elim", {}).get(star_idx, 0))


## Raw (non-recursive) possible-position set for a record: the explicit
## seq_candidates list if one exists, else the seq_lo..seq_hi range with 0
## bounds treated as fully open (1.._star_count). Empty means "no sequence
## information at all" — distinct from "narrowed to nothing," which can't
## happen for a live record. Used only by _records_provably_distinct(),
## which must not call _effective_seq_candidates()/
## _compute_excluded_positions_for() — see that function's comment.
func _raw_seq_candidate_set(r: Dictionary) -> Array:
    var explicit: Array = r.get("seq_candidates", [])
    if not explicit.is_empty():
        return explicit
    var lo: int = int(r.get("seq_lo", 0))
    var hi: int = int(r.get("seq_hi", 0))
    if lo <= 0 and hi <= 0:
        return []
    if lo <= 0:
        lo = 1
    if hi <= 0:
        hi = _host._star_count
    var out: Array = []
    for p in range(lo, hi + 1):
        out.append(p)
    return out


## The record's own stored positions NARROWED by whatever this refresh has
## derived. Every reader of a record's sequence should go through here
## rather than _raw_seq_candidate_set directly: derived narrowing used to
## be written straight back into seq_lo/seq_hi/seq_candidates, which is
## what made it unreleasable (pin four of five names, un-pin one, and the
## fifth stayed pinned forever). It now lives in the derived layer and is
## intersected on read instead.
func _seq_candidate_set_for(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return []
    var base: Array = _raw_seq_candidate_set(_match_records[record_idx])
    var der: Array = []
    if record_idx < _derived.size():
        der = _derived[record_idx]["seq_candidates"]
    if der.is_empty():
        return base
    if base.is_empty():
        return der.duplicate()
    var out: Array = []
    for p in base:
        if der.has(p):
            out.append(p)
    return out


## Records a derived narrowing, intersecting with anything already derived
## this refresh so two passes can only ever tighten, never contradict.
## Returns true if the set actually got smaller (drives the fixpoint loop).
func _narrow_derived_seq(record_idx: int, positions: Array) -> bool:
    if record_idx < 0 or record_idx >= _derived.size():
        return false
    var cur: Array = _derived[record_idx]["seq_candidates"]
    var next: Array = []
    if cur.is_empty():
        next = positions.duplicate()
    else:
        for p in cur:
            if positions.has(p):
                next.append(p)
    # An empty intersection means the player's notes contradict themselves;
    # keep the previous set rather than asserting "no position is possible",
    # which every downstream reader treats as "unknown" anyway.
    if next.is_empty():
        return false
    if next.size() == cur.size():
        return false
    next.sort()
    _derived[record_idx]["seq_candidates"] = next
    # This is the only thing that can turn a record into a single-position
    # owner mid-refresh, so it is the only place the owner list can go
    # stale. Left stale, an exclusion cascade would slip to the next round.
    _seq_singleton_built = false
    return true


# ==================================================
# RECORD IDENTITY UNIFICATION — the missing mirror of
# _records_provably_distinct below.
#
# Every merge in this codebase used to happen only at a hardcoded pairwise
# UI entry point: the Listen handler merging into a pitch SLOT record
# (_reconcile_unique_pitch_slot), an identity confirm merging by star_idx,
# a Sequence commit merging by exact position, a name pick merging by name.
# Each of those only fires when the player touches that specific control,
# and only unifies records colliding on that ONE key. Nothing ever asked
# the general question: "do these two records provably describe the same
# star, whatever route each of them got its facts by?"
#
# So a record identified by NAME that the player gave a singleton Pitch to,
# and a star-map record whose pitch was legitimately revealed by Listen,
# stayed permanently separate — each holding half the picture, neither
# showing the other's facts, on every surface. Confirmed live (2026-08-07,
# Helios/C#5): four separate reported symptoms — Sort:Name missing its
# Color, the star map missing its Name, and the Sort:Pitch slot missing its
# Name — were all one instance of this single missing rule, and every
# earlier propagation bug this session was another.
#
# _records_provably_identical mirrors _records_provably_distinct exactly:
# same category sweep, same singleton-incidence gating for the non-alldiff
# axes (Color/Pitch/Degree), same unconfirmed-stub guard for Pitch.
# ==================================================

## The confirmed value of one raw states dict, or -1/"" when none. Reads
## the RAW dict (not _effective_*_state) deliberately — _merge_match_records
## compares raw states when deciding whether a merge conflicts, so the
## conflict pre-check below has to look at exactly what it will look at.
func _raw_confirmed_int_key(r: Dictionary, states_key: String) -> int:
    for k in r.get(states_key, {}):
        if int(r[states_key][k]) == 1:
            return int(k)
    return -1


func _raw_confirmed_string_key(r: Dictionary, states_key: String) -> String:
    for k in r.get(states_key, {}):
        if int(r[states_key][k]) == 1:
            return str(k)
    return ""


## THE single place a merge conflict is detected. Returns one identifier
## per conflict that _merge_match_records() would raise a dialog for, in
## the same order it raises them; empty means the merge is purely additive.
##
## Both consumers read this rather than restating the conditions:
## _merge_match_records()'s allow_await=false guard, and
## _records_have_merge_conflict() below. Keeping ONE list is the point —
## the two used to be independent copies of the same six-way check, which
## is precisely the shape of duplication that silently rots.
##
## Reads RAW state dicts, not _effective_*_state, because that is what the
## merge itself compares when deciding to raise each dialog.
func _merge_conflict_kinds(idx_a: int, idx_b: int) -> Array[String]:
    var kinds: Array[String] = []
    if idx_a < 0 or idx_a >= _match_records.size() \
            or idx_b < 0 or idx_b >= _match_records.size():
        return kinds
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    var a_name: String = str(a.get("name", ""))
    var b_name: String = str(b.get("name", ""))
    if a_name != "" and b_name != "" and a_name != b_name:
        kinds.append("name")

    var a_lo: int = int(a.get("seq_lo", 0))
    var b_lo: int = int(b.get("seq_lo", 0))
    if a_lo > 0 and a_lo == int(a.get("seq_hi", 0)) \
            and b_lo > 0 and b_lo == int(b.get("seq_hi", 0)) and a_lo != b_lo:
        kinds.append("sequence")

    var ac: int = _raw_confirmed_int_key(a, "color_states")
    var bc: int = _raw_confirmed_int_key(b, "color_states")
    if ac >= 0 and bc >= 0 and ac != bc:
        kinds.append("color")

    var ad: int = _raw_confirmed_int_key(a, "degree_states")
    var bd: int = _raw_confirmed_int_key(b, "degree_states")
    if ad >= 0 and bd >= 0 and ad != bd:
        kinds.append("degree")

    var ap: String = _raw_confirmed_string_key(a, "pitch_states")
    var bp: String = _raw_confirmed_string_key(b, "pitch_states")
    if ap != "" and bp != "" and ap != bp:
        kinds.append("pitch")

    var ar: int = _raw_confirmed_int_key(a, "repeat_states")
    var br: int = _raw_confirmed_int_key(b, "repeat_states")
    if ar >= 0 and br >= 0 and ar != br:
        kinds.append("repeat")

    for label_key in ["color_slot_label", "pitch_slot_label", "degree_slot_label", "repeat_slot_label"]:
        var al: String = str(a.get(label_key, ""))
        var bl: String = str(b.get(label_key, ""))
        if al != "" and bl != "" and al != bl:
            kinds.append(label_key)

    return kinds


## Values one record CONFIRMS while the other ELIMINATES the same value.
##
## _merge_conflict_kinds above only compares confirm against confirm — two
## different confirmed colours, two different exact positions. It never saw
## this shape, and the union in _merge_match_records resolves it silently:
##
##     if sv == 1 or tv == 1: target[k] = 1
##
## Confirm beats eliminate, so merging a record that says "this is G4" with
## one that says "this is NOT G4" produces a record saying "this is G4" and
## the player's elimination simply ceases to exist. The board then looks
## perfectly consistent, which is the worst possible outcome: the mistake is
## not corrected, it is concealed, and the player never learns their
## reasoning was wrong.
##
## That is the merge half of the absorption hole. The other half — a mark
## contradicting ground truth after identity settles — is handled in
## _detect_contradictions.
##
## Returns human-readable descriptions, empty when the two records can be
## merged without destroying anything.
## Why two records that sit on the SAME star cannot both be right — empty
## when there is no reason, which is the ordinary case.
##
## A star has exactly one name, fires at exactly one position, plays exactly
## one note and has exactly one colour. So the contradiction is never "two
## records share a star" — records are views, and a star is routinely held
## by a Sort:Name row, a Sort:Pitch slot and a Staff position at once. It is
## "two views disagree about a single-valued property of that one star",
## which is a clash in the CELL, not in the record count.
##
## Reads only each record's OWN defining fields and marks. That is not a
## detail: once both records are pinned to a star, _effective_name_state
## reads ground truth off star_idx and hands BOTH of them that star's real
## name, so they stop looking distinct at exactly the moment they are most
## broken — the corruption masks its own proof. _records_provably_distinct
## collapses for the same reason and must not be used here (measured
## 2026-08-13: it reported false for two differently-named records pinned to
## one star, silencing a real error test_contradictions.gd had been catching
## since it was written).
func _same_star_value_clash(idx_a: int, idx_b: int) -> Array[String]:
    var out: Array[String] = _merge_value_clashes(idx_a, idx_b)
    if idx_a < 0 or idx_a >= _match_records.size() \
            or idx_b < 0 or idx_b >= _match_records.size():
        return out
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    var an: String = str(a.get("name", ""))
    var bn: String = str(b.get("name", ""))
    if an != "" and bn != "" and an != bn:
        out.append("name (%s vs %s)" % [an, bn])

    # Only an EXACT position is a claim; a range is still open.
    var alo: int = int(a.get("seq_lo", 0))
    var blo: int = int(b.get("seq_lo", 0))
    if alo > 0 and alo == int(a.get("seq_hi", 0)) \
            and blo > 0 and blo == int(b.get("seq_hi", 0)) and alo != blo:
        out.append("firing position (%d vs %d)" % [alo, blo])

    # Slot labels carry their value in the first token ("A#4 A", "Red B").
    for pair in [["pitch_slot_label", "pitch"], ["color_slot_label", "colour"],
            ["degree_slot_label", "degree"]]:
        var al: String = str(a.get(pair[0], ""))
        var bl: String = str(b.get(pair[0], ""))
        if al == "" or bl == "":
            continue
        var av: String = al.get_slice(" ", 0)
        var bv: String = bl.get_slice(" ", 0)
        if av != bv:
            out.append("%s (%s vs %s)" % [pair[1], av, bv])
    return out


func _merge_value_clashes(idx_a: int, idx_b: int) -> Array[String]:
    var out: Array[String] = []
    if idx_a < 0 or idx_a >= _match_records.size() \
            or idx_b < 0 or idx_b >= _match_records.size():
        return out
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    for axis in [
        {"key": "color_states",  "label": "colour"},
        {"key": "degree_states", "label": "degree"},
        {"key": "pitch_states",  "label": "pitch"},
        {"key": "name_states",   "label": "name"},
        {"key": "repeat_states", "label": "repeat count"},
    ]:
        var states_key: String = str(axis["key"])
        var av: Dictionary = a.get(states_key, {})
        var bv: Dictionary = b.get(states_key, {})
        for k in av:
            var a_state: int = int(av[k])
            var b_state: int = int(bv.get(k, 0))
            if (a_state == 1 and b_state == 2) or (a_state == 2 and b_state == 1):
                out.append("%s %s" % [str(axis["label"]), _value_label(states_key, k)])

    # star_elim is the same question asked about a star rather than a value.
    var ae: Dictionary = a.get("star_elim", {})
    var be: Dictionary = b.get("star_elim", {})
    for k in ae:
        var a_state: int = int(ae[k])
        var b_state: int = int(be.get(k, 0))
        if (a_state == 1 and b_state == 2) or (a_state == 2 and b_state == 1):
            var si: int = int(k)
            var nm: String = str(_host._star_names[si]) if si >= 0 and si < _host._star_names.size() else "?"
            out.append("star %s" % nm)

    # One record holds a staff note the other is marked as NOT firing on.
    for pair in [[a, b], [b, a]]:
        var held: Array = (pair[1] as Dictionary).get("melody_ticks", [])
        for blocked in (pair[0] as Dictionary).get("seq_note_blocks", []):
            if held.has(blocked):
                out.append("note %d" % int(blocked))

    return out


## Readable name for a state-dict key, for warning text.
func _value_label(states_key: String, key) -> String:
    match states_key:
        "color_states":
            var ci: int = int(key)
            if ci >= 0 and ci < _host.COLOR_NAME_LABELS.size():
                return str(_host.COLOR_NAME_LABELS[ci])
            return str(key)
        "degree_states":
            return str(key)
        "repeat_states":
            return _repeat_value_label(int(key))
    return str(key)


func _records_have_merge_conflict(idx_a: int, idx_b: int) -> bool:
    return not _merge_conflict_kinds(idx_a, idx_b).is_empty()


## Every uniquely-identifying fact a record confirms, as a token set. Two
## records describe the same star exactly when their sets intersect, which
## turns the identity test from a full category sweep PER PAIR into one
## sweep per record plus a small set intersection.
##
## This was measured, not guessed: at 75 records _settle_identical_records
## was taking 2.2-3.5 SECONDS, essentially the whole sequence-entry stall,
## because it re-swept 4 colours + 10 notes + every degree for each of
## ~2800 pairs, on every rescan.
##
## Only genuinely unique facts become tokens — Colour/Pitch/Degree qualify
## only at incidence 1, same gating as the exclusion rules, since a shared
## value proves nothing about identity.
func _identity_signature(record_idx: int) -> Dictionary:
    if _identity_sig_cache.has(record_idx):
        return _identity_sig_cache[record_idx]
    var sig: Dictionary = {}
    var r: Dictionary = _match_records[record_idx]

    var star: int = int(r.get("star_idx", -1))
    if star >= 0:
        sig["X:%d" % star] = true
    var nm: String = str(r.get("name", ""))
    if nm == "":
        # A name confirmed on a slot row is every bit as much an identity
        # claim as one promoted into r["name"], and it must produce the
        # same token — otherwise the two records are never seen as the same
        # entity and never merge.
        #
        # That gap was self-reinforcing. Promotion into r["name"] is
        # deliberately REFUSED when another record already holds the name
        # (it would mint a duplicate identity), so the claim stays in
        # name_states — precisely the situation where recognising the two
        # as one entity matters most. The result was a name assigned from a
        # Sort:Pitch or Sort:Sequence slot doing nothing at all: no token,
        # no merge, and _find_match_record_by_name returning the OTHER
        # record, which is what the star map reads through.
        #
        # Raw name_states, never _effective_name_state: a DERIVED name
        # confirm must not drive a merge, because merging is destructive
        # and cannot be undone when the derived layer is wiped (Phase 3).
        # Names need no singleton guard the way Colour and Pitch do below —
        # they are alldiff, so a confirmed name always identifies exactly
        # one star.
        for k in (r.get("name_states", {}) as Dictionary):
            if int((r["name_states"] as Dictionary)[k]) == 1:
                nm = str(k)
                break
    if nm != "":
        sig["N:" + nm] = true
    var lo: int = int(r.get("seq_lo", 0))
    if lo > 0 and lo == int(r.get("seq_hi", 0)):
        sig["S:%d" % lo] = true
    for label_key in ["color_slot_label", "pitch_slot_label", "degree_slot_label"]:
        var lbl: String = str(r.get(label_key, ""))
        if lbl != "":
            sig["L:" + lbl] = true

    for ci in _host.COLOR_NAME_LABELS.size():
        if _color_star_count(ci) == 1 and _effective_color_state(record_idx, ci) == 1:
            sig["C:%d" % ci] = true

    # Same unconfirmed-stub guard as everywhere else: a bare auto-created
    # star-widget record's ground-truth pitch isn't earned until Listen.
    if not (_record_is_unconfirmed_star_widget_stub(record_idx) \
            and not bool(r.get("pitch_revealed", false))):
        for note in _host._widgets._distinct_note_names():
            if _pitch_star_count(note) == 1 and _effective_pitch_state(record_idx, note) == 1:
                sig["P:" + str(note)] = true

    var degrees_set: Dictionary = {}
    for s in _host._star_count:
        degrees_set[int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        if _degree_star_count(int(deg)) == 1 and _effective_degree_state(record_idx, int(deg)) == 1:
            sig["D:%d" % int(deg)] = true

    _identity_sig_cache[record_idx] = sig
    return sig


## Do these two records provably describe the SAME star? True when they
## share any fact that uniquely identifies one star.
func _records_provably_identical(idx_a: int, idx_b: int) -> bool:
    if idx_a < 0 or idx_a >= _match_records.size() \
            or idx_b < 0 or idx_b >= _match_records.size() or idx_a == idx_b:
        return false
    # Both pinned to a star is decisive either way, and cheap — check it
    # before building signatures.
    var a_star: int = int(_match_records[idx_a].get("star_idx", -1))
    var b_star: int = int(_match_records[idx_b].get("star_idx", -1))
    if a_star >= 0 and b_star >= 0:
        return a_star == b_star
    var sig_a: Dictionary = _identity_signature(idx_a)
    if sig_a.is_empty():
        return false
    var sig_b: Dictionary = _identity_signature(idx_b)
    for k in sig_a:
        if sig_b.has(k):
            return true
    return false


## Merges every pair of records that provably describe the same star, so
## facts gathered through different surfaces end up on one record instead
## of two half-pictures. Runs first in _full_propagation_refresh() so the
## later settle passes see unified records.
##
## Skips any pair needing a conflict dialog (allow_await=false makes the
## merge itself refuse) — this pass is synchronous and must not suspend.
## Those pairs keep surfacing through the explicit commit paths, which can
## await properly.
##
## SCANS EACH j DESCENDING, AND DOES NOT RESTART. _merge_match_records()
## removes the source record, shifting every index above it — which is why
## this used to restart the whole O(n^2) sweep after every single merge.
## Measured at 75 records that cost 2.2-3.5 SECONDS and was essentially the
## entire sequence-entry stall. Walking j from high to low means a removal
## only ever shifts indices we have already passed, so the scan stays
## valid and the pass is O(n^2) once instead of O(merges x n^2).
## Pairs this refresh refused to merge because their marks clash, as
## {a, b, clashes}. Rebuilt by _settle_identical_records every refresh and
## read by _detect_contradictions later in the same one, so a standing
## conflict is RE-DERIVED each frame from records that both still exist —
## no persistence, and it clears the moment either mark is fixed.
##
## Refusals from player-driven merges surface the same way: the refresh
## that follows the click finds the same still-identical pair again.
var _merge_refusals: Array[Dictionary] = []


func _settle_identical_records() -> void:
    _merge_refusals.clear()
    var i: int = 0
    while i < _match_records.size():
        var j: int = _match_records.size() - 1
        while j > i:
            # Never fold anything into an auto-created star-widget stub on
            # THIS path. A merge is destructive and permanent, and this pass
            # is the engine INFERRING identity — so an inference the player
            # can retract was producing a consequence they could not.
            #
            # Reported 2026-08-14: naming a Sort:Pitch slot whose note only
            # one star plays merged the slot into that star's stub, which
            # put the name on the star map; UNDO SELECTS then cleared the
            # name but the star stayed identified, because the records had
            # already been fused and there is no un-merge.
            #
            # The player's own confirm path is deliberately NOT affected:
            # _confirm_match_record_identity calls _merge_match_records
            # directly for exactly this stub case, and should — there the
            # player asserted the identity outright, and the star widget
            # that owns the assertion can take it back. What is removed here
            # is only the engine doing it behind them.
            #
            # Declining outright WOULD lose information, which is why the
            # conclusion is written down instead of dropped. Measured: with
            # a bare `continue` here, a name record carrying a player-
            # assigned singleton pitch stopped resolving to its star
            # entirely (test_deduction_closures §2 went to eff_star=-1) —
            # that identity came from the merge, not from candidate
            # narrowing, so refusing silently deleted a real deduction.
            #
            # So: same conclusion, non-destructive form. The real record
            # gets the stub's star as a DERIVED star_idx, which every
            # _effective_* reader already honours, and which is rebuilt each
            # refresh and releases the moment its premise does. The stub
            # keeps its own star_idx and gains nothing — in particular not a
            # name, which is what _confirmed_name_for_star prints on the
            # star map, and what made the report visible.
            var i_stub: bool = _record_is_unconfirmed_star_widget_stub(i) \
                and not _record_has_unpromoted_name_claim(i)
            var j_stub: bool = _record_is_unconfirmed_star_widget_stub(j) \
                and not _record_has_unpromoted_name_claim(j)
            if i_stub or j_stub:
                if i_stub != j_stub and _records_provably_identical(i, j):
                    var stub_idx: int = i if i_stub else j
                    var real_idx: int = j if i_stub else i
                    var s: int = int(_match_records[stub_idx].get("star_idx", -1))
                    if s >= 0 and _effective_star_idx(real_idx) < 0:
                        _derived[real_idx]["star_idx"] = s
                j -= 1
                continue
            if _records_provably_identical(i, j):
                var clashes: Array[String] = _merge_value_clashes(i, j)
                if not clashes.is_empty():
                    _merge_refusals.append({"a": i, "b": j, "clashes": clashes})
                    j -= 1
                    continue
                _merge_match_records(i, j, false)
                # Record indices just shifted, and _identity_sig_cache /
                # _distinct_pair_cache / _candidate_star_cache /
                # _confirmer_clique_cache are all keyed by (or store) them.
                _clear_deduction_caches()
            j -= 1
        i += 1


## Pairwise distinctness memo. This is the innermost primitive of the whole
## engine — every exclusion function, every confirmer clique, coverage, and
## each Sort row's bounds derivation bottoms out here, and each call sweeps
## all five categories. Cached per refresh; same lifetime as the candidate
## sets, so it's cleared everywhere they are.
var _distinct_pair_cache: Dictionary = {}

## Per-record identity token sets — see _identity_signature(). Same
## index-keyed lifetime as the caches above.
var _identity_sig_cache: Dictionary = {}

## Per-record distinctness profiles — see _distinct_profile(). Same
## index-keyed lifetime as the caches above.
var _distinct_profile_cache: Dictionary = {}


func _records_provably_distinct(idx_a: int, idx_b: int) -> bool:
    if idx_a < 0 or idx_a >= _match_records.size() or idx_b < 0 or idx_b >= _match_records.size():
        return false  # can't prove distinctness with an invalid index
    # Symmetric, so normalise the key rather than caching both orderings.
    var key: String = "%d:%d" % [mini(idx_a, idx_b), maxi(idx_a, idx_b)]
    if _distinct_pair_cache.has(key):
        return bool(_distinct_pair_cache[key])
    var verdict: bool = _compute_records_provably_distinct(idx_a, idx_b)
    _distinct_pair_cache[key] = verdict
    return verdict


## Per-record view of everything _compute_records_provably_distinct needs:
## the raw possible-position set, and per axis the single confirmed value
## (null if none) plus the set of eliminated ones. Built once per record;
## the pairwise test is then a handful of dictionary lookups instead of
## ~90 _effective_*_state() calls.
##
## Uses the same _effective_*_state functions the loops did, so the verdict
## is unchanged — only how often they're evaluated. Note each axis can hold
## at most one confirmed value by construction (a record can't be two
## colours), which is what makes the collapse valid.
func _distinct_profile(record_idx: int) -> Dictionary:
    if _distinct_profile_cache.has(record_idx):
        return _distinct_profile_cache[record_idx]

    var seq_set: Dictionary = {}
    for p in _seq_candidate_set_for(record_idx):
        seq_set[int(p)] = true

    var prof: Dictionary = {"seq": seq_set}

    var col: Dictionary = {"confirmed": null, "eliminated": {}}
    for ci in _host.COLOR_NAME_LABELS.size():
        var s: int = _effective_color_state(record_idx, ci)
        if s == 1: col["confirmed"] = ci
        elif s == 2: (col["eliminated"] as Dictionary)[ci] = true
    prof["color"] = col

    var pit: Dictionary = {"confirmed": null, "eliminated": {}}
    for note in _host._widgets._distinct_note_names():
        var s2: int = _effective_pitch_state(record_idx, str(note))
        if s2 == 1: pit["confirmed"] = str(note)
        elif s2 == 2: (pit["eliminated"] as Dictionary)[str(note)] = true
    prof["pitch"] = pit

    var nam: Dictionary = {"confirmed": null, "eliminated": {}}
    for n in _host._star_names:
        var s3: int = _effective_name_state(record_idx, str(n))
        if s3 == 1: nam["confirmed"] = str(n)
        elif s3 == 2: (nam["eliminated"] as Dictionary)[str(n)] = true
    prof["name"] = nam

    var st: Dictionary = {"confirmed": null, "eliminated": {}}
    for si in _host._star_count:
        var s4: int = _effective_star_state(record_idx, si)
        if s4 == 1: st["confirmed"] = si
        elif s4 == 2: (st["eliminated"] as Dictionary)[si] = true
    prof["star"] = st

    var deg: Dictionary = {"confirmed": null, "eliminated": {}}
    var degrees_set: Dictionary = {}
    for s5 in _host._star_count:
        degrees_set[int(_host._star_degrees[s5]) if s5 < _host._star_degrees.size() else 0] = true
    for d in degrees_set.keys():
        var s6: int = _effective_degree_state(record_idx, int(d))
        if s6 == 1: deg["confirmed"] = int(d)
        elif s6 == 2: (deg["eliminated"] as Dictionary)[int(d)] = true
    prof["degree"] = deg

    _distinct_profile_cache[record_idx] = prof
    return prof


func _compute_records_provably_distinct(idx_a: int, idx_b: int) -> bool:
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    var a_star: int = int(a.get("star_idx", -1))
    var b_star: int = int(b.get("star_idx", -1))
    if a_star >= 0 and b_star >= 0:
        return a_star != b_star

    var a_name: String = str(a.get("name", ""))
    var b_name: String = str(b.get("name", ""))
    if a_name != "" and b_name != "" and a_name != b_name:
        return true

    # The player marked one of them as NOT firing on a note the other is the
    # record of (the Sequence row's right-click on a repeat note). Own fields
    # on both sides, so the mark is seen whatever else has been derived.
    for pair in [[a, b], [b, a]]:
        var held: Array = (pair[1] as Dictionary).get("melody_ticks", [])
        for blocked in (pair[0] as Dictionary).get("seq_note_blocks", []):
            if held.has(blocked):
                return true

    # Sequence-range disjointness: if the two records' possible-position
    # sets don't overlap at all, they can't be the same star, regardless of
    # whether either side is pinned to an exact position. This was missing
    # entirely — every _compute_excluded_*_for() function gates its
    # cross-record exclusion on this function, so a Sort:Name record's
    # Sequence range (e.g. "not position 15") could never exclude that name
    # from a different, position-keyed record's Staff-popup checklist no
    # matter how correctly it was entered, since nothing here ever compared
    # ranges. Deliberately reads the RAW seq_lo/seq_hi/seq_candidates
    # fields, not _effective_seq_candidates() — that function calls
    # _compute_excluded_positions_for(), which calls back into this
    # function, so using it here would recurse.
    var pa_prof: Dictionary = _distinct_profile(idx_a)
    var pb_prof: Dictionary = _distinct_profile(idx_b)

    var a_seq: Dictionary = pa_prof["seq"]
    var b_seq: Dictionary = pb_prof["seq"]
    if not a_seq.is_empty() and not b_seq.is_empty():
        var overlap: bool = false
        for v in a_seq:
            if b_seq.has(v):
                overlap = true
                break
        if not overlap:
            return true

    # One confirmed value landing in the other side's eliminated set is
    # exactly what the five per-category loops used to look for, but those
    # ran ~90 _effective_*_state() calls PER PAIR — the dominant cost of
    # warming the pairwise cache (measured: ~590 ms for a full sweep cold
    # vs ~8 ms warm). The profile does that work once per record instead.
    for axis in ["color", "pitch", "name", "star", "degree"]:
        var ca = pa_prof[axis]["confirmed"]
        var cb = pb_prof[axis]["confirmed"]
        if ca != null and (pb_prof[axis]["eliminated"] as Dictionary).has(ca):
            return true
        if cb != null and (pa_prof[axis]["eliminated"] as Dictionary).has(cb):
            return true

    # A second, explicit Degree sweep used to follow here, asking exactly
    # what the "degree" entry of the loop above already asks — one side
    # confirming a degree the other rules out. It survived the move to
    # profiles because it was written before them and reads
    # _effective_degree_state directly, so it cost ~8 uncached effective
    # reads on EVERY pair verdict, which is the innermost loop of the whole
    # engine. Removed 2026-08-11; the profile covers the same ground.

    return false


func _parse_candidate_list(raw: String) -> Array:
    var result: Dictionary = {}
    for chunk in raw.split(",", false):
        var c: String = chunk.strip_edges()
        if c == "":
            continue
        var dash: int = c.find("-")
        if dash > 0:
            var a_str: String = c.substr(0, dash).strip_edges()
            var b_str: String = c.substr(dash + 1).strip_edges()
            if a_str.is_valid_int() and b_str.is_valid_int():
                var a: int = int(a_str)
                var b: int = int(b_str)
                if a > b:
                    var tmp := a; a = b; b = tmp
                for p in range(a, b + 1):
                    result[p] = true
        elif c.is_valid_int():
            result[int(c)] = true
    var out: Array = result.keys()
    out.sort()
    return out


func _effective_seq_candidates(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return []
    # Through _seq_candidate_set_for, NOT the record's own fields: that is the
    # committed view (own marks narrowed by what this refresh derived), and
    # this reader used to bypass it. A narrowing that lived only in the
    # derived layer -- a group bound, or a position shared from another record
    # for the same star -- therefore never reached any Sequence display or
    # _player_positions_for_star, although every other cross-record reader saw
    # it. Same own-field-read-of-a-derivable-value mistake as
    # _seq_singleton_owners and _find_match_record_by_exact_seq.
    # Empty from there means "no sequence information", i.e. fully open.
    var base: Array = _seq_candidate_set_for(record_idx).duplicate()
    if base.is_empty():
        for p in range(1, _host._star_count + 1):
            base.append(p)

    # Dictionary, not the returned Array: this filter runs once per record
    # per fixpoint round, and `Array.has()` is a linear scan, so the pairing
    # was O(positions x excluded) — ~200 comparisons a record on a 15-star
    # board, for no reason. Membership is the only thing asked of it.
    var excluded: Dictionary = {}
    for e in _compute_excluded_positions_for(record_idx):
        excluded[int(e)] = true
    var result: Array = []
    for p in base:
        if not excluded.has(int(p)):
            result.append(p)
    return result


func _settle_singleton_sequences() -> void:
    # Case 1 promotion: if exclusion has narrowed a record down to exactly
    # one surviving sequence candidate, that's logically the same fact as
    # an exact commit — "only 4 is left" IS "this is position 4." Recording
    # it lets _compute_excluded_positions_for and _record_descriptor_state
    # use it to exclude position 4 elsewhere, same as if the player had
    # typed "4" directly.
    #
    # PHASE 2: this lands in the derived layer, not seq_lo/seq_hi. It used
    # to overwrite the player's own fields, which is why un-pinning any one
    # of four names left the fifth pinned to its derived position forever —
    # nothing recorded that the pin was the engine's, so nothing could take
    # it back. The derived layer is wiped every refresh, so the promotion
    # now survives exactly as long as the exclusions that produced it.
    #
    # Lives here rather than inline inside _effective_seq_candidates —
    # that function is a read-only query every widget builder calls
    # expecting no side effects, so the write belongs in an explicit
    # "settle" step instead. Skipped only for a record the player already
    # pinned, so an explicit commit is never silently restated.
    #
    # The "another record already owns this exact position" guard that used
    # to sit here is GONE (2026-08-11). It dated from when this pass wrote
    # into seq_lo/seq_hi, where a second record landing on a taken position
    # would have minted a duplicate exact-position identity and demanded a
    # merge this synchronous loop cannot await. Writing to the derived layer
    # mints nothing and merges nothing. Worse, the guard was self-defeating:
    # a Sort:Name row narrowed to position 6 was blocked from recording it
    # precisely BECAUSE the Staff popup for position 6 existed — the one
    # case where the two records need to see each other. The narrowing
    # stayed invisible to every other record, so nothing downstream could
    # rule position 6 out, and _settle_same_position_identity below never
    # saw a pair to unify.
    #
    # Nothing unsound is let through: _effective_seq_candidates has already
    # removed every position owned by a provably-DISTINCT record, so a
    # position that survives to be the last one standing is either
    # genuinely free or held by a record that may well be this same star.
    #
    # Iterated to a fixpoint by the loop in _full_propagation_refresh(), so
    # a promotion that only becomes visible after an earlier record's own
    # promotion no longer has to wait for the next refresh.
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var already_exact: bool = int(r.get("seq_lo", 0)) > 0 and int(r.get("seq_lo", 0)) == int(r.get("seq_hi", 0))
        if already_exact:
            continue
        # Already narrowed to one by an EARLIER round — there is nothing
        # left to conclude, and _narrow_derived_seq would refuse the write
        # anyway. Skipping here avoids the _effective_seq_candidates call,
        # which is this pass's whole cost (it sweeps every single-position
        # owner asking _records_provably_distinct). Sound because narrowing
        # is monotone within a refresh: the derived set only shrinks, and
        # an empty intersection is refused, so a set at 1 stays at 1.
        if i < _derived.size() and (_derived[i]["seq_candidates"] as Array).size() == 1:
            continue
        var result: Array = _effective_seq_candidates(i)
        if result.size() != 1:
            continue
        _narrow_derived_seq(i, result)


## A record keyed by a staff NOTE (the Staff popup's) is, by that fact alone,
## the star that fires at that note: the player chose the note. Its position
## is therefore known without any Sequence entry, but nothing recorded it --
## the record carried melody_ticks and seq_lo/seq_hi = 0, so a Sort row pinned
## to the same note and the popup for that note were two unconnected halves of
## one star. Found by test_widget_path_independence (family F): a name, colour
## and position entered on the Sort row never reached the popup for that note.
##
## Written to the DERIVED layer, so it is wiped and re-derived every refresh
## and can never outlive its premise; the same-position pass then shares facts
## between the popup and every other record on that position. Skipped when the
## record's own marks already exclude the rank (a contradiction the player
## made, which this must not paper over), and when its notes disagree about
## which star they are.
##
## ONLY A FIRST FIRING GIVES A POSITION (2026-10-10, repeats are earned -- see
## _seq_pos_for_melody_tick). A repeat note says less: its star has already
## been heard, so its position is one of those that first fired before it.
## That bound is all this derives for it; which of them it is, the player
## pins. Both readings use only what the staff shows.
func _settle_melody_tick_positions() -> void:
    # FIRST NOTES HIDDEN: a note says nothing about where its star comes in the
    # firing order, so a clicked note's entry stays blank (see _notes_hidden).
    if _notes_hidden():
        return
    for i in _match_records.size():
        var ticks: Array = _match_records[i].get("melody_ticks", [])
        if ticks.is_empty():
            continue
        var rank: int = 0
        var consistent: bool = true
        var latest: int = _host._star_count   # positions first fired before every repeat note held
        for t in ticks:
            var tick: int = int(t)
            if _tick_is_first_fire(tick):
                var here: int = _seq_pos_for_melody_tick(tick)
                if here < 1 or here > _host._star_count or (rank > 0 and here != rank):
                    consistent = false
                rank = here
            else:
                latest = mini(latest, _stars_begun_by_tick(tick - 1))
        if not consistent:
            continue
        var raw: Array = _raw_seq_candidate_set(_match_records[i])
        if rank > 0:
            if rank > latest or (not raw.is_empty() and not raw.has(rank)):
                continue
            _narrow_derived_seq(i, [rank])
        elif latest < _host._star_count:
            var open: Array = []
            for p in range(1, latest + 1):
                if raw.is_empty() or raw.has(p):
                    open.append(p)
            if not open.is_empty():
                _narrow_derived_seq(i, open)


## NOTES PLACED -> REPEATS MARKS (2026-10-11). A star's repeat count is the
## number of repeat notes that are its own, so the notes the board has settled
## bound it: at least the notes PLACED on the star's position, at most those
## plus the notes that could still be it. Every count outside that range is
## ruled out on the Repeats axis of each record known to sit on that position.
##
## Counted per POSITION (a value), from the repeat notes' own candidate sets;
## a note nobody has opened could be any earlier star, so it only ever widens
## the upper bound. Derived layer, so it lets go the moment a note is unplaced.
## The reverse direction (a confirmed count ruling notes in or out) is offered
## as a hint step, not applied silently.
func _settle_repeat_counts_from_notes() -> void:
    if not _seq_repeats():
        return
    if _notes_hidden():
        # No positions to count by. What a record's own notes say is enough: a
        # star holding k notes repeats at least k - 1 times.
        var all_counts: Array = _repeat_count_domain()
        for i0 in _match_records.size():
            var held: int = (_match_records[i0].get("melody_ticks", []) as Array).size()
            if held < 2:
                continue
            for v0 in all_counts:
                if int(v0) < held - 1 and _effective_repeat_state(i0, int(v0)) == 0:
                    _add_derived_state(i0, "repeat_states", int(v0), 2)
        return
    var placed: Dictionary = {}     # position -> notes placed on it
    var possible: Dictionary = {}   # position -> notes placed on it or still open to it
    for tick in range(1, _melody_tick_count() + 1):
        if _tick_is_first_fire(tick):
            continue
        var latest: int = _stars_begun_by_tick(tick - 1)
        var idx: int = _find_match_record_by_melody_tick(tick)
        var cands: Array = []
        if idx >= 0:
            cands = _effective_seq_candidates(idx)
        else:
            for p in range(1, latest + 1):
                cands.append(p)
        if idx >= 0 and cands.size() == 1:
            placed[int(cands[0])] = int(placed.get(int(cands[0]), 0)) + 1
        for c in cands:
            if int(c) <= latest:
                possible[int(c)] = int(possible.get(int(c), 0)) + 1
    var counts: Array = _repeat_count_domain()
    for entry in _seq_singleton_owners():
        var i: int = int((entry as Array)[0])
        var rank: int = int((entry as Array)[1])
        var lo: int = int(placed.get(rank, 0))
        var hi: int = int(possible.get(rank, 0))
        for v in counts:
            if (int(v) < lo or int(v) > hi) and _effective_repeat_state(i, int(v)) == 0:
                _add_derived_state(i, "repeat_states", int(v), 2)


## Sequence is alldiff — exactly one star per position — so two records
## whose surviving position sets are BOTH the same single position describe
## the same star, whatever route each of them reached it by.
##
## They cannot simply be merged. _settle_identical_records deliberately runs
## against an empty derived layer: a merge destroys a record and there is no
## way to un-merge when the derived layer is wiped, so a merge must never
## rest on a fact that can evaporate — and a position narrowed by this
## refresh's own exclusions is exactly such a fact. The facts are SHARED
## through the derived layer instead. Both records stay, each gains what the
## other knows, and the whole lot is released the moment the narrowing that
## justified it goes away.
##
## This is the missing link under a family of "my entry didn't show up"
## reports (confirmed live 2026-08-11, Chroneeia/6 and Keraides/14). A
## Sort:Name row narrowed to position 6 and the Staff popup for position 6
## were two halves of one star, and neither could see the other because the
## only thing proving them the same was derived. The popup kept offering the
## magenta "still possible" pair that the name row had already resolved, and
## the name row never received the popup's own pitch eliminations.
func _settle_same_position_identity() -> void:
    var at_position: Dictionary = {}
    for i in _match_records.size():
        # _seq_candidate_set_for, not _effective_seq_candidates: the former
        # is the committed view every other cross-record reader consults
        # (raw intersected with what this refresh derived), so identity here
        # can never rest on something the rest of the engine cannot see.
        var cands: Array = _seq_candidate_set_for(i)
        if cands.size() != 1:
            continue
        var p: int = int(cands[0])
        if not at_position.has(p):
            at_position[p] = []
        (at_position[p] as Array).append(i)

    _share_within_groups(at_position)

    # The same rule keyed on a confirmed NAME, which is alldiff exactly as
    # position is: two records that both (effectively) confirm one name are one
    # star. Raw-name pairs are merged by _settle_identical_records; the case
    # left over is a name confirmed only by DERIVATION -- most commonly the
    # last name standing after the player X'd every other one on a Sort row --
    # which cannot drive a merge (the derived layer is wiped every refresh) and
    # used to share nothing at all. Found by
    # test_widget_path_independence: a position/colour slot whose every other
    # name was X'd read Pyrios from its own row, while Pyrios's own Sort:Name
    # row showed no position and no colour, because nothing linked the two.
    # Reads _effective_name_state, which never consults star_idx, so an
    # unconfirmed star-widget stub cannot appear here by way of ground truth.
    var at_name: Dictionary = {}
    for i in _match_records.size():
        for n in _host._star_names:
            if _effective_name_state(i, str(n)) == 1:
                if not at_name.has(str(n)):
                    at_name[str(n)] = []
                (at_name[str(n)] as Array).append(i)
                break
    _share_within_groups(at_name)

    # Deliberately does NOT invalidate _distinct_pair_cache /
    # _distinct_profile_cache the way _settle_derived_eliminations does.
    # Everything downstream of this pass reads the derived layer through
    # _effective_*_state, which consults it directly and never those caches,
    # and the fixpoint loop clears them at the end of every round anyway. A
    # mid-round clear here only costs a full re-warm (measured at ~590 ms
    # cold on a full board) to buy a conclusion the next round reaches for
    # free — it made a 57-record refresh 312 ms -> 482 ms on its own.


## Shares what each record knows with every other record in the same group,
## where a group is a set of records that all pin one alldiff value (a
## position, a name) and so are one star. Both directions, via the derived
## layer.
func _share_within_groups(groups: Dictionary) -> void:
    for key in groups:
        var group: Array = groups[key]
        if group.size() < 2:
            continue
        for a in group:
            for b in group:
                if a == b:
                    continue
                # Provably distinct records cannot both hold one position,
                # so if a pair ever gets here the board is already wrong and
                # sharing would launder it into one that looks consistent —
                # the same absorption failure the merge path refuses. The
                # pair is reachable only when BOTH are raw-pinned to the
                # position, which gives both an "S:<pos>" identity token and
                # sends them through _settle_identical_records, where the
                # clash is reported as a merge refusal. So: skip, and leave
                # the reporting to the pass that can already see it.
                if _records_provably_distinct(int(a), int(b)):
                    continue
                _share_derived_facts(int(a), int(b))
                # _share_derived_facts carries the value axes only. For a
                # group keyed on POSITION the sequence already agrees by
                # construction, but a group keyed on NAME can hold one record
                # that knows the position and one that does not. Same star,
                # so the narrower set holds for both. Skipped when it says
                # nothing (the whole range), which would only churn the
                # derived layer.
                var cs: Array = _seq_candidate_set_for(int(a))
                if not cs.is_empty() and cs.size() < _host._star_count:
                    _narrow_derived_seq(int(b), cs)


## Records that denote the SAME STAR must agree about that star.
##
## _settle_same_position_identity is the same rule for a shared sequence
## POSITION, and was the only place _share_derived_facts was ever called —
## so two records known to be one star still knew different things about it,
## as long as they had not both been pinned to a position.
##
## Reported 2026-08-14: once "the star that fires 11th" resolved to a
## specific star, its Staff popup showed that star's pitch and colour, but
## the Sort:Pitch and Sort:Colour rows for those same values showed nothing,
## and the star map popup never learned the name exclusion the player had
## entered against the 11th. Three surfaces, one cause — those rows are
## different records for the same star, and nothing carried anything
## between them.
##
## Only newly safe to do at all. Two records sharing a star used to be
## reported as an impossible state; now it is ordinary (see
## _same_star_value_clash), so co-located records can be treated as what
## they are — views of one thing.
##
## A genuine disagreement is skipped rather than laundered: sharing across
## it would let one side's value quietly overwrite the other's, destroying
## the evidence _detect_contradictions needs to report the clash on this
## very refresh. Same reasoning as the merge path's refusal.
func _settle_same_star_identity() -> void:
    var by_star: Dictionary = {}
    for i in _match_records.size():
        var s: int = _effective_star_idx(i)
        if s < 0:
            continue
        if not by_star.has(s):
            by_star[s] = []
        (by_star[s] as Array).append(i)

    for s2 in by_star:
        var group: Array = by_star[s2]
        if group.size() < 2:
            continue
        for a in group:
            for b in group:
                if int(a) == int(b):
                    continue
                if not _same_star_value_clash(int(a), int(b)).is_empty():
                    continue
                # Deliberately NOT _share_derived_facts. That reads through
                # _effective_*_state, which returns GROUND TRUTH for any
                # star-bound record, so it needs an anti-leak guard — and
                # that guard is _record_is_unconfirmed_star_widget_stub,
                # which means "star-bound and unnamed" and therefore
                # misclassifies a Sequence row that has resolved to a star.
                # Measured: it refused every share in the reported scenario.
                #
                # Only the player's OWN marks move here. They contain no
                # ground truth by construction, so there is nothing to leak
                # and no guard to get wrong — and they are exactly what the
                # report was missing: an exclusion the player entered
                # against one view of a star, invisible from its others.
                _share_player_marks(int(a), int(b))


## Copies the marks the PLAYER made on `src` into `dst`'s derived layer.
##
## Strictly narrower than _share_derived_facts, and safe where that is not:
## it reads each record's OWN state dicts rather than the _effective_*
## readers, so no ground-truth tier is ever consulted and a star-bound
## source cannot leak its star's real name or pitch. That means it needs no
## trustworthiness guard, which matters because the available one
## (_record_is_unconfirmed_star_widget_stub, i.e. "star-bound and unnamed")
## misclassifies any Sort row that has resolved to a star.
##
## Writes go to the derived layer, so they release with their premise, and
## _add_derived_state never overwrites what dst already holds — a real
## disagreement survives to be reported rather than being papered over.
func _share_player_marks(src: int, dst: int) -> void:
    if src < 0 or src >= _match_records.size() or dst < 0 or dst >= _match_records.size():
        return
    var s: Dictionary = _match_records[src]
    for pair in [["name_states", "name_states"], ["color_states", "color_states"],
            ["pitch_states", "pitch_states"], ["degree_states", "degree_states"],
            ["repeat_states", "repeat_states"]]:
        var key: String = str(pair[0])
        for v in (s.get(key, {}) as Dictionary):
            var st: int = int((s.get(key, {}) as Dictionary)[v])
            # 1 and 2 only: 3/4 are the staff popup's soft/protected states,
            # which are relative to the record they were drawn on.
            if st == 1 or st == 2:
                _add_derived_state(dst, key, v, st)
    # star_elim is the same question asked about a star rather than a value.
    for k in (s.get("star_elim", {}) as Dictionary):
        var se: int = int((s.get("star_elim", {}) as Dictionary)[k])
        if se == 1 or se == 2:
            _add_derived_state(dst, "star_elim", k, se)


## Copies everything `src` effectively knows into `dst`'s DERIVED layer.
## Returns true if anything was actually added, which drives the fixpoint.
##
## _add_derived_state refuses to overwrite, so nothing dst already holds is
## touched: a genuine disagreement between the two survives to be reported
## rather than being silently resolved in the copier's favour.
##
## star_idx is deliberately NOT copied. Binding dst to a star flips every
## axis at once onto the ground-truth tier, which is a far larger claim than
## "these two records are the same star" — and the per-axis copies below
## already carry everything src legitimately knows.
func _share_derived_facts(src: int, dst: int) -> void:
    # Nothing may be copied OUT of a bare auto-created star-widget record.
    # _build_star_widgets_impl gives every star one the instant its widget is
    # drawn, so its star_idx is unearned — and every _effective_*_state below
    # reads ground truth off star_idx. Copying even the "given" axes out of
    # one hands dst a value the player never established, and a singleton
    # colour or degree among them would go on to resolve dst's identity
    # outright, which is the full leak. Same compound condition
    # _identity_signature uses: a stub is trustworthy only once Listen has
    # actually revealed it. Sharing INTO a stub stays fine — the caller runs
    # both directions and only this one is dangerous.
    if _record_is_unconfirmed_star_widget_stub(src) \
            and not bool(_match_records[src].get("pitch_revealed", false)):
        return

    for n in _host._star_names:
        var name_str: String = str(n)
        var sn: int = _effective_name_state(src, name_str)
        if sn != 0 and _effective_name_state(dst, name_str) == 0:
            _add_derived_state(dst, "name_states", name_str, sn)

    # Colour and Degree are the "given" axes — painted on the map and
    # traceable by eye — so src's ground-truth tier is public information
    # either way and needs no earned-knowledge guard.
    for ci in _host.COLOR_NAME_LABELS.size():
        var sc: int = _effective_color_state(src, int(ci))
        if sc != 0 and _effective_color_state(dst, int(ci)) == 0:
            _add_derived_state(dst, "color_states", int(ci), sc)

    var degrees_set: Dictionary = {}
    for si in _host._star_count:
        degrees_set[int(_host._star_degrees[si]) if si < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        var sd: int = _effective_degree_state(src, int(deg))
        if sd != 0 and _effective_degree_state(dst, int(deg)) == 0:
            _add_derived_state(dst, "degree_states", int(deg), sd)

    # Repeat count: a single-valued property of the star like the others, so
    # two records of one star must agree on it. It has no ground-truth tier
    # (it is hidden, like Name), so reading it through the effective reader
    # cannot leak anything. Missing until the Repeats section reached the
    # Staff popup and the star widget, which made it enterable on records
    # that share a star: a count entered on the Sort row never showed on the
    # popup for that note.
    for rv in _repeat_values_all():
        var srep: int = _effective_repeat_state(src, int(rv))
        if srep != 0 and _effective_repeat_state(dst, int(rv)) == 0:
            _add_derived_state(dst, "repeat_states", int(rv), srep)

    # Pitch is NOT public. _effective_pitch_state reads ground truth off
    # star_idx, and a bare auto-created star-widget record holds a star_idx
    # it never earned — copying from one would hand over an unlistened note.
    # Same compound guard _identity_signature uses: a stub contributes only
    # once Listen has actually revealed it.
    if not (_record_is_unconfirmed_star_widget_stub(src) \
            and not bool(_match_records[src].get("pitch_revealed", false))):
        for note in _host._widgets._distinct_note_names():
            var nn: String = str(note)
            var sp: int = _effective_pitch_state(src, nn)
            if sp != 0 and _effective_pitch_state(dst, nn) == 0:
                _add_derived_state(dst, "pitch_states", nn, sp)


## Writes the cross-record NAME exclusions into the derived layer, so the
# ==================================================
# SHARED-VALUE AXIS TABLE
#
# Pitch, Colour and Degree obey the same three rules, and Name obeys one of
# them. Those rules used to be written out once per axis — ten near-identical
# functions — and that duplication has a measured cost, not a theoretical
# one. Every one of these was a separate bug, found across 2026-08-11/12,
# and each fix touched exactly one axis while the others kept the defect:
#
#   * the cross-record exclusion reached only the DISPLAY, not the engine —
#     fixed for Name, then found again in Pitch (42 wrong clues on a real
#     save), then again in Colour, then again in Degree
#   * _effective_degree_state never read the derived layer its three
#     siblings did, so _settle_singleton_degrees had been DEAD CODE since
#     the derived layer landed — invisible precisely because Degree's copy
#     of the rule looked correct in isolation
#
# Writing a rule once is the fix for that class. An axis is described by
# data + small dispatchers below; the rules themselves live in exactly one
# function each.
#
# What deliberately does NOT join:
#   * SEQUENCE — its rules narrow a candidate SET, not a value->state dict,
#     and its exclusion runs off _seq_singleton_owners rather than cliques.
#     Genuinely a different shape; forcing it in would be worse.
#   * Name's EXCLUSION — Name is alldiff, so one confirmer is proof and the
#     incidence/clique machinery does not apply. Name joins the singleton
#     rule only.
#
# Dispatch is a `match` on an int rather than stored Callables on purpose:
# the last perf pass showed Callable construction, not the deduction, was
# the dominant cost in these passes (~570 allocations a round).
# ==================================================

enum Axis { NAME, PITCH, COLOR, DEGREE, REPEAT }

## Axes carrying a shared (non-alldiff) value, in the order the fixpoint
## has always run them. Name is excluded: it is alldiff and takes the
## single-confirmer path instead. REPEAT belongs here, not with Name -- a
## repeat-count value is shared across multiple stars by construction (most
## share 0), the same shape as Pitch/Colour/Degree, even though (unlike
## those three) it is hidden rather than given -- see _axis_confirms' own
## REPEAT note for why that difference needs no special-casing here.
const CLIQUE_AXES: Array = [Axis.PITCH, Axis.COLOR, Axis.DEGREE, Axis.REPEAT]


func _axis_states_key(axis: int) -> String:
    match axis:
        Axis.NAME:   return "name_states"
        Axis.PITCH:  return "pitch_states"
        Axis.COLOR:  return "color_states"
        Axis.DEGREE: return "degree_states"
        Axis.REPEAT: return "repeat_states"
    return ""


## Every value the axis can take on this puzzle. Cached for the refresh:
## _compute_excluded_for_axis is called once per RECORD from the widget
## display paths, so rebuilding (and re-allocating) the domain array there
## was per-record work for a value that only changes when the puzzle does.
var _axis_domain_cache: Dictionary = {}


func _axis_domain(axis: int) -> Array:
    if _axis_domain_cache.has(axis):
        return _axis_domain_cache[axis]
    var built: Array = _build_axis_domain(axis)
    _axis_domain_cache[axis] = built
    return built


func _build_axis_domain(axis: int) -> Array:
    var out: Array = []
    match axis:
        Axis.NAME:
            for n in _host._star_names:
                out.append(str(n))
        Axis.PITCH:
            for n in _host._widgets._distinct_note_names():
                out.append(str(n))
        Axis.COLOR:
            for ci in _host.COLOR_NAME_LABELS.size():
                out.append(int(ci))
        Axis.DEGREE:
            var seen: Dictionary = {}
            for s in _host._star_count:
                seen[int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0] = true
            out = seen.keys()
        Axis.REPEAT:
            # -1 (never-fires, an authoring gap) is excluded from the
            # domain -- it is not a legitimate value for the player to
            # confirm/deduce, unlike every real repeat-count.
            out = _repeat_count_domain()
    return out


## THE REPEAT COUNTS THE PLAYER IS SHOWN, which is also the engine's domain for
## the axis: the counts some star of this puzzle really has, ascending.
##
## Author ruling 2026-10-11 (second of the day, and it replaces the first):
## Listen reveals every star's count, so a count no star has is disproved by
## the Star Map itself and must not be offered as a button anywhere. For a few
## hours the domain was "0 up to the number of repeat notes", so the engine
## would not know which counts occur; with only the occurring counts on
## screen that would have left the engine unable to see what the player sees.
## The two must be the same list, so the engine's narrowed-to-one rule fires
## exactly when the player has one button left.
##
## Falls back to the player's own bucket list when the puzzle carries no
## repeat counts at all (a bare test board).
func _repeat_values_shown() -> Array:
    var seen: Dictionary = {}
    for rc in _host._repeat_count:
        if int(rc) >= 0:
            seen[int(rc)] = true
    if seen.is_empty():
        return _get_repeat_bucket_values()
    var out: Array = seen.keys()
    out.sort()
    return out


func _repeat_count_domain() -> Array:
    return _repeat_values_shown()


## Every count a record could carry a mark for: the shown counts plus whatever
## the Sort:Repeats bucket list holds. For clearing and sharing marks, where
## missing a value would strand it.
func _repeat_values_all() -> Array:
    var out: Array = _repeat_values_shown()
    for v in _get_repeat_bucket_values():
        if not out.has(int(v)):
            out.append(int(v))
    out.sort()
    return out


func _axis_state(axis: int, record_idx: int, value) -> int:
    match axis:
        Axis.NAME:   return _effective_name_state(record_idx, str(value))
        Axis.PITCH:  return _effective_pitch_state(record_idx, str(value))
        Axis.COLOR:  return _effective_color_state(record_idx, int(value))
        Axis.DEGREE: return _effective_degree_state(record_idx, int(value))
        Axis.REPEAT: return _effective_repeat_state(record_idx, int(value))
    return 0


## How many stars actually carry this value — the incidence the clique must
## reach before the value can be ruled out anywhere else.
func _axis_incidence(axis: int, value) -> int:
    match axis:
        Axis.PITCH:  return _pitch_star_count(str(value))
        Axis.COLOR:  return _color_star_count(int(value))
        Axis.DEGREE: return _degree_star_count(int(value))
        Axis.REPEAT: return _repeat_count_star_count(int(value))
    return 0


func _axis_clique_key(axis: int, value) -> String:
    match axis:
        Axis.PITCH:  return "P:" + str(value)
        Axis.COLOR:  return "C:%d" % int(value)
        Axis.DEGREE: return "D:%d" % int(value)
        Axis.REPEAT: return "R:%d" % int(value)
    return ""


## Does this record count as a confirmer of `value`? Pitch alone needs a
## guard: an auto-created star-widget record holds a star_idx it never
## earned, so its ground-truth note must not count until Listen has
## actually revealed it. Colour and Degree are "given" axes — painted on
## the map — so their ground-truth tier is no leak. REPEAT needs no guard
## either: its only ground-truth tier is gated on Listen inside
## _effective_repeat_state (_repeat_given_for_record, 2026-10-11), so a
## confirm comes from the player's own mark or from a star they have Listened
## to — there is nothing un-earned to leak.
func _axis_confirms(axis: int, record_idx: int, value) -> bool:
    if axis == Axis.PITCH \
            and _record_is_unconfirmed_star_widget_stub(record_idx) \
            and not bool(_match_records[record_idx].get("pitch_revealed", false)):
        return false
    return _axis_state(axis, record_idx, value) == 1


## Records this axis has nothing left to say about. Each of these was an
## optimisation in the per-axis original, not a semantic guard — once the
## skip condition holds, the state reads already return a confirm and the
## rule writes nothing. Preserved per-axis rather than unified so this
## refactor stays behaviour-neutral.
func _axis_skip_record(axis: int, record_idx: int) -> bool:
    if axis == Axis.PITCH:
        return bool(_match_records[record_idx].get("pitch_revealed", false))
    # NAME is deliberately NOT skipped on a resolved star_idx. Colour,
    # Pitch and Degree all read ground truth through _effective_star_idx, so
    # once a record is bound there is nothing left for the rule to conclude
    # — but _effective_name_state refuses to consult star_idx at all (its
    # own comment: a star_idx set by mere widget auto-creation is not a
    # player-confirmed identity). A bound record's NAME can still be
    # deduced by elimination, so skipping it would silently suppress real
    # deductions. Caught while chasing the perf of this very refactor —
    # the first draft applied the skip to every axis.
    if axis == Axis.NAME:
        return false
    # REPEAT is the same shape as NAME here, for the same reason:
    # _effective_repeat_state has no star_idx tier at all, so a bound
    # record's repeat-count is exactly as undetermined as an unbound one's
    # until the player's own marks (or elimination) say otherwise.
    if axis == Axis.REPEAT:
        return false
    return _effective_star_idx(record_idx) >= 0


## Colour is the only axis whose writes feed something outside the state
## dicts: a narrowed colour changes the candidate-star set that the star-map
## name checklists read through star_elim.
func _axis_after_write(axis: int, record_idx: int) -> void:
    if axis == Axis.COLOR:
        _recompute_color_star_elim(record_idx)


# ── RULE 1: cross-record exclusion (incidence / pigeonhole) ──────────────
## Values ruled out for `record_idx` because every star carrying them is
## already accounted for by other, provably-distinct records. Replaces the
## three identical _compute_excluded_{pitches,colors,degrees}_for bodies;
## those names survive as wrappers because widgets calls them directly.
func _compute_excluded_for_axis(axis: int, record_idx: int) -> Array:
    var excluded: Array = []
    for value in _axis_domain(axis):
        var inc: int = _axis_incidence(axis, value)
        if inc <= 0:
            continue
        var clique: Array = _confirmer_clique(_axis_clique_key(axis, value),
            func(i: int) -> bool: return _axis_confirms(axis, i, value))
        if _value_fully_accounted_for(record_idx, clique, inc):
            excluded.append(value)
    return excluded


# ── RULE 2: push those exclusions into the derived layer ─────────────────
## Without this the exclusion reaches only the display and no deduction pass
## can see it — the exact defect found four times over, once per axis.
##
## Cliques are built ONCE per pass, not once per (record x value): the
## Callable handed to _confirmer_clique is rebuilt at each call site even
## when the clique itself is cached, and that allocation was the dominant
## cost of these passes (164ms -> 52ms on Pitch when hoisted).
func _settle_derived_exclusions_for_axis(axis: int) -> void:
    var ready: Array = []   # [value, clique, incidence] for viable values only
    for value in _axis_domain(axis):
        var inc: int = _axis_incidence(axis, value)
        if inc <= 0:
            continue
        var clique: Array = _confirmer_clique(_axis_clique_key(axis, value),
            func(i: int) -> bool: return _axis_confirms(axis, i, value))
        # A clique smaller than the incidence can never account for every
        # carrier, so the value is dropped before the record loop rather
        # than re-tested once per record.
        if clique.size() >= inc:
            ready.append([value, clique, inc])
    if ready.is_empty():
        return

    var states_key: String = _axis_states_key(axis)
    for i in _match_records.size():
        # "Ground truth already governs" is TRUE for a record the player has
        # really identified, and FALSE for an auto-created star-widget stub.
        # A stub has star_idx >= 0 from the instant its widget renders, but
        # _effective_name_state and _effective_pitch_state deliberately
        # withhold ground truth from it (see
        # _record_is_unconfirmed_star_widget_stub) precisely so its true
        # name and pitch do not leak. So its Name axis really is unknown —
        # measured 2026-08-13: all 15 names still open on a star-7 stub —
        # and skipping it threw away every derivable exclusion for every
        # star widget's Name checklist.
        #
        # Unskipping can only ADD conclusions: this pass writes solely
        # through _add_derived_state, which never overwrites player input,
        # and its clique reasoning does not consult star_idx at all.
        if _effective_star_idx(i) >= 0 and not _record_is_unconfirmed_star_widget_stub(i):
            continue   # genuinely identified; ground truth governs
        for e in ready:
            var value = (e as Array)[0]
            if _axis_state(axis, i, value) != 0:
                continue
            if _value_fully_accounted_for(i, (e as Array)[1], int((e as Array)[2])):
                if _add_derived_state(i, states_key, value, 2):
                    _axis_after_write(axis, i)


# ── RULE 3: narrowed-to-one is a confirm ─────────────────────────────────
## One remaining candidate IS a confirm on THIS record, regardless of
## whether the axis is alldiff — alldiff-ness only governs whether the value
## can also be ruled out for OTHER records, which is Rule 1's job.
func _settle_singleton_for_axis(axis: int) -> void:
    var states_key: String = _axis_states_key(axis)
    var domain: Array = _axis_domain(axis)
    for i in _match_records.size():
        if _axis_skip_record(axis, i):
            continue
        var confirmed_value = null
        var remaining = null
        var remaining_count: int = 0
        for value in domain:
            var state: int = _axis_state(axis, i, value)
            if state == 1:
                confirmed_value = value
                break
            if state != 2:
                remaining_count += 1
                remaining = value
        if confirmed_value == null and remaining_count == 1:
            if _add_derived_state(i, states_key, remaining, 1):
                _axis_after_write(axis, i)
        elif confirmed_value != null and axis == Axis.NAME:
            # Name alone has an identity consequence: promote a PLAYER'S
            # confirm into r["name"], never a merely derived one, since
            # r["name"] is what can feed a destructive merge. Re-run every
            # refresh so a promotion skipped earlier (another record held
            # the name at the time) keeps retrying. Idempotent.
            var nm: String = str(confirmed_value)
            if str(_match_records[i].get("name", "")) == "" \
                    and int((_match_records[i].get("name_states", {}) as Dictionary).get(nm, 0)) == 1:
                _propagate_name_states_confirmed_same_record(i, nm)


## rest of the engine sees what the display sites have always shown.
##
## _compute_excluded_names_for was applied ONLY where a checklist is drawn.
## Every deduction pass read _effective_name_state instead, which knows
## nothing about it — so a Staff popup with thirteen names X'd and a
## fourteenth already claimed by another record showed the player exactly one
## name left, and _settle_singleton_names still counted two and confirmed
## nothing. Name is alldiff with one canonical record per name, so the
## exclusion is unconditional and needs no incidence guard; putting it in the
## derived layer makes the engine agree with the screen instead of trailing
## it, and it is released with its causes like every other derived fact.
## Same reasoning as _settle_same_position_identity for why no cache is
## invalidated here: _settle_singleton_names, the pass this exists to feed,
## reads the derived layer straight through _effective_name_state.
func _settle_derived_name_exclusions() -> void:
    # Deliberately does NOT call _compute_excluded_names_for per record,
    # even though that is the function whose result this mirrors. WHICH
    # records confirm a name does not depend on who is asking, and that
    # function rediscovers it on every call — running it once per record
    # made this n^2 dictionary walks (~115 ms of a 57-record refresh).
    # Hoisted, it is records x confirmers, and confirmers is at most the
    # number of star names.
    var confirmers: Array = []
    for j in _match_records.size():
        if _record_is_unconfirmed_star_widget_stub(j):
            continue
        var nm: String = _confirmed_name_for_record(j)
        if nm != "":
            confirmers.append([j, nm])
    if confirmers.is_empty():
        return
    for i in _match_records.size():
        if _confirmed_name_for_record(i) != "":
            continue   # already named — no name exclusion can tell it more
        for entry in confirmers:
            var j2: int = int((entry as Array)[0])
            if j2 == i:
                continue
            var nm2: String = str((entry as Array)[1])
            # Cheap test first: most names are already settled, and
            # distinctness is the expensive half of the pair.
            if _effective_name_state(i, nm2) != 0:
                continue
            if _records_provably_distinct(i, j2):
                _add_derived_state(i, "name_states", nm2, 2)



## Every record already down to exactly one position, as [record_idx, pos].
##
## A position is taken when a provably-different record is down to exactly
## one candidate — whether the player typed it or this refresh derived it.
## (Reading seq_lo == seq_hi alone stopped seeing derived pins the moment
## they moved into the derived layer, which silently dropped every exclusion
## cascade.) Which records those are does not depend on WHO is asking, so it
## is answered once per refresh rather than rebuilt inside every
## _compute_excluded_positions_for call — that function is itself called
## once per record per fixpoint round, so the scan was running n^2 times.
var _seq_singleton_cache: Array = []
var _seq_singleton_built: bool = false


func _seq_singleton_owners() -> Array:
    if _seq_singleton_built:
        return _seq_singleton_cache
    _seq_singleton_cache = []
    for i in _match_records.size():
        var s: Array = _seq_candidate_set_for(i)
        if s.size() == 1:
            _seq_singleton_cache.append([i, int(s[0])])
    _seq_singleton_built = true
    return _seq_singleton_cache


func _compute_excluded_positions_for(record_idx: int) -> Array:
    # Reads the CURRENT set of records live (through the cache above, which
    # is invalidated by every narrowing). Nothing is stored or pushed, so a
    # record created AFTER some other record's position was confirmed still
    # sees the exclusion correctly — proven necessary by the Sort:Color
    # test: color-slot records created after the Blue/15 confirmation never
    # received a one-time push, because a push cannot reach something that
    # doesn't exist yet.
    var excluded: Array = []
    for entry in _seq_singleton_owners():
        var i: int = int((entry as Array)[0])
        if i == record_idx:
            continue
        if _records_provably_distinct(record_idx, i):
            excluded.append(int((entry as Array)[1]))
    return excluded


func _compute_excluded_names_for(record_idx: int) -> Array[String]:
    # Same live-query shape as _compute_excluded_positions_for above —
    # Name (this record-level name_states mechanism) is alldiff, single
    # canonical record per name via _get_or_create_match_record_for_name,
    # same as Sequence's _get_or_create_match_record_for_seq — so the
    # exclusion is unconditional, no incidence-count guard needed (unlike
    # Pitch below). Deliberately calls _effective_name_state, NOT this
    # function's own eventual caller — that's the "base" ground-truth/
    # slot-label/raw tier, safe to call here with no recursion, since the
    # cross-record exclusion this computes is layered on TOP of it only at
    # display call sites, never inside _effective_name_state itself.
    # Name is alldiff, so a record confirms at most ONE name — found once
    # per record here rather than by asking _effective_name_state about all
    # 15 of them. The distinctness check is hoisted out of that loop too:
    # it never depended on the name, so it was being recomputed once per
    # (record x name) instead of once per record. Together those made this
    # the second-largest cost in a refresh at 75 records (~640 ms across a
    # full set of rows, measured).
    var excluded: Array[String] = []
    for i in _match_records.size():
        if i == record_idx or _record_is_unconfirmed_star_widget_stub(i):
            continue
        var confirmed: String = _confirmed_name_for_record(i)
        if confirmed == "":
            continue
        if _records_provably_distinct(record_idx, i):
            excluded.append(confirmed)
    return excluded


## The single name a record confirms, or "". Checks the identity field
## first (set by every real confirmation path) and falls back to a scan of
## name_states for a record confirmed before that promotion existed.
func _confirmed_name_for_record(record_idx: int) -> String:
    var r: Dictionary = _match_records[record_idx]
    var nm: String = str(r.get("name", ""))
    if nm != "":
        return nm
    for k in (r.get("name_states", {}) as Dictionary):
        if int(r["name_states"][k]) == 1:
            return str(k)
    return ""


# ==================================================
# CROSS-RECORD VALUE EXCLUSION — general cardinality (pigeonhole) rule.
#
# All three non-alldiff axes (Color, Pitch, Degree) used to gate on
# `_X_star_count(v) != 1` — i.e. they implemented ONLY the k=1 special case
# of the real rule, and silently did nothing for every value with two or
# more stars. The general rule:
#
#   A value V can be ruled out for record R once the number of OTHER
#   records that confirm V, and are provably distinct from R and from each
#   other, has reached V's total incidence count. All the stars carrying V
#   are then accounted for, so R cannot be another one.
#
# k=1 is just that with incidence 1. Confirmed live (2026-08-07): with
# every star's pitch revealed via Listen and colors sorted, all Blue stars
# were G4 or A#4 — two stars per note, so incidence 2 — and G4/A#4 were
# never excluded from any other colour's slot, because `!= 1` skipped them
# outright. The counting idea already existed in this file for VALIDATION
# (_confirm_color_against_cap catches "5 records confirmed Blue when only 4
# stars are Blue"); it just never reached the exclusion side.
#
# Name and Sequence deliberately keep their own simpler functions: both are
# alldiff, so incidence is always 1 and the general rule collapses back to
# the pairwise check they already do.
# ==================================================

## Largest set of records that all confirm one value AND are pairwise
## provably distinct — i.e. how many DIFFERENT stars are demonstrably
## accounted for by that value so far. Greedy, so it can undercount when
## the distinctness graph is awkward (exact maximum clique is NP-hard);
## undercounting only ever means "exclude later than strictly possible",
## never a wrong exclusion, so the approximation is safe in the sound
## direction. Cached per value for the reasons in _clear_deduction_caches().
func _confirmer_clique(cache_key: String, confirms: Callable) -> Array:
    if _confirmer_clique_cache.has(cache_key):
        return _confirmer_clique_cache[cache_key]
    var clique: Array = []
    for i in _match_records.size():
        if not bool(confirms.call(i)):
            continue
        var independent: bool = true
        for j in clique:
            if not _records_provably_distinct(i, int(j)):
                independent = false
                break
        if independent:
            clique.append(i)
    _confirmer_clique_cache[cache_key] = clique
    return clique


## Is every star carrying this value already accounted for by records other
## than record_idx? See this section's header comment for the rule.
func _value_fully_accounted_for(record_idx: int, clique: Array, incidence: int) -> bool:
    if incidence <= 0:
        return false
    # The loop below counts AT MOST clique.size(), so a clique smaller than
    # the incidence can never reach it — the answer is already known without
    # asking about distinctness at all. That matters far more than it looks:
    # _records_provably_distinct is the innermost primitive of the engine,
    # and this function is called once per (record x value) by all three
    # non-alldiff exclusion passes, every fixpoint round. Most values have
    # nobody (or one lone record) confirming them, so most of those calls
    # were walking a clique that could not possibly qualify. Adding this
    # line took cold pair verdicts on a 57-record board from ~5300 per
    # refresh to a fraction of that — see the profiling note in
    # [[deduction_refresh_perf_budget]].
    if clique.size() < incidence:
        return false
    var n: int = 0
    for i in clique:
        var idx: int = int(i)
        if idx == record_idx:
            return false   # this record is itself one of the carriers
        if _records_provably_distinct(record_idx, idx):
            n += 1
    return n >= incidence


# The three wrappers below exist because constellation_puzzle_widgets.gd
# calls them by name to strike values out of the Staff popup / Sort:tab
# checklists. The rule itself lives once, in _compute_excluded_for_axis;
# these only re-impose the typed return the widget call sites expect.
# Per-axis quirks that used to be re-explained here — Pitch's unearned-
# ground-truth stub guard, Colour and Degree being "given" axes that need
# no such guard — now live in _axis_confirms, stated once.

func _compute_excluded_pitches_for(record_idx: int) -> Array[String]:
    var out: Array[String] = []
    for v in _compute_excluded_for_axis(Axis.PITCH, record_idx):
        out.append(str(v))
    return out


func _compute_excluded_colors_for(record_idx: int) -> Array[int]:
    var out: Array[int] = []
    for v in _compute_excluded_for_axis(Axis.COLOR, record_idx):
        out.append(int(v))
    return out


func _compute_excluded_degrees_for(record_idx: int) -> Array[int]:
    var out: Array[int] = []
    for v in _compute_excluded_for_axis(Axis.DEGREE, record_idx):
        out.append(int(v))
    return out


# ==================================================
# CLUE COVERAGE — built on the CELL model, per the unified-grid design
# intent (the grid is meant to be the one shared checker for entropy,
# trimming, and coverage alike, not a parallel ad-hoc checker per consumer).
#
# A clue's persisted "cells" (ConstellationLogicPuzzle CACHE_VERSION 4) are
# its actual ASSERTIONS, each {cat_a, star_a, cat_b, star_b, is_true}
# meaning "the star identified via cat_a and the star identified via cat_b
# are (is_true) / are not (not is_true) the same star" — see
# _build_matrix()'s own `is_true: star_a == star_b`.
#
# _match_records models exactly that same thing: one record IS a
# hypothesized star identity with descriptors attached. So a cell is
# "resolved" when the player's own records assert the same relation, and
# the sign falls out natively — an ELIMINATION resolves an is_true==false
# cell just as fully as a confirm resolves an is_true==true one. That is
# the whole reason the previous chars-based version could not be made
# correct by adjustment: "chars" records which entities a clue MENTIONS,
# and two clues asserting opposite things carry identical chars.
#
# Also note what's gone: no ground-truth lookup (sequence_rank_solution /
# star_names / star_colors as an answer key) appears below any more. Both
# sides are expressed in the same descriptor space, so coverage no longer
# asks "is the truth about this star known" — only "did the player record
# this relation."
# ==================================================

## Player-space state of one descriptor — "is this record the star that
## (has this name / fires at this position / is this color / plays this
## note)" — as 1 confirmed, 2 ruled out, 0 unknown. `star` identifies WHICH
## descriptor via the cached ground-truth arrays, exactly the way each
## Form's own label rendering does; it is not itself an answer-key read,
## since nothing here returns the star.
func _record_descriptor_state(record_idx: int, cat: int, star: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    if star < 0 or star >= _host._star_count:
        return 0
    match cat:
        ConstellationLogicPuzzle.Category.NAME:
            if star >= _host._star_names.size():
                return 0
            return _effective_name_state(record_idx, str(_host._star_names[star]))
        ConstellationLogicPuzzle.Category.SEQUENCE:
            if star >= _host._sequence_rank_solution.size():
                return 0
            var pos: int = int(_host._sequence_rank_solution[star]) + 1
            # Deliberately the stored-plus-derived set, NOT
            # _effective_seq_candidates: the latter calls
            # _compute_excluded_positions_for, which loops every record
            # calling _records_provably_distinct, which itself sweeps every
            # category — all of that nested inside this function's own
            # per-record loop, inside a per-cell loop, inside a per-clue
            # loop, re-run on every _populate_markers_panel(). That was the
            # multi-second Study-panel delay (roughly 10^6 ops per repaint).
            # No coverage is lost: an exclusion _compute_excluded_positions_
            # for would have found is recorded into the derived layer by
            # _settle_singleton_sequences() on the same refresh, and
            # _seq_candidate_set_for() reads that.
            var seq_set: Array = _seq_candidate_set_for(record_idx)
            if seq_set.is_empty():
                return 0   # no sequence information at all on this record
            if seq_set.size() == 1:
                return 1 if int(seq_set[0]) == pos else 2
            return 0 if seq_set.has(pos) else 2
        ConstellationLogicPuzzle.Category.COLOR:
            if star >= _host._star_colors.size():
                return 0
            return _effective_color_state(record_idx, int(_host._star_colors[star]))
        ConstellationLogicPuzzle.Category.PITCH:
            # Skip an auto-created star-widget stub's un-earned ground-truth
            # tier, same guard _compute_excluded_pitches_for uses — a stub
            # exists for every star the instant its widget renders, and its
            # pitch is only legitimately known once Listen has fired.
            if _record_is_unconfirmed_star_widget_stub(record_idx) \
                    and not bool(_match_records[record_idx].get("pitch_revealed", false)):
                return 0
            var note: String = _host._widgets._note_name_for_star(star)
            if note == "?":
                return 0
            return _effective_pitch_state(record_idx, note)
    return 0


## Has the player's own note state resolved this cell to the value the clue
## asserts? Three sound routes, matching how the records actually get used:
##  - is_true: one record confirms BOTH descriptors (they're the same star).
##  - not is_true: one record confirms one descriptor and rules out the
##    other (same record can't be both) ...
##  - not is_true: ...or two DIFFERENT records confirm one descriptor each
##    and are provably distinct (so the descriptors are on different stars).
func _cell_resolved_by_player(cell: Dictionary) -> bool:
    var cat_a: int = int(cell.get("cat_a", -1))
    var star_a: int = int(cell.get("star_a", -1))
    var cat_b: int = int(cell.get("cat_b", -1))
    var star_b: int = int(cell.get("star_b", -1))
    var want_true: bool = bool(cell.get("is_true", false))

    var confirms_a: Array[int] = []
    var confirms_b: Array[int] = []
    for i in _match_records.size():
        var sa: int = _record_descriptor_state(i, cat_a, star_a)
        var sb: int = _record_descriptor_state(i, cat_b, star_b)
        if want_true:
            if sa == 1 and sb == 1:
                return true
        else:
            if (sa == 1 and sb == 2) or (sb == 1 and sa == 2):
                return true
        if sa == 1:
            confirms_a.append(i)
        if sb == 1:
            confirms_b.append(i)

    if not want_true:
        for ia in confirms_a:
            for ib in confirms_b:
                if ia != ib and _records_provably_distinct(ia, ib):
                    return true
    return false


## Coverage for one clue: how many of its asserted cells the player's own
## notes have resolved. Returns {"covered": int, "total": int}; total drops
## any cell with an out-of-range star (corrupted/stale cache), so it can be
## zero — check before dividing.
## The search-term token a descriptor would render as, matching the format
## _characteristic_label() writes into search_terms. Used to tell a cell
## the clue actually STATED from one it merely consumed.
func _descriptor_term(cat: int, star: int) -> String:
    if star < 0 or star >= _host._star_count:
        return ""
    match cat:
        ConstellationLogicPuzzle.Category.NAME:
            return "N:" + str(_host._star_names[star]) if star < _host._star_names.size() else ""
        ConstellationLogicPuzzle.Category.SEQUENCE:
            if star >= _host._sequence_rank_solution.size():
                return ""
            return "S:%d" % (int(_host._sequence_rank_solution[star]) + 1)
        ConstellationLogicPuzzle.Category.COLOR:
            if star >= _host._star_colors.size():
                return ""
            return "C:" + str(_host.COLOR_NAME_LABELS[int(_host._star_colors[star])])
        ConstellationLogicPuzzle.Category.PITCH:
            var n: String = _host._widgets._note_name_for_star(star)
            return "P:" + n if n != "?" else ""
    return ""


## Is this cell something the clue TOLD the player, or just the matrix cell
## the generator happened to consume?
##
## grid_updates marks the sampled cell, which is routinely stronger than the
## sentence: Form 8/Range emits {id x SEQUENCE(exact rank), true} while its
## text only says "among the first N" — its own comment says so — and Form
## 5/Pairwise Order emits BOTH stars' exact position cells while the text
## gives only an ordering. Coverage built on raw cells therefore demanded
## exact positions the clue never disclosed, so relational and range Forms
## could never reach "Used Up".
##
## A cell was genuinely stated exactly when BOTH of its descriptors were
## rendered into the text — which search_terms records verbatim. Form 1
## ("the star that fires 3rd IS X") renders both, so it counts; Range and
## Pairwise Order never render the exact rank, so their bookkeeping cells
## are skipped. Negation Forms render both sides, so False cells keep
## working as before.
func _cell_was_stated(cell: Dictionary, terms: Array) -> bool:
    if terms.is_empty():
        return true   # pre-CACHE_VERSION-5 clue: fall back to counting it
    var ta: String = _descriptor_term(int(cell.get("cat_a", -1)), int(cell.get("star_a", -1)))
    var tb: String = _descriptor_term(int(cell.get("cat_b", -1)), int(cell.get("star_b", -1)))
    if ta == "" or tb == "":
        return false
    return terms.has(ta) and terms.has(tb)


# ==================================================
# DISCLOSURE EVALUATION — coverage for RELATIONAL clue content.
#
# A cell can only ever say "these two descriptors are the same star / are
# different stars." Most Forms' actual content is relational — ordering,
# offsets, adjacency, counts, extremes, ranges, and Mutual Exclusion's
# "all have different pitches" — and none of that fits in a cell. Measured
# on real puzzles, that left ~78% of clues with nothing coverage could
# score at all (they fell back to COVERAGE_UNMEASURABLE).
#
# `disclosures` (CACHE_VERSION 6) is the encoding that does fit: the same
# typed constraint vocabulary the generator already built for the
# uniqueness CSP, now persisted, plus two value-axis kinds the CSP has no
# use for. See [[clue-encodings-four-representations]] for why this is the
# right one of the four and `cells` was the wrong one.
#
# EVERY test below is deliberately CONSERVATIVE — it answers "do the
# player's own notes already FORCE this, in every assignment still open to
# them?", never "does this look consistent with their notes?". A clue is
# far better left in Useful one refresh too long than moved to Used Up
# while it still has something to give.
# ==================================================

## LOCATED tier: records bound to `star` as a map POSITION, whether the
## player placed them there or the engine derived it.
##
## The auto-stub guard is load-bearing — _build_star_widgets_impl gives
## every star a star_idx-bound record the instant its floating widget
## renders, which is not the player knowing anything.
##
## Split out from _records_identifying_star() because conflating the two
## shipped a bug (2026-08-12): a bare Sort:Name row DENOTES its star by
## definition — the row's whole identity is that name — while saying
## nothing about WHERE on the map that star is. Anything reasoning about
## topology needs this tier; anything resolving a cell wants the union
## below.
func _records_bound_to_star(star: int) -> Array:
    var out: Array = []
    for i in _match_records.size():
        if _effective_star_idx(i) == star \
                and not _record_is_unconfirmed_star_widget_stub(i):
            out.append(i)
    return out


## DENOTES tier: records that provably stand for `star` by either route —
## bound to its map position as above, or carrying a confirmed Name or
## Sequence descriptor for it. Only those two axes can denote: they are the
## alldiff axes, so confirming one names exactly one star, while Colour and
## Pitch are shared and identify nothing on their own.
func _records_identifying_star(star: int) -> Array:
    var out: Array = _records_bound_to_star(star)
    for i in _match_records.size():
        if out.has(i):
            continue
        if _record_descriptor_state(i, ConstellationLogicPuzzle.Category.NAME, star) == 1 \
                or _record_descriptor_state(i, ConstellationLogicPuzzle.Category.SEQUENCE, star) == 1:
            out.append(i)
    return out


## Star-index-keyed sequence candidates. _effective_seq_candidates() is the
## expensive reader (_compute_excluded_positions_for sweeps every record),
## and a single Mutual Exclusion or Extreme clue asks about the same star
## repeatedly, as do the three coverage tabs in turn. Cleared with the rest
## by _clear_deduction_caches().
var _star_positions_cache: Dictionary = {}


## The 1-based sequence positions still open to `star` under the player's
## notes. Empty means UNKNOWN (nothing identifies the star yet), which
## every caller must read as "not entailed" — never as "no positions".
func _player_positions_for_star(star: int) -> Array:
    if _star_positions_cache.has(star):
        return _star_positions_cache[star]
    var recs: Array = _records_identifying_star(star)
    var out: Array = []
    var seeded: bool = false
    for idx in recs:
        var c: Array = _effective_seq_candidates(int(idx))
        if c.is_empty():
            continue
        if not seeded:
            out = c.duplicate()
            seeded = true
            continue
        # Identity unification should have merged these already; intersect
        # rather than trust that, so a stale split can only under-report.
        var merged: Array = []
        for p in out:
            if c.has(p):
                merged.append(p)
        out = merged
    _star_positions_cache[star] = out
    return out


## True only when EVERY still-open position pair satisfies `relation` — the
## definition of "the player's notes force this". Unknown on either side
## (empty set) is false, never vacuously true.
func _all_position_pairs_satisfy(pa: Array, pb: Array, relation: Callable) -> bool:
    if pa.is_empty() or pb.is_empty():
        return false
    for x in pa:
        for y in pb:
            if not bool(relation.call(int(x), int(y))):
                return false
    return true


func _positions_strictly_before(pa: Array, pb: Array) -> bool:
    return _all_position_pairs_satisfy(pa, pb, func(x: int, y: int) -> bool: return x < y)


## Full value domain for a shared-value axis, read from ground truth (every
## colour and every note in the constellation sits on some star).
func _value_domain(cat: int) -> Array:
    # Repeat Count is the exception to "read from ground truth": which counts
    # occur is hidden, so its domain is every count the staff allows.
    if cat == ConstellationLogicPuzzle.Category.REPEAT:
        return _repeat_count_domain()
    var out: Array = []
    for s in _host._star_count:
        var v
        if cat == ConstellationLogicPuzzle.Category.COLOR:
            if s >= _host._star_colors.size():
                continue
            v = int(_host._star_colors[s])
        elif cat == ConstellationLogicPuzzle.Category.REPEAT:
            if s >= _host._repeat_count.size():
                continue
            var rc: int = int(_host._repeat_count[s])
            if rc < 0:
                continue   # never-fires sentinel, not a real repeat value
            v = rc
        else:
            var n: String = _host._widgets._note_name_for_star(s)
            if n == "?":
                continue
            v = n
        if not out.has(v):
            out.append(v)
    return out


## Values on `cat` still open to `star`. Empty means UNKNOWN, same contract
## as _player_positions_for_star().
## Same lifetime and reasoning as _star_positions_cache: values_all_different
## asks about the same star once per pair, and _effective_pitch_state is not
## cheap enough to redo O(pairs x domain) times per tab repaint.
var _star_values_cache: Dictionary = {}


## The RAW Colour/Pitch value of a star, matching the generator's
## _name_group_key exactly — Colour is the raw colour index, Pitch the raw
## pitch-table index. Deliberately NOT the sub-ranked matrix value: a group
## key must say "which colour", where the matrix value says "which star",
## and confusing the two is what makes a group claim look like an identity
## claim. Both sides must agree on this or a group_key will never match.
func _raw_group_key(cat: int, star: int) -> int:
    if star < 0 or star >= _host._star_count:
        return -1
    match cat:
        ConstellationLogicPuzzle.Category.COLOR:
            return int(_host._star_colors[star]) if star < _host._star_colors.size() else -1
        ConstellationLogicPuzzle.Category.PITCH:
            return int(_host._star_pitch_index[star]) if star < _host._star_pitch_index.size() else -1
        ConstellationLogicPuzzle.Category.REPEAT:
            # -1 = not known, always (2026-10-11). A star's repeat count is
            # hidden, so no consumer may sort stars into Repeat groups by the
            # answer the way Colour (painted) and Pitch (Listened) allow.
            # Every caller already treats -1 as "cannot tell".
            return -1
    return -1


func _possible_values_for_star(star: int, cat: int) -> Array:
    var vkey: String = "%d:%d" % [star, cat]
    if _star_values_cache.has(vkey):
        return _star_values_cache[vkey]
    var recs: Array = _records_identifying_star(star)
    if recs.is_empty():
        _star_values_cache[vkey] = []
        return []
    var out: Array = []
    for v in _value_domain(cat):
        var eliminated: bool = false
        for idx in recs:
            var st: int = 0
            if cat == ConstellationLogicPuzzle.Category.COLOR:
                st = _effective_color_state(int(idx), int(v))
            elif cat == ConstellationLogicPuzzle.Category.REPEAT:
                st = _effective_repeat_state(int(idx), int(v))
            else:
                st = _effective_pitch_state(int(idx), str(v))
            if st == 2:
                eliminated = true
                break
        if not eliminated:
            out.append(v)
    _star_values_cache[vkey] = out
    return out


func _value_sets_disjoint(a: Array, b: Array) -> bool:
    if a.is_empty() or b.is_empty():
        return false
    for v in a:
        if b.has(v):
            return false
    return true


## Has the player already derived everything this disclosure says?
##
## Rank fields in the fact vocabulary are 0-based (they index
## sequence_rank_solution); player-side positions are 1-based, hence the +1
## on every crossing.
func _disclosure_satisfied(f: Dictionary) -> bool:
    var kind: String = str(f.get("kind", ""))
    # FIRST NOTES HIDDEN: the board keeps no positions, so a fact about firing
    # order is judged against the notes each row holds (_note_fact_entailed).
    # Kinds that cannot be judged that way fall through to the readings below,
    # which find no positions and answer "not yet".
    if _notes_hidden():
        var by_notes: Dictionary = _note_fact_entailed(f)
        if bool(by_notes["known"]):
            return bool(by_notes["value"])
    match kind:
        "ordinal_exact":
            var p: Array = _player_positions_for_star(int(f.get("s", -1)))
            return p.size() == 1 and int(p[0]) == int(f.get("r", -1)) + 1
        "ordinal_neg":
            var pn: Array = _player_positions_for_star(int(f.get("s", -1)))
            return not pn.is_empty() and not pn.has(int(f.get("r", -1)) + 1)
        "ordinal_cmp":
            var pa: Array = _player_positions_for_star(int(f.get("a", -1)))
            var pb: Array = _player_positions_for_star(int(f.get("b", -1)))
            if bool(f.get("a_gt_b", false)):
                return _positions_strictly_before(pb, pa)
            return _positions_strictly_before(pa, pb)
        "ordinal_chain":
            var ca: Array = _player_positions_for_star(int(f.get("a", -1)))
            var cm: Array = _player_positions_for_star(int(f.get("mid", -1)))
            var cb: Array = _player_positions_for_star(int(f.get("b", -1)))
            return _positions_strictly_before(ca, cm) and _positions_strictly_before(cm, cb)
        "ordinal_adjacent", "ordinal_offset":
            var off: int = int(f.get("offset", 1))
            var oa: Array = _player_positions_for_star(int(f.get("a", -1)))
            var ob: Array = _player_positions_for_star(int(f.get("b", -1)))
            return _all_position_pairs_satisfy(oa, ob,
                func(x: int, y: int) -> bool: return x == y + off)
        "ordinal_range":
            var rp: Array = _player_positions_for_star(int(f.get("s", -1)))
            if rp.is_empty():
                return false
            var lo: int = int(f.get("lo", 0)) + 1
            var hi: int = int(f.get("hi", 0)) + 1
            for x in rp:
                if int(x) < lo or int(x) > hi:
                    return false
            return true
        "ordinal_pair_set":
            # Form 26 (Firing Relation): the two stars' ranks are one of an allowed
            # list of pairs. Entailed when every position pair the player still
            # allows is on that list (positions 1-based, the pairs' ranks 0-based).
            var pair_a: Array = _player_positions_for_star(int(f.get("a", -1)))
            var pair_b: Array = _player_positions_for_star(int(f.get("b", -1)))
            var allowed_pairs: Dictionary = {}
            for pr in f.get("pairs", []):
                allowed_pairs[int(pr[0]) * 1000 + int(pr[1])] = true
            return _all_position_pairs_satisfy(pair_a, pair_b,
                func(x: int, y: int) -> bool: return allowed_pairs.has((x - 1) * 1000 + (y - 1)))
        "value_in_set":
            # Form 25 (Firing Position): the star's rank is one of an allowed
            # set. Entailed when every position the player still allows for it
            # is in that set (positions are 1-based, the fact's ranks 0-based).
            var vp: Array = _player_positions_for_star(int(f.get("s", -1)))
            if vp.is_empty():
                return false
            var allowed_set: Array = f.get("allowed", [])
            for x in vp:
                var in_set: bool = false
                for al in allowed_set:
                    if int(al) + 1 == int(x):
                        in_set = true
                        break
                if not in_set:
                    return false
            return true
        "ordinal_either_or":
            var ep: Array = _player_positions_for_star(int(f.get("s", -1)))
            if ep.is_empty():
                return false
            var r1: int = int(f.get("r1", -1)) + 1
            var r2: int = int(f.get("r2", -1)) + 1
            for x in ep:
                if int(x) != r1 and int(x) != r2:
                    return false
            return true
        "ordinal_extreme":
            var xs: Array = _player_positions_for_star(int(f.get("s", -1)))
            var want_lowest: bool = bool(f.get("want_lowest", false))
            var neighbors: Array = f.get("neighbors", [])
            if neighbors.is_empty():
                return false
            for n in neighbors:
                var np: Array = _player_positions_for_star(int(n))
                var ok: bool = _positions_strictly_before(xs, np) if want_lowest \
                    else _positions_strictly_before(np, xs)
                if not ok:
                    return false
            return true
        "ordinal_count_before":
            # Needs EVERY neighbour's side settled, not just enough of them
            # to hit k — an undecided neighbour could still land either
            # way and change the count.
            var cs: Array = _player_positions_for_star(int(f.get("s", -1)))
            var cneighbors: Array = f.get("neighbors", [])
            if cneighbors.is_empty():
                return false
            var before: int = 0
            for n2 in cneighbors:
                var n2p: Array = _player_positions_for_star(int(n2))
                if _positions_strictly_before(n2p, cs):
                    before += 1
                elif not _positions_strictly_before(cs, n2p):
                    return false   # this neighbour is still undecided
            return before == int(f.get("k", -1))
        "descriptor_not_in_group":
            # "Neither Helios nor the star that fires 7th note is blue."
            # Entailed when every star the descriptor could still BE sits
            # outside the named Colour/Pitch group.
            #
            # Sound for the same reason the column rule is:
            # _stars_possible_for_descriptor returns a SUPERSET of the
            # truth, so if no member of that superset is in the group, the
            # real star certainly is not either. An overcount can only make
            # this answer "not yet", never "yes" wrongly.
            #
            # Keyed on the DESCRIPTOR, not on a Name record, which is the
            # whole point: a Sequence subject ("the star that fires 7th
            # note is not blue") is exactly as evaluable as a Name one, and
            # the player records both the same way — by crossing the colour
            # off that descriptor's row.
            var dcat: int = int(f.get("cat", -1))
            var dstar: int = int(f.get("star", -1))
            var gcat: int = int(f.get("group_cat", -1))
            var gkey: int = int(f.get("group_key", -1))
            if dstar < 0 or dstar >= _host._star_count:
                return false
            if gcat == ConstellationLogicPuzzle.Category.REPEAT:
                # No star's repeat count can be looked up (it is hidden), so
                # this is entailed by the player's own Repeats marks instead:
                # every count they still allow the star differs from the one
                # the clue denies.
                var open_counts: Array = _possible_values_for_star(dstar, gcat)
                return not open_counts.is_empty() and not open_counts.has(gkey)
            var possible: Array = _stars_possible_for_descriptor(dcat, dstar)
            if possible.is_empty():
                return false
            for ps in possible:
                if _raw_group_key(gcat, int(ps)) == gkey:
                    return false   # still could be a member — not yet entailed
            return true
        "values_all_different":
            var cat: int = int(f.get("cat", -1))
            var stars: Array = f.get("stars", [])
            if stars.size() < 2:
                return false
            var sets: Array = []
            for s2 in stars:
                sets.append(_possible_values_for_star(int(s2), cat))
            for i2 in sets.size():
                for j2 in range(i2 + 1, sets.size()):
                    if not _value_sets_disjoint(sets[i2], sets[j2]):
                        return false
            return true
        "descriptor_either_or":
            # "A is either B or C." Entailed when the player has ruled out
            # every OTHER value on that axis for the record holding A —
            # narrowing to the same two the clue named. Compared by
            # rendered term, not star index, so shared-value axes
            # (Colour/Pitch) don't demand eliminating a star whose value
            # is one of the two named.
            var acat: int = int(f.get("cat_a", -1))
            var astar: int = int(f.get("star_a", -1))
            var bcat: int = int(f.get("cat_b", -1))
            var t1: String = _descriptor_term(bcat, int(f.get("s1", -1)))
            var t2: String = _descriptor_term(bcat, int(f.get("s2", -1)))
            if t1 == "" or t2 == "":
                return false
            for i3 in _match_records.size():
                if _record_descriptor_state(i3, acat, astar) != 1:
                    continue
                var all_others_out: bool = true
                for t3 in _host._star_count:
                    var term: String = _descriptor_term(bcat, int(t3))
                    if term == "" or term == t1 or term == t2:
                        continue
                    if _record_descriptor_state(i3, bcat, int(t3)) != 2:
                        all_others_out = false
                        break
                if all_others_out:
                    return true
            return false
        "distance_hop":
            # "The star identified by <ref's descriptor> is N hops from the
            # star identified by <target's descriptor>" — or, with
            # negated=true, is NOT N hops from it (Form 19's "not
            # connected" is exactly negated hops=1).
            #
            # Exhausted when NEITHER side can narrow any further — see
            # _distance_side_exhausted for what that means per category and
            # why it is not "did this pass change anything".
            #
            # This kind no longer evaluates the claim against the solution
            # at all. It used to: it looked up the real distance between the
            # disclosure's two star indices and asked whether it matched.
            # That was measuring the ANSWER, not the player's grid, and it
            # needed a gate ("has the player located both ends") bolted on
            # to stop it entailing on a blank board. The gate was the part
            # that broke — twice, in both directions. The clue's content is
            # a constraint on two descriptors, so its exhaustion is a
            # property of those descriptors' remaining freedom and nothing
            # else. What the claim actually rules out is applied by
            # _settle_distance_constraints, where it can propagate.
            var drc: int = int(f.get("ref_cat", -1))
            var dtc: int = int(f.get("target_cat", -1))
            var dref: int = int(f.get("ref", -1))
            var dtgt: int = int(f.get("target", -1))
            if dref < 0 or dtgt < 0 or drc < 0 or dtc < 0:
                return false   # version-6 clue: no descriptor framing to score
            return _distance_side_exhausted(drc, dref) \
                and _distance_side_exhausted(dtc, dtgt)
        "values_same":
            var vcat: int = int(f.get("cat", -1))
            var va: Array = _possible_values_for_star(int(f.get("a", -1)), vcat)
            var vb: Array = _possible_values_for_star(int(f.get("b", -1)), vcat)
            return va.size() == 1 and vb.size() == 1 and va[0] == vb[0]
        "firing_position":
            # A Firing Position clue says something about which notes are the
            # star's. Used up once the board has settled every one of them.
            return _board_notes_settled_for_star(int(f.get("s", -1)))
        "firing_relation":
            return _board_notes_settled_for_star(int(f.get("a", -1))) \
                and _board_notes_settled_for_star(int(f.get("b", -1)))
        "repeat_count_range":
            # "repeats at least once" / "does not repeat twice": entailed when
            # every repeat count the player still allows the star agrees.
            var rstar: int = int(f.get("star", -1))
            if _board_notes_settled_for_star(rstar):
                return true
            var counts: Array = _possible_values_for_star(rstar, ConstellationLogicPuzzle.Category.REPEAT)
            if counts.is_empty():
                return false
            var negated: bool = bool(f.get("negated", false))
            for c in counts:
                var inside: bool = int(c) >= int(f.get("lo", 0)) and int(c) <= int(f.get("hi", 0))
                if inside == negated:
                    return false
            return true
    return false


## Has the player settled which notes are this star's? True when the star's
## position is known and every repeat note that could be it (any after its
## first note) has been decided one way or the other on that note's own
## record: placed on this position, or no longer able to be it. A repeat note
## nobody has opened is undecided, so an untouched board answers false.
##
## The unit is the CELL (repeat note x position), read off the note's record,
## which is where that cell lives; a star's own Sort row says nothing about it.
func _board_notes_settled_for_star(star: int) -> bool:
    if star < 0 or star >= _host._star_count or not _seq_repeats():
        return false
    var positions: Array = _player_positions_for_star(star)
    if positions.size() != 1:
        return false
    var rank: int = int(positions[0])
    var first: int = _first_tick_for_rank(rank)
    for tick in range(first + 1, _melody_tick_count() + 1):
        if _tick_is_first_fire(tick):
            continue
        var idx: int = _find_match_record_by_melody_tick(tick)
        if idx < 0:
            return false
        var cands: Array = _effective_seq_candidates(idx)
        if cands.has(rank) and cands.size() != 1:
            return false
    return true


## Kinds _disclosure_satisfied() can actually rule on. Anything else (today
## only "flavor", which asserts nothing) must not enter the denominator —
## counting an unscoreable disclosure as unmet would pin its clue below
## 1.0 forever, which is exactly the failure mode raw `cells` had.
const SCOREABLE_DISCLOSURE_KINDS: Array = [
    "ordinal_exact", "ordinal_neg", "ordinal_cmp", "ordinal_chain",
    "ordinal_adjacent", "ordinal_offset", "ordinal_range", "value_in_set", "ordinal_pair_set",
    "ordinal_either_or", "ordinal_extreme", "ordinal_count_before",
    "values_all_different", "values_same", "descriptor_either_or",
    # Group Negation (Form 24). Descriptor-keyed so a Sequence subject
    # scores exactly like a Name one -- see _disclosure_satisfied.
    "descriptor_not_in_group",
    # CACHE_VERSION 6 content, added 2026-08-12. Only present on clues
    # generated after that date — older saves' distance clues carry no
    # distance disclosure and score exactly as they did before.
    "distance_hop",
    # What a clue says about the repeat notes (2026-10-10, repeats are
    # earned): scored against the notes the player has placed.
    "firing_position", "firing_relation", "repeat_count_range",
]


func _clue_coverage(cells: Array, terms: Array = [], disclosures: Array = []) -> Dictionary:
    var covered: int = 0
    var total: int = 0
    _scoring_clue_terms = terms
    for d in disclosures:
        if not (d is Dictionary):
            continue
        if not SCOREABLE_DISCLOSURE_KINDS.has(str((d as Dictionary).get("kind", ""))):
            continue
        total += 1
        if _disclosure_satisfied(d):
            covered += 1
    _scoring_clue_terms = []
    for cell in cells:
        if not (cell is Dictionary):
            continue
        var c: Dictionary = cell
        var star_a: int = int(c.get("star_a", -1))
        var star_b: int = int(c.get("star_b", -1))
        if star_a < 0 or star_a >= _host._star_count \
                or star_b < 0 or star_b >= _host._star_count:
            continue
        if not _cell_was_stated(c, terms):
            continue   # consumed-but-unstated bookkeeping cell
        total += 1
        if _cell_resolved_by_player(c):
            covered += 1
    return {"covered": covered, "total": total}


## Memoizes _clue_coverage_fraction within one refresh cycle. Each of the
## three coverage tabs iterates the FULL clue list and asks every clue for
## its fraction, so without this the same answer is recomputed once per tab
## per repaint. Cleared at the top of _full_propagation_refresh() (the only
## thing that can change the answer) and on _load_match_records().
var _coverage_cache: Dictionary = {}

## Per-value confirmer cliques (see _confirmer_clique). Building one is
## O(records²) in _records_provably_distinct calls, and every Sort:tab row
## and popup asks for the same values over and over while a panel rebuilds,
## so without this the cardinality rule would reintroduce the same
## multi-second stall the coverage code just had. Cleared by
## _clear_deduction_caches().
var _confirmer_clique_cache: Dictionary = {}


## Candidate-star sets, keyed by record index. Split out of the clique
## cache rather than sharing it: the two have genuinely different
## lifetimes — a clique stays valid for a whole refresh, while a candidate
## set is invalidated the moment that record's own colour/pitch/degree
## state changes, which _settle_derived_eliminations() does mid-pass. They
## were briefly in one dict; nothing read a stale entry on today's call
## order, but that was luck, not design.
var _candidate_star_cache: Dictionary = {}

## "<cat>:<star>" -> Array of map stars that descriptor could denote. Same
## lifetime as _candidate_star_cache, which it is built from. One distance
## clue asks for the same two rows on every fixpoint round and again from
## every coverage tab.
var _descriptor_star_cache: Dictionary = {}

## The puzzle's distance_hop disclosures, parsed once per refresh. Depends
## only on the loaded clues, so unlike every cache above it survives
## _clear_deduction_caches() and is dropped by _reset_derived() instead.
var _distance_constraints_cache: Array = []
var _distance_constraints_built: bool = false

## "<cat>:<star>" -> the stars that descriptor can still denote, as proved
## by a settle pass rather than inferred from any record. This is the
## derived layer for VALUES, and it exists because a conclusion about "the
## star that fires 11th" must not depend on whether a UI row for the 11th
## position happens to have been created. Wiped by _reset_derived().
var _derived_descriptor_stars: Dictionary = {}


## Record that descriptor (cat, value) can only be one of `allowed`.
## Returns whether that is NEWS, so the fixpoint can tell it has not settled.
##
## THE place a conclusion about a VALUE gets stored. Every settle pass that
## proves something about a descriptor must come through here, because
## writing only onto records makes the conclusion depend on whether a UI row
## exists — with no row, the loop writing it runs zero times and the fact is
## DISCARDED, not merely undisplayed. That shipped once (distance narrowing,
## 2026-08-14) and was found twice more by auditing for the same shape.
##
## Monotone within a refresh: intersects, never widens. The whole map is
## wiped by _reset_derived(), so nothing outlives its premise.
func _narrow_descriptor_row(cat: int, value: int, allowed: Array) -> bool:
    var key: String = "%d:%d" % [cat, value]
    var prev = _derived_descriptor_stars.get(key, null)
    if prev == null:
        _derived_descriptor_stars[key] = allowed.duplicate()
        return allowed.size() < _host._star_count
    var keep: Dictionary = {}
    for a in allowed:
        keep[int(a)] = true
    var next: Array = []
    for p in (prev as Array):
        if keep.has(int(p)):
            next.append(int(p))
    if next.size() == (prev as Array).size():
        return false
    _derived_descriptor_stars[key] = next
    return true


## Invalidated by any change to _match_records. Called at the start of
## _full_propagation_refresh() (which precedes every full UI rebuild) and
## from _save_puzzle_notes() (which every mutation path already calls), so
## a popup opened without an intervening refresh can't read stale data.
##
## `keep_proven_distinct` is for the FIXPOINT ONLY, and is unsafe anywhere
## else. Inside one refresh the derived layer only ever grows — every pass
## adds facts and `_add_derived_state` refuses to overwrite — so pairwise
## distinctness is MONOTONE there: every route to a `true` verdict (raw
## star_idx/name mismatch, disjoint sequence sets, one side's confirmed
## value in the other's eliminated set) is reached by facts being ADDED,
## and none can be un-reached by adding more. A `true` therefore cannot
## decay into a `false` before the next `_reset_derived()`, so re-deriving
## it once per round is pure waste. A `false` still has to be recomputed —
## that is exactly the verdict more facts can flip.
##
## It must stay false on every other caller, because PLAYER input can be
## WITHDRAWN (un-X a colour, clear a name), and that is not monotone at all
## — a pair proven distinct by a mark that no longer exists must be
## forgotten. That is why this is an opt-in argument rather than the
## default.
##
## Measured on the 57-record save: cold pair verdicts fell from ~5300 per
## refresh to well under half, with `_settle_singleton_sequences` (which
## alone accounted for 2839 of them) the biggest beneficiary.
func _clear_deduction_caches(keep_proven_distinct: bool = false) -> void:
    if keep_proven_distinct:
        var proven: Dictionary = {}
        for k in _distinct_pair_cache:
            if bool(_distinct_pair_cache[k]):
                proven[k] = true
        _clear_deduction_caches_all()
        _distinct_pair_cache = proven
        return
    _clear_deduction_caches_all()


func _clear_deduction_caches_all() -> void:
    _coverage_cache.clear()
    _star_positions_cache.clear()
    _star_values_cache.clear()
    _confirmer_clique_cache.clear()
    _candidate_star_cache.clear()
    _distinct_pair_cache.clear()
    _identity_sig_cache.clear()
    _distinct_profile_cache.clear()
    _listened_stars_cache.clear()
    _listened_stars_built = false
    _pitch_earned_stars_cache.clear()
    _pitch_earned_stars_built = false
    # Axis domains depend only on the loaded puzzle, but clearing them here
    # keeps every derived cache on one lifetime — a domain surviving a
    # constellation switch would be a silent wrong answer.
    _axis_domain_cache.clear()
    _seq_singleton_cache.clear()
    _seq_singleton_built = false
    # Descriptor rows are built from candidate sets, which this just
    # dropped. The parsed constraint LIST is not cleared here — it depends
    # only on the loaded clues, never on player state, and rebuilding it
    # every round of the fixpoint would re-walk every clue's disclosures for
    # nothing. _reset_derived() drops it once per refresh instead.
    _descriptor_star_cache.clear()
    _hint_chain_cache_valid = false


## Convenience wrapper — 0.0 (nothing recorded yet) to 1.0 (every assertion
## this clue makes is already in the player's notes), 0.0 for a clue with
## no usable cells rather than dividing by zero.
## Returns 0.0-1.0, or UNMEASURABLE (-1.0) when the clue has no cell this
## engine can score.
##
## That is the common case, not an edge case: a cell can only express "these
## two descriptors are the same star / different stars", and most Forms'
## content is RELATIONAL — ordering, offsets, adjacency, counts, extremes,
## and Mutual Exclusion's "all have different pitches", the single largest
## bucket. Measured on real puzzles, ~78% of clues have no scoreable cell.
## Sequence-axis relational content does have an encoding (solver_facts:
## ordinal_cmp / ordinal_range / ordinal_offset / ...), but it is neither
## persisted nor consumed here yet, and the non-Sequence axes have no
## encoding at all.
##
## Reporting those as 0.0 would bury them in "Unused" permanently — a worse
## failure than the over-counting this replaced. UNMEASURABLE lets the tabs
## show them as actionable instead of asserting something false about them.
const COVERAGE_UNMEASURABLE: float = -1.0


func _clue_coverage_fraction(cells: Array, terms: Array = [], disclosures: Array = []) -> float:
    var key: String = str(cells) + "|" + str(terms) + "|" + str(disclosures)
    if _coverage_cache.has(key):
        return float(_coverage_cache[key])
    var cov: Dictionary = _clue_coverage(cells, terms, disclosures)
    var total: int = int(cov["total"])
    var result: float = COVERAGE_UNMEASURABLE if total <= 0 \
        else float(cov["covered"]) / float(total)
    _coverage_cache[key] = result
    return result


## DEV EXPLAINER. One plain-text line per scoreable assertion of `clue` that
## the player's board does NOT yet reflect, plus a leading count line.
##
## It asks exactly the questions coverage asks (_disclosure_satisfied,
## _cell_was_stated, _cell_resolved_by_player) and adds no reasoning of its
## own, so "still to input" can never disagree with the Clues tab's own
## coverage. It reads the player's board, never ground truth, for the
## VERDICT; ground truth is used only to NAME the stars a clue already
## refers to, which is a dev convenience and is why the tab is flag-gated.
##
## Returns [] when the clue has nothing scoreable at all, which the caller
## words separately from "everything is recorded".
func explain_unrecorded_assertions(clue: Dictionary) -> Array[String]:
    var lines: Array[String] = []
    var total: int = 0
    var cells: Array = clue.get("cells", [])
    var terms: Array = clue.get("search_terms", [])
    _scoring_clue_terms = terms
    for d in (clue.get("disclosures", []) as Array):
        if not (d is Dictionary):
            continue
        if not SCOREABLE_DISCLOSURE_KINDS.has(str((d as Dictionary).get("kind", ""))):
            continue
        total += 1
        if not _disclosure_satisfied(d):
            lines.append(_describe_disclosure(d))
    _scoring_clue_terms = []
    for cell in cells:
        if not (cell is Dictionary):
            continue
        var c: Dictionary = cell
        var sa: int = int(c.get("star_a", -1))
        var sb: int = int(c.get("star_b", -1))
        if sa < 0 or sa >= _host._star_count or sb < 0 or sb >= _host._star_count:
            continue
        if not _cell_was_stated(c, terms):
            continue
        total += 1
        if not _cell_resolved_by_player(c):
            lines.append("%s %s %s." % [
                _describe_descriptor(int(c.get("cat_a", -1)), sa),
                "is" if bool(c.get("is_true", false)) else "is NOT",
                _describe_descriptor(int(c.get("cat_b", -1)), sb)])
    if total == 0:
        return []
    # A clue can restate one fact through several cells (and a disclosure plus
    # its cells); show each distinct sentence once, but count every assertion.
    var seen: Dictionary = {}
    var unique: Array[String] = []
    for ln in lines:
        if not seen.has(ln):
            seen[ln] = true
            unique.append(ln)
    var head: Array[String] = ["%d of %d assertions still to input." % [lines.size(), total]]
    head.append_array(unique)
    return head


## A descriptor (category + the star it names) the way the player would see
## it in the clue text.
func _describe_descriptor(cat: int, star: int) -> String:
    var t: String = _descriptor_term(cat, star)
    if t == "":
        return "star %d" % star
    var val: String = t.substr(2)
    match cat:
        ConstellationLogicPuzzle.Category.NAME: return val
        ConstellationLogicPuzzle.Category.SEQUENCE: return _seq_noun(int(val))
        ConstellationLogicPuzzle.Category.COLOR: return "the %s star" % val.to_lower()
        ConstellationLogicPuzzle.Category.PITCH: return "the star with pitch %s" % val
    return val


## Disclosures name bare map stars (a dev shorthand): label by Name.
func _describe_star(star: int) -> String:
    if star >= 0 and star < _host._star_names.size():
        return str(_host._star_names[star])
    return "star %d" % star


func _describe_star_list(stars: Array) -> String:
    var parts: Array[String] = []
    for s in stars:
        parts.append(_describe_star(int(s)))
    return ", ".join(parts)


func _describe_disclosure(f: Dictionary) -> String:
    var kind: String = str(f.get("kind", ""))
    match kind:
        "ordinal_exact":
            return "%s %s %s." % [_describe_star(int(f.get("s", -1))), _seq_verb(), _seq_ord(int(f.get("r", -1)) + 1)]
        "ordinal_neg":
            return "%s does NOT %s %s." % [_describe_star(int(f.get("s", -1))), _seq_verb_base(), _seq_ord(int(f.get("r", -1)) + 1)]
        "ordinal_cmp":
            var a: String = _describe_star(int(f.get("a", -1)))
            var b: String = _describe_star(int(f.get("b", -1)))
            return "%s %s %s %s." % [a, _seq_rel_verb_for(int(f.get("a", -1))), "after" if bool(f.get("a_gt_b", false)) else "before", b]
        "ordinal_chain":
            return "%s %s before %s, which %s before %s." % [
                _describe_star(int(f.get("a", -1))), _seq_rel_verb_for(int(f.get("a", -1))), _describe_star(int(f.get("mid", -1))),
                _seq_rel_verb_for(int(f.get("mid", -1))), _describe_star(int(f.get("b", -1)))]
        "ordinal_adjacent", "ordinal_offset":
            return "%s %s %d after %s." % [
                _describe_star(int(f.get("a", -1))), _seq_rel_verb_for(int(f.get("a", -1))), int(f.get("offset", 1)), _describe_star(int(f.get("b", -1)))]
        "ordinal_range":
            if _seq_repeats():
                return "%s %s between note %d and note %d." % [
                    _describe_star(int(f.get("s", -1))), _seq_rel_verb_for(int(f.get("s", -1))),
                    _first_tick_for_rank(int(f.get("lo", 0)) + 1), _first_tick_for_rank(int(f.get("hi", 0)) + 1)]
            return "%s %s between the %d and %d positions." % [
                _describe_star(int(f.get("s", -1))), _seq_verb(), int(f.get("lo", 0)) + 1, int(f.get("hi", 0)) + 1]
        "ordinal_pair_set":
            return "The firings of %s and %s stand in the relation the clue describes." % [
                _describe_star(int(f.get("a", -1))), _describe_star(int(f.get("b", -1)))]
        "value_in_set":
            return "%s %s." % [_describe_star(int(f.get("s", -1))), _firing_set_phrase(f.get("allowed", []))]
        "ordinal_either_or":
            return "%s %s %s or %s." % [_describe_star(int(f.get("s", -1))), _seq_verb(),
                _seq_ord(int(f.get("r1", -1)) + 1), _seq_ord(int(f.get("r2", -1)) + 1)]
        "ordinal_extreme":
            return "%s %s %s of: %s." % [_describe_star(int(f.get("s", -1))), _seq_rel_verb_for(int(f.get("s", -1))),
                "before all" if bool(f.get("want_lowest", false)) else "after all",
                _describe_star_list(f.get("neighbors", []))]
        "ordinal_count_before":
            return "Exactly %d of [%s] %s before %s." % [int(f.get("k", -1)),
                _describe_star_list(f.get("neighbors", [])), _seq_rel_verb_base(), _describe_star(int(f.get("s", -1)))]
        "values_all_different":
            return "These all differ in %s: %s." % [_category_word(int(f.get("cat", -1))), _describe_star_list(f.get("stars", []))]
        "values_same":
            return "%s and %s share the same %s." % [_describe_star(int(f.get("a", -1))),
                _describe_star(int(f.get("b", -1))), _category_word(int(f.get("cat", -1)))]
        "descriptor_either_or":
            return "%s is either %s or %s." % [
                _describe_descriptor(int(f.get("cat_a", -1)), int(f.get("star_a", -1))),
                _describe_descriptor(int(f.get("cat_b", -1)), int(f.get("s1", -1))),
                _describe_descriptor(int(f.get("cat_b", -1)), int(f.get("s2", -1)))]
        "descriptor_not_in_group":
            var gcat: int = int(f.get("group_cat", -1))
            var gkey: int = int(f.get("group_key", -1))
            var grp: String = "group %d" % gkey
            if gcat == ConstellationLogicPuzzle.Category.COLOR and gkey >= 0 and gkey < _host.COLOR_NAME_LABELS.size():
                grp = str(_host.COLOR_NAME_LABELS[gkey]).to_lower()
            elif gcat == ConstellationLogicPuzzle.Category.PITCH and gkey >= 0 and gkey < _host._pitch_freqs.size():
                grp = "pitch " + ConstellationLogicPuzzle.note_name_for_freq(float(_host._pitch_freqs[gkey]))
            return "%s is NOT %s." % [_describe_descriptor(int(f.get("cat", -1)), int(f.get("star", -1))), grp]
        "distance_hop":
            return "%s is %s %d hop(s) from %s." % [
                _describe_descriptor(int(f.get("ref_cat", -1)), int(f.get("ref", -1))),
                "NOT" if bool(f.get("negated", false)) else "exactly",
                int(f.get("hops", 1)),
                _describe_descriptor(int(f.get("target_cat", -1)), int(f.get("target", -1)))]
        "firing_position":
            return "The notes %s fires on are as the clue describes." % _describe_star(int(f.get("s", -1)))
        "firing_relation":
            return "The notes %s and %s fire on stand in the relation the clue describes." % [
                _describe_star(int(f.get("a", -1))), _describe_star(int(f.get("b", -1)))]
        "repeat_count_range":
            var rlo: int = int(f.get("lo", 0))
            var rhi: int = int(f.get("hi", 0))
            var span: String = "exactly %d" % rlo if rlo == rhi \
                else ("at least %d" % rlo if rhi >= ConstellationLogicPuzzle.REPEAT_COUNT_UNBOUNDED \
                else ("at most %d" % rhi if rlo <= 0 else "between %d and %d" % [rlo, rhi]))
            return "%s %s %s time(s)." % [_describe_star(int(f.get("star", -1))),
                "does NOT repeat" if bool(f.get("negated", false)) else "repeats", span]
    return kind


func _category_word(cat: int) -> String:
    match cat:
        ConstellationLogicPuzzle.Category.COLOR: return "colour"
        ConstellationLogicPuzzle.Category.PITCH: return "pitch"
        ConstellationLogicPuzzle.Category.SEQUENCE: return "position"
        ConstellationLogicPuzzle.Category.NAME: return "name"
        ConstellationLogicPuzzle.Category.REPEAT: return "repeat count"
    return "value"


## HINT SUPPORT (tiers 1 and 2 of the ZebraTutor hint ladder). Indices, into
## `clues`, of the clues that STILL HAVE SOMETHING TO GIVE: at least one of
## their scoreable assertions is not yet reflected on the player's board.
##
## "Something to give" is deliberately the SAME question the coverage
## machinery already answers -- _clue_coverage_fraction < 1.0 -- rather than
## a second definition that could drift from it. It reads the player's own
## board through _disclosure_satisfied / _cell_resolved_by_player, never
## ground truth, so a hint pointing at a clue cannot leak anything the
## clue's own sentence doesn't already say. A clue with nothing measurable
## (COVERAGE_UNMEASURABLE) is skipped: pointing at a sentence that asserts
## nothing scoreable would be a hint that gives nothing.
##
## KNOWN LIMIT, stated so nobody over-reads it: "not yet on your board" is
## not "you can act on it right now". A clue can be unmet yet need another
## fact first. This tier promises only that the clue's content is new to the
## board, not that it is the next best move -- ranking by actionability is
## the explanation engine's job (later phase), not this predicate's.
##
## `clues` is the caller's list of dicts carrying cells / search_terms /
## disclosures (constellation_puzzle_widgets._all_final_clues_for_tabs()),
## so this never reaches into the overlay's own clue cache.
func clue_indices_with_something_to_give(clues: Array) -> Array[int]:
    var out: Array[int] = []
    for i in clues.size():
        var c = clues[i]
        if not (c is Dictionary):
            continue
        var cells: Array = c["cells"] if (c as Dictionary).get("cells") is Array else []
        var terms: Array = c["search_terms"] if (c as Dictionary).get("search_terms") is Array else []
        var discs: Array = c["disclosures"] if (c as Dictionary).get("disclosures") is Array else []
        var frac: float = _clue_coverage_fraction(cells, terms, discs)
        if frac != COVERAGE_UNMEASURABLE and frac < 1.0:
            out.append(i)
    return out


const _NextStepFinder = preload("res://constellation_next_step_finder.gd")

## Solver instance used ONLY for constraint propagation (never backtracking).
## Built lazily and rebuilt if the star count changes.
var _hint_solver = null


func _hint_solver_for(star_count: int):
    if _hint_solver == null or int(_hint_solver.star_count) != star_count:
        _hint_solver = ConstellationLogicPuzzle.new()
        _hint_solver.star_count = star_count
        # This solver exists ONLY for hint propagation (step_for_facts calls its
        # _propagate_only) -- never generation, never a uniqueness proof -- so it
        # is safe to cap _resolve_locked_group's recursion the same way the MUS
        # explainer does (c715963: budget 10 gave IDENTICAL output to unlimited
        # on that measurement). Needed here for real: hint_full_chain calls
        # hint_next_steps in a loop, and without this a single tier-5 press
        # measured 2.5-4.9s on a blank 17-18 star board (2026-09-27). Under-
        # closing is the safe direction -- it can only make a step MISS an
        # elimination it would otherwise have found, never invent a wrong one.
        _hint_solver.resolve_call_budget = 10
    return _hint_solver


## The player's Sequence board as the solver's own grid: grid[star][rank] is
## true while the player's notes still allow that star at that rank. UNKNOWN
## (no record identifies the star) is all-true -- never "no positions" -- the
## same contract _player_positions_for_star documents. Reads the player's
## records only, never ground truth.
func _player_sequence_grid() -> Array:
    var n: int = _host._star_count
    var grid: Array = []
    for s in n:
        var row: Array = []
        row.resize(n)
        var known: Array = _player_positions_for_star(s)
        for r in n:
            row[r] = known.is_empty() or known.has(r + 1)
        grid.append(row)
    return grid


## Descriptor categories the CLUE ITSELF used for `star` -- the only ways a
## hint may name a star. _describe_descriptor(SEQUENCE, star) would read
## "the star that fires 3rd" from ground truth, which is a spoiler unless the
## clue already said it, so a star with no descriptor in the clue's own
## search_terms is simply not nameable. Name first: it is the least
## ambiguous thing to point at.
func _clue_descriptor_for_star(clue: Dictionary, star: int) -> String:
    var terms: Array = clue["search_terms"] if clue.get("search_terms") is Array else []
    # SEQUENCE is deliberately NOT a way to name a star here. These steps are
    # about which POSITIONS a star can hold, so "the star that fires 9th
    # cannot fire 3rd" or "... must fire 9th" says nothing: it describes the
    # star by the very thing being deduced. Measured 2026-09-26: 17 of 28
    # Sequence steps from Equality/Mutex clues were that tautology. A star the
    # clue names only by its position therefore yields no step.
    for cat in [ConstellationLogicPuzzle.Category.NAME, ConstellationLogicPuzzle.Category.COLOR,
            ConstellationLogicPuzzle.Category.PITCH]:
        var t: String = _descriptor_term(int(cat), star)
        if t != "" and terms.has(t):
            return _describe_descriptor(int(cat), star)
    return ""


## Sequence-axis steps for hint_next_steps, given the player's own board (or the
## default one). `grid` is a parameter for the same reason as the other three
## _hint_*_steps functions: a test can hand in a truth-built board, and
## hint_full_chain hands in a WORKING COPY it narrows step by step.
##
## A step is: this clue, propagated on top of the board, rules out at least one
## rank for a star the clue itself names. Unlike clue_indices_with_something_to_give
## this IS actionability -- see the finder's header.
##
## Each entry: {"clue_index", "star", "descriptor", "eliminated_ranks" (0-based),
## "resolved_rank" (0-based, or -1)}. Only stars nameable from the clue's own
## text are reported, so a hint cannot name anything the clue does not.
func _hint_sequence_steps(clues: Array, solver, grid: Array = []) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var board: Array = grid if not grid.is_empty() else _player_sequence_grid()
    for ci in clue_indices_with_something_to_give(clues):
        var clue: Dictionary = clues[ci]
        var facts: Array = []
        for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
            if f is Dictionary and not ConstellationLogicPuzzle.VALUE_FACT_KINDS.has(str((f as Dictionary).get("kind", ""))):
                facts.append(f)
        var step: Dictionary = _NextStepFinder.step_for_facts(solver, board, facts)
        if not bool(step["consistent"]) or (step["eliminated"] as Array).is_empty():
            continue
        var by_star: Dictionary = {}
        for cell in step["eliminated"]:
            var s: int = int(cell[0])
            if not by_star.has(s):
                by_star[s] = []
            (by_star[s] as Array).append(int(cell[1]))
        var resolved: Dictionary = {}
        for cell2 in step["resolved"]:
            resolved[int(cell2[0])] = int(cell2[1])
        for s2 in by_star:
            var label: String = _clue_descriptor_for_star(clue, int(s2))
            if label == "":
                continue
            out.append({
                "axis": "sequence",
                "clue_index": int(ci),
                "star": int(s2),
                "descriptor": label,
                "eliminated_ranks": by_star[s2],
                "resolved_rank": int(resolved.get(int(s2), -1)),
                "resolved": int(resolved.get(int(s2), -1)) >= 0,
                "gain": (by_star[s2] as Array).size(),
            })
    return out


## True when the Hint tab has nothing sound to offer on this puzzle. It was
## true on every repeating melody for a few hours on 2026-10-12, between hiding
## the first notes and re-basing the finder on who fires on each note
## (_hint_owner_steps); nothing makes it true now. Kept so the tab's own
## "switched off" branch has one switch to read if a case turns up.
func hints_unavailable() -> bool:
    return false


## HINT SUPPORT (tiers 3 and 4, and the per-iteration search inside tier 5's
## hint_full_chain). Every clue that gives the player a step RIGHT NOW, best
## first, across all four axes.
##
## `boards` is a parameter so hint_full_chain can hand in a WORKING COPY it
## narrows step by step, and so a test can hand in a truth-built board; omitted
## keys fall back to the real board, exactly the pre-tier-5 behaviour. Keys:
## "seq" (star x rank), "name" (name x star), "rank" (position x star).
##
## Ranked: a step that pins something to one position first, then the one that
## rules out the most, then clue order, then axis.
func hint_next_steps(clues: Array, boards: Dictionary = {}) -> Array[Dictionary]:
    var solver = _hint_solver_for(_host._star_count)
    # FIRST NOTES HIDDEN (2026-10-12): the Sequence, position and joint steps
    # below all reason about firing-order positions, which that board does not
    # keep and the player is not told. There the steps are about who fires on
    # each note (_hint_owner_steps), plus the Name steps, which read groups and
    # simply find nothing in a position they cannot resolve.
    if _notes_hidden():
        var hidden_out: Array[Dictionary] = []
        hidden_out.append_array(_hint_owner_steps(clues, solver))
        hidden_out.append_array(_hint_name_steps(clues, solver,
            boards["name"] if boards.has("name") else _player_name_grid()))
        # Several clues together only once no single clue gives anything: a
        # one-clue step is the easier one to follow, and this search costs more.
        if hidden_out.is_empty():
            hidden_out.append_array(_hint_owner_multi_steps(clues, solver))
        # And the whole melody at once only after that: the widest search.
        # OFF by default (owner_global_hints_enabled): measured 2026-10-12 on
        # three stalled boards, it gave up on all three within the budget a
        # hint press can afford, so in the game it would only add a pause.
        if hidden_out.is_empty() and owner_global_hints_enabled:
            hidden_out.append_array(_hint_owner_global_steps(clues, solver))
        hidden_out.sort_custom(func(a, b):
            if bool(a["resolved"]) != bool(b["resolved"]):
                return bool(a["resolved"])
            if int(a["gain"]) != int(b["gain"]):
                return int(a["gain"]) > int(b["gain"])
            if int(a["clue_index"]) != int(b["clue_index"]):
                return int(a["clue_index"]) < int(b["clue_index"])
            return str(a["axis"]) < str(b["axis"]))
        return hidden_out
    var seq_grid: Array = boards["seq"] if boards.has("seq") else _player_sequence_grid()
    var name_grid: Array = boards["name"] if boards.has("name") else _player_name_grid()
    var rank_grid: Array = boards["rank"] if boards.has("rank") else _player_rank_grid()
    var tick_board: Dictionary = boards["ticks"] if boards.has("ticks") else _player_tick_board()
    var out: Array[Dictionary] = []
    out.append_array(_hint_note_steps(clues, solver, seq_grid, tick_board))
    out.append_array(_hint_sequence_steps(clues, solver, seq_grid))
    out.append_array(_hint_name_steps(clues, solver, name_grid))
    out.append_array(_hint_position_steps(clues, solver, rank_grid))
    out.append_array(_hint_joint_steps(clues, solver, {"name": name_grid, "rank": rank_grid}))
    out.sort_custom(func(a, b):
        if bool(a["resolved"]) != bool(b["resolved"]):
            return bool(a["resolved"])
        if int(a["gain"]) != int(b["gain"]):
            return int(a["gain"]) > int(b["gain"])
        if int(a["clue_index"]) != int(b["clue_index"]):
            return int(a["clue_index"]) < int(b["clue_index"])
        return str(a["axis"]) < str(b["axis"]))
    return out


## Marks one hint_next_steps() entry's eliminated cells false on a WORKING COPY
## of the boards (never the real player records). Sound because the entry's own
## eliminations are exactly the cells the finder already proved impossible;
## nothing here does new reasoning, it only records what tier 5's loop already
## found so the NEXT iteration can build on it.
func _apply_step_to_boards(step: Dictionary, boards: Dictionary) -> void:
    match str(step["axis"]):
        "sequence":
            var row: Array = boards["seq"][int(step["star"])]
            for r in (step["eliminated_ranks"] as Array):
                row[int(r)] = false
        "name":
            var row2: Array = boards["name"][int(step["star"])]
            for s in (step["eliminated_stars"] as Array):
                row2[int(s)] = false
        "position":
            var row3: Array = boards["rank"][int(step["star"])]
            for s2 in (step["eliminated_stars"] as Array):
                row3[int(s2)] = false
        "note":
            var rank: int = int(step["rank"])
            for t in (step["must_ticks"] as Array):
                boards["ticks"][int(t)] = [rank]
            for t2 in (step["cannot_ticks"] as Array):
                (boards["ticks"][int(t2)] as Array).erase(rank)


# ── REPEAT-NOTE STEPS (2026-10-11) ───────────────────────────────────────
# "Does this one clue, on top of the player's board, settle whose a repeat
# note is?" The unit is the CELL (repeat note x position): the board holds, per
# repeat note, the positions it could still be; a step turns some of those
# cells off, or leaves a note with one.
#
# A clue only yields a step for a star whose POSITION the player already has
# (the note buttons are positions, so until then there is nothing to click).
# For that star the notes it could still own are the repeat notes after its
# first note that the board has not ruled out for it. Every way of choosing
# among them that the clue's own repeat facts allow is listed; a note in ALL of
# them must be the star's, a note in NONE cannot be. One clue at a time, no
# search beyond that list, so the player can follow it. No ground truth: the
# star index in a fact is only the handle the fact names its star by, exactly
# as in the Sequence steps.

## The player's board for the repeat notes: note -> positions (1-based) it could
## still be. A note nobody has opened could be any star heard before it.
func _player_tick_board() -> Dictionary:
    var out: Dictionary = {}
    if not _seq_repeats():
        return out
    for tick in range(1, _melody_tick_count() + 1):
        if _tick_is_first_fire(tick):
            continue
        var latest: int = _stars_begun_by_tick(tick - 1)
        var idx: int = _find_match_record_by_melody_tick(tick)
        var cands: Array = []
        if idx >= 0:
            for c in _effective_seq_candidates(idx):
                if int(c) <= latest:
                    cands.append(int(c))
        else:
            for p in range(1, latest + 1):
                cands.append(p)
        out[tick] = cands
    return out


## The one position a star's row of the Sequence grid allows (1-based), or 0.
func _single_rank_in_grid(seq_grid: Array, star: int) -> int:
    if star < 0 or star >= seq_grid.size():
        return 0
    var found: int = 0
    var row: Array = seq_grid[star]
    for r in row.size():
        if bool(row[r]):
            if found > 0:
                return 0
            found = r + 1
    return found


## How a note step may name its star: by a Name/Colour/Pitch descriptor the clue
## itself states, or failing that by the first note the clue states for it.
## (The first note is not a spoiler here as it is in a Sequence step: the star's
## position is already on the board, and what is being worked out is a
## different thing, its repeat notes.)
func _note_step_descriptor(clue: Dictionary, star: int, rank: int) -> String:
    var label: String = _clue_descriptor_for_star(clue, star)
    if label != "":
        return label
    var terms: Array = clue["search_terms"] if clue.get("search_terms") is Array else []
    if terms.has("S:%d" % _first_tick_for_rank(rank)):
        return _seq_noun(rank)
    return ""


## Most notes a star may have open for the step search (2^n choices are listed).
const NOTE_STEP_MAX_OPEN: int = 12
## Most pairs of choices tried for a clue relating two stars.
const NOTE_STEP_PAIR_BUDGET: int = 20000


## {"first", "placed": [notes], "open": [notes]} for a position on a tick board.
func _note_frame(rank: int, ticks: Dictionary) -> Dictionary:
    var first: int = _first_tick_for_rank(rank)
    var placed: Array = []
    var open: Array = []
    var keys: Array = ticks.keys()
    keys.sort()
    for t in keys:
        if int(t) <= first:
            continue
        var cands: Array = ticks[t]
        if not cands.has(rank):
            continue
        if cands.size() == 1:
            placed.append(int(t))
        else:
            open.append(int(t))
    return {"first": first, "placed": placed, "open": open}


func _note_set_for_mask(frame: Dictionary, mask: int) -> Array:
    var out: Array = [int(frame["first"])]
    out.append_array(frame["placed"])
    var open: Array = frame["open"]
    for i in open.size():
        if mask & (1 << i):
            out.append(int(open[i]))
    out.sort()
    return out


## THE REVERSE LINK (2026-10-11): what the player's OWN Repeats marks say about
## the star at a position -- {"exact": count or -1, "not": {count: true}}. Read
## from the raw marks (and a Sort:Repeats slot) of every record known to sit on
## that position, never from the derived layer: a hint must rest on what the
## player entered, and the derived Repeats bounds come from the notes themselves.
func _player_repeat_marks_for_rank(rank: int) -> Dictionary:
    var out: Dictionary = {"exact": -1, "not": {}}
    for entry in _seq_singleton_owners():
        if int((entry as Array)[1]) != rank:
            continue
        var r: Dictionary = _match_records[int((entry as Array)[0])]
        # A count Listen has given is as much the player's as one they marked.
        var given: int = _repeat_given_for_record(int((entry as Array)[0]))
        if given >= 0:
            out["exact"] = given
        var label: String = str(r.get("repeat_slot_label", ""))
        if label != "":
            out["exact"] = int(label.get_slice(" ", 0).substr(1))
        var states: Dictionary = r.get("repeat_states", {})
        for k in states:
            if int(states[k]) == 1:
                out["exact"] = int(k)
            elif int(states[k]) == 2:
                (out["not"] as Dictionary)[int(k)] = true
    return out


func _repeat_marks_say_something(marks: Dictionary) -> bool:
    return int(marks.get("exact", -1)) >= 0 or not (marks.get("not", {}) as Dictionary).is_empty()


func _note_unary_holds(solver, notes: Array, facts: Array, marks: Dictionary = {}) -> bool:
    if not marks.is_empty():
        var repeats: int = notes.size() - 1
        if int(marks.get("exact", -1)) >= 0 and repeats != int(marks["exact"]):
            return false
        if (marks.get("not", {}) as Dictionary).has(repeats):
            return false
    for f in facts:
        var fd: Dictionary = f
        if str(fd["kind"]) == "firing_position":
            var v: int = solver._firing_value(notes, fd["sel"])
            if v < 0 or v < int(fd["lo"]) or v > int(fd["hi"]):
                return false
        else:
            var count: int = notes.size() - 1
            if (count >= int(fd["lo"]) and count <= int(fd["hi"])) == bool(fd.get("negated", false)):
                return false
    return true


## Every choice of a star's open notes (as bit masks over frame["open"]) that
## its own facts in this clue allow.
func _note_options(solver, frame: Dictionary, facts: Array) -> Array:
    var out: Array = []
    for mask in (1 << (frame["open"] as Array).size()):
        if _note_unary_holds(solver, _note_set_for_mask(frame, mask), facts, frame.get("marks", {})):
            out.append(mask)
    return out


func _note_pair_holds(solver, fd: Dictionary, notes_of: Dictionary) -> bool:
    var na: Array = notes_of[int(fd["a"])]
    var nb: Array = notes_of[int(fd["b"])]
    if str(fd["kind"]) == "values_same":
        return na.size() == nb.size()
    return solver._firing_rel_holds(solver._firing_pick_notes(na, fd["pick_a"]),
        solver._firing_pick_notes(nb, fd["pick_b"]), fd["spec"])


## Turns "which masks survive" into the notes that are in all of them / none.
func _note_verdict(frame: Dictionary, all_and: int, all_or: int) -> Dictionary:
    var must: Array = []
    var cannot: Array = []
    var open: Array = frame["open"]
    for i in open.size():
        if all_and & (1 << i):
            must.append(int(open[i]))
        elif not (all_or & (1 << i)):
            cannot.append(int(open[i]))
    return {"must": must, "cannot": cannot}


func _hint_note_steps(clues: Array, solver, seq_grid: Array, ticks: Dictionary) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if ticks.is_empty():
        return out
    for ci in clue_indices_with_something_to_give(clues):
        var clue: Dictionary = clues[ci]
        var unary: Dictionary = {}   # star -> facts about that star alone
        var binary: Array = []
        var stars: Dictionary = {}
        for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
            if not (f is Dictionary):
                continue
            var fd: Dictionary = f
            var kind: String = str(fd.get("kind", ""))
            var one: int = -1
            if kind == "firing_position":
                one = int(fd.get("s", -1))
            elif kind == "repeat_count_range":
                one = int(fd.get("star", -1))
            elif kind == "firing_relation" or (kind == "values_same" \
                    and int(fd.get("cat", -1)) == ConstellationLogicPuzzle.Category.REPEAT):
                binary.append(fd)
                stars[int(fd.get("a", -1))] = true
                stars[int(fd.get("b", -1))] = true
            if one >= 0:
                if not unary.has(one):
                    unary[one] = []
                (unary[one] as Array).append(fd)
                stars[one] = true
        if stars.is_empty():
            continue
        var frames: Dictionary = {}   # star -> frame, only where the position is known
        for s in stars:
            var rank: int = _single_rank_in_grid(seq_grid, int(s))
            if rank > 0:
                var fr: Dictionary = _note_frame(rank, ticks)
                if (fr["open"] as Array).size() <= NOTE_STEP_MAX_OPEN:
                    fr["rank"] = rank
                    # The player's own Repeats marks narrow the choices too.
                    fr["marks"] = _player_repeat_marks_for_rank(rank)
                    frames[int(s)] = fr
        var verdicts: Dictionary = {}   # star -> {"must", "cannot"}
        if not binary.is_empty() and stars.size() == 2 and frames.size() == 2:
            # Two stars related by the clue: every allowed pair of choices.
            var pair: Array = frames.keys()
            var sa: int = int(pair[0])
            var sb: int = int(pair[1])
            var opts_a: Array = _note_options(solver, frames[sa], unary.get(sa, []))
            var opts_b: Array = _note_options(solver, frames[sb], unary.get(sb, []))
            if opts_a.size() * opts_b.size() > NOTE_STEP_PAIR_BUDGET:
                continue
            var and_a: int = -1
            var or_a: int = 0
            var and_b: int = -1
            var or_b: int = 0
            var any: bool = false
            for ma in opts_a:
                var na: Array = _note_set_for_mask(frames[sa], int(ma))
                for mb in opts_b:
                    var nb: Array = _note_set_for_mask(frames[sb], int(mb))
                    var clash: bool = false
                    for t in nb:
                        if na.has(t):
                            clash = true   # one note cannot be two stars
                            break
                    if clash:
                        continue
                    var notes_of: Dictionary = {sa: na, sb: nb}
                    var good: bool = true
                    for bf in binary:
                        if not _note_pair_holds(solver, bf, notes_of):
                            good = false
                            break
                    if not good:
                        continue
                    any = true
                    and_a &= int(ma)
                    or_a |= int(ma)
                    and_b &= int(mb)
                    or_b |= int(mb)
            if not any:
                continue   # the board contradicts the clue: not a hint
            verdicts[sa] = _note_verdict(frames[sa], and_a, or_a)
            verdicts[sb] = _note_verdict(frames[sb], and_b, or_b)
        else:
            # Otherwise each star on its own facts (a relation the clue also
            # states is simply not used: weaker, never wrong).
            for s2 in unary:
                if not frames.has(int(s2)):
                    continue
                var opts: Array = _note_options(solver, frames[int(s2)], unary[s2])
                if opts.is_empty():
                    continue
                var all_and: int = -1
                var all_or: int = 0
                for m in opts:
                    all_and &= int(m)
                    all_or |= int(m)
                verdicts[int(s2)] = _note_verdict(frames[int(s2)], all_and, all_or)
        for s3 in verdicts:
            var v: Dictionary = verdicts[s3]
            if (v["must"] as Array).is_empty() and (v["cannot"] as Array).is_empty():
                continue
            var rank3: int = int(frames[s3]["rank"])
            var label: String = _note_step_descriptor(clue, int(s3), rank3)
            if label == "":
                continue
            out.append({
                "axis": "note",
                "clue_index": int(ci),
                "star": int(s3),
                "rank": rank3,
                "descriptor": label,
                "must_ticks": v["must"],
                "cannot_ticks": v["cannot"],
                "resolved": not (v["must"] as Array).is_empty(),
                "gain": (v["must"] as Array).size() + (v["cannot"] as Array).size(),
            })
    # FROM THE PLAYER'S OWN REPEATS MARKS ALONE, no clue: a star marked as
    # repeating twice with exactly two notes still open to it must own both; one
    # marked as never repeating owns none. clue_index -1 says there is no clue
    # to show. "star" is a handle for re-finding the step, not a map star: the
    # position is all this reasons about.
    for rank2 in range(1, _host._star_count + 1):
        var marks: Dictionary = _player_repeat_marks_for_rank(rank2)
        if not _repeat_marks_say_something(marks):
            continue
        var fr2: Dictionary = _note_frame(rank2, ticks)
        if (fr2["open"] as Array).is_empty() or (fr2["open"] as Array).size() > NOTE_STEP_MAX_OPEN:
            continue
        fr2["marks"] = marks
        var opts2: Array = _note_options(solver, fr2, [])
        if opts2.is_empty():
            continue   # the marks contradict the notes placed: not a hint
        var and2: int = -1
        var or2: int = 0
        for m2 in opts2:
            and2 &= int(m2)
            or2 |= int(m2)
        var v2: Dictionary = _note_verdict(fr2, and2, or2)
        if (v2["must"] as Array).is_empty() and (v2["cannot"] as Array).is_empty():
            continue
        var who: String = _known_name_for_seq_position(rank2)
        out.append({
            "axis": "note",
            "clue_index": -1,
            "from_marks": true,
            "star": -rank2,
            "rank": rank2,
            "descriptor": who if who != "" else _seq_noun(rank2),
            "must_ticks": v2["must"],
            "cannot_ticks": v2["cannot"],
            "resolved": not (v2["must"] as Array).is_empty(),
            "gain": (v2["must"] as Array).size() + (v2["cannot"] as Array).size(),
        })
    return out


# ── NOTE-OWNER STEPS (2026-10-12): hints with the first notes hidden ─────
# On a repeating melody the board keeps no firing-order position; Sequence is
# which notes each row's star fires on. So a step is about CELLS of (row,
# note): "with what you know, Helios must fire on note 6" / "cannot fire on
# notes 1 and 2". One clue at a time, on top of the player's own rows.
#
# THE ROW a step is about is the one the CLUE ITSELF lets the player find:
# the Name row if the clue names the star, the map star's own row if the clue
# picks it out by a colour or (Listened) pitch only one star has, else the row
# of the note the clue names it by ("the star that fires 3rd note" is the
# entry for note 3). A star the clue gives no such handle for yields no step.
# What that row already says is read through _repeat_note_state_for_record,
# the same reading the row's own buttons show.
#
# WHAT A FACT MEANS is the sentence's meaning with no note marked as anyone's
# first -- the table above ConstellationLogicPuzzle._solve_note_owners:
# a Sequence label is "fires on note T", an order fact compares the earliest
# note each star has.
#
# HOW A STEP IS FOUND. If the row's star is known to fire n times (Listen, or
# a confirmed Repeats mark), every way of completing its notes to n that the
# clue's facts allow is listed; a note in ALL of them must be the star's, a
# note in NONE cannot be. Two stars a clue relates are listed together. With
# the count unknown only what a fact says outright is used. Weaker than a full
# search, never wrong: the real melody is always one of the listed ways.

## Most ways of completing one row's notes that are listed for a step.
const OWNER_STEP_MAX_SETS: int = 3000
## Most pairs of ways tried for a clue relating two stars.
const OWNER_STEP_PAIR_BUDGET: int = 40000


## The note a Sequence label prints for a star / for a 0-based rank. A number
## in the clue's own text ("the star that fires 3rd note"), read off the table
## only to translate the fact's rank back into that number.
func _label_note_for_rank0(rank0: int) -> int:
    return _first_tick_for_rank(rank0 + 1)


func _label_note_for_star(star: int) -> int:
    if star < 0 or star >= _host._sequence_rank_solution.size():
        return 0
    return _label_note_for_rank0(int(_host._sequence_rank_solution[star]))


## A clue's note label, worded as the generator prints it
## (ConstellationLogicPuzzle._seq_tick_phrase): "the star that first fires on
## note 5" for a star that fires more than once, else "the star that fires 15th
## note".
func _label_phrase_for_star(star: int, t_label: int) -> String:
    if star >= 0 and star < _host._repeat_count.size() and int(_host._repeat_count[star]) > 0:
        return "the star that first fires on note %d" % t_label
    return "the star that fires %s" % ConstellationLogicPuzzle._ordinal(t_label)


## Does exactly one map star have this star's colour / (Listened) pitch? Only
## then does "the red star" point the player at one row.
func _star_alone_in_group(star: int, cat: int) -> bool:
    var mine: int = _raw_group_key(cat, star)
    if mine < 0:
        return false
    for s in _host._star_count:
        if s != star and _raw_group_key(cat, s) == mine:
            return false
    return true


## The NOTE's column: the map stars whose own row says they do not fire on
## `tick` ({star: true}). Asked of the note, in one pass over the rows -- the
## matrix-up form of "could this star fire there". `skip` is a row to leave out
## (the one asking). Rows the Star Map made for itself are read on purpose:
## where such a row sits is its widget's place, and a "not this note" mark or a
## full set of notes on it is the player's own. No name or pitch is read off
## it; its firing count is, but only through _repeat_given_for_record, which
## answers nothing until the player has Listened to that star.
func _map_stars_ruling_out_note(tick: int, skip: int = -1) -> Dictionary:
    var out: Dictionary = {}
    for b in _match_records.size():
        if b == skip:
            continue
        var at_star: int = _effective_star_idx(b)
        if at_star >= 0 and _repeat_note_state_for_record(b, tick) >= 2:
            out[at_star] = true
    return out


## The row for a star and what it says: {"label", "record", "held": [notes],
## "ruled": [notes], "open": [notes], "count": times it fires or -1}. `clue`
## null means "whichever row denotes the star" (used for scoring, where there
## is no one clue); with a clue, only a handle that clue states. {} if none.
func _owner_frame(star: int, clue = null) -> Dictionary:
    if star < 0 or star >= _host._star_count:
        return {}
    var terms: Array = []
    if clue != null and (clue as Dictionary).get("search_terms") is Array:
        terms = (clue as Dictionary)["search_terms"]
    var label: String = ""
    var rec: int = -1
    var own_note: int = 0
    var visible_star: bool = false
    var name_term: String = _descriptor_term(ConstellationLogicPuzzle.Category.NAME, star)
    var color_term: String = _descriptor_term(ConstellationLogicPuzzle.Category.COLOR, star)
    var pitch_term: String = _descriptor_term(ConstellationLogicPuzzle.Category.PITCH, star)
    var t_label: int = _label_note_for_star(star)
    if name_term != "" and (clue == null or terms.has(name_term)) \
            and (clue != null or _find_match_record_by_name(str(_host._star_names[star])) >= 0):
        label = str(_host._star_names[star])
        rec = _find_match_record_by_name(label)
    elif color_term != "" and (clue == null or terms.has(color_term)) \
            and _star_alone_in_group(star, ConstellationLogicPuzzle.Category.COLOR) \
            and (clue != null or _find_match_record_by_star_idx(star) >= 0):
        label = _describe_descriptor(ConstellationLogicPuzzle.Category.COLOR, star)
        rec = _find_match_record_by_star_idx(star)
        visible_star = true
    elif pitch_term != "" and (clue == null or terms.has(pitch_term)) and _player_knows_star_pitch(star) \
            and _star_alone_in_group(star, ConstellationLogicPuzzle.Category.PITCH) \
            and (clue != null or _find_match_record_by_star_idx(star) >= 0):
        label = _describe_descriptor(ConstellationLogicPuzzle.Category.PITCH, star)
        rec = _find_match_record_by_star_idx(star)
        visible_star = true
    elif t_label > 0 and (clue == null or terms.has("S:%d" % t_label)):
        label = _label_phrase_for_star(star, t_label)
        rec = _find_match_record_by_melody_tick(t_label)
        own_note = t_label
    if label == "":
        return {}
    var held: Array = []
    var ruled: Array = []
    var open: Array = []
    for t in range(1, _melody_tick_count() + 1):
        var state: int = _repeat_note_state_for_record(rec, t) if rec >= 0 else 0
        if t == own_note:
            state = 1
        elif own_note > 0 and t < own_note:
            state = 2   # the label names this star by its FIRST note (2026-10-14)
        if state == 1:
            held.append(t)
        elif state == 0:
            open.append(t)
        else:
            ruled.append(t)
    var count: int = _known_fire_count_for_record(rec) if rec >= 0 else -1
    if count < 0 and visible_star and _player_knows_star_pitch(star) \
            and star < _host._repeat_count.size() and int(_host._repeat_count[star]) >= 0:
        count = int(_host._repeat_count[star]) + 1   # Listen gives it, and the clue points at the map star
    # WHICH STAR IS THIS ROW? (2026-10-12) The row's notes and the map are two
    # halves of one question, so what the board knows about the stars this row
    # could still be is used here too:
    #   - if every star it could be is Listened, the row fires one of THEIR
    #     counts (often a single one, long before the name is pinned to a star);
    #   - a note every one of those stars' own rows has ruled out is ruled out
    #     for this row.
    var counts: Array = []
    if count > 0:
        counts = [count]
    elif not visible_star:
        var cands: Array = []
        if rec >= 0:
            cands = _candidate_stars_for_record(rec)
        else:
            for s0 in _host._star_count:
                cands.append(s0)
        var all_known: bool = not cands.is_empty()
        var seen: Dictionary = {}
        for s in cands:
            if _player_knows_star_pitch(int(s)) and int(s) < _host._repeat_count.size() and int(_host._repeat_count[int(s)]) >= 0:
                seen[int(_host._repeat_count[int(s)]) + 1] = true
            else:
                all_known = false
        if all_known:
            counts = seen.keys()
            counts.sort()
        if rec >= 0 and cands.size() < _host._star_count:
            var still_open: Array = []
            for t3 in open:
                var ruling_out: Dictionary = _map_stars_ruling_out_note(int(t3), rec)
                var everyone_rules_it_out: bool = true
                for s2 in cands:
                    if not ruling_out.has(int(s2)):
                        everyone_rules_it_out = false
                        break
                if everyone_rules_it_out:
                    ruled.append(int(t3))
                else:
                    still_open.append(int(t3))
            open = still_open
    # Which row this is, for whoever acts on a step: the Name row, the map
    # star's own row, or the entry of a staff note.
    var row_kind: String = "note" if own_note > 0 else ("star" if visible_star else "name")
    # A note number, a map star's index, or a name: written as if/else because
    # the three are different types on purpose (a ternary warns about that).
    var row_key = label
    if own_note > 0:
        row_key = own_note
    elif visible_star:
        row_key = star
    return {"label": label, "record": rec, "held": held, "ruled": ruled, "open": open, "count": count,
        "counts": counts, "row_kind": row_kind, "row_key": row_key}


## Every way of completing a row's notes to its known count: {"ok": false} when
## the count is unknown or there are too many to list, else {"ok": true,
## "sets": [sorted note lists]} (empty when the row already contradicts it).
##
## The row may fire one of SEVERAL counts (frame["counts"]: one per star it
## could still be); then the ways for each are listed together, since the real
## one is among them whichever star the row turns out to be.
func _owner_sets(frame: Dictionary) -> Dictionary:
    var counts: Array = frame.get("counts", [])
    if counts.is_empty():
        return {"ok": false}
    var held: Array = frame["held"]
    var open: Array = frame["open"]
    var grand_total: int = 0
    for c in counts:
        var kc: int = int(c) - held.size()
        if kc < 0 or kc > open.size():
            continue
        var total: int = 1
        for i in kc:
            @warning_ignore("integer_division")
            total = total * (open.size() - i) / (i + 1)
            if total > OWNER_STEP_MAX_SETS:
                return {"ok": false}
        grand_total += total
        if grand_total > OWNER_STEP_MAX_SETS:
            return {"ok": false}
    var sets: Array = []
    for c2 in counts:
        var k: int = int(c2) - held.size()
        if k < 0 or k > open.size():
            continue
        var idx: Array = []
        for i2 in k:
            idx.append(i2)
        while true:
            var one: Array = held.duplicate()
            for j in idx:
                one.append(int(open[int(j)]))
            one.sort()
            sets.append(one)
            # next combination of k indices out of open.size()
            var p: int = k - 1
            while p >= 0 and int(idx[p]) == open.size() - k + p:
                p -= 1
            if p < 0:
                break
            idx[p] = int(idx[p]) + 1
            for q in range(p + 1, k):
                idx[q] = int(idx[q - 1]) + 1
    return {"ok": true, "sets": sets}


## Does a full set of notes for `star` satisfy the facts about that star alone?
func _owner_unary_holds(solver, _star: int, notes: Array, facts: Array) -> bool:
    for f in facts:
        var fd: Dictionary = f
        # Labels name a star by its FIRST note (2026-10-14: "the star that
        # first fires on note T"), so these three are about notes[0].
        match str(fd["kind"]):
            "ordinal_exact":
                if int(notes[0]) != _label_note_for_rank0(int(fd["r"])):
                    return false
            "ordinal_neg":
                if int(notes[0]) == _label_note_for_rank0(int(fd["r"])):
                    return false
            "ordinal_either_or":
                if int(notes[0]) != _label_note_for_rank0(int(fd["r1"])) \
                        and int(notes[0]) != _label_note_for_rank0(int(fd["r2"])):
                    return false
            "ordinal_range":
                var first: int = int(notes[0])
                if int(fd["lo"]) > 0 and first < _label_note_for_rank0(int(fd["lo"])):
                    return false
                if int(fd["hi"]) < _host._star_count - 1 and first > _label_note_for_rank0(int(fd["hi"])):
                    return false
            "firing_position":
                var v: int = solver._firing_value(notes, fd["sel"])
                if v < 0 or v < int(fd["lo"]) or v > int(fd["hi"]):
                    return false
            "repeat_count_range":
                var reps: int = notes.size() - 1
                if (reps >= int(fd["lo"]) and reps <= int(fd["hi"])) == bool(fd.get("negated", false)):
                    return false
    return true


## Does a pair of full sets satisfy a fact relating the two stars?
func _owner_pair_holds(solver, fd: Dictionary, notes_of: Dictionary) -> bool:
    var na: Array = notes_of[int(fd["a"])]
    var nb: Array = notes_of[int(fd["b"])]
    if str(fd["kind"]) == "ordinal_cmp":
        return (int(na[0]) > int(nb[0])) == bool(fd["a_gt_b"])
    return solver._firing_rel_holds(solver._firing_pick_notes(na, fd["pick_a"]),
        solver._firing_pick_notes(nb, fd["pick_b"]), fd["spec"])


## A clue's facts sorted for the step finder: {"unary": star -> [facts],
## "binary": [facts], "stars": {star: true}}. An ordinal_chain is its two
## comparisons. Kinds the finder does not read are left out (never wrong, only
## weaker): neighbour counts and extremes, rank arithmetic, the pair table.
func _owner_facts_of(clue: Dictionary) -> Dictionary:
    var unary: Dictionary = {}
    var binary: Array = []
    var stars: Dictionary = {}
    # "X is either the star that fires 5th note or the star that fires 15th
    # note" also carries each LABEL's own fact, and the true option's label is
    # X itself: "X fires on note 5". Read against X's row that is the answer to
    # the either/or, which the clue does not give. Those label facts are left
    # out for the either/or's own subject; the either/or fact says what the
    # clue says.
    var either_label_ranks: Dictionary = {}   # star -> {rank0: true}
    for f0 in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if f0 is Dictionary and str((f0 as Dictionary).get("kind", "")) == "ordinal_either_or":
            var es: int = int(f0.get("s", -1))
            if not either_label_ranks.has(es):
                either_label_ranks[es] = {}
            either_label_ranks[es][int(f0.get("r1", -1))] = true
            either_label_ranks[es][int(f0.get("r2", -1))] = true
    for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if not (f is Dictionary):
            continue
        var fd: Dictionary = f
        if str(fd.get("kind", "")) == "ordinal_exact" and either_label_ranks.has(int(fd.get("s", -1))) \
                and (either_label_ranks[int(fd.get("s", -1))] as Dictionary).has(int(fd.get("r", -1))):
            continue
        var one: int = -1
        match str(fd.get("kind", "")):
            "ordinal_exact", "ordinal_neg", "ordinal_either_or", "ordinal_range", "firing_position":
                one = int(fd.get("s", -1))
            "repeat_count_range":
                one = int(fd.get("star", -1))
            "ordinal_cmp", "firing_relation":
                binary.append(fd)
                stars[int(fd.get("a", -1))] = true
                stars[int(fd.get("b", -1))] = true
            "ordinal_chain":
                for pair in [[int(fd["mid"]), int(fd["a"])], [int(fd["b"]), int(fd["mid"])]]:
                    binary.append({"kind": "ordinal_cmp", "a": pair[0], "b": pair[1], "a_gt_b": true})
                    stars[pair[0]] = true
                    stars[pair[1]] = true
        if one >= 0:
            if not unary.has(one):
                unary[one] = []
            (unary[one] as Array).append(fd)
            stars[one] = true
    return {"unary": unary, "binary": binary, "stars": stars}


## What the facts about one star say OUTRIGHT, with no count to list by:
## {"must": [notes], "cannot": [notes]} among the row's open notes.
func _owner_direct_verdict(frame: Dictionary, facts: Array) -> Dictionary:
    var open: Array = frame["open"]
    var must: Array = []
    var cannot: Array = []
    for f in facts:
        var fd: Dictionary = f
        match str(fd["kind"]):
            "ordinal_exact":
                # Its first note: it fires there and on nothing earlier.
                var t: int = _label_note_for_rank0(int(fd["r"]))
                if open.has(t) and not must.has(t):
                    must.append(t)
                for o0 in open:
                    if int(o0) < t and not cannot.has(int(o0)):
                        cannot.append(int(o0))
            "ordinal_neg":
                # Not its FIRST note. It could still fire there later -- unless
                # it fires only once, or no earlier note is left for it (then
                # a firing on note T would be its first).
                var tn: int = _label_note_for_rank0(int(fd["r"]))
                var earlier_left: bool = false
                for e in (frame["held"] as Array) + open:
                    if int(e) < tn:
                        earlier_left = true
                        break
                if (frame.get("counts", []) == [1] or not earlier_left) and open.has(tn) and not cannot.has(tn):
                    cannot.append(tn)
            "ordinal_either_or":
                var t_lo: int = mini(_label_note_for_rank0(int(fd["r1"])), _label_note_for_rank0(int(fd["r2"])))
                for o1 in open:
                    if int(o1) < t_lo and not cannot.has(int(o1)):
                        cannot.append(int(o1))
            "ordinal_range":
                if int(fd["lo"]) > 0:
                    var floor_note: int = _label_note_for_rank0(int(fd["lo"]))
                    for o in open:
                        if int(o) < floor_note and not cannot.has(int(o)):
                            cannot.append(int(o))
            "firing_position":
                var sel: Dictionary = fd["sel"]
                if str(sel["kind"]) == "count":
                    var wa: int = int(sel["lo"])
                    var wb: int = int(sel["hi"])
                    for o2 in open:
                        if int(o2) < wa or int(o2) > wb:
                            continue
                        if int(fd["hi"]) <= 0 and not cannot.has(int(o2)):
                            cannot.append(int(o2))
                        elif int(fd["lo"]) >= wb - wa + 1 and not must.has(int(o2)):
                            must.append(int(o2))
    must.sort()
    cannot.sort()
    return {"must": must, "cannot": cannot}


## Which of a row's OPEN notes are in every listed set / in none of them.
func _owner_verdict_from_sets(frame: Dictionary, sets: Array) -> Dictionary:
    var must: Array = []
    var cannot: Array = []
    for o in frame["open"]:
        var in_all: bool = true
        var in_any: bool = false
        for one in sets:
            if (one as Array).has(o):
                in_any = true
            else:
                in_all = false
        if in_all:
            must.append(int(o))
        elif not in_any:
            cannot.append(int(o))
    return {"must": must, "cannot": cannot}


## Every combination of one listed set per related star (stars[i:]) that shares
## no note with the others and satisfies each relation once both its stars are
## chosen; marks the set indices taking part in keep[i].
func _owner_rel_combos(solver, binary: Array, stars: Array, listed: Dictionary, i: int,
        chosen: Dictionary, chosen_idx: Array, keep: Array) -> void:
    if i == stars.size():
        for k in chosen_idx.size():
            (keep[k] as Dictionary)[int(chosen_idx[k])] = true
        return
    var s: int = int(stars[i])
    var sets: Array = listed[s]
    for idx in sets.size():
        var one: Array = sets[idx]
        var clash: bool = false
        for other in chosen:
            for t in one:
                if (chosen[other] as Array).has(t):
                    clash = true   # one note is one star
                    break
            if clash:
                break
        if clash:
            continue
        chosen[s] = one
        var good: bool = true
        for bf in binary:
            if chosen.has(int(bf["a"])) and chosen.has(int(bf["b"])) \
                    and (int(bf["a"]) == s or int(bf["b"]) == s) \
                    and not _owner_pair_holds(solver, bf, chosen):
                good = false
                break
        if good:
            chosen_idx.append(idx)
            _owner_rel_combos(solver, binary, stars, listed, i + 1, chosen, chosen_idx, keep)
            chosen_idx.pop_back()
        chosen.erase(s)


func _hint_owner_steps(clues: Array, solver) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for ci in clue_indices_with_something_to_give(clues):
        var clue: Dictionary = clues[ci]
        var sorted_facts: Dictionary = _owner_facts_of(clue)
        var unary: Dictionary = sorted_facts["unary"]
        var binary: Array = sorted_facts["binary"]
        if (sorted_facts["stars"] as Dictionary).is_empty():
            continue
        var frames: Dictionary = {}
        var listed: Dictionary = {}   # star -> the sets its own facts allow, where they can be listed
        for s in sorted_facts["stars"]:
            var fr: Dictionary = _owner_frame(int(s), clue)
            if fr.is_empty():
                continue
            frames[int(s)] = fr
            var all_sets: Dictionary = _owner_sets(fr)
            if bool(all_sets["ok"]):
                var kept: Array = []
                for one in all_sets["sets"]:
                    if _owner_unary_holds(solver, int(s), one, unary.get(int(s), [])):
                        kept.append(one)
                listed[int(s)] = kept
        var contradiction: bool = false
        for s0 in listed:
            if (listed[s0] as Array).is_empty():
                contradiction = true   # the board already contradicts the clue: not a hint
        if contradiction:
            continue
        # The stars the clue relates (two, or three for a chain or a
        # Betweenness), all listable: keep only the combinations of sets that
        # share no note and satisfy every relation between them. Three-star
        # clues were left to their weakest outright reading until 2026-10-14
        # ("Helios fires after Keriion, which fires after the star that plays
        # C#5" gave nothing even with every count known).
        var rel_stars: Array = []
        for bf in binary:
            for key in ["a", "b"]:
                if not rel_stars.has(int(bf[key])):
                    rel_stars.append(int(bf[key]))
        var rel_ok: bool = rel_stars.size() >= 2 and rel_stars.size() <= 3
        var combos: int = 1
        for rs in rel_stars:
            if not listed.has(rs):
                rel_ok = false
                break
            combos *= maxi(1, (listed[rs] as Array).size())
        if rel_ok and combos <= OWNER_STEP_PAIR_BUDGET:
            var keep: Array = []
            for _k in rel_stars.size():
                keep.append({})
            _owner_rel_combos(solver, binary, rel_stars, listed, 0, {}, [], keep)
            if (keep[0] as Dictionary).is_empty():
                continue   # contradiction
            for ki in rel_stars.size():
                var sk: int = int(rel_stars[ki])
                var kept_sets: Array = []
                for idx in (listed[sk] as Array).size():
                    if (keep[ki] as Dictionary).has(idx):
                        kept_sets.append(listed[sk][idx])
                listed[sk] = kept_sets
        for s2 in frames:
            var frame: Dictionary = frames[s2]
            var verdict: Dictionary
            if listed.has(s2):
                verdict = _owner_verdict_from_sets(frame, listed[s2])
            else:
                verdict = _owner_direct_verdict(frame, unary.get(s2, []))
            # Stated outright by an order fact whatever the counts: a star that
            # first fires AFTER another fires on no note up to the earliest the
            # other could begin (note 1, if nothing is known about it).
            var cannot: Array = verdict["cannot"]
            for bf3 in binary:
                if str(bf3["kind"]) != "ordinal_cmp":
                    continue
                var later: int = int(bf3["a"]) if bool(bf3["a_gt_b"]) else int(bf3["b"])
                var earlier: int = int(bf3["b"]) if bool(bf3["a_gt_b"]) else int(bf3["a"])
                if later != int(s2):
                    continue
                var earliest: int = 1
                if frames.has(earlier):
                    var poss: Array = (frames[earlier]["held"] as Array) + (frames[earlier]["open"] as Array)
                    if not poss.is_empty():
                        earliest = int(poss.min())
                for o in frame["open"]:
                    if int(o) <= earliest and not cannot.has(int(o)):
                        cannot.append(int(o))
            cannot.sort()
            var must: Array = verdict["must"]
            if must.is_empty() and cannot.is_empty():
                continue
            out.append({
                "axis": "note",
                "plain_notes": true,
                "clue_index": int(ci),
                "star": int(s2),
                "rank": 0,
                "descriptor": str(frame["label"]),
                "row_kind": str(frame["row_kind"]),
                "row_key": frame["row_key"],
                "must_ticks": must,
                "cannot_ticks": cannot,
                "resolved": not must.is_empty(),
                "gain": must.size() + cannot.size(),
            })
        # What the clue says about HOW OFTEN a star fires, for a row whose count
        # the board does not have yet. Marking it is what lets the row's notes
        # be worked out, so it is offered as a step in its own right.
        for s4 in frames:
            var rep_step: Dictionary = _owner_repeat_step(frames[s4], unary.get(s4, []))
            if not rep_step.is_empty():
                rep_step["clue_index"] = int(ci)
                rep_step["star"] = int(s4)
                out.append(rep_step)
    out.append_array(_hint_owner_board_steps())
    return out


# ── SEVERAL CLUES TOGETHER (2026-10-12) ──────────────────────────────────
# One clue at a time placed 18 of 42 notes on three measured puzzles and then
# ran out with most clues still unused: the rest needs clues combined.
#
# A WORLD pools the facts of several clues onto the player's ROWS. A row is
# what a clue's own wording points at (_owner_frame), so two clues talk about
# the same thing exactly when they point at the same row -- "Helios" twice, or
# "Helios" and "the star that fires 3rd note" once Helios's row holds note 3.
# Two rows the board has not joined are kept apart even when they are secretly
# one star; they are only forced to share no note when they are KNOWN to be
# different stars (two names, two map stars, or rows the board proves
# distinct), or when one clue relates them (a clue never relates a star to
# itself). That keeps every conclusion one the player could reach: nothing
# rests on which map star a name is unless the board already says.
#
# Each row whose firing count is known lists the ways its notes could be
# completed; ways no fact allows are struck out, then ways with no compatible
# partner in a related row, round after round until nothing changes. A note
# in every surviving way must be the row's; a note in none cannot be.
#
# A step names the SMALLEST set of clues found to force it: clues are dropped
# one at a time while the conclusion still follows.

## Most clues a multi-clue step is allowed to name. A hint that needs more is
## not a hint a player can follow.
const OWNER_MULTI_MAX_CLUES: int = 3
## Rounds of striking out before a world is taken as settled.
const OWNER_WORLD_MAX_ROUNDS: int = 8


func _owner_entity_key(frame: Dictionary) -> String:
    if int(frame["record"]) >= 0:
        return "r%d" % int(frame["record"])
    return "%s:%s" % [str(frame["row_kind"]), str(frame["row_key"])]


## Are two rows known to be different stars?
func _owner_rows_known_distinct(fa: Dictionary, fb: Dictionary) -> bool:
    if str(fa["row_kind"]) == str(fb["row_kind"]) and str(fa["row_kind"]) != "note" \
            and str(fa["row_key"]) != str(fb["row_key"]):
        return true   # two names, or two map stars
    if int(fa["record"]) >= 0 and int(fb["record"]) >= 0:
        return _records_provably_distinct(int(fa["record"]), int(fb["record"]))
    return false


## Frames built during one world search, keyed by star and clue: the same row
## is asked for many times while clues are dropped and the world rebuilt.
var _owner_frame_memo: Dictionary = {}
var _owner_frame_memo_on: bool = false


func _owner_frame_memoised(star: int, clue: Dictionary, clue_index: int) -> Dictionary:
    if not _owner_frame_memo_on:
        return _owner_frame(star, clue)
    var key: String = "%d|%d" % [star, clue_index]
    if not _owner_frame_memo.has(key):
        _owner_frame_memo[key] = _owner_frame(star, clue)
    return _owner_frame_memo[key]


## Pools the clues at `indices` and narrows. {"ok": false} when the board
## contradicts them (never a hint); else {"ok": true, "rows": key -> {"frame",
## "clues": {index: true}, "star"}, "verdicts": key -> {"must", "cannot"},
## "links": [[key, key, clue index]]}.
func _owner_world(clues: Array, indices: Array, solver) -> Dictionary:
    var rows: Dictionary = {}
    var relations: Array = []   # {"fd", "ka", "kb", "ci"}
    var shown: Array = _repeat_values_shown()
    for ci in indices:
        var clue: Dictionary = clues[int(ci)]
        var sorted_facts: Dictionary = _owner_facts_of(clue)
        var key_of: Dictionary = {}
        for s in sorted_facts["stars"]:
            var fr: Dictionary = _owner_frame_memoised(int(s), clue, int(ci))
            if fr.is_empty():
                continue
            var key: String = _owner_entity_key(fr)
            key_of[int(s)] = key
            if not rows.has(key):
                rows[key] = {"frame": fr, "facts": [], "clues": {}, "star": int(s)}
            for f in (sorted_facts["unary"] as Dictionary).get(int(s), []):
                (rows[key]["facts"] as Array).append(f)
                (rows[key]["clues"] as Dictionary)[int(ci)] = true
        for bf in sorted_facts["binary"]:
            var a: int = int(bf["a"])
            var b: int = int(bf["b"])
            if key_of.has(a) and key_of.has(b) and str(key_of[a]) != str(key_of[b]):
                relations.append({"fd": bf, "ka": key_of[a], "kb": key_of[b], "ci": int(ci)})
                (rows[key_of[a]]["clues"] as Dictionary)[int(ci)] = true
                (rows[key_of[b]]["clues"] as Dictionary)[int(ci)] = true
    # The ways each row's notes could be completed, where they can be listed.
    for key2 in rows:
        var row: Dictionary = rows[key2]
        var frame: Dictionary = row["frame"]
        # What the pooled clues say about HOW OFTEN the star fires narrows the
        # counts tried, even before the player has marked it on the row.
        var by_fact: Dictionary = {}
        var counted: bool = false
        for f2 in row["facts"]:
            if str(f2["kind"]) != "repeat_count_range":
                continue
            if not counted:
                counted = true
                for v in shown:
                    by_fact[int(v) + 1] = true
            for v2 in shown:
                if (int(v2) >= int(f2["lo"]) and int(v2) <= int(f2["hi"])) == bool(f2.get("negated", false)):
                    by_fact.erase(int(v2) + 1)
        if counted:
            var base: Array = (frame["counts"] as Array) if not (frame["counts"] as Array).is_empty() else by_fact.keys()
            var narrowed: Array = []
            for c in base:
                if by_fact.has(int(c)):
                    narrowed.append(int(c))
            narrowed.sort()
            if narrowed.is_empty():
                return {"ok": false}
            frame = frame.duplicate()
            frame["counts"] = narrowed
            row["frame"] = frame
        var all_sets: Dictionary = _owner_sets(frame)
        row["sets"] = null
        if bool(all_sets["ok"]):
            var kept: Array = []
            for one in all_sets["sets"]:
                if _owner_unary_holds(solver, int(row["star"]), one, row["facts"]):
                    kept.append(one)
            if kept.is_empty():
                return {"ok": false}
            row["sets"] = kept
    # Pairs of rows that constrain each other: a relation a clue states (the
    # two share no note AND the relation holds), or simply known to be
    # different stars (they share no note).
    var pairs: Array = []
    for rel in relations:
        pairs.append(rel)
    var keys: Array = rows.keys()
    for i in keys.size():
        for j in range(i + 1, keys.size()):
            if _owner_rows_known_distinct(rows[keys[i]]["frame"], rows[keys[j]]["frame"]):
                pairs.append({"fd": {}, "ka": keys[i], "kb": keys[j], "ci": -1})
    var changed: bool = true
    var rounds: int = 0
    while changed and rounds < OWNER_WORLD_MAX_ROUNDS:
        changed = false
        rounds += 1
        for pr in pairs:
            var sets_a = rows[pr["ka"]]["sets"]
            var sets_b = rows[pr["kb"]]["sets"]
            if sets_a == null or sets_b == null:
                continue
            if (sets_a as Array).size() * (sets_b as Array).size() > OWNER_STEP_PAIR_BUDGET:
                continue
            var fd: Dictionary = pr["fd"]
            var keep_a: Dictionary = {}
            var keep_b: Dictionary = {}
            for ia in (sets_a as Array).size():
                var na: Array = sets_a[ia]
                for ib in (sets_b as Array).size():
                    if keep_a.has(ia) and keep_b.has(ib):
                        continue
                    var nb: Array = sets_b[ib]
                    var clash: bool = false
                    for t in nb:
                        if na.has(t):
                            clash = true
                            break
                    if clash:
                        continue
                    # A relation is stored with ka = the row of its star `a`.
                    if not fd.is_empty() and not _owner_pair_holds(solver, fd, {int(fd["a"]): na, int(fd["b"]): nb}):
                        continue
                    keep_a[ia] = true
                    keep_b[ib] = true
            if keep_a.is_empty():
                return {"ok": false}
            if keep_a.size() < (sets_a as Array).size():
                var la: Array = []
                for ia2 in (sets_a as Array).size():
                    if keep_a.has(ia2):
                        la.append(sets_a[ia2])
                rows[pr["ka"]]["sets"] = la
                changed = true
            if keep_b.size() < (sets_b as Array).size():
                var lb: Array = []
                for ib2 in (sets_b as Array).size():
                    if keep_b.has(ib2):
                        lb.append(sets_b[ib2])
                rows[pr["kb"]]["sets"] = lb
                changed = true
    var verdicts: Dictionary = {}
    for key3 in rows:
        var row3: Dictionary = rows[key3]
        var verdict: Dictionary
        if row3["sets"] != null:
            verdict = _owner_verdict_from_sets(row3["frame"], row3["sets"])
        else:
            verdict = _owner_direct_verdict(row3["frame"], row3["facts"])
        verdicts[key3] = verdict
    # An order fact says outright that the later star fires on no note up to
    # the earliest the other could begin.
    for rel2 in relations:
        var fd2: Dictionary = rel2["fd"]
        if str(fd2["kind"]) != "ordinal_cmp":
            continue
        var later_is_a: bool = bool(fd2["a_gt_b"])
        var later_key: String = str(rel2["ka"]) if later_is_a else str(rel2["kb"])
        var earlier_key: String = str(rel2["kb"]) if later_is_a else str(rel2["ka"])
        var earliest: int = 1
        var erow: Dictionary = rows[earlier_key]
        if erow["sets"] != null:
            earliest = 999999
            for es in erow["sets"]:
                earliest = mini(earliest, int((es as Array)[0]))
        else:
            var poss: Array = (erow["frame"]["held"] as Array) + (erow["frame"]["open"] as Array)
            if not poss.is_empty():
                earliest = int(poss.min())
        var cannot: Array = verdicts[later_key]["cannot"]
        for o in rows[later_key]["frame"]["open"]:
            if int(o) <= earliest and not cannot.has(int(o)) and not (verdicts[later_key]["must"] as Array).has(int(o)):
                cannot.append(int(o))
        cannot.sort()
    var links: Array = []
    for rel3 in relations:
        links.append([str(rel3["ka"]), str(rel3["kb"]), int(rel3["ci"])])
    return {"ok": true, "rows": rows, "verdicts": verdicts, "links": links}


## Steps that take SEVERAL clues, offered once no single clue gives anything
## (hint_next_steps only calls this then). Each carries "clue_indices", the
## clues to show, smallest set found; "clue_index" is the first of them.
func _hint_owner_multi_steps(clues: Array, solver) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var waiting: Array = []
    for ci in clue_indices_with_something_to_give(clues):
        waiting.append(int(ci))
    if waiting.size() < 2:
        return out
    _owner_frame_memo = {}
    _owner_frame_memo_on = true
    var whole: Dictionary = _owner_world(clues, waiting, solver)
    if bool(whole["ok"]):
        for key in whole["verdicts"]:
            var verdict: Dictionary = whole["verdicts"][key]
            var must: Array = verdict["must"]
            var cannot: Array = verdict["cannot"]
            if must.is_empty() and cannot.is_empty():
                continue
            # What to explain: the notes the row MUST take if there are any
            # (that is the step that moves the board), else the ones ruled out.
            var want_must: bool = not must.is_empty()
            var target: Array = must if want_must else cannot
            # Only the clues that reach this row through the rows they relate.
            var reach: Dictionary = {str(key): true}
            var grew: bool = true
            while grew:
                grew = false
                for link in whole["links"]:
                    if reach.has(link[0]) != reach.has(link[1]):
                        reach[link[0]] = true
                        reach[link[1]] = true
                        grew = true
            var subset: Array = []
            for ci2 in waiting:
                for rk in reach:
                    if (whole["rows"][rk]["clues"] as Dictionary).has(int(ci2)) and not subset.has(int(ci2)):
                        subset.append(int(ci2))
            # Drop clues one at a time while the conclusion still follows.
            var i: int = subset.size() - 1
            while i >= 0 and subset.size() > 1:
                var trial: Array = subset.duplicate()
                trial.remove_at(i)
                var w: Dictionary = _owner_world(clues, trial, solver)
                var still: bool = bool(w["ok"]) and (w["verdicts"] as Dictionary).has(key)
                if still:
                    var got: Array = w["verdicts"][key]["must" if want_must else "cannot"]
                    for t in target:
                        if not got.has(t):
                            still = false
                            break
                if still:
                    subset = trial
                i -= 1
            if subset.size() > OWNER_MULTI_MAX_CLUES:
                continue   # a hint needing more clues than that is not one a player can follow
            # (One clue can be left: this search also uses what a clue says
            # about how often its star fires, which the one-clue finder does
            # not. It is then an ordinary one-clue step.)
            subset.sort()
            var frame: Dictionary = whole["rows"][key]["frame"]
            out.append({
                "axis": "note",
                "plain_notes": true,
                "multi": subset.size() > 1,
                "clue_index": int(subset[0]),
                "clue_indices": subset,
                "star": int(whole["rows"][key]["star"]),
                "rank": 0,
                "descriptor": str(frame["label"]),
                "row_kind": str(frame["row_kind"]),
                "row_key": frame["row_key"],
                "must_ticks": target.duplicate() if want_must else [],
                "cannot_ticks": [] if want_must else target.duplicate(),
                "resolved": want_must,
                "gain": target.size(),
            })
    _owner_frame_memo_on = false
    _owner_frame_memo = {}
    return out


# ── THE WHOLE MELODY AT ONCE (2026-10-12) ────────────────────────────────
# Pooling clues row by row moved nothing on the measured puzzles, because the
# strongest thing a player knows is not about any one row: EVERY NOTE IS
# EXACTLY ONE MAP STAR'S, and Listen gives how many notes each map star has.
# So this searches the melody itself -- one map star per note, each star as
# many notes as it fires -- for the assignments that fit the board and the
# clues, and reports what they all agree on.
#
# Only what the player can use goes in:
#   - the notes each ROW holds or rules out, applied to the map stars that
#     row could still be (_candidate_stars_for_record). A row tied to one map
#     star fixes that star; a Name row not yet tied to a star only says "one
#     of the stars this name could be fires here";
#   - a clue's fact, applied to what the clue's own wording points at: a map
#     star (a colour or Listened pitch only it has), the star of a note ("the
#     star that fires 3rd note" is whoever fires on note 3 in the assignment
#     being tried), or a NAME -- and a fact about a name holds if it is true
#     of at least one map star that name could still be.
# A name's facts are tested together on one candidate star, but two names are
# not forced onto different stars, and a relation between two names is tested
# on its own. Both make the search accept more than the truth allows, never
# less, so what every accepted assignment agrees on is certainly true.
#
# It needs every star Listened (the counts), and it gives up -- offering
# nothing -- when the board is still so open that the assignments cannot be
# listed within OWNER_GLOBAL_MAX_SOLUTIONS / the node budget.

## Search steps one whole-melody search may spend. MEASURED 2026-10-12: about
## 40,000 a second in the test runner, and the search runs in one go when a
## hint is asked for, so this is roughly a second's pause at most (longer in a
## web build). Raising it finds more and stalls the game longer.
const OWNER_GLOBAL_NODE_BUDGET: int = 40000
const OWNER_GLOBAL_MAX_SOLUTIONS: int = 600
## Most clues a whole-melody step may name. Above that it is not offered.
const OWNER_GLOBAL_MAX_CLUES: int = 4

var _owner_global_nodes: int = 0
var _owner_global_gave_up: bool = false
## Whether hint_next_steps runs the whole-melody search. False: it is sound
## (test_owner_hints.gd lists every assignment it accepts on one board and the
## real melody is among them) but too slow to finish where it would matter --
## 424 assignments in 0.7 s on the smallest measured board, and still unfinished
## after 75 s and 133 s on the other two. It needs a faster search before it
## is worth a player's wait.
var owner_global_hints_enabled: bool = false


## Who a fact is about, for the whole-melody search: {"stars": [map stars it
## could be]} or {"note": T} (whoever fires on note T). {} = the clue gives the
## player no way to find it.
func _owner_subject(star: int, clue: Dictionary, clue_index: int) -> Dictionary:
    var fr: Dictionary = _owner_frame_memoised(star, clue, clue_index)
    if fr.is_empty():
        return {}
    match str(fr["row_kind"]):
        "star":
            return {"stars": [int(fr["row_key"])], "name": ""}
        "note":
            return {"note": int(fr["row_key"])}
    var rec: int = int(fr["record"])
    var cands: Array = []
    if rec >= 0:
        cands = _candidate_stars_for_record(rec).duplicate()
    else:
        for s in _host._star_count:
            cands.append(s)
    return {"stars": cands, "name": str(fr["label"]), "record": rec}


## Everything the search needs for the clues at `indices`, or {"ok": false}.
func _owner_global_setup(clues: Array, indices: Array) -> Dictionary:
    var n_notes: int = _melody_tick_count()
    var need: Array = []
    for s in _host._star_count:
        if not _player_knows_star_pitch(s) or s >= _host._repeat_count.size() or int(_host._repeat_count[s]) < 0:
            return {"ok": false}   # a star not Listened: its count is not known
        need.append(int(_host._repeat_count[s]) + 1)
    var all_mask: int = (1 << _host._star_count) - 1
    var allowed: Array = []
    for _t in n_notes + 1:
        allowed.append(all_mask)
    # The rows: a note a row holds is one of the stars that row could be; a
    # note a row rules out is not that row's star, when the row is one star.
    for i in _match_records.size():
        var held: Array = _match_records[i].get("melody_ticks", [])
        var blocks: Array = _match_records[i].get("seq_note_blocks", [])
        if held.is_empty() and blocks.is_empty():
            continue
        var cands: Array = _candidate_stars_for_record(i)
        var mask: int = 0
        for c in cands:
            mask |= 1 << int(c)
        for t in held:
            if int(t) >= 1 and int(t) <= n_notes:
                allowed[int(t)] = int(allowed[int(t)]) & mask
        if cands.size() == 1:
            for t2 in blocks:
                if int(t2) >= 1 and int(t2) <= n_notes:
                    allowed[int(t2)] = int(allowed[int(t2)]) & ~(1 << int(cands[0]))
    var fixed: Array = []        # per map star: facts about that star alone
    for _s in _host._star_count:
        fixed.append([])
    var by_note: Array = []      # {"note", "fd"}: about whoever fires on a note
    var names: Dictionary = {}   # name -> {"stars", "facts", "held", "blocks"}
    var relations: Array = []    # {"fd", "a": subject, "b": subject}
    for ci in indices:
        var clue: Dictionary = clues[int(ci)]
        var sorted_facts: Dictionary = _owner_facts_of(clue)
        var subj: Dictionary = {}
        for s2 in sorted_facts["stars"]:
            var sub: Dictionary = _owner_subject(int(s2), clue, int(ci))
            if sub.is_empty():
                continue
            subj[int(s2)] = sub
            for f in (sorted_facts["unary"] as Dictionary).get(int(s2), []):
                if sub.has("note"):
                    by_note.append({"note": int(sub["note"]), "fd": f})
                elif (sub["stars"] as Array).size() == 1:
                    (fixed[int((sub["stars"] as Array)[0])] as Array).append(f)
                elif str(sub["name"]) != "":
                    if not names.has(str(sub["name"])):
                        var nrec: int = int(sub.get("record", -1))
                        names[str(sub["name"])] = {"stars": sub["stars"], "facts": [],
                            "held": _match_records[nrec].get("melody_ticks", []) if nrec >= 0 else [],
                            "blocks": _match_records[nrec].get("seq_note_blocks", []) if nrec >= 0 else []}
                    (names[str(sub["name"])]["facts"] as Array).append(f)
        for bf in sorted_facts["binary"]:
            if subj.has(int(bf["a"])) and subj.has(int(bf["b"])):
                relations.append({"fd": bf, "a": subj[int(bf["a"])], "b": subj[int(bf["b"])]})
    for t3 in range(1, n_notes + 1):
        if int(allowed[t3]) == 0:
            return {"ok": false}   # the board contradicts itself: not a hint
    return {"ok": true, "n": n_notes, "need": need, "allowed": allowed, "fixed": fixed,
        "by_note": by_note, "names": names, "relations": relations}


## The map stars a subject could be in a finished assignment.
func _owner_subject_stars(sub: Dictionary, owners: Array) -> Array:
    if sub.has("note"):
        return [int(owners[int(sub["note"]) - 1])]
    return sub["stars"]


## Does a finished assignment (notes_of[s] = that star's notes) fit everything
## that could not be checked on the way?
func _owner_global_leaf_ok(melody_setup: Dictionary, owners: Array, notes_of: Array, solver) -> bool:
    for bn in melody_setup["by_note"]:
        var who: int = int(owners[int(bn["note"]) - 1])
        if not _owner_unary_holds(solver, who, notes_of[who], [bn["fd"]]):
            return false
    for name in melody_setup["names"]:
        var req: Dictionary = melody_setup["names"][name]
        if _owner_name_fits(req, notes_of, solver).is_empty():
            return false
    for rel in melody_setup["relations"]:
        var fd: Dictionary = rel["fd"]
        var found: bool = false
        for sa in _owner_subject_stars(rel["a"], owners):
            for sb in _owner_subject_stars(rel["b"], owners):
                if int(sa) != int(sb) and _owner_pair_holds(solver, fd,
                        {int(fd["a"]): notes_of[int(sa)], int(fd["b"]): notes_of[int(sb)]}):
                    found = true
                    break
            if found:
                break
        if not found:
            return false
    return true


## The map stars a name could be in a finished assignment: of the stars its row
## still allows, those whose notes include every note the row holds, none it
## rules out, and satisfy every fact the clues state about the name.
func _owner_name_fits(req: Dictionary, notes_of: Array, solver) -> Array:
    var out: Array = []
    for s in req["stars"]:
        var mine: Array = notes_of[int(s)]
        var good: bool = true
        for t in req["held"]:
            if not mine.has(t):
                good = false
                break
        if good:
            for t2 in req["blocks"]:
                if mine.has(t2):
                    good = false
                    break
        if good and _owner_unary_holds(solver, int(s), mine, req["facts"]):
            out.append(int(s))
    return out


func _owner_global_step(t: int, melody_setup: Dictionary, owners: Array, notes_of: Array, sols: Array, cap: int, solver) -> void:
    if sols.size() >= cap or _owner_global_gave_up:
        return
    _owner_global_nodes -= 1
    if _owner_global_nodes <= 0:
        _owner_global_gave_up = true
        return
    var n: int = int(melody_setup["n"])
    if t > n:
        if _owner_global_leaf_ok(melody_setup, owners, notes_of, solver):
            sols.append(owners.duplicate())
        return
    var need: Array = melody_setup["need"]
    var mask: int = int((melody_setup["allowed"] as Array)[t])
    # Notes still to hand out must cover what every star is still owed.
    for s in _host._star_count:
        if not (mask & (1 << s)):
            continue
        var mine: Array = notes_of[s]
        if mine.size() >= int(need[s]):
            continue
        mine.append(t)
        owners[t - 1] = s
        var ok: bool = true
        if mine.size() == int(need[s]):
            ok = _owner_unary_holds(solver, s, mine, (melody_setup["fixed"] as Array)[s])
        if ok:
            _owner_global_step(t + 1, melody_setup, owners, notes_of, sols, cap, solver)
        mine.pop_back()
        owners[t - 1] = -1
        if sols.size() >= cap or _owner_global_gave_up:
            return


## Every assignment that fits, up to `cap`: {"complete": the search finished
## and found fewer than cap, "sols": [owners per note]}.
func _owner_global_solve(melody_setup: Dictionary, cap: int, solver, budget: int = OWNER_GLOBAL_NODE_BUDGET) -> Dictionary:
    var owners: Array = []
    for _t in int(melody_setup["n"]):
        owners.append(-1)
    var notes_of: Array = []
    for _s in _host._star_count:
        notes_of.append([])
    var sols: Array = []
    _owner_global_nodes = budget
    _owner_global_gave_up = false
    _owner_global_step(1, melody_setup, owners, notes_of, sols, cap, solver)
    return {"complete": not _owner_global_gave_up and sols.size() < cap, "sols": sols}


## Is "star s fires / does not fire on each of `notes`" true in EVERY assignment
## that fits? Asked by looking for one that breaks it. A search that gives up
## answers no.
func _owner_global_forced(melody_setup: Dictionary, star: int, notes: Array, want_must: bool, solver) -> bool:
    for t in notes:
        var trial: Dictionary = melody_setup.duplicate()
        var allowed: Array = (melody_setup["allowed"] as Array).duplicate()
        allowed[int(t)] = (int(allowed[int(t)]) & ~(1 << star)) if want_must else (int(allowed[int(t)]) & (1 << star))
        trial["allowed"] = allowed
        if int(allowed[int(t)]) == 0:
            continue
        @warning_ignore("integer_division")   # a third of the budget, rounded down, is what is meant
        var res: Dictionary = _owner_global_solve(trial, 1, solver, OWNER_GLOBAL_NODE_BUDGET / 3)
        if not (res["sols"] as Array).is_empty() or _owner_global_gave_up:
            return false
    return true


## How a whole-melody step may name a map star: by a colour or Listened pitch
## only it has. "" = no way to say which star, so no step about it.
func _owner_visible_star_label(star: int) -> String:
    if _star_alone_in_group(star, ConstellationLogicPuzzle.Category.COLOR):
        return _describe_descriptor(ConstellationLogicPuzzle.Category.COLOR, star)
    if _player_knows_star_pitch(star) and _star_alone_in_group(star, ConstellationLogicPuzzle.Category.PITCH):
        return _describe_descriptor(ConstellationLogicPuzzle.Category.PITCH, star)
    return ""


func _hint_owner_global_steps(clues: Array, solver) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var waiting: Array = []
    for ci in clue_indices_with_something_to_give(clues):
        waiting.append(int(ci))
    _owner_frame_memo = {}
    _owner_frame_memo_on = true
    var melody_setup: Dictionary = _owner_global_setup(clues, waiting)
    if bool(melody_setup["ok"]):
        var res: Dictionary = _owner_global_solve(melody_setup, OWNER_GLOBAL_MAX_SOLUTIONS, solver)
        var sols: Array = res["sols"]
        if bool(res["complete"]) and not sols.is_empty():
            var n_notes: int = int(melody_setup["n"])
            for s in _host._star_count:
                var label: String = _owner_visible_star_label(s)
                if label == "":
                    continue
                var row: int = _find_match_record_by_star_idx(s)
                var must: Array = []
                var cannot: Array = []
                for t in range(1, n_notes + 1):
                    if row >= 0 and _repeat_note_state_for_record(row, t) != 0:
                        continue   # already on the row
                    var always: bool = true
                    var ever: bool = false
                    for sol in sols:
                        if int(sol[t - 1]) == s:
                            ever = true
                        else:
                            always = false
                    if always:
                        must.append(t)
                    elif not ever:
                        cannot.append(t)
                if must.is_empty() and cannot.is_empty():
                    continue
                var want_must: bool = not must.is_empty()
                # At most two notes per step: each one is re-proved for every
                # clue dropped below, and the step claims only what was proved.
                var target: Array = (must if want_must else cannot).slice(0, 2)
                # The fewest clues found that still force it, dropping one at a time.
                var subset: Array = waiting.duplicate()
                var i: int = subset.size() - 1
                while i >= 0:
                    var trial: Array = subset.duplicate()
                    trial.remove_at(i)
                    var trial_setup: Dictionary = _owner_global_setup(clues, trial)
                    if bool(trial_setup["ok"]) and _owner_global_forced(trial_setup, s, target, want_must, solver):
                        subset = trial
                    i -= 1
                if subset.size() > OWNER_GLOBAL_MAX_CLUES:
                    continue   # needs more clues than a player can follow in one hint
                subset.sort()
                var step: Dictionary = {
                    "axis": "note",
                    "plain_notes": true,
                    "whole_melody": true,
                    "multi": subset.size() > 1,
                    "clue_index": int(subset[0]) if not subset.is_empty() else -1,
                    "star": s,
                    "rank": 0,
                    "descriptor": label,
                    "row_kind": "star",
                    "row_key": s,
                    "must_ticks": target if want_must else [],
                    "cannot_ticks": [] if want_must else target,
                    "resolved": want_must,
                    "gain": target.size(),
                }
                if subset.is_empty():
                    step["from_marks"] = true
                    step["from_text"] = "Every note is exactly one star's, and you know how often each star fires. From the notes already on your rows"
                else:
                    step["clue_indices"] = subset
                out.append(step)
    _owner_frame_memo_on = false
    _owner_frame_memo = {}
    return out


## Steps that need NO clue, only the Name rows as they stand (clue_index -1).
## Every star has a name and every note has exactly one star, so:
##   - a Name row known to fire n times, holding h notes, with exactly n - h
##     notes still open, fires on all of them;
##   - a note no row holds yet, which every Name row but one has ruled out,
##     is that one name's.
## The Name rows are read as a clue naming the star would read them
## (_owner_frame), a row nobody has opened counting as fully open.
func _hint_owner_board_steps() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var frames: Array = []
    for n in _host._star_count:
        if n >= _host._star_names.size():
            return out
        frames.append(_owner_frame(n, {"search_terms": ["N:" + str(_host._star_names[n])]}))
    var must_by_name: Dictionary = {}   # name star -> {note: why}
    for n2 in frames.size():
        var fr: Dictionary = frames[n2]
        if fr.is_empty():
            continue
        var counts: Array = fr["counts"]
        var open: Array = fr["open"]
        if counts.size() == 1 and not open.is_empty() and open.size() == int(counts[0]) - (fr["held"] as Array).size():
            for t in open:
                if not must_by_name.has(n2):
                    must_by_name[n2] = {}
                (must_by_name[n2] as Dictionary)[int(t)] = "With as many notes left open as %s still has to fire on" % str(fr["label"])
    for t2 in range(1, _melody_tick_count() + 1):
        if _find_match_record_by_melody_tick(t2) >= 0:
            continue   # some row holds it: that row's star fires there
        var only: int = -1
        var several: bool = false
        for n3 in frames.size():
            var fr3: Dictionary = frames[n3]
            if fr3.is_empty() or (fr3["open"] as Array).has(t2):
                if only >= 0:
                    several = true
                    break
                only = n3
        if only >= 0 and not several and not (frames[only] as Dictionary).is_empty():
            if not must_by_name.has(only):
                must_by_name[only] = {}
            if not (must_by_name[only] as Dictionary).has(t2):
                (must_by_name[only] as Dictionary)[t2] = "With every other name ruled out for it"
    for n4 in must_by_name:
        var notes: Array = (must_by_name[n4] as Dictionary).keys()
        notes.sort()
        out.append({
            "axis": "note",
            "plain_notes": true,
            "clue_index": -1,
            "from_marks": true,
            "from_text": str((must_by_name[n4] as Dictionary)[notes[0]]),
            "star": int(n4),
            "rank": 0,
            "descriptor": str(frames[int(n4)]["label"]),
            "row_kind": "name",
            "row_key": str(frames[int(n4)]["label"]),
            "must_ticks": notes,
            "cannot_ticks": [],
            "resolved": true,
            "gain": notes.size(),
        })
    return out


## A step on a row's REPEATS entry from one clue's facts about that star's
## count ("Helios repeats once", or the wording "first fires" / "the only
## firing of"): the counts still open on the row that the clue rules out, and
## the one it leaves if only one is left. {} when the row's count is already
## known or the clue says nothing new about it.
func _owner_repeat_step(frame: Dictionary, facts: Array) -> Dictionary:
    if int(frame["count"]) > 0:
        return {}
    var rec: int = int(frame["record"])
    var shown: Array = _repeat_values_shown()
    var open: Array = []
    for v in shown:
        var state: int = _effective_repeat_state(rec, int(v)) if rec >= 0 else 0
        if state == 1:
            return {}
        if state == 0:
            open.append(int(v))
    var allowed: Dictionary = {}
    for v2 in shown:
        allowed[int(v2)] = true
    var says_something: bool = false
    for f in facts:
        var fd: Dictionary = f
        if str(fd["kind"]) != "repeat_count_range":
            continue
        says_something = true
        for v3 in shown:
            if (int(v3) >= int(fd["lo"]) and int(v3) <= int(fd["hi"])) == bool(fd.get("negated", false)):
                allowed.erase(int(v3))
    if not says_something:
        return {}
    var cannot: Array = []
    var left: Array = []
    for v4 in open:
        if allowed.has(int(v4)):
            left.append(int(v4))
        else:
            cannot.append(int(v4))
    if cannot.is_empty() or left.is_empty():
        return {}   # nothing new, or the row already contradicts the clue
    return {
        "axis": "repeat",
        "descriptor": str(frame["label"]),
        "row_kind": str(frame["row_kind"]),
        "row_key": frame["row_key"],
        "must_value": int(left[0]) if left.size() == 1 else -1,
        "cannot_values": cannot,
        "resolved": left.size() == 1,
        "gain": cannot.size(),
    }


## Is a fact about notes already entailed by the board, with the first notes
## hidden? The scoring twin of the step finder: same rows, same reading.
## {"known": false} for a kind this cannot judge (the caller's old reading
## stands); else {"known": true, "value": bool}.
##
## A star can have several rows on the board that are not yet joined (its Name
## row, its map star's row, the entry of the note a clue names it by). A fact is
## recorded as soon as ANY of them entails it -- found 2026-10-12, when "the
## star that plays E5 is the star that fires 9th note" stayed "waiting" after
## the E5 star's row held note 9, because a still-empty Name row was read
## instead. So every choice of row per star is tried.
func _note_fact_entailed(f: Dictionary) -> Dictionary:
    var stars: Array = []
    for key in ["s", "a", "mid", "b"]:
        if f.has(key) and not stars.has(int(f[key])):
            stars.append(int(f[key]))
    var choices: Array = []
    for s in stars:
        var rows: Array = _owner_frames_all(int(s), str(f.get("kind", "")) == "ordinal_exact")
        if rows.is_empty():
            rows = [{}]
        choices.append(rows)
    var pick: Array = []
    for _c in choices:
        pick.append(0)
    var result: Dictionary = {"known": false}
    while true:
        _scoring_frames = {}
        for i in stars.size():
            _scoring_frames[int(stars[i])] = (choices[i] as Array)[int(pick[i])]
        result = _note_fact_entailed_picked(f)
        if not bool(result["known"]) or bool(result["value"]):
            break
        var p: int = pick.size() - 1
        while p >= 0 and int(pick[p]) == (choices[p] as Array).size() - 1:
            pick[p] = 0
            p -= 1
        if p < 0:
            break
        pick[p] = int(pick[p]) + 1
    _scoring_frames = {}
    return result


## The rows chosen for the current try of _note_fact_entailed.
var _scoring_frames: Dictionary = {}
## The search terms of the clue being scored, or empty when a fact is judged
## with no clue in hand. See _owner_frames_all.
var _scoring_clue_terms: Array = []

func _scoring_frame(star: int) -> Dictionary:
    return _scoring_frames.get(star, {})


## Every row on the board that stands for a star, one frame each: its Name row,
## its map star's row (when a colour or Listened pitch only it has would let a
## clue point at it), the entry of its label note.
##
## The label-note entry is offered ONLY for the fact that is the label itself
## (ordinal_exact, "... is the star that fires T-th note"). For any other fact
## it would be circular: which note is a star's label is read off the melody,
## so judging "Alpha first fires within the first 2 notes" against the entry of
## Alpha's own first note answers yes before the player has done anything.
func _owner_frames_all(star: int, with_label_note: bool = false) -> Array:
    var out: Array = []
    if star < 0 or star >= _host._star_count:
        return out
    var terms: Array = [_descriptor_term(ConstellationLogicPuzzle.Category.NAME, star),
        _descriptor_term(ConstellationLogicPuzzle.Category.COLOR, star),
        _descriptor_term(ConstellationLogicPuzzle.Category.PITCH, star)]
    var label_note: int = _label_note_for_star(star)
    if with_label_note and label_note > 0:
        terms.append("S:%d" % label_note)
    # Scoring ONE CLUE (_scoring_clue_terms set by _clue_coverage): only the
    # rows that clue itself points at count, exactly as for its hint step. A
    # fact the board happens to hold on some other, unjoined row for the same
    # star is not yet recorded where the clue's reader would look -- counting
    # it made clues drop out of the hint finder early (measured 2026-10-12).
    if not _scoring_clue_terms.is_empty():
        terms = []
        var all_terms: Array = [_descriptor_term(ConstellationLogicPuzzle.Category.NAME, star),
            _descriptor_term(ConstellationLogicPuzzle.Category.COLOR, star),
            _descriptor_term(ConstellationLogicPuzzle.Category.PITCH, star)]
        for at in all_terms:
            if str(at) != "" and _scoring_clue_terms.has(at):
                terms.append(at)
        # The label-note entry only when it is the clue's SOLE way of naming
        # the star. "The star that plays E5 is the star that fires 9th note"
        # is recorded when the E5 star's row holds note 9 -- not by the entry
        # of note 9 itself, which holds note 9 by definition.
        if terms.is_empty() and label_note > 0 and _scoring_clue_terms.has("S:%d" % label_note):
            terms.append("S:%d" % label_note)
    for term in terms:
        if str(term) == "":
            continue
        var fr: Dictionary = _owner_frame(star, {"search_terms": [term]})
        if not fr.is_empty():
            out.append(fr)
    return out


func _note_fact_entailed_picked(f: Dictionary) -> Dictionary:
    var kind: String = str(f.get("kind", ""))
    var solver = _hint_solver_for(_host._star_count)
    match kind:
        "ordinal_pair_set":
            # Built from the first-note table, which this board does not use;
            # the same clue's firing_relation carries what the sentence says.
            return {"known": true, "value": true}
        "ordinal_exact", "ordinal_neg", "ordinal_either_or", "ordinal_range", "firing_position":
            var star: int = int(f.get("s", -1))
            var fr: Dictionary = _scoring_frame(star)
            if fr.is_empty():
                return {"known": true, "value": false}
            var all_sets: Dictionary = _owner_sets(fr)
            if bool(all_sets["ok"]):
                var sets: Array = all_sets["sets"]
                if sets.is_empty():
                    return {"known": true, "value": false}
                for one in sets:
                    if not _owner_unary_holds(solver, star, one, [f]):
                        return {"known": true, "value": false}
                return {"known": true, "value": true}
            # Count unknown: only what the row's own notes settle outright.
            var held: Array = fr["held"]
            var open: Array = fr["open"]
            # The row's first note is settled when its earliest possible note
            # is one it holds; labels are about that first note (2026-10-14).
            var first_settled: int = -1
            if not (held + open).is_empty() and held.has(int((held + open).min())):
                first_settled = int((held + open).min())
            match kind:
                "ordinal_exact":
                    return {"known": true, "value": first_settled == _label_note_for_rank0(int(f["r"]))}
                "ordinal_neg":
                    var tn: int = _label_note_for_rank0(int(f["r"]))
                    var held_earlier: bool = not held.is_empty() and int(held.min()) < tn
                    return {"known": true, "value": (fr["ruled"] as Array).has(tn) or held_earlier}
                "ordinal_either_or":
                    return {"known": true, "value": first_settled > 0 and (first_settled == _label_note_for_rank0(int(f["r1"])) or first_settled == _label_note_for_rank0(int(f["r2"])))}
                "ordinal_range":
                    var good: bool = true
                    if int(f["lo"]) > 0:
                        for t in held + open:
                            if int(t) < _label_note_for_rank0(int(f["lo"])):
                                good = false
                    if int(f["hi"]) < _host._star_count - 1:
                        var has_early: bool = false
                        for t2 in held:
                            if int(t2) <= _label_note_for_rank0(int(f["hi"])):
                                has_early = true
                        good = good and has_early
                    return {"known": true, "value": good}
            return {"known": true, "value": false}
        "ordinal_cmp", "ordinal_chain":
            var pairs: Array = []
            if kind == "ordinal_cmp":
                var later: int = int(f["a"]) if bool(f["a_gt_b"]) else int(f["b"])
                var earlier: int = int(f["b"]) if bool(f["a_gt_b"]) else int(f["a"])
                pairs.append([later, earlier])
            else:
                pairs.append([int(f["mid"]), int(f["a"])])
                pairs.append([int(f["b"]), int(f["mid"])])
            for pr in pairs:
                var fl: Dictionary = _scoring_frame(int(pr[0]))
                var fe: Dictionary = _scoring_frame(int(pr[1]))
                if fl.is_empty() or fe.is_empty() or (fe["held"] as Array).is_empty():
                    return {"known": true, "value": false}
                var later_poss: Array = (fl["held"] as Array) + (fl["open"] as Array)
                if later_poss.is_empty() or int((fe["held"] as Array).min()) >= int(later_poss.min()):
                    return {"known": true, "value": false}
            return {"known": true, "value": true}
        "firing_relation":
            var fa: Dictionary = _scoring_frame(int(f.get("a", -1)))
            var fb: Dictionary = _scoring_frame(int(f.get("b", -1)))
            if fa.is_empty() or fb.is_empty():
                return {"known": true, "value": false}
            # Entailed only once both rows hold every note their stars fire on.
            var ca: Array = fa["counts"]
            var cb: Array = fb["counts"]
            if ca.size() != 1 or cb.size() != 1 \
                    or (fa["held"] as Array).size() != int(ca[0]) or (fb["held"] as Array).size() != int(cb[0]):
                return {"known": true, "value": false}
            return {"known": true, "value": _owner_pair_holds(solver, f, {int(f["a"]): fa["held"], int(f["b"]): fb["held"]})}
    return {"known": false}


## Cached result of the last hint_full_chain() computation. Same one-slot,
## invalidate-on-_clear_deduction_caches() lifetime as every other cache in
## this file (_coverage_cache, _star_positions_cache, ...) -- valid exactly
## while the player's own notes haven't changed. Needed for real: measured
## 2026-09-27, an early-game chain on an 18-star puzzle costs ~5s to build
## (~70-90ms per step, up to ~70 steps), and the Hint tab recomputes on every
## repaint while it is showing a chain -- without this, switching tabs and
## back would re-pay that cost for no reason.
var _hint_chain_cache: Array[Dictionary] = []
var _hint_chain_cache_valid: bool = false

## Diagnostic only: real (non-cached) computations since this engine was
## created. Lets a test assert the cache is doing its job without relying on
## wall-clock timing.
var hint_chain_computations: int = 0


## HINT SUPPORT (tier 5, "walk me through every step"). Tier 4 stops at the
## single best step; measured (and reported, 2026-09-27) as not explicit
## enough, since further steps are often immediately reachable from the one it
## just gave. This applies hint_next_steps' best step to a WORKING COPY of the
## boards, re-derives, and repeats -- literally automating what a player would
## get by pressing tier 4 over and over -- and returns the whole reachable
## chain in the order they would reach it.
##
## Sound by construction: every entry is a real hint_next_steps() result at the
## point it was found, over a board built only from applying EARLIER entries in
## this same chain (never ground truth). Terminates because each entry removes
## at least one True cell from a finite board (max_steps is a safety valve
## only, never expected to bind).
func hint_full_chain(clues: Array, max_steps: int = 200) -> Array[Dictionary]:
    if _hint_chain_cache_valid:
        return _hint_chain_cache
    hint_chain_computations += 1
    if _notes_hidden():
        # No working copy of the note rows exists yet to apply a step to and
        # search again, so this is every step available on the board AS IT IS,
        # best first -- not the steps those would unlock in turn.
        _hint_chain_cache = hint_next_steps(clues)
        _hint_chain_cache_valid = true
        return _hint_chain_cache
    var boards: Dictionary = {"seq": _player_sequence_grid(), "name": _player_name_grid(), "rank": _player_rank_grid(),
        "ticks": _player_tick_board()}
    var chain: Array[Dictionary] = []
    for _i in max_steps:
        var steps: Array[Dictionary] = hint_next_steps(clues, boards)
        if steps.is_empty():
            break
        var step: Dictionary = steps[0]
        chain.append(step)
        _apply_step_to_boards(step, boards)
    _hint_chain_cache = chain
    _hint_chain_cache_valid = true
    return chain


## The player's Name board as a name x star grid: grid[name][star] is true
## while the player's own notes still allow that name on that map star. A name
## with no record narrowing it is all-true (unknown, never "no stars").
func _player_name_grid() -> Array:
    var n: int = _host._star_count
    var grid: Array = []
    for name_idx in n:
        var row: Array = []
        row.resize(n)
        for s in n:
            row[s] = false
        for s2 in _stars_possible_for_descriptor(ConstellationLogicPuzzle.Category.NAME, name_idx):
            if int(s2) >= 0 and int(s2) < n:
                row[int(s2)] = true
        grid.append(row)
    return grid


## Is this row constraint ALREADY TRUE of everything the player's board still
## allows? Every open star is inside the allowed set (or outside the excluded
## one). A constraint that rules nothing out because it is trivial (allowed =
## every star, nothing excluded) is NOT entailed -- it says nothing, which is
## "not enough known yet", not "already known".
func _row_constraint_entailed(row: Array, c: Dictionary) -> bool:
    var open: Array = []
    for s in row.size():
        if bool(row[s]):
            open.append(s)
    if open.is_empty():
        return false
    if c.has("allowed"):
        var allowed: Dictionary = {}
        for a in c["allowed"]:
            allowed[int(a)] = true
        if allowed.size() >= row.size():
            return false
        for s2 in open:
            if not allowed.has(int(s2)):
                return false
        return true
    var excluded: Array = c.get("excluded", [])
    if excluded.is_empty():
        return false
    for s3 in open:
        if excluded.has(int(s3)):
            return false
    return true


## The same for a pair constraint: every star still open to BOTH rows lies in one
## known group (same) or in known groups that cannot meet (different). An unknown
## group (-1) means the player cannot tell, so it is never entailed.
func _pair_constraint_entailed(c: Dictionary, grids: Dictionary) -> bool:
    var mine: Array = grids[c["grid"]][int(c["row"])]
    var groups_a: Dictionary = {}
    for s in mine.size():
        if bool(mine[s]):
            var g: int = int(c["group_of"][s])
            if g < 0:
                return false
            groups_a[g] = true
    var groups_b: Dictionary = {}
    if c.has("other_fixed"):
        for f in c["other_fixed"]:
            var gf: int = int(c["group_of"][int(f)])
            if gf < 0:
                return false
            groups_b[gf] = true
    else:
        var other: Array = grids[c["other_grid"]][int(c["other_row"])]
        for t in other.size():
            if bool(other[t]):
                var gt: int = int(c["group_of"][t])
                if gt < 0:
                    return false
                groups_b[gt] = true
    if groups_a.is_empty() or groups_b.is_empty():
        return false
    if bool(c["same"]):
        return groups_a.size() == 1 and groups_b.size() == 1 and groups_a.keys()[0] == groups_b.keys()[0]
    for k in groups_a:
        if groups_b.has(k):
            return false
    return true


## The stars a Sequence fact is ABOUT (its subject, partner and neighbour fields).
func _fact_star_ids(f: Dictionary) -> Array:
    var out: Array = []
    var n: int = _host._star_count
    for k in ["s", "a", "b", "mid"]:
        if f.has(k) and int(f[k]) >= 0 and int(f[k]) < n and not out.has(int(f[k])):
            out.append(int(f[k]))
    for k2 in ["neighbors", "stars"]:
        if f.get(k2) is Array:
            for x in (f[k2] as Array):
                if int(x) >= 0 and int(x) < n and not out.has(int(x)):
                    out.append(int(x))
    return out


## The player's three boards after the alldiff closure the finder itself starts
## from: name x star, position x star, and star x position. Entailment must be
## judged on THESE, not on the raw notes: with 14 of 15 names pinned the last
## name has exactly one star left, but only after closure does the board say so
## (measured: read raw, a name showed 15 open stars and nothing was ever judged
## entailed on a real late-game board). {} if the board contradicts itself.
func _closed_boards() -> Dictionary:
    var solver = _hint_solver_for(_host._star_count)
    var out: Dictionary = {"name": _player_name_grid(), "rank": _player_rank_grid(), "seq": _player_sequence_grid()}
    for k in out:
        if not solver._alldiff_eliminate(out[k]):
            return {}
    return out


## Does this clue say ONLY what the player's (closed) board already entails?
## Every part that can be checked must hold, and at least one part must be
## checkable: a clue with nothing checkable is "unknown", not "known".
##
## A Sequence fact is entailed once every star it is about has a single position
## left: clues are true, so a fact about fully-placed stars is already known.
## distance_hop is left to the engine (it settles those into the board itself).
func _clue_entailed(clue: Dictionary, closed: Dictionary) -> bool:
    if closed.is_empty():
        return false
    var checkable: int = 0
    for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if not (f is Dictionary):
            continue
        var kind: String = str((f as Dictionary).get("kind", ""))
        if kind.begins_with("ordinal_"):
            checkable += 1
            var stars: Array = _fact_star_ids(f)
            if stars.is_empty():
                return false
            for s in stars:
                var open_ranks: int = 0
                for r in (closed["seq"][int(s)] as Array).size():
                    if bool(closed["seq"][int(s)][r]):
                        open_ranks += 1
                if open_ranks != 1:
                    return false
        elif kind == "distance_hop":
            checkable += 1
            if not _disclosure_satisfied(f):
                return false
    for c in _name_constraints_for_clue(clue):
        if c.has("other"):
            continue
        checkable += 1
        if not _row_constraint_entailed(closed["name"][int(c["row"])], c):
            return false
    for c2 in _position_constraints_for_clue(clue):
        checkable += 1
        if not _row_constraint_entailed(closed["rank"][int(c2["row"])], c2):
            return false
    for c3 in _joint_constraints_for_clue(clue):
        checkable += 1
        if not _pair_constraint_entailed(c3, closed):
            return false
    return checkable > 0


## How many clues are still waiting, and how many of those already say only what
## the player's board entails. Used when there is no step to give: those clues are
## not a deduction to make, they are things the player may simply not have noted.
func hint_waiting_breakdown(clues: Array) -> Dictionary:
    var waiting: Array[int] = clue_indices_with_something_to_give(clues)
    var closed: Dictionary = _closed_boards()
    var entailed: int = 0
    for ci in waiting:
        if _clue_entailed(clues[ci], closed):
            entailed += 1
    return {"waiting": waiting.size(), "entailed": entailed}


## HINT-ONLY comparison mode: pretend every star's pitch is known. Off in
## normal use, so the hints keep the engine's own rule (a pitch only counts once
## the player has Listened to that star). hint_pitch_blocked() flips it on for
## one comparison run to learn whether Listening is what stands between the
## player and a step. Never left on: it is always restored.
var _hint_assume_pitch_known: bool = false


func _hint_knows_pitch(star: int) -> bool:
    return _hint_assume_pitch_known or _player_knows_star_pitch(star)


## _stars_possible_for_descriptor, except that in comparison mode a PITCH
## descriptor is looked up against every star's true pitch instead of only the
## Listened ones.
func _hint_possible_stars(cat: int, star: int) -> Array:
    if _hint_assume_pitch_known and cat == ConstellationLogicPuzzle.Category.PITCH:
        var key: int = _raw_group_key(cat, star)
        var out: Array = []
        for s in _host._star_count:
            if _raw_group_key(cat, s) == key:
                out.append(s)
        return out
    return _stars_possible_for_descriptor(cat, star)


func _unlistened_star_count() -> int:
    var n: int = 0
    for s in _host._star_count:
        if not _player_knows_star_pitch(s):
            n += 1
    return n


## True when the player is being held up by pitch they have not Listened to
## for: some star is unlistened, and the hints would find MORE (steps or ruled-
## out cells) if every pitch were known. The caller uses it only when no step is
## available now, i.e. when progress genuinely requires it.
func hint_pitch_blocked(clues: Array) -> bool:
    if _unlistened_star_count() == 0:
        return false
    var now: Array[Dictionary] = hint_next_steps(clues)
    var now_gain: int = 0
    for st in now:
        now_gain += int(st["gain"])
    _hint_assume_pitch_known = true
    var assumed: Array[Dictionary] = hint_next_steps(clues)
    _hint_assume_pitch_known = false
    var assumed_gain: int = 0
    for st2 in assumed:
        assumed_gain += int(st2["gain"])
    return assumed_gain > now_gain


## Which map stars a group ("colour k", "pitch k", "the rank-k position")
## could contain, as far as the PLAYER knows. Returns {"maybe": stars that
## could be members, "certain": stars known to be members}, or {} when the
## group has no handle star. The handle star is the disclosure's own way of
## naming a value (see the note above _stars_possible_for_descriptor): it only
## keys the lookup, and everything returned comes from the player's board.
##   Colour   painted on the map, so exact: maybe == certain.
##   Pitch    only Listened stars can be counted as certain members; an
##            unlistened star stays a maybe.
##   Position a group of one star, certain only once the player has narrowed
##            "the star that fires r-th" to a single star.
func _group_members_for_player(cat: int, key: int) -> Dictionary:
    var handle: int = -1
    for s in _host._star_count:
        var k: int = -1
        if cat == ConstellationLogicPuzzle.Category.SEQUENCE:
            k = int(_host._sequence_rank_solution[s]) if s < _host._sequence_rank_solution.size() else -1
        else:
            k = _raw_group_key(cat, s)
        if k == key:
            handle = s
            break
    if handle < 0:
        return {}
    var maybe: Array = _hint_possible_stars(cat, handle)
    var certain: Array = []
    match cat:
        ConstellationLogicPuzzle.Category.COLOR:
            certain = maybe.duplicate()
        ConstellationLogicPuzzle.Category.PITCH:
            for m in maybe:
                if _hint_knows_pitch(int(m)):
                    certain.append(int(m))
        ConstellationLogicPuzzle.Category.SEQUENCE:
            if maybe.size() == 1:
                certain = maybe.duplicate()
    return {"maybe": maybe, "certain": certain, "handle": handle}


## How a group reads in a sentence. Only ever built from a group the clue itself
## states, so it names nothing the clue does not.
func _group_phrase(cat: int, key: int, handle: int) -> String:
    match cat:
        ConstellationLogicPuzzle.Category.COLOR:
            var t: String = _descriptor_term(cat, handle)
            return "a %s star" % t.substr(2).to_lower() if t != "" else "a star of that colour"
        ConstellationLogicPuzzle.Category.PITCH:
            var tp: String = _descriptor_term(cat, handle)
            return "a star with pitch %s" % tp.substr(2) if tp != "" else "a star with that pitch"
        ConstellationLogicPuzzle.Category.SEQUENCE:
            return _seq_noun(key + 1)
    return "a star in that group"


## A star the way the player can see it: by its painted colour. The only
## visible identity a star has, so a unique colour names it outright and a
## shared one says how many share it.
##
## `board` is the player's name x star grid. When every OTHER star of the same
## colour is already claimed by a name the player has pinned, the star is
## named by exclusion ("the yellow star that is not Beta's"), which says which
## one it is; otherwise it only says how many share the colour.
func _visible_star_phrase(star: int, board: Array = []) -> String:
    if star < 0 or star >= _host._star_colors.size():
        return ""
    var color_idx: int = int(_host._star_colors[star])
    var label: String = str(_host.COLOR_NAME_LABELS[color_idx]).to_lower()
    var others: Array = []
    for s in _host._star_colors.size():
        if s != star and int(_host._star_colors[s]) == color_idx:
            others.append(s)
    if others.is_empty():
        return "the %s star" % label
    if not board.is_empty():
        var owners: Array[String] = []
        for o in others:
            var owner: int = -1
            for nm in board.size():
                var open_stars: int = 0
                var only: int = -1
                for c in (board[nm] as Array).size():
                    if bool(board[nm][c]):
                        open_stars += 1
                        only = c
                if open_stars == 1 and only == int(o):
                    owner = nm
                    break
            if owner < 0:
                break
            owners.append(_describe_star(owner) + "'s")
        if owners.size() == others.size():
            return "the %s star that is not %s" % [label, " or ".join(owners)]
    return "one of the %d %s stars" % [others.size() + 1, label]


## Stars one hop from `star` on the map (its connected stars).
func _neighbors_of(star: int) -> Array:
    var out: Array = []
    for t in _host._star_count:
        if t != star and _host.star_distance(star, t) == 1:
            out.append(t)
    return out


## True only when the PLAYER's notes put `a` strictly before `b` in every
## still-open arrangement. Unknown on either side is false, never vacuously
## true -- the same contract as _positions_strictly_before.
func _definitely_before(a: int, b: int) -> bool:
    return _positions_strictly_before(_player_positions_for_star(a), _player_positions_for_star(b))


## Every star each position predicate could still allow, given ONLY the
## player's own position knowledge: a star is dropped only when the player's
## notes CERTAINLY violate the predicate, so the set is always a superset of the
## truth. On a board with no position knowledge nothing is dropped, so these
## clues yield no step until the player has placed something.
func _stars_allowed_by_position_fact(fd: Dictionary) -> Array:
    var kind: String = str(fd.get("kind", ""))
    var out: Array = []
    for s in _host._star_count:
        match kind:
            "name_rank_range":
                var pos: Array = _player_positions_for_star(s)
                if pos.is_empty():
                    out.append(s)
                    continue
                var lo: int = int(fd.get("lo", 0)) + 1
                var hi: int = int(fd.get("hi", 0)) + 1
                for p in pos:
                    if int(p) >= lo and int(p) <= hi:
                        out.append(s)
                        break
            "name_rank_set":
                var set_pos: Array = _player_positions_for_star(s)
                if set_pos.is_empty():
                    out.append(s)
                    continue
                var fits: bool = false
                for p2 in set_pos:
                    for al in (fd.get("allowed", []) as Array):
                        if int(al) + 1 == int(p2):
                            fits = true
                            break
                    if fits:
                        break
                if fits:
                    out.append(s)
            "name_nbr_count":
                # Exactly k of its connected stars fire before it. Bound the
                # count by what is certain (definitely before) and what is
                # still open (neither certainly before nor certainly after).
                var k: int = int(fd.get("k", -1))
                var before: int = 0
                var unsure: int = 0
                for t in _neighbors_of(s):
                    if _definitely_before(int(t), s):
                        before += 1
                    elif not _definitely_before(s, int(t)):
                        unsure += 1
                if before <= k and k <= before + unsure:
                    out.append(s)
            "name_nbr_extreme":
                var want_lowest: bool = bool(fd.get("want_lowest", false))
                var holds: bool = true
                for t2 in _neighbors_of(s):
                    if (want_lowest and _definitely_before(int(t2), s)) \
                            or (not want_lowest and _definitely_before(s, int(t2))):
                        holds = false
                        break
                if holds:
                    out.append(s)
    return out


## What a Firing Position fact (Form 25) says of its star, as a verb phrase:
## the notes it could FIRST fire on, read off the public note table, or -- when
## the set is too long to list -- that its firing pattern fits the clue. The
## clue's own sentence is the precise statement; this only names the allowed set.
func _firing_set_phrase(allowed: Array) -> String:
    if allowed.is_empty() or allowed.size() > 6:
        return "has a firing pattern that fits the clue"
    var notes: Array[String] = []
    for r in allowed:
        notes.append(str(_first_tick_for_rank(int(r) + 1)))
    return "%s on one of notes %s" % [_seq_rel_verb(), ", ".join(notes)]


func _position_fact_phrase(fd: Dictionary) -> String:
    match str(fd.get("kind", "")):
        "name_rank_range":
            if _seq_repeats():
                return "a star that first fires between note %d and note %d" % [
                    _first_tick_for_rank(int(fd.get("lo", 0)) + 1), _first_tick_for_rank(int(fd.get("hi", 0)) + 1)]
            return "a star that %s %s to %s" % [_seq_verb(), _seq_ord(int(fd.get("lo", 0)) + 1),
                _seq_ord(int(fd.get("hi", 0)) + 1)]
        "name_rank_set":
            return "a star that %s" % _firing_set_phrase(fd.get("allowed", []))
        "name_nbr_count":
            return "a star with exactly %d of its connected stars %s before it" % [
                int(fd.get("k", 0)), "first firing" if _seq_repeats() else "firing"]
        "name_nbr_extreme":
            return "a star that %s %s all of its connected stars" % [_seq_rel_verb(), "before" if bool(fd.get("want_lowest", false)) else "after"]
    return "a star that fits"


## "fires before / after every star of a group" and "earliest / latest in its
## own group". Only CERTAIN members can rule a star out (the claim is universal
## over members, so a possible-but-unproven member proves nothing); the extreme
## kind also needs the subject to BE a member, so it starts from the maybe-set.
## Returns {"allowed", "phrase"} or {} if the group has no handle.
func _stars_allowed_by_group_order_fact(fd: Dictionary) -> Dictionary:
    var kind: String = str(fd.get("kind", ""))
    var cat: int = int(fd.get("cat", -1))
    var key: int = int(fd.get("group_key", -1))
    var grp: Dictionary = _group_members_for_player(cat, key)
    if grp.is_empty():
        return {}
    var certain: Array = grp["certain"]
    var noun: String = _group_phrase(cat, key, int(grp["handle"])).trim_prefix("a ")
    var allowed: Array = []
    if kind == "name_extreme_in_group":
        var want_lowest: bool = bool(fd.get("want_lowest", false))
        for s in (grp["maybe"] as Array):
            var beaten: bool = false
            for m in certain:
                if int(m) == int(s):
                    continue
                if (want_lowest and _definitely_before(int(m), int(s))) \
                        or (not want_lowest and _definitely_before(int(s), int(m))):
                    beaten = true
                    break
            if not beaten:
                allowed.append(int(s))
        var extreme_word: String = "earliest" if want_lowest else "latest"
        var extreme_phrase: String = ("%s first-firing %s" if _seq_repeats() else "%s-firing %s") % [extreme_word, noun]
        return {"allowed": allowed, "phrase": "the %s" % extreme_phrase}
    var precedes: bool = kind == "name_precedes_group"
    for s2 in _host._star_count:
        var violated: bool = false
        for m2 in certain:
            if int(m2) == s2:
                violated = true   # the name is not itself one of the group
                break
            if (precedes and _definitely_before(int(m2), s2)) \
                    or (not precedes and _definitely_before(s2, int(m2))):
                violated = true
                break
        if not violated:
            allowed.append(s2)
    return {"allowed": allowed, "phrase": "a star that %s %s every %s" % [_seq_rel_verb(), "before" if precedes else "after", noun]}


## Each star's group on Colour or Pitch as the PLAYER knows it: Colour is
## painted (always known); Pitch only for Listened stars, -1 (a wildcard) for
## the rest.
func _player_group_of(cat: int) -> Array:
    var out: Array = []
    for s in _host._star_count:
        if cat == ConstellationLogicPuzzle.Category.PITCH and not _hint_knows_pitch(s):
            out.append(-1)
        else:
            out.append(_raw_group_key(cat, s))
    return out


## The Name restrictions one clue makes, each resolved against what the player
## knows. Kinds handled: name_group, name_group_neg, descriptor_not_in_group on
## a Name subject, descriptor_either_or on a Name subject. The rest of the Name
## vocabulary (position predicates, order-vs-group, extremes, same/different
## group, distance) is a later phase. Each entry:
## {"row", "allowed"|"excluded", "phrase", "positive"}. A restriction that the
## player's knowledge cannot express yet (e.g. a negation whose group has no
## certain member) is simply omitted -- omitting only loses a step, never
## invents one.
func _name_constraints_for_clue(clue: Dictionary) -> Array:
    var out: Array = []
    var terms: Array = clue["search_terms"] if clue.get("search_terms") is Array else []
    # Equality Pair / Mutual Exclusion attach companion Name facts whose group
    # value is the TRUE colour/pitch of a star the clue does not tell the
    # player. Those clues are read by _hint_joint_steps through their own
    # participants instead; see _clue_has_values_fact.
    var companion_kinds: Array = ["name_group", "name_group_neg", "name_same_group", "name_different_group"]
    var skip_companions: bool = _clue_has_values_fact(clue)
    for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if not (f is Dictionary):
            continue
        var fd: Dictionary = f
        var kind: String = str(fd.get("kind", ""))
        if skip_companions and companion_kinds.has(kind):
            continue
        var row: int = -1
        var cat: int = -1
        var key: int = -1
        var positive: bool = true
        if kind == "name_group" or kind == "name_group_neg":
            row = int(fd.get("name_star", -1))
            cat = int(fd.get("cat", -1))
            key = int(fd.get("group_key", -1))
            positive = kind == "name_group"
        elif kind == "descriptor_not_in_group" and int(fd.get("cat", -1)) == ConstellationLogicPuzzle.Category.NAME:
            row = int(fd.get("star", -1))
            cat = int(fd.get("group_cat", -1))
            key = int(fd.get("group_key", -1))
            positive = false
        elif kind == "descriptor_either_or" and int(fd.get("cat_a", -1)) == ConstellationLogicPuzzle.Category.NAME:
            var row_e: int = int(fd.get("star_a", -1))
            if row_e < 0 or not terms.has(_descriptor_term(ConstellationLogicPuzzle.Category.NAME, row_e)):
                continue
            var bcat: int = int(fd.get("cat_b", -1))
            var allowed_e: Array = []
            for s_e in [int(fd.get("s1", -1)), int(fd.get("s2", -1))]:
                for st in _hint_possible_stars(bcat, s_e):
                    if not allowed_e.has(int(st)):
                        allowed_e.append(int(st))
            if not allowed_e.is_empty():
                out.append({"row": row_e, "allowed": allowed_e, "positive": true,
                    "phrase": "one of the two stars the clue names"})
            continue
        elif kind == "name_rank_range" or kind == "name_nbr_count" or kind == "name_nbr_extreme" or kind == "name_rank_set":
            var row_p: int = int(fd.get("name_star", -1))
            if row_p < 0 or not terms.has(_descriptor_term(ConstellationLogicPuzzle.Category.NAME, row_p)):
                continue
            out.append({"row": row_p, "allowed": _stars_allowed_by_position_fact(fd),
                "positive": true, "phrase": _position_fact_phrase(fd)})
            continue
        elif kind == "name_precedes_group" or kind == "name_follows_group" or kind == "name_extreme_in_group":
            var row_o: int = int(fd.get("name_star", -1))
            if row_o < 0 or not terms.has(_descriptor_term(ConstellationLogicPuzzle.Category.NAME, row_o)):
                continue
            var ordered: Dictionary = _stars_allowed_by_group_order_fact(fd)
            if ordered.is_empty():
                continue
            out.append({"row": row_o, "allowed": ordered["allowed"], "positive": true, "phrase": ordered["phrase"]})
            continue
        elif kind == "name_same_group" or kind == "name_different_group":
            var name_a: int = int(fd.get("name_star_a", -1))
            var name_b: int = int(fd.get("name_star_b", -1))
            var pcat: int = int(fd.get("cat", -1))
            var nterm_a: String = _descriptor_term(ConstellationLogicPuzzle.Category.NAME, name_a)
            var nterm_b: String = _descriptor_term(ConstellationLogicPuzzle.Category.NAME, name_b)
            if name_a < 0 or name_b < 0 or not terms.has(nterm_a) or not terms.has(nterm_b):
                continue
            if pcat != ConstellationLogicPuzzle.Category.COLOR and pcat != ConstellationLogicPuzzle.Category.PITCH:
                continue
            var same_kind: bool = kind == "name_same_group"
            var gof: Array = _player_group_of(pcat)
            var word: String = _category_word(pcat)
            # One constraint per direction, so each name gets its own sentence.
            out.append({"row": name_a, "other": name_b, "same": same_kind, "group_of": gof,
                "positive": same_kind, "phrase": "a star that shares its %s with %s" % [word, _describe_star(name_b)]})
            out.append({"row": name_b, "other": name_a, "same": same_kind, "group_of": gof,
                "positive": same_kind, "phrase": "a star that shares its %s with %s" % [word, _describe_star(name_a)]})
            continue
        else:
            continue
        if row < 0 or row >= _host._star_count or cat < 0 or key < 0:
            continue
        if not terms.has(_descriptor_term(ConstellationLogicPuzzle.Category.NAME, row)):
            continue   # never name a star the clue does not
        var grp: Dictionary = _group_members_for_player(cat, key)
        if grp.is_empty():
            continue
        var phrase: String = _group_phrase(cat, key, int(grp["handle"]))
        if positive:
            out.append({"row": row, "allowed": grp["maybe"], "positive": true, "phrase": phrase})
        elif not (grp["certain"] as Array).is_empty():
            out.append({"row": row, "excluded": grp["certain"], "positive": false, "phrase": phrase})
    return out


## The player's Sequence board as a position x star grid: grid[rank][star] is
## true while the player's notes still allow that star at that position. The
## transpose of _player_sequence_grid, because a clue about "the star that
## fires 7th" restricts a POSITION's candidate stars, not a star's positions.
func _player_rank_grid() -> Array:
    var by_star: Array = _player_sequence_grid()
    var n: int = _host._star_count
    var grid: Array = []
    for r in n:
        var row: Array = []
        row.resize(n)
        for s in n:
            row[s] = bool(by_star[s][r])
        grid.append(row)
    return grid


## The restrictions a clue makes on a POSITION descriptor ("the star that fires
## 7th"): descriptor_not_in_group ("... is not blue", "... is not pitch E") and
## descriptor_either_or ("... is Alpha or Beta") with a Sequence subject. This
## is where Colour and Pitch facts land on the Sequence axis: a colour group
## says which stars a position cannot be. The subject is only ever named by the
## clue's own term (S:<n>), and group membership comes from what the player
## knows (see _group_members_for_player). Each entry: {"row": rank,
## "allowed"|"excluded", "phrase", "positive", "handle"}.
func _position_constraints_for_clue(clue: Dictionary) -> Array:
    var out: Array = []
    var terms: Array = clue["search_terms"] if clue.get("search_terms") is Array else []
    var seq: int = ConstellationLogicPuzzle.Category.SEQUENCE
    for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if not (f is Dictionary):
            continue
        var fd: Dictionary = f
        var kind: String = str(fd.get("kind", ""))
        var handle: int = -1
        if kind == "descriptor_not_in_group" and int(fd.get("cat", -1)) == seq:
            handle = int(fd.get("star", -1))
        elif kind == "descriptor_either_or" and int(fd.get("cat_a", -1)) == seq:
            handle = int(fd.get("star_a", -1))
        else:
            continue
        if handle < 0 or handle >= _host._sequence_rank_solution.size():
            continue
        if not terms.has(_descriptor_term(seq, handle)):
            continue   # never name a position the clue does not
        var rank: int = int(_host._sequence_rank_solution[handle])
        if kind == "descriptor_not_in_group":
            var gcat: int = int(fd.get("group_cat", -1))
            var gkey: int = int(fd.get("group_key", -1))
            var grp: Dictionary = _group_members_for_player(gcat, gkey)
            if grp.is_empty() or (grp["certain"] as Array).is_empty():
                continue
            out.append({"row": rank, "excluded": grp["certain"], "positive": false,
                "phrase": _group_phrase(gcat, gkey, int(grp["handle"])), "handle": handle})
        else:
            var bcat: int = int(fd.get("cat_b", -1))
            var allowed: Array = []
            for s_e in [int(fd.get("s1", -1)), int(fd.get("s2", -1))]:
                for st in _hint_possible_stars(bcat, s_e):
                    if not allowed.has(int(st)):
                        allowed.append(int(st))
            if not allowed.is_empty():
                out.append({"row": rank, "allowed": allowed, "positive": true,
                    "phrase": "one of the two stars the clue names", "handle": handle})
    return out


## Position-axis steps (Colour/Pitch/Name facts about a Sequence descriptor).
## Same shape as _hint_name_steps with rows = positions; entries carry
## axis "position" and `star` = the position index (0-based) they describe.
func _hint_position_steps(clues: Array, solver, grid: Array = []) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var board: Array = grid if not grid.is_empty() else _player_rank_grid()
    for ci in clue_indices_with_something_to_give(clues):
        var clue: Dictionary = clues[ci]
        var constraints: Array = _position_constraints_for_clue(clue)
        if constraints.is_empty():
            continue
        var step: Dictionary = _NextStepFinder.step_for_sets(solver, board, constraints)
        if not bool(step["consistent"]) or (step["eliminated"] as Array).is_empty():
            continue
        var by_row: Dictionary = {}
        for cell in step["eliminated"]:
            var rk: int = int(cell[0])
            if not by_row.has(rk):
                by_row[rk] = []
            (by_row[rk] as Array).append(int(cell[1]))
        var resolved: Dictionary = {}
        for cell2 in step["resolved"]:
            resolved[int(cell2[0])] = int(cell2[1])
        for rk2 in by_row:
            var why: Dictionary = {}
            for c in constraints:
                if int(c["row"]) == int(rk2):
                    why = c
                    break
            if why.is_empty():
                continue
            out.append({
                "axis": "position",
                "clue_index": int(ci),
                "star": int(rk2),
                "descriptor": _describe_descriptor(ConstellationLogicPuzzle.Category.SEQUENCE, int(why["handle"])),
                "eliminated_stars": by_row[rk2],
                "resolved_star": int(resolved.get(int(rk2), -1)),
                "resolved_desc": _visible_star_phrase(int(resolved.get(int(rk2), -1))),
                "resolved": int(resolved.get(int(rk2), -1)) >= 0,
                "gain": (by_row[rk2] as Array).size(),
                "phrase": str(why.get("phrase", "")),
                "positive": bool(why.get("positive", true)),
            })
    return out


## Does this clue carry an Equality Pair / Mutual Exclusion fact? Those Forms
## ALSO attach companion Name facts (name_group, name_group_neg,
## name_same_group, name_different_group) whose group_key is the TRUE colour or
## pitch of the star the other participant denotes. That value is not in the
## clue text and the player may not be able to know it ("Alpha and the star
## that fires 9th have the same colour" would announce the 9th star's colour), so
## the hints never read those companions. _hint_joint_steps reads the clue's own
## participants instead. Measured 2026-09-26 before this fix: 24 of 25
## Equality/Mutex clues across 6 puzzles produced a Name hint from a companion.
func _clue_has_values_fact(clue: Dictionary) -> bool:
    for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if f is Dictionary and ["values_same", "values_all_different"].has(str((f as Dictionary).get("kind", ""))):
            return true
    return false


## One participant of a values_same / values_all_different fact, as the CLUE
## names it: {"cat", "star", "spec"}, where spec says where its candidate stars
## live -- a NAME row, a POSITION row, or a fixed set (a given Colour/Pitch
## descriptor such as "the star that plays E5"). {} if the clue does not name it
## or names it some other way.
func _values_participant(clue: Dictionary, star: int, axis: int) -> Dictionary:
    var terms: Array = clue["search_terms"] if clue.get("search_terms") is Array else []
    var node: Dictionary = {}
    for ch in (clue["chars"] if clue.get("chars") is Array else []):
        if ch is Dictionary and int((ch as Dictionary).get("star", -1)) == star and int((ch as Dictionary).get("cat", -1)) != axis:
            node = ch
            break
    if node.is_empty():
        return {}
    var cat: int = int(node["cat"])
    var term: String = _descriptor_term(cat, star)
    if term == "" or not terms.has(term):
        return {}
    match cat:
        ConstellationLogicPuzzle.Category.NAME:
            return {"cat": cat, "star": star, "grid": "name", "row": star}
        ConstellationLogicPuzzle.Category.SEQUENCE:
            return {"cat": cat, "star": star, "grid": "rank", "row": int(_host._sequence_rank_solution[star])}
        ConstellationLogicPuzzle.Category.COLOR, ConstellationLogicPuzzle.Category.PITCH:
            return {"cat": cat, "star": star, "fixed": _hint_possible_stars(cat, star)}
    return {}


func _participant_words(p: Dictionary) -> String:
    if int(p["cat"]) == ConstellationLogicPuzzle.Category.NAME:
        return _describe_star(int(p["star"]))
    return _describe_descriptor(int(p["cat"]), int(p["star"]))


## The joint constraints of a clue's Equality Pair / Mutual Exclusion facts:
## every participant that sits on a NAME or POSITION row is related to every
## other participant, whichever kind that is. Each entry is one direction, so
## each row gets its own sentence. Empty for a clue with no such fact.
func _joint_constraints_for_clue(clue: Dictionary) -> Array:
    var out: Array = []
    for f in (clue["disclosures"] if clue.get("disclosures") is Array else []):
        if not (f is Dictionary):
            continue
        var fd: Dictionary = f
        var kind: String = str(fd.get("kind", ""))
        if kind != "values_same" and kind != "values_all_different":
            continue
        var axis: int = int(fd.get("cat", -1))
        if axis != ConstellationLogicPuzzle.Category.COLOR and axis != ConstellationLogicPuzzle.Category.PITCH:
            continue
        var stars: Array = [int(fd.get("a", -1)), int(fd.get("b", -1))] if kind == "values_same" else (fd.get("stars", []) as Array)
        var parts: Array = []
        for s in stars:
            var p: Dictionary = _values_participant(clue, int(s), axis)
            if p.is_empty():
                parts = []
                break
            parts.append(p)
        if parts.size() < 2:
            continue
        var same: bool = kind == "values_same"
        var gof: Array = _player_group_of(axis)
        var word: String = _category_word(axis)
        for i in parts.size():
            if not (parts[i] as Dictionary).has("grid"):
                continue   # a fixed participant has no row of its own to narrow
            for j in parts.size():
                if i == j:
                    continue
                var mine: Dictionary = parts[i]
                var other: Dictionary = parts[j]
                var c: Dictionary = {"grid": mine["grid"], "row": int(mine["row"]), "same": same,
                    "group_of": gof, "positive": same, "handle": int(mine["star"]),
                    "phrase": "a star that shares its %s with %s" % [word, _participant_words(other)]}
                if other.has("grid"):
                    c["other_grid"] = other["grid"]
                    c["other_row"] = int(other["row"])
                else:
                    c["other_fixed"] = other["fixed"]
                out.append(c)
    return out


## Joint Name x Position steps: the Equality Pair / Mutual Exclusion clues, read
## through their own participants (see _clue_has_values_fact for why not through
## their companion facts). `boards` is a parameter so a test can hand in
## truth-built grids: {"name": name x star, "rank": position x star}.
func _hint_joint_steps(clues: Array, solver, boards: Dictionary = {}) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var grids: Dictionary = boards if not boards.is_empty() else {"name": _player_name_grid(), "rank": _player_rank_grid()}
    for ci in clue_indices_with_something_to_give(clues):
        var clue: Dictionary = clues[ci]
        var constraints: Array = _joint_constraints_for_clue(clue)
        if constraints.is_empty():
            continue
        var step: Dictionary = _NextStepFinder.step_for_joint(solver, grids, constraints)
        if not bool(step["consistent"]) or (step["eliminated"] as Array).is_empty():
            continue
        var by_row: Dictionary = {}
        for cell in step["eliminated"]:
            var key: String = "%s:%d" % [str(cell[0]), int(cell[1])]
            if not by_row.has(key):
                by_row[key] = {"grid": str(cell[0]), "row": int(cell[1]), "stars": []}
            (by_row[key]["stars"] as Array).append(int(cell[2]))
        var resolved: Dictionary = {}
        for cell2 in step["resolved"]:
            resolved["%s:%d" % [str(cell2[0]), int(cell2[1])]] = int(cell2[2])
        for key2 in by_row:
            var entry: Dictionary = by_row[key2]
            var why: Dictionary = {}
            for c in constraints:
                if str(c["grid"]) == str(entry["grid"]) and int(c["row"]) == int(entry["row"]):
                    why = c
                    break
            if why.is_empty():
                continue
            var is_name: bool = str(entry["grid"]) == "name"
            var res_star: int = int(resolved.get(key2, -1))
            out.append({
                "axis": "name" if is_name else "position",
                "clue_index": int(ci),
                "star": int(entry["row"]),
                "descriptor": _describe_descriptor(ConstellationLogicPuzzle.Category.NAME if is_name else ConstellationLogicPuzzle.Category.SEQUENCE, int(why["handle"])),
                "eliminated_stars": entry["stars"],
                "resolved_star": res_star,
                "resolved_desc": _visible_star_phrase(res_star, grids["name"] if is_name else []),
                "resolved": res_star >= 0,
                "gain": (entry["stars"] as Array).size(),
                "phrase": str(why.get("phrase", "")),
                "positive": bool(why.get("positive", true)),
            })
    return out


## Name-axis steps for hint_next_steps, given the player's own name grid (or the
## default one). `grid` is a parameter so a test can hand in a board built from
## ground truth and check every conclusion against it.
func _hint_name_steps(clues: Array, solver, grid: Array = []) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var board: Array = grid if not grid.is_empty() else _player_name_grid()
    for ci in clue_indices_with_something_to_give(clues):
        var clue: Dictionary = clues[ci]
        var constraints: Array = _name_constraints_for_clue(clue)
        if constraints.is_empty():
            continue
        var step: Dictionary = _NextStepFinder.step_for_sets(solver, board, constraints)
        if not bool(step["consistent"]) or (step["eliminated"] as Array).is_empty():
            continue
        var by_name: Dictionary = {}
        for cell in step["eliminated"]:
            var nm: int = int(cell[0])
            if not by_name.has(nm):
                by_name[nm] = []
            (by_name[nm] as Array).append(int(cell[1]))
        var resolved: Dictionary = {}
        for cell2 in step["resolved"]:
            resolved[int(cell2[0])] = int(cell2[1])
        for nm2 in by_name:
            # Only a name the clue itself restricts is reported, and it is
            # named by the clue's own term.
            var why: Dictionary = {}
            for c in constraints:
                if int(c["row"]) == int(nm2):
                    why = c
                    break
            if why.is_empty():
                continue
            out.append({
                "axis": "name",
                "clue_index": int(ci),
                "star": int(nm2),
                "descriptor": _describe_descriptor(ConstellationLogicPuzzle.Category.NAME, int(nm2)),
                "eliminated_stars": by_name[nm2],
                "resolved_star": int(resolved.get(int(nm2), -1)),
                "resolved_desc": _visible_star_phrase(int(resolved.get(int(nm2), -1)), board),
                "resolved": int(resolved.get(int(nm2), -1)) >= 0,
                "gain": (by_name[nm2] as Array).size(),
                "phrase": str(why.get("phrase", "")),
                "positive": bool(why.get("positive", true)),
            })
    return out


func _record_is_unconfirmed_star_widget_stub(record_idx: int) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    # _build_star_widgets_impl() auto-creates a star_idx-bound record for
    # EVERY star the instant its floating widget is built
    # (_get_or_create_match_record_for_star_idx), regardless of anything
    # the player has done — so star_idx >= 0 alone is NOT proof the player
    # has legitimately confirmed that star's identity. r["name"] is a safe
    # signal: it's only ever set by a real player action
    # (_confirm_match_record_identity, or a name-slot record's own
    # defining field) — never by mere auto-creation. Without this guard,
    # _effective_name_state/_effective_pitch_state's ground-truth tier
    # (star_idx >= 0 → read the true value directly) leaks every
    # unconfirmed star's true name/pitch into _records_provably_distinct,
    # which _compute_excluded_names_for/_compute_excluded_pitches_for
    # then surface as if legitimately deduced — caught via a singleton
    # Pitch slot showing every OTHER star's Name selector as already
    # solved on a puzzle that had barely started.
    var r: Dictionary = _match_records[record_idx]
    return int(r.get("star_idx", -1)) >= 0 and str(r.get("name", "")) == ""


## True when the player has explicitly confirmed a name for this record
## via name_states, even though _propagate_name_states_confirmed_same_
## record refused to promote it into r["name"] because another record
## already owned that name (see that function's own comment). Used to
## carve this one case out of _record_is_unconfirmed_star_widget_stub's
## definition at its ONE call site that matters here — see
## _settle_identical_records(). Deliberately NOT folded into
## _record_is_unconfirmed_star_widget_stub itself: that predicate also
## gates _identity_signature()'s pitch-token generation, and a record can
## reach here with star_idx set from mere auto-creation (never Listened)
## — relaxing THAT check too would leak its true pitch through the "P:"
## token the same way the stub guard exists to prevent. Name is safe to
## check unconditionally: name_states is only ever written by an actual
## player click, never by auto-creation.
##
## FIXED (real save): "Nyxeai is claimed by 2 entries (an unplaced entry,
## slot D5 A)", permanently, with no refresh ever clearing it. Sequence:
## Listen on a star merges its record into that note's blank Sort:Pitch
## slot (_reconcile_unique_pitch_slot) — the slot survives with a real
## star_idx but name=="" (nothing had named it yet), so it now satisfies
## the stub predicate despite no longer being a bare auto-created
## placeholder. A separately-created name record already owned "Nyxeai"
## (confirmed via the pitch checklist), so naming the slot the same name
## correctly wrote name_states but was correctly refused .name promotion
## — and _settle_identical_records() then PERMANENTLY refused to ever
## true-merge the slot (its own comment: "Never fold anything into an
## auto-created star-widget stub on THIS path"), because nothing
## distinguished "genuinely still untouched" from "touched, just refused
## a duplicate write." Two records claiming one name, forever, with no
## code path that could ever reconcile them — reproduced directly via
## dev_tests/probe_scratch.gd before this fix, confirmed gone after.
func _record_has_unpromoted_name_claim(record_idx: int) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    var name_states: Dictionary = _match_records[record_idx].get("name_states", {})
    for k in name_states:
        if int(name_states[k]) == 1:
            return true
    return false


## Resolves a CLICKED melody TICK on the staff to its seq_pos (RANK) via the
## PRE-TRANSLATED _host._melody_seq_pos_sequence (a plain array of already-
## resolved seq_pos values, one per tick) -- never sequence_rank_solution
## directly. That split is load-bearing, not style: an earlier draft
## subscripted sequence_rank_solution[star_idx] right here, which the
## matrix-up lint correctly caught (D1: "a position read an identity off
## ground truth") -- see melody_seq_pos_sequence's own comment in
## constellation_logic_puzzle.gd for why the translation belongs in the
## generator instead.
##
## REPEATS ARE EARNED (author ruling 2026-10-10; this replaces the 2026-10-03
## "repeat shape is public" behaviour). What the staff gives the player is
## which notes are a star's FIRST firing, and so the order stars first fire in.
## Which earlier star a REPEAT note belongs to is not given.
##
## So this returns what the BOARD knows about a note: the public rank for a
## first firing; for a repeat note, the position the player has pinned it to,
## or 0 while that is still open. Every caller must treat 0 as "not known".
## Falls back to the tick itself when there is no precomputed array (old
## cache, or a clean 1:1 melody where tick and rank coincide).
func _seq_pos_for_melody_tick(tick: int) -> int:
    if _notes_hidden():
        return 0   # no note says where its star comes in the firing order
    if _host._melody_seq_pos_sequence.is_empty():
        return tick
    var event_idx: int = tick - 1
    if event_idx < 0 or event_idx >= _host._melody_seq_pos_sequence.size():
        return tick
    if not _tick_is_first_fire(tick):
        return _pinned_seq_pos_for_repeat_tick(tick)
    var resolved: int = int(_host._melody_seq_pos_sequence[event_idx])
    return resolved if resolved > 0 else tick


## FIRST NOTES ARE HIDDEN (author ruling 2026-10-12). On a repeating melody the
## player is never told which notes are a star's first firing, and the game
## must not act on it for them. So the board keeps NO firing-order position on
## such a melody: what it knows about Sequence is which notes a record holds
## (melody_ticks) and which it is marked as not firing on (seq_note_blocks),
## nothing else. While this is true:
##   - a clicked note opens a blank entry (_settle_melody_tick_positions is off)
##   - _seq_pos_for_melody_tick answers 0 for every note
##   - every note is the same kind of button (_repeat_note_state_for_record)
##   - the hint finder is off (it reasons about firing-order positions)
## False on a 1:1 melody, where note and position are the same thing and
## nothing is hidden. `notes_hidden_enabled` false is a TEST SEAM for the
## older behaviour, which told the player the first notes.
var notes_hidden_enabled: bool = true

func _notes_hidden() -> bool:
    return notes_hidden_enabled and _seq_repeats()


## Is this note a star's FIRST firing? NOT player-facing since 2026-10-12 (see
## _notes_hidden): nothing shown or derived for the player may call this on a
## repeating melody. Kept for the seam, and for a 1:1 melody where it is true
## of every note.
func _tick_is_first_fire(tick: int) -> bool:
    var table: Array = _host._melody_seq_pos_sequence
    var idx: int = tick - 1
    if idx < 0 or idx >= table.size():
        return true
    var here: int = int(table[idx])
    for i in idx:
        if int(table[i]) == here:
            return false
    return true


## The position the player has pinned a repeat note to, or 0. "Pinned" is the
## note's own record being down to one position, by typing or by deduction.
func _pinned_seq_pos_for_repeat_tick(tick: int) -> int:
    var idx: int = _find_match_record_by_melody_tick(tick)
    if idx < 0:
        return 0
    var s: Array = _seq_candidate_set_for(idx)
    return int(s[0]) if s.size() == 1 else 0


## How many times the board knows this record's star fires, or -1. Known means
## the count Listen gave, or a Repeats value confirmed on the record.
func _known_fire_count_for_record(record_idx: int) -> int:
    var given: int = _repeat_given_for_record(record_idx)
    if given >= 0:
        return given + 1
    for v in _repeat_values_shown():
        if _effective_repeat_state(record_idx, int(v)) == 1:
            return int(v) + 1
    return -1


## What the board says about "does this record's star fire on note `tick`?" --
## for EVERY note when the first notes are hidden (_notes_hidden), for repeat
## notes only under the seam. The state of that note's button on the record's
## Sequence row and in the Staff popup's "Same star as note" row
## (2026-10-12: every note is on the row; a first note is the position set).
##   0  open
##   1  yes: the record holds the note, or the note's own record and this one
##      are both down to the same single position
##   2  no, by deduction: the note's own record is provably another star, or
##      shares no position with this one
##   3  no, by the player's own mark on this record (seq_note_blocks)
## The reverse link from a known repeat COUNT is deliberately not applied here:
## it stays a hint step (ruling 2026-10-11).
func _repeat_note_state_for_record(record_idx: int, tick: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    var r: Dictionary = _match_records[record_idx]
    if (r.get("melody_ticks", []) as Array).has(tick):
        return 1
    if (r.get("seq_note_blocks", []) as Array).has(tick):
        return 3
    # THE COUNT CAPS THE ROW (author ruling 2026-10-12, replacing the earlier
    # "hint step only"): a star known to fire n times that already holds n
    # notes fires on no other.
    var fires: int = _known_fire_count_for_record(record_idx)
    if fires > 0 and (r.get("melody_ticks", []) as Array).size() >= fires:
        return 2
    var note_rec: int = _find_match_record_by_melody_tick(tick)
    if _notes_hidden():
        # No positions on this board: the only deduction left is identity.
        return 2 if note_rec >= 0 and _records_provably_distinct(record_idx, note_rec) else 0
    var mine: Array = _effective_seq_candidates(record_idx)
    if note_rec >= 0:
        var theirs: Array = _effective_seq_candidates(note_rec)
        if mine.size() == 1 and theirs.size() == 1 and int(mine[0]) == int(theirs[0]):
            return 1
        if _records_provably_distinct(record_idx, note_rec):
            return 2
        var shared: bool = false
        for p in mine:
            if theirs.has(p):
                shared = true
                break
        if not shared:
            return 2
    # NOT applied (author, 2026-10-12): "this star cannot have first fired
    # before the note". It made ruling out note 1 on a row silently remove
    # note 2 as well, on the strength of note 2 being a repeat note -- which
    # the player is not shown.
    return 0


## Every note the board knows a position fires on: its first note, plus each
## repeat note the player has pinned to it.
func _known_ticks_for_rank(seq_pos: int) -> Array:
    var out: Array = [_first_tick_for_rank(seq_pos)]
    for tick in range(1, _melody_tick_count() + 1):
        if not _tick_is_first_fire(tick) and _pinned_seq_pos_for_repeat_tick(tick) == seq_pos:
            out.append(tick)
    return out


## The Sort tabs' melody-tick domain size (matches _draw_melody_staff's own
## tick_count): the real melody length when known, else star_count. A single
## source for this so every Seq.-field entry point (range/candidate commit,
## bound validation) agrees with the staff on how many ticks exist.
func _melody_tick_count() -> int:
    return _host._melody_seq_pos_sequence.size() if not _host._melody_seq_pos_sequence.is_empty() else _host._star_count


## True when the melody has more notes than stars (every Beginner
## constellation): some star fires more than once, so a Sequence statement
## about ORDER means the star's FIRST note.
func _seq_repeats() -> bool:
    return _melody_tick_count() > _host._star_count


## The first note a rank fires on -- the number a clue prints to name it, and
## public (see _seq_pos_for_melody_tick). Falls back to the rank itself with no
## table. A position's LATER notes are not readable here on purpose: they are
## what the player works out (_known_ticks_for_rank is the board's view).
func _first_tick_for_rank(seq_pos: int) -> int:
    var table: Array = _host._melody_seq_pos_sequence
    for i in table.size():
        if int(table[i]) == seq_pos:
            return i + 1
    return seq_pos


## How many stars have fired for the first time by note `tick` (inclusive): the
## highest rank among notes 1..tick, because ranks first appear in rank order.
## "Fires after note N" therefore means rank >= this + 1. With no table, rank
## and note coincide.
func _stars_begun_by_tick(tick: int) -> int:
    var table: Array = _host._melody_seq_pos_sequence
    if table.is_empty():
        return clampi(tick, 0, _host._star_count)
    var best: int = 0
    for i in mini(maxi(tick, 0), table.size()):
        best = maxi(best, int(table[i]))
    return best


## Wording for a Sequence value, in staff notes. A star is named by its FIRST
## note, matching ConstellationLogicPuzzle._seq_first_tick; a 1:1 melody gives
## exactly the original text.
func _seq_verb() -> String:
    return "fires"


## The bare form, for "does NOT ___".
func _seq_verb_base() -> String:
    return "fire"


## Relational wording (order between stars is FIRST-firing order): "first
## fires" when the melody repeats, so "A fires before B" is never ambiguous.
func _seq_rel_verb() -> String:
    return "first fires" if _seq_repeats() else "fires"


## The same relational verb for ONE named star: "first fires" only if THAT star
## actually fires more than once, as in the generator's clue wording
## (ConstellationLogicPuzzle._seq_verb_for). Used by the dev explainer's lines
## about named stars; the hint phrases about unnamed stars keep _seq_rel_verb().
func _seq_rel_verb_for(star: int) -> String:
    if star >= 0 and star < _host._repeat_count.size() and int(_host._repeat_count[star]) > 0:
        return "first fires"
    return "fires"


func _seq_rel_verb_base() -> String:
    return "first fire" if _seq_repeats() else "fire"


## "10th note" -- the star's first note.
func _seq_ord(rank1: int) -> String:
    return ConstellationLogicPuzzle._ordinal(_first_tick_for_rank(rank1))


## "the star that fires 10th note".
func _seq_noun(rank1: int) -> String:
    var star: int = _host._sequence_rank_solution.find(rank1 - 1)
    if star >= 0 and _seq_repeats():
        return _label_phrase_for_star(star, _first_tick_for_rank(rank1))
    return "the star that fires %s" % _seq_ord(rank1)


## Every note the board knows a rank fires on: "8th note", or "notes 8, 10, 12"
## once the player has placed repeat notes 10 and 12 on it.
func _seq_ticks_phrase(rank1: int) -> String:
    var ticks: Array = _known_ticks_for_rank(rank1)
    if ticks.size() == 1:
        return ConstellationLogicPuzzle._ordinal(int(ticks[0]))
    var parts := PackedStringArray()
    for t in ticks:
        parts.append(str(t))
    return "notes %s" % ", ".join(parts)


## Inclusive RANK bounds [lo, hi] for typed staff notes, non-exact entries
## only: the lower box "N <" means the star first fires AFTER note N, the
## upper box "< M" means it first fires BEFORE note M. 0 = no bound; callers
## must reject M == 1 (nothing fires before note 1) and a lo past the last
## rank, both of which come back as an unusable bound. In a 1:1 melody this is
## exactly [N + 1, M - 1], the original arithmetic.
func _seq_bounds_for_ticks(typed_lo: int, typed_hi: int) -> Array:
    var lo: int = 0 if typed_lo <= 0 else _stars_begun_by_tick(typed_lo) + 1
    var hi: int = 0 if typed_hi <= 0 else _stars_begun_by_tick(typed_hi - 1)
    return [lo, hi]


## The note the lower bound box shows. The player's own typed note is shown
## while it still describes the bound (the star's first note must be after it,
## which is `_stars_begun_by_tick(typed) == inclusive_lo - 1`); otherwise the
## last first-note at or before the bound, so a bound narrowed by deduction
## still reads as a real note on the staff.
func _exclusive_display_lo(inclusive_lo: int, inclusive_hi: int, typed_tick: int = 0) -> int:
    if inclusive_lo <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return _first_tick_for_rank(inclusive_hi)
    var rank: int = inclusive_lo - 1
    if rank <= 0:
        return 0
    if typed_tick > 0 and _stars_begun_by_tick(typed_tick) == rank:
        return typed_tick
    return _first_tick_for_rank(rank)


## Upper-bound counterpart of _exclusive_display_lo: the typed note is kept
## while `_stars_begun_by_tick(typed - 1) == inclusive_hi`.
func _exclusive_display_hi(inclusive_lo: int, inclusive_hi: int, typed_tick: int = 0) -> int:
    if inclusive_hi <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return _first_tick_for_rank(inclusive_hi)
    var shown: int = inclusive_hi + 1
    if shown > _host._star_count:
        return 0
    if typed_tick > 0 and _stars_begun_by_tick(typed_tick - 1) == inclusive_hi:
        return typed_tick
    return _first_tick_for_rank(shown)


func _parse_exclusive_bounds(raw_lo: int, raw_hi: int) -> Array:
    if raw_lo > 0 and raw_hi > 0 and raw_lo == raw_hi:
        return [raw_lo, raw_hi]
    var lo: int = raw_lo + 1 if raw_lo > 0 else 0
    var hi: int = raw_hi - 1 if raw_hi > 0 else 0
    if lo > 0 and hi > 0 and lo > hi:
        return [0, 0]
    return [lo, hi]


func _effective_seq_bounds(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return [0, 0, []]
    var r: Dictionary = _match_records[record_idx]
    var stored_lo: int = int(r.get("seq_lo", 0))
    var stored_hi: int = int(r.get("seq_hi", 0))
    if stored_lo > 0 and stored_lo == stored_hi and (r.get("seq_candidates", []) as Array).is_empty():
        return [stored_lo, stored_hi, []]

    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return [0, 0, []]

    candidates.sort()
    var eff_lo: int = candidates[0]
    var eff_hi: int = candidates[candidates.size() - 1]

    var mid_excluded: Array = []
    for p in range(eff_lo, eff_hi + 1):
        if not candidates.has(p):
            mid_excluded.append(p)

    var display_lo: int = eff_lo if (stored_lo > 0 or eff_lo > 1) else 0
    var display_hi: int = eff_hi if (stored_hi > 0 or eff_hi < _host._star_count) else 0
    return [display_lo, display_hi, mid_excluded]


## How many times the derivation passes may re-run before giving up.
## Each round can only ADD derived facts and the fact space is finite, so
## this terminates well short of the cap in practice — it exists so a rule
## that somehow oscillates degrades into a stale frame instead of hanging
## the game.
const DERIVATION_MAX_ROUNDS: int = 8




func _full_propagation_refresh() -> void:
    _clear_deduction_caches()
    # Everything the engine concluded last time is thrown away here, before
    # anything reads it. That single line is what makes derived facts
    # releasable: nothing survives whose cause has gone away, so no pass
    # needs ownership marks to tell its own output from the player's.
    _reset_derived()

    # Merging runs against the EMPTY derived layer, so identity is decided
    # from player input alone. That is deliberate: a merge destroys one of
    # the two records, and there is no way to un-merge when the derived
    # layer is wiped — so a merge must never rest on a fact that can
    # evaporate. Derived identity is Phase 3, and needs non-destructive
    # aliasing before it can drive this safely.
    _settle_identical_records()

    # _derive_color_eliminations_from_star_elim() was REMOVED here (2026-08-07).
    # It was the member->group special case for exactly one axis pair (every
    # star of a colour X'd for a name => that colour eliminated for that
    # name), and _settle_derived_eliminations subsumes it for Colour, Pitch
    # and Degree alike — any value no candidate star carries gets eliminated.
    # Keeping both was actively harmful: it re-derived colour eliminations
    # from a star_elim that still held last refresh's derived output. The
    # derived layer removes that whole failure mode at the source.
    #
    # The passes below are a monotone fixpoint: each only ever adds derived
    # facts, and only from premises already present. Iterating means a
    # conclusion that becomes reachable *because* of another pass's output
    # lands on this frame rather than waiting for the player's next click —
    # the old single-pass order had a documented "resolves on the next
    # refresh instead" caveat in _settle_singleton_sequences for exactly
    # that reason.
    for _round in DERIVATION_MAX_ROUNDS:
        var before: int = _derived_fact_count()
        # Inside the loop as of Phase 3, where it used to run once before
        # it. Identity is now derived, so it both feeds and is fed by the
        # other passes: eliminations narrow a candidate set to one star,
        # that binding resolves the record's other axes through ground
        # truth, and those resolutions narrow further records. Running it
        # once could only ever catch the first link of that chain.
        # FIRST in the round: distance eliminations are the only ones that
        # need no player input at all (map topology alone rules positions
        # out), so they are premises for everything below rather than
        # consequences of it. Running them here means the colour/pitch
        # narrowing they imply lands on the same frame instead of waiting
        # for the next round.
        _settle_distance_constraints()
        _settle_melody_tick_positions()
        _settle_star_identity_from_candidates()
        # The column half, immediately after the row half — the same pair a
        # grid player scans after every mark, and neither implies the other.
        _settle_identity_from_value_columns()
        # After both identity halves, so a position bound THIS round is
        # already claimed and can rule itself out for every other name.
        _settle_alldiff_position_exclusions()
        _settle_derived_eliminations()
        # AFTER the eliminations above, so it sees the narrowest candidate
        # sets. Runs for EVERY record rather than only the one whose colour
        # button was just clicked: _recompute_color_star_elim used to be
        # reachable only from the direct colour-toggle handlers, so a
        # candidate set narrowed by any other route never reached the
        # star-map name checklists.
        _settle_star_elim_from_candidates()
        _settle_group_sequence_bounds()
        _settle_singleton_sequences()
        _settle_repeat_counts_from_notes()
        # AFTER the sequence narrowing above, so a record that only just
        # resolved to a single position is already visible as occupying it.
        _settle_same_position_identity()
        # The same rule keyed on STAR rather than position. After the
        # position version, so a record that only just resolved is already
        # visible as occupying its star.
        _settle_same_star_identity()
        # AFTER the sharing, and BEFORE _settle_singleton_names, which is
        # the pass that could not see these exclusions at all.
        # Name is alldiff, so its exclusion is the single-confirmer kind and
        # keeps its own pass; only the singleton rule is shared.
        _settle_derived_name_exclusions()
        _settle_singleton_for_axis(Axis.NAME)
        # Pitch, Colour and Degree in that order — unchanged from when each
        # had its own hand-written pair. Exclusion before singleton on every
        # axis: the singleton rule counts remaining values, so it has to run
        # after the pass that rules values out, or it counts values the
        # display has already struck through.
        for axis in CLIQUE_AXES:
            _settle_derived_exclusions_for_axis(int(axis))
            _settle_singleton_for_axis(int(axis))
        # Monotone: inside the fixpoint a proven-distinct pair stays proven,
        # so only the unproven verdicts are worth re-deriving next round.
        _clear_deduction_caches(true)
        if _derived_fact_count() == before:
            break
    _detect_contradictions()
    _host._refresh_contradiction_banner()
    _host._widgets._build_star_widgets()
    _host._widgets._build_star_tags()
    _host._melody_staff_panel.queue_redraw()
    _host._widgets.request_markers_rebuild()


# ==================================================
# CANDIDATE-STAR SET — the general closure for group/member propagation on
# every "given" axis at once, replacing what would otherwise be a separate
# hand-written rule per (axis x direction) pair.
#
# Every record has a set of stars it could still be. Once that set is
# known, ALL of these fall out of it uniformly instead of needing their own
# implementations:
#   * member -> group: a "White A" slot's candidates are the white stars,
#     so any value no white star carries is eliminated for it (this is the
#     "all Blue stars are G4/A#4, so Blue slots can't be anything else"
#     case).
#   * group -> member: a star-bound record's candidate set is that one
#     star, so its given values are pinned (already the ground-truth tier
#     in _effective_*_state).
#   * identity by elimination: a candidate set narrowed to exactly ONE star
#     means the record IS that star — set star_idx and every ground-truth
#     tier cascades at once.
#
# Only Colour and Degree drive the set unconditionally: both are "given"
# axes (painted on the map / traceable by eye), so reading them leaks
# nothing. Pitch contributes ONLY for stars whose pitch the player has
# actually revealed via Listen — using ground-truth pitch otherwise would
# hand over an un-earned answer, the leak class documented throughout this
# file. Name and Sequence never contribute: their star mapping is precisely
# what the puzzle withholds.
# ==================================================

## Scanned every record on every call, and is called inside per-star loops
## that are themselves inside per-record loops (_candidate_stars_for_record,
## _settle_derived_eliminations) — O(records^2 x stars). Built once per
## refresh instead; invalidated by _clear_deduction_caches() along with
## everything else derived from _match_records.
var _listened_stars_cache: Dictionary = {}
var _listened_stars_built: bool = false


func _player_knows_star_pitch(star: int) -> bool:
    if not _listened_stars_built:
        _listened_stars_cache.clear()
        for r in _match_records:
            var s: int = int(r.get("star_idx", -1))
            if s >= 0 and bool(r.get("pitch_revealed", false)):
                _listened_stars_cache[s] = true
        _listened_stars_built = true
    return _listened_stars_cache.has(star)


## Stars whose pitch the player has EARNED through ANY record bound to them
## — Listen (pitch_revealed) or a Sort:Pitch slot label — counting DERIVED
## star bindings too (via _effective_star_idx), unlike
## _player_knows_star_pitch above, which reads only each record's own
## star_idx and is the narrower question candidate sets ask. This is what
## lets a Sequence row co-identified with a Listened or pitch-slotted record
## inherit that pitch, while a star that is merely IDENTIFIED (named,
## bound) but never Listened does not read as known — see the gate in
## _effective_pitch_state. Built once per refresh by a no-arg pass so the
## per-call lookup stays O(1); invalidated with the other caches.
var _pitch_earned_stars_cache: Dictionary = {}
var _pitch_earned_stars_built: bool = false


func _pitch_earned_for_star(star: int) -> bool:
    if not _pitch_earned_stars_built:
        _build_pitch_earned_stars()
    return _pitch_earned_stars_cache.has(star)


func _build_pitch_earned_stars() -> void:
    _pitch_earned_stars_cache.clear()
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var revealed: bool = bool(r.get("pitch_revealed", false))
        if not (revealed or str(r.get("pitch_slot_label", "")) != ""):
            continue
        # An auto-created star-widget stub only counts once the player has
        # Listened to it: its bare star_idx says the widget rendered, not
        # that anything about the star was learned.
        if _record_is_unconfirmed_star_widget_stub(i) and not revealed:
            continue
        var s: int = _effective_star_idx(i)
        if s >= 0:
            _pitch_earned_stars_cache[s] = true
    _pitch_earned_stars_built = true


## Stars this record could still be. Intersects every constraint that maps
## soundly onto stars; returns every star when nothing constrains it.
##
## The honour_derived parameter is GONE (Phase 2). It existed because
## _recompute_color_star_elim wrote its conclusions into the same star_elim
## dict this function reads, so without a way to ignore its own previous
## output every derived mark re-justified itself and could never be
## released. Derived facts now live in their own layer, wiped at the top of
## each refresh, so reading them back here is not just safe but required:
## the round-to-round fixpoint is how one pass's conclusion becomes the
## next pass's premise.
func _candidate_stars_for_record(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return []
    if _candidate_star_cache.has(record_idx):
        return _candidate_star_cache[record_idx]

    var out: Array = []
    var pinned: int = _effective_star_idx(record_idx)
    if pinned >= 0 and pinned < _host._star_count:
        out = [pinned]
        _candidate_star_cache[record_idx] = out
        return out

    # Repeat count — only for stars the player has Listened to, whose count
    # Listen gives (2026-10-11). This is what makes "Helios is one of the stars
    # that repeat once" a NAME deduction: once the player has marked that on
    # Helios's row, every Listened star with a different count stops being a
    # candidate for it. One confirmed count is looked up once, outside the loop.
    var rep_confirmed: int = -1
    for rv in _repeat_count_domain():
        if _effective_repeat_state(record_idx, int(rv)) == 1:
            rep_confirmed = int(rv)
            break

    # NOTES (2026-10-12, first notes hidden). What this row's own notes say
    # about which map star it can be -- the link between "which notes does
    # Helios fire on" and "which star is Helios". Own fields on both sides:
    #   - it holds more notes than a Listened star fires at all;
    #   - a row bound to that star is marked as not firing on a note this row
    #     holds (or the other way round);
    #   - a row bound to that star already holds every note the star fires,
    #     and this row holds some other note.
    var my_held: Array = _match_records[record_idx].get("melody_ticks", [])
    var my_blocks: Array = _match_records[record_idx].get("seq_note_blocks", [])
    var notes_matter: bool = _notes_hidden() and not (my_held.is_empty() and my_blocks.is_empty())
    # ONE pass over the rows, asking of each row that sits on a map star what
    # its notes say about THIS row -- never a pass per star. Rows the Star Map
    # made for itself are read too, on purpose: where such a row sits is its
    # widget's own place on the map, and the notes on it are marks the player
    # made there. Nothing here reads a name, pitch or count off it.
    var star_ruled_out_by_notes: Dictionary = {}
    if notes_matter:
        for b in _match_records.size():
            if b == record_idx:
                continue
            var at_star: int = _effective_star_idx(b)
            if at_star < 0 or at_star >= _host._star_count:
                continue
            var their_held: Array = _match_records[b].get("melody_ticks", [])
            var their_blocks: Array = _match_records[b].get("seq_note_blocks", [])
            for t in my_held:
                if their_blocks.has(t):
                    star_ruled_out_by_notes[at_star] = true
            for t2 in their_held:
                if my_blocks.has(t2):
                    star_ruled_out_by_notes[at_star] = true
            # That star's notes are all accounted for, and none is this row's.
            if not my_held.is_empty() and _player_knows_star_pitch(at_star) and at_star < _host._repeat_count.size() \
                    and int(_host._repeat_count[at_star]) >= 0 and their_held.size() >= int(_host._repeat_count[at_star]) + 1:
                star_ruled_out_by_notes[at_star] = true

    for s in _host._star_count:
        if _star_elim_state_for_record(record_idx, s) == 2:
            continue
        if _player_knows_star_pitch(s) and s < _host._repeat_count.size() and int(_host._repeat_count[s]) >= 0:
            var s_rep: int = int(_host._repeat_count[s])
            if (rep_confirmed >= 0 and rep_confirmed != s_rep) or _effective_repeat_state(record_idx, s_rep) == 2:
                continue
            if notes_matter and my_held.size() > s_rep + 1:
                continue
        if star_ruled_out_by_notes.has(s):
            continue
        # Colour — always given.
        var sc: int = int(_host._star_colors[s]) if s < _host._star_colors.size() else -1
        if sc >= 0 and _effective_color_state(record_idx, sc) == 2:
            continue
        # Degree — always given.
        var sd: int = int(_host._star_degrees[s]) if s < _host._star_degrees.size() else -1
        if sd >= 0 and _effective_degree_state(record_idx, sd) == 2:
            continue
        # Pitch — only for stars the player has actually listened to.
        if _player_knows_star_pitch(s):
            var note: String = _host._widgets._note_name_for_star(s)
            if note != "?" and _effective_pitch_state(record_idx, note) == 2:
                continue
        out.append(s)
    _candidate_star_cache[record_idx] = out
    return out


## star_elim for a record index, input then derived — the by-index twin of
## _star_elim_state(), which can only be reached through a name and so is
## unusable for slot records that have none yet.
func _star_elim_state_for_record(record_idx: int, star_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    var own: int = int((_match_records[record_idx].get("star_elim", {}) as Dictionary).get(star_idx, 0))
    if own != 0:
        return own
    return _derived_state(record_idx, "star_elim", star_idx)


## |candidates| == 1 means the record IS that star. Setting star_idx makes
## every _effective_*_state ground-truth tier fire at once, so Colour,
## Degree, and (once listened) Pitch all resolve without their own rules.
## Map positions already claimed by a record, for the two identity passes'
## "somebody else is already that star" refusal.
##
## SKIPS unconfirmed star-widget stubs, and that exclusion is the whole
## point. _build_star_widgets_impl creates a star_idx-bound record for
## EVERY star the instant its floating widget renders, so counting stubs as
## occupants marks all fifteen positions taken before the player has done
## anything — and both identity passes then refuse every binding they would
## ever make. Measured 2026-08-13: with stubs present, collapsing a record's
## row to a single position bound nothing at all; without them, the same
## collapse bound immediately. The row pass had carried that inline and
## unfiltered since Phase 3.
##
## A stub is not a competing claim to a position. It IS the position,
## waiting to learn what sits there — `name` empty is exactly what marks it
## as carrying no player knowledge (see
## _record_is_unconfirmed_star_widget_stub). Once a real record binds there,
## the two become provably identical and the merge machinery folds them.
## A record carrying a name still blocks, which is the case the refusal was
## actually written for: two records must not derive their way onto one star
## with neither noticing.
func _occupied_positions() -> Dictionary:
    var occupied: Dictionary = {}
    for i in _match_records.size():
        if _record_is_unconfirmed_star_widget_stub(i):
            continue
        var si: int = _effective_star_idx(i)
        if si >= 0:
            occupied[si] = i
    return occupied


func _settle_star_identity_from_candidates() -> void:
    # Occupied stars are collected once and maintained as we go, rather
    # than rescanned per record. This pass moved inside the fixpoint in
    # Phase 3, so a per-record O(n) scan for "does anyone else own this
    # star" became O(n^2) per round times up to DERIVATION_MAX_ROUNDS —
    # measured at +70ms on a 52-record board before this was hoisted.
    var occupied: Dictionary = _occupied_positions()

    var bound_any: bool = false
    for i in _match_records.size():
        if _effective_star_idx(i) >= 0:
            continue
        var cands: Array = _candidate_stars_for_record(i)
        if cands.size() != 1:
            continue
        var s: int = int(cands[0])
        # Refuse if any other record already IS that star — effective
        # identity, not just the own field, so two records cannot both
        # derive their way onto the same star with neither noticing. A
        # genuine conflict belongs on an explicit path that can await the
        # dialog, not here.
        if occupied.has(s):
            continue
        occupied[s] = i
        # PHASE 3: derived, not written into the record. The old
        # r["star_idx"] = s here is the binding that could never be
        # released — clear the colour eliminations that produced it and it
        # stayed put forever, because nothing marked it as the engine's.
        _derived[i]["star_idx"] = s
        bound_any = true
        # _sync_color_states_from_star_idx(i) is deliberately NOT called
        # any more. It copied ground truth into the record's own
        # color_states — a derived conclusion written into player input,
        # which is the exact thing this phase exists to stop. The
        # ground-truth tier in _effective_color_state now reads through
        # _effective_star_idx and gets the same answer without the write.

    # Identity resolution invalidates every derived cache: cliques depend on
    # provable-distinctness, candidate sets on this record's own state, and
    # the listened-stars set on which record owns which star_idx — which is
    # exactly what just changed. Routed through the shared helper so a cache
    # added later can't be missed.
    #
    # ONCE, at the end of the pass — not inside the loop per binding, where
    # it used to sit. k bindings meant k full cache wipes mid-pass, each
    # forcing a cold re-warm of the pairwise-distinctness and profile caches
    # that the very next record then paid for again. Deferring is safe: the
    # only thing a later record in THIS pass needs from an earlier binding is
    # "is that star taken", and that comes from the `occupied` dict, which is
    # maintained by hand right here and never went through a cache. Anything
    # subtler that a stale candidate set would miss is picked up by the next
    # fixpoint round, which is exactly what the loop is for.
    if bound_any:
        _clear_deduction_caches(true)   # monotone — see that function


## Name is alldiff with map positions: a position one name occupies is a
## position no OTHER name can occupy. Sounds trivial, and the engine did not
## have it — verified 2026-08-13 by binding a name record to star 7 and
## finding star_elim[7] still 0 on every other name record.
##
## That gap is why _propagate_name_confirmed used to broadcast the same
## conclusion by hand, writing star_elim=2 straight into every other name
## record's OWN dict on confirmation. Those writes were indistinguishable
## from the player's own X marks and nothing released them: undo the
## binding and they stayed forever. Deriving it here instead means it is
## rebuilt from scratch each refresh and evaporates the moment its premise
## does — the whole reason the derived layer exists.
##
## Stated over VALUES, not records, so it needs no notion of "the Name
## family" and no completeness check. A name value's row is a superset of
## the truth and the truth is non-empty (every name is somewhere), so a row
## that has collapsed to ONE position means the name really is there — and
## alldiff then rules that position out for every other name. Cascades
## through the fixpoint as those rows collapse in turn.
##
## Restricted to records that actually carry a name, matching the broadcast
## it replaces. An anonymous slot ("Red A", one of several same-colour
## stars) is not a candidate for any particular name, so asserting "this
## slot is not star 7" on its behalf would contaminate
## _records_provably_distinct with a claim nothing supports — the exact
## regression the old broadcast's own comment records.
func _settle_alldiff_position_exclusions() -> void:
    if _host._star_names.size() != _host._star_count:
        return   # alldiff premise unmet; a short table proves nothing

    # position -> the name value handle that has collapsed onto it
    var claimed: Dictionary = {}
    for v in _host._star_count:
        var poss: Array = _stars_possible_for_descriptor(
            ConstellationLogicPuzzle.Category.NAME, int(v))
        if poss.size() == 1:
            claimed[int(poss[0])] = int(v)
    if claimed.is_empty():
        return

    var wrote: bool = false
    for s in claimed:
        var pos: int = int(s)
        var owner_v: int = int(claimed[s])

        # The conclusion, stored on the VALUES it is about: every OTHER name
        # loses this position. Written here rather than only onto records
        # because a name with no Sort row would otherwise lose the exclusion
        # entirely — and since distance narrowing can now pin a rowless
        # descriptor, a rowless name really can reach this loop.
        for v2 in _host._star_count:
            if int(v2) == owner_v:
                continue
            var row: Array = _stars_possible_for_descriptor(
                ConstellationLogicPuzzle.Category.NAME, int(v2))
            if not row.has(pos):
                continue
            var kept: Array = []
            for r2 in row:
                if int(r2) != pos:
                    kept.append(int(r2))
            if _narrow_descriptor_row(ConstellationLogicPuzzle.Category.NAME, int(v2), kept):
                wrote = true

        var owners: Dictionary = {}
        for oi in _records_holding_descriptor(
                ConstellationLogicPuzzle.Category.NAME, owner_v):
            owners[int(oi)] = true
        for i in _match_records.size():
            if owners.has(i):
                continue   # this record IS the name that owns the position
            if str(_match_records[i].get("name", "")) == "":
                continue   # anonymous slot — see the note above
            if _star_elim_state_for_record(i, pos) != 0:
                continue   # already ruled out, or the player marked it
            if _add_derived_state(i, "star_elim", pos, 2):
                wrote = true
    if wrote:
        _clear_deduction_caches(true)


## The COLUMN half of the identity rule. _settle_star_identity_from_
## candidates above is the ROW half: "this record has only one position
## left, so it is that one". This is the transpose: "this position has only
## one value left, so that value is here". A grid player scans both after
## every mark; the engine only ever scanned rows, so a column the player
## collapsed by elimination went unnoticed until they placed it by hand.
##
## Counted over VALUES, never over records — and that is the whole reason
## this pass needs no preconditions. The record-based version of the same
## rule ("among the Name ROWS, if one is left...") is unsound without two
## guards, because a name whose row has not been created yet is simply
## absent from the tally, so the count reads too LOW and can hit 1 while
## the real answer is 5. Over values there is no such thing as an absent
## name: an unconstrained one comes back from
## _stars_possible_for_descriptor as "could be anywhere", so it appears in
## every column and the count reads too HIGH instead. Same missing
## knowledge, opposite failure direction — one unsound by default, the
## other conservative by default.
##
## Soundness, in full:
##   * some value of an alldiff category genuinely occupies position S;
##   * _stars_possible_for_descriptor is a SUPERSET of the truth, so that
##     value's row contains S, so the column count is always >= 1;
##   * a count that is an overcount and still reads exactly 1 means the
##     true count is exactly 1.
## No family-completeness check, no distinctness check, no interaction with
## record merging.
##
## Restricted to the alldiff axes by the maths, not by a special case:
## Colour and Pitch are shared across stars, so "only one colour value can
## be here" is not a conclusion — several stars carry the same colour and
## the premise never holds in the first place.
func _settle_identity_from_value_columns() -> void:
    var occupied: Dictionary = _occupied_positions()

    var bound_any: bool = false
    for cat in [ConstellationLogicPuzzle.Category.NAME,
            ConstellationLogicPuzzle.Category.SEQUENCE]:
        # The alldiff premise is checked, not assumed: the argument above
        # needs exactly one value per position. A short name table (a
        # half-loaded puzzle) would make "some value occupies S" false and
        # every conclusion below unsound.
        if int(cat) == ConstellationLogicPuzzle.Category.NAME \
                and _host._star_names.size() != _host._star_count:
            continue
        if int(cat) == ConstellationLogicPuzzle.Category.SEQUENCE \
                and _host._sequence_rank_solution.size() != _host._star_count:
            continue

        # Value handles. Every descriptor in this engine is addressed as
        # (cat, star) where the star index selects the VALUE — see
        # _descriptor_term. Both categories are permutations of the star
        # set, so ranging over star indices visits each value exactly once.
        var rows: Array = []
        for v in _host._star_count:
            rows.append(_stars_possible_for_descriptor(int(cat), int(v)))

        for s in _host._star_count:
            if occupied.has(int(s)):
                continue   # already settled by the row half or by the player
            var owner: int = -1
            var count: int = 0
            for v in _host._star_count:
                if (rows[int(v)] as Array).has(int(s)):
                    count += 1
                    owner = int(v)
                    if count > 1:
                        break
            if count != 1:
                continue

            # Write it onto whichever record already holds that descriptor.
            # The conclusion belongs to the VALUE first: this descriptor is
            # at this position, full stop.
            #
            # This used to write only onto records, justified by "a value
            # with no record has a row of every star, so it can never be a
            # unique owner". That was true when it was written and MY OWN
            # distance fix made it false the same day — _derived_descriptor_
            # stars can now pin a rowless descriptor, so a rowless value
            # really can win a column, and the binding was being dropped on
            # the floor. Caught by re-auditing rather than by the lint,
            # which cannot see a premise going stale.
            if _narrow_descriptor_row(int(cat), owner, [int(s)]):
                bound_any = true

            # Records still get it, for display. No record is CREATED here:
            # that would resize _match_records underneath the pass iterating
            # it.
            for i in _records_holding_descriptor(int(cat), owner):
                if _effective_star_idx(int(i)) >= 0:
                    continue
                _derived[int(i)]["star_idx"] = int(s)
                occupied[int(s)] = int(i)
                bound_any = true
                break

    if bound_any:
        # Same invalidation as the row half: identity resolution changes
        # candidate sets, cliques and the listened-stars map at once.
        _clear_deduction_caches(true)


## Eliminates every given-axis value that NO candidate star carries. This
## is the member -> group half; the group -> member half is the ground-truth
## tier that fires once star_idx resolves.
func _settle_derived_eliminations() -> void:
    # PHASE 2: no release pass any more. This function used to open by
    # walking derived_value_elim_marks and hand-reverting every entry it
    # had written into the player's own colour/degree/pitch dicts on the
    # previous refresh, because a derivation left sitting in those dicts
    # re-justified itself and became permanent. The derived layer is wiped
    # wholesale at the top of the refresh instead, so there is nothing left
    # to release and derived_value_elim_marks is gone.
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if _effective_star_idx(i) >= 0:
            continue   # ground truth already governs this record
        var cands: Array = _candidate_stars_for_record(i)
        if cands.is_empty() or cands.size() >= _host._star_count:
            continue   # unconstrained: nothing to derive
        var colors: Dictionary = {}
        var degrees: Dictionary = {}
        var notes: Dictionary = {}
        var all_pitches_known: bool = true
        for c in cands:
            var s: int = int(c)
            if s < _host._star_colors.size():
                colors[int(_host._star_colors[s])] = true
            if s < _host._star_degrees.size():
                degrees[int(_host._star_degrees[s])] = true
            if _player_knows_star_pitch(s):
                var n: String = _host._widgets._note_name_for_star(s)
                if n != "?":
                    notes[n] = true
            else:
                all_pitches_known = false

        # Every write below goes to the derived layer. _add_derived_state
        # leaves any value the player already set alone, so the old
        # "only if currently 0" guards are now the layer's own contract.
        for ci in _host.COLOR_NAME_LABELS.size():
            if not colors.has(int(ci)) and _effective_color_state(i, int(ci)) == 0:
                _add_derived_state(i, "color_states", int(ci), 2)

        for s2 in _host._star_count:
            var dv: int = int(_host._star_degrees[s2]) if s2 < _host._star_degrees.size() else -1
            if dv >= 0 and not degrees.has(dv) and _effective_degree_state(i, dv) == 0:
                _add_derived_state(i, "degree_states", dv, 2)

        # Only sound once EVERY candidate's pitch is player-known: an
        # unlistened candidate could be carrying the very note about to be
        # eliminated.
        if all_pitches_known and not bool(r.get("pitch_revealed", false)):
            for n2 in _host._widgets._distinct_note_names():
                var nn: String = str(n2)
                if not notes.has(nn) and _effective_pitch_state(i, nn) == 0:
                    _add_derived_state(i, "pitch_states", nn, 2)

    # This pass writes the very colour/degree/pitch state that candidate
    # sets AND pairwise distinctness are derived FROM, so both caches are
    # now potentially stale. Relying on the call order not to re-read one
    # is exactly the fragility these caches were split out to avoid.
    #
    # Only the UNPROVEN half of the pair cache is dropped: this pass adds
    # eliminations and never removes any, so a pair already proven distinct
    # stays proven — see _clear_deduction_caches's monotonicity note.
    _candidate_star_cache.clear()
    var proven_pairs: Dictionary = {}
    for k in _distinct_pair_cache:
        if bool(_distinct_pair_cache[k]):
            proven_pairs[k] = true
    _distinct_pair_cache = proven_pairs


# ==================================================
# DISTANCE CONSTRAINTS (map topology).
#
# FOURTH structural rule class, after record-identity unification, the
# cardinality/pigeonhole exclusions, and group->member narrowing.
#
# A distance clue reads "<descriptor A> is (not) N hops from <descriptor B>".
# Neither side names a map star: A is a hidden label ("Astaeis", "the star
# that fires 6th") and B is usually a GROUP noun phrase ("a yellow star",
# "the star that plays E5"). So the claim the player is actually given is
#
#     the star A denotes is N hops from SOME star that B denotes
#
# which is a constraint on WHERE each side can be, and eliminates every map
# position that has no possible partner at that distance. That is where the
# information lives, and until this pass existed none of it was extracted:
# the disclosure was only ever asked "is this clue used up yet".
#
# The two worked examples from the 2026-08-12 report:
#
#   "The star that fires 6th is 1 hop from a yellow star."  Yellow is
#   painted on the map, so the group is exactly known. No two yellow stars
#   are adjacent in this constellation, so no yellow star has a yellow
#   neighbour — every yellow position is eliminated for the 6th-firing star,
#   and _settle_derived_eliminations then turns that candidate-set narrowing
#   into "6th is not yellow". Pure topology: no player input required, so it
#   fires on a blank board.
#
#   "Astaeis is one hop from the star that plays E5."  Astaeis is confined
#   to that star's neighbours, and the colours and pitches those neighbours
#   carry are the only ones left open to it.
#
# Deliberately NOT reasoning from the disclosure's raw `ref`/`target` star
# indices. Those are solution positions; the text discloses only the two
# descriptors, so using them directly would leak the answer and assert more
# than the player was told. They survive only as the handle every disclosure
# uses to name a value (see _descriptor_term).
# ==================================================

## Every map star the descriptor (cat, star) could still denote, given only
## what the player knows. This is the (descriptor -> stars) row that the
## per-characteristic sweeps have always needed and never had; each caller
## used to hand-roll its own version star by star.
##
## Always a SUPERSET of the truth — never narrower than the evidence — so
## every elimination built on it is sound.
func _stars_possible_for_descriptor(cat: int, star: int) -> Array:
    var key: String = "%d:%d" % [cat, star]
    if _descriptor_star_cache.has(key):
        return _descriptor_star_cache[key]

    var out: Array = []
    match cat:
        ConstellationLogicPuzzle.Category.COLOR:
            # Painted on the map: the group is exactly known from the start.
            var want: int = int(_host._star_colors[star]) \
                if star < _host._star_colors.size() else -1
            for s in _host._star_count:
                if s < _host._star_colors.size() and int(_host._star_colors[s]) == want:
                    out.append(s)
        ConstellationLogicPuzzle.Category.PITCH:
            # A star's note is known only once Listen has fired on it. An
            # unlistened star could be carrying this note, so it stays in —
            # dropping it would narrow on evidence the player does not have.
            var wantn: String = _host._widgets._note_name_for_star(star)
            for s in _host._star_count:
                if not _player_knows_star_pitch(s) \
                        or _host._widgets._note_name_for_star(s) == wantn:
                    out.append(s)
        _:
            # NAME and SEQUENCE are hidden and alldiff: the descriptor
            # denotes exactly one star, but which one is the thing being
            # solved. Its record's candidate set IS the player's knowledge
            # of that, so this reads the existing grid rather than
            # duplicating it. Several records may confirm the same
            # descriptor (Sort tabs, star widgets, popups) — intersect, as
            # each is an independent constraint on the same star.
            var narrowed: bool = false
            for i in _match_records.size():
                if _record_descriptor_state(i, cat, star) != 1:
                    continue
                var cands: Array = _candidate_stars_for_record(i)
                if not narrowed:
                    out = cands.duplicate()
                    narrowed = true
                    continue
                var keep: Dictionary = {}
                for c in cands:
                    keep[int(c)] = true
                var merged: Array = []
                for o in out:
                    if keep.has(int(o)):
                        merged.append(int(o))
                out = merged
            if not narrowed:
                for s in _host._star_count:
                    out.append(s)

    # Intersect with anything a settle pass has proved about this DESCRIPTOR
    # directly, independent of whether any record holds it. Without this a
    # distance narrowing existed only as star_elim on records, so a
    # descriptor with no UI row of its own kept reading as "could be any
    # star" no matter what the clues had already settled.
    var pinned: Array = _derived_descriptor_stars.get("%d:%d" % [cat, star], [])
    if not pinned.is_empty():
        var keep_p: Dictionary = {}
        for p in pinned:
            keep_p[int(p)] = true
        var narrowed_out: Array = []
        for o in out:
            if keep_p.has(int(o)):
                narrowed_out.append(int(o))
        out = narrowed_out

    _descriptor_star_cache[key] = out
    return out


## Records that carry descriptor (cat, value) as CONFIRMED — the write side
## of the matrix. Deriving happens over values; landing a conclusion where
## the UI can show it needs the records holding that value, and that lookup
## was being open-coded everywhere it was needed.
##
## Deliberately narrow: this is plumbing at the output edge, and must not
## grow into a reasoning primitive. To ask what a descriptor could BE, use
## _stars_possible_for_descriptor — which needs no records at all, and is
## sound precisely because it does not depend on one existing.
func _records_holding_descriptor(cat: int, value: int) -> Array:
    var out: Array = []
    for i in _match_records.size():
        if _record_descriptor_state(i, cat, value) == 1:
            out.append(i)
    return out


## Of `mine`, the positions that still have a partner in `theirs` consistent
## with the claim. Everything dropped is provably impossible.
##
## The two directions are NOT mirror images, and getting that backwards is
## the easy way to make this unsound:
##
##   positive ("is N hops from one of them") — a position survives if ANY
##   partner sits at N. One witness is enough, because the claim is
##   existential.
##
##   negated ("is not N hops from it") — a position dies only if EVERY
##   partner sits at N, since then whichever star the other side really
##   denotes, the forbidden distance holds. A single partner at some other
##   distance leaves the position open.
func _distance_allowed_stars(mine: Array, theirs: Array, hops: int, negated: bool) -> Array:
    var out: Array = []
    for m in mine:
        var si: int = int(m)
        var considered: int = 0
        var at_hops: int = 0
        for t in theirs:
            var ti: int = int(t)
            if ti == si:
                continue   # a star is not its own partner
            considered += 1
            # star_distance returns -1 for an unreachable pair (Bellows has
            # isolated stars); -1 never equals a real hop count, so those
            # simply fail to witness, which is the right answer both ways.
            if _host.star_distance(si, ti) == hops:
                at_hops += 1
        if negated:
            if not (considered > 0 and at_hops == considered):
                out.append(si)
        elif at_hops > 0:
            out.append(si)
    return out


## Every distance_hop disclosure across the puzzle's clues, in the matrix
## framing. Built once per refresh — the fixpoint runs this pass up to
## DERIVATION_MAX_ROUNDS times and the clue list cannot change mid-refresh.
func _distance_constraints() -> Array:
    if _distance_constraints_built:
        return _distance_constraints_cache
    _distance_constraints_built = true
    _distance_constraints_cache = []
    if _host == null or not (_host._form_clues_cache is Array):
        return _distance_constraints_cache
    for raw in _host._form_clues_cache:
        if not (raw is Dictionary):
            continue
        var discs = (raw as Dictionary).get("disclosures", [])
        if not (discs is Array):
            continue
        for d in discs:
            if not (d is Dictionary):
                continue
            var f: Dictionary = d
            if str(f.get("kind", "")) != "distance_hop":
                continue
            # A CACHE_VERSION 6 clue carries no descriptor framing, only two
            # solution star indices — unusable here, and skipped rather than
            # guessed at. CACHE_VERSION 7 regenerates those puzzles anyway;
            # this is the belt to that braces.
            if int(f.get("ref_cat", -1)) < 0 or int(f.get("target_cat", -1)) < 0:
                continue
            if int(f.get("hops", -1)) < 0:
                continue
            _distance_constraints_cache.append(f)
    return _distance_constraints_cache


func _settle_distance_constraints() -> void:
    var wrote: bool = false
    for f in _distance_constraints():
        var c: Dictionary = f
        var hops: int = int(c.get("hops", -1))
        var neg: bool = bool(c.get("negated", false))
        var rc: int = int(c.get("ref_cat", -1))
        var tc: int = int(c.get("target_cat", -1))
        var rs: int = int(c.get("ref", -1))
        var ts: int = int(c.get("target", -1))
        if rs < 0 or ts < 0:
            continue
        var ref_poss: Array = _stars_possible_for_descriptor(rc, rs)
        var tgt_poss: Array = _stars_possible_for_descriptor(tc, ts)
        if ref_poss.is_empty() or tgt_poss.is_empty():
            continue   # nothing to constrain against
        # BOTH directions. The subject side is the one the player usually
        # cares about, but a Form 19 clue names two hidden descriptors and
        # each narrows the other.
        if _apply_distance_side(rc, rs, ref_poss, tgt_poss, hops, neg):
            wrote = true
        if _apply_distance_side(tc, ts, tgt_poss, ref_poss, hops, neg):
            wrote = true
    if wrote:
        # This pass writes the star_elim that candidate sets are computed
        # FROM, so those caches — and the descriptor rows built on top of
        # them — are now stale. Monotone: eliminations only ever accumulate
        # within a refresh, so proven-distinct pairs are kept.
        _clear_deduction_caches(true)


## Writes one side's eliminations into the derived layer. Returns whether
## anything new was recorded, so the fixpoint can tell if it has settled.
func _apply_distance_side(cat: int, star: int, mine: Array, theirs: Array,
        hops: int, negated: bool) -> bool:
    # Only the hidden axes own records to narrow. There is no per-record
    # slot standing for "the yellow stars" as a group, and Colour/Pitch
    # membership is read off the map rather than deduced — so the given
    # side is a source of constraint here, never a target of one.
    if cat != ConstellationLogicPuzzle.Category.NAME \
            and cat != ConstellationLogicPuzzle.Category.SEQUENCE:
        return false
    var allowed: Array = _distance_allowed_stars(mine, theirs, hops, negated)
    if allowed.size() >= mine.size():
        return false   # rules nothing out
    var allow: Dictionary = {}
    for a in allowed:
        allow[int(a)] = true

    # FIRST, and unconditionally: narrow the DESCRIPTOR itself.
    #
    # This used to write only into records holding the descriptor, which
    # made the deduction depend on whether a UI row happened to exist. It
    # does not: "the star that fires 11th" denotes exactly one star by
    # definition, and "the 11th is 3 hops from a red star" is decidable from
    # topology and colour alone, so that identification is available at
    # puzzle load. With no record for the 11th position, the loop below ran
    # zero times and the conclusion was DISCARDED — then appeared later, out
    # of nowhere, the moment some unrelated interaction created the record.
    # Reported 2026-08-14, and the earlier "0 records -> 15/15, 30 records ->
    # 7/15" probe readings were the same effect, misread at the time.
    #
    # The narrowing is a fact about the VALUE. Records are where it gets
    # DISPLAYED, and that is all the loop below is for.
    var wrote: bool = _narrow_descriptor_row(cat, star, allowed)

    for i in _records_holding_descriptor(cat, star):
        for m in mine:
            var si: int = int(m)
            if allow.has(si):
                continue
            if _star_elim_state_for_record(int(i), si) != 0:
                continue   # already ruled out; _add_derived_state would no-op
            if _add_derived_state(int(i), "star_elim", si, 2):
                wrote = true
    return wrote


## Is this side of a distance claim incapable of yielding anything further?
##
## Deliberately NOT "did applying the constraint change anything this
## round". The engine now applies these itself, so that test would report
## every distance clue exhausted the instant its own pass ran — the clue
## justifying its own retirement, which is the failure mode the derived
## layer exists to prevent.
func _distance_side_exhausted(cat: int, star: int) -> bool:
    match cat:
        ConstellationLogicPuzzle.Category.COLOR:
            # Visible from the first frame: it never held anything back.
            return true
        ConstellationLogicPuzzle.Category.PITCH:
            # Settled once every star this group could contain has actually
            # been listened to. Until then an unheard star might join or
            # leave it, and the clue still has reach.
            for s in _stars_possible_for_descriptor(cat, star):
                if not _player_knows_star_pitch(int(s)):
                    return false
            return true
    # Hidden axis: exhausted exactly when the player has pinned it to one
    # map position. Then the hop relation is readable straight off the map
    # and nothing is left to give.
    #
    # This is where the 2026-08-12 fix was still too weak: it asked whether
    # a record was BOUND to a star, which misses a position the player
    # narrowed to by elimination without ever placing anything.
    return _stars_possible_for_descriptor(cat, star).size() == 1


# ==================================================
# GROUP -> MEMBER PROPAGATION (disjunction narrowing).
#
# THIRD distinct structural rule class in this engine, after record-identity
# unification and the cardinality/pigeonhole exclusion rule. This one is
# about facts that apply to a GROUP rather than to one record:
#
#   A star known to be (say) White is one of the White slot records, though
#   we can't tell WHICH. So any constraint true of EVERY White slot is true
#   of that star, even though no merge is possible and none should be —
#   "White A" is an arbitrary discovery-order letter, not an identity.
#
# The engine already had the opposite direction for exactly one axis pair
# (_derive_color_eliminations_from_star_elim: every star of a colour X'd
# for a name => that colour eliminated for that name), and nothing at all
# in this direction. Confirmed live 2026-08-07: "The star that plays D5
# precedes every white star" entered as a lower bound on every White slot's
# Sequence row never reached any white star's own map widget.
#
# SCOPE — deliberately narrow, stated rather than assumed complete:
#   * Implemented: Sequence-position narrowing, from Colour and Pitch slot
#     groups onto a star-bound record.
#   * NOT implemented: the same narrowing driven by Degree groups (their
#     "Conn A"/"Conn B" labels collide across different degree values —
#     see _effective_degree_state's own comment — so the group can't be
#     identified reliably); group->member propagation on the Name, Colour
#     or Pitch axes; and member->group in any direction beyond the one
#     colour/name case that already existed.
# ==================================================

## Union of the sequence positions still available to a slot group, or []
## when the group can't be trusted to cover the value's stars exactly, or
## when any member is wholly unconstrained (union would be everything, so
## narrowing is a no-op anyway).
func _group_position_union(record_idx: int, label_key: String, prefix: String, incidence: int) -> Array:
    if incidence <= 0 or prefix == "":
        return []
    var group: Array = []
    for j in _match_records.size():
        if j == record_idx:
            continue
        var lbl: String = str(_match_records[j].get(label_key, ""))
        if lbl != "" and lbl.begins_with(prefix):
            group.append(j)
    # The group must account for every star carrying the value; a partial
    # set proves nothing about which slot this star is.
    if group.size() != incidence:
        return []
    var union: Dictionary = {}
    for j in group:
        var member_set: Array = _seq_candidate_set_for(int(j))
        if member_set.is_empty():
            return []   # unconstrained member — union is every position
        for p in member_set:
            union[int(p)] = true
    var out: Array = union.keys()
    out.sort()
    return out


## Pushes every record's candidate-star narrowing out into star_elim, which
## is what the star-map widgets' per-star name checklists actually read.
## _recompute_color_star_elim does the work; this just makes sure it runs
## for all records on every refresh instead of only for whichever record a
## colour button was clicked on.
func _settle_star_elim_from_candidates() -> void:
    for i in _match_records.size():
        _recompute_color_star_elim(i)


func _settle_group_sequence_bounds() -> void:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var s: int = _effective_star_idx(i)
        if s < 0 or s >= _host._star_count:
            continue   # only a star-bound record has a knowable group
        var lo: int = int(r.get("seq_lo", 0))
        if lo > 0 and lo == int(r.get("seq_hi", 0)):
            continue   # already pinned exactly; nothing left to narrow

        var unions: Array = []
        if s < _host._star_colors.size():
            var ci: int = int(_host._star_colors[s])
            if ci >= 0 and ci < _host.COLOR_NAME_LABELS.size():
                var cu: Array = _group_position_union(
                    i, "color_slot_label", str(_host.COLOR_NAME_LABELS[ci]), _color_star_count(ci))
                if not cu.is_empty():
                    unions.append(cu)
        # Pitch group — only when the player has actually revealed this
        # star's pitch, else the group membership itself is un-earned.
        if _player_knows_star_pitch(s):
            var note: String = _host._widgets._note_name_for_star(s)
            if note != "?":
                var pu: Array = _group_position_union(
                    i, "pitch_slot_label", note, _pitch_star_count(note))
                if not pu.is_empty():
                    unions.append(pu)
        # Degree group — now identifiable, since the slot label carries the
        # degree value (see _get_or_create_match_record_for_degree_slot).
        if s < _host._star_degrees.size():
            var dg: int = int(_host._star_degrees[s])
            var du: Array = _group_position_union(
                i, "degree_slot_label", "Conn%d " % dg, _degree_star_count(dg))
            if not du.is_empty():
                unions.append(du)
        if unions.is_empty():
            continue

        var current: Array = _seq_candidate_set_for(i)
        if current.is_empty():
            current = []
            for p in range(1, _host._star_count + 1):
                current.append(p)
        var narrowed: Array = current.duplicate()
        for u in unions:
            var next: Array = []
            for p in narrowed:
                if (u as Array).has(p):
                    next.append(p)
            narrowed = next
        # An empty result would mean the player's own entries contradict;
        # surface that through their explicit entries rather than silently
        # writing an impossible record here.
        if narrowed.is_empty() or narrowed.size() >= current.size():
            continue
        # Into the derived layer, NOT seq_candidates/seq_lo/seq_hi. Writing
        # a group narrowing into the player's own fields overwrote what they
        # had typed and could never be taken back once the group changed.
        _narrow_derived_seq(i, narrowed)
