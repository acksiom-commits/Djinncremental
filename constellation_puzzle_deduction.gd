class_name ConstellationPuzzleDeduction
extends RefCounted

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
#   "manual_name_blocks": Dictionary,   # {name(String): true} — names the player
#   "manual_pitch_blocks": Dictionary,  # X'd directly, as opposed to state-2
#   "manual_color_blocks": Dictionary,  # entries that are fallout from confirming
#                                        # a sibling value. Lets the Undo row tell
#                                        # "Undo selects" (revert sibling-clearing
#                                        # fallout only) apart from "Undo blocks"
#                                        # (revert the player's own X clicks only).
#   "protected_pitch_notes": Dictionary,  # {note_name(String): true} — right-click
#   "protected_color_idxs": Dictionary,   # "still possible" flags, one dict per
#   "protected_staff_names": Dictionary,  # category; cosmetic hints, not hard facts.
#   "pitch_revealed": bool,       # true once the record's pitch has been shown to the player
#   "star_elim": Dictionary,      # {star_idx(int): state(int)} — which stars are ruled out for THIS record
#   "star_idx": int,              # -1 until resolvable from seq_lo==seq_hi or map-widget confirm
#   "color_slot_label": String,   # "" unless bound to a Sort:Color grid slot (e.g. "Blue A")
#   "pitch_slot_label": String,   # "" unless bound to a Sort:Pitch grid slot
#   "degree_slot_label": String,  # "" unless bound to a Sort:Sequence grid slot
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
    return {
        "color_states":  {},
        "degree_states": {},
        "pitch_states":  {},
        "name_states":   {},
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
# KNOWN GAP — contradictions that get absorbed before this runs. If a
# record's marks identify a star UNIQUELY, _settle_identical_records merges
# it into that star's record, and every axis then reads ground truth, which
# overrides the offending mark. The impossible state disappears instead of
# being reported, and the player's wrong mark silently vanishes with it.
# Found while testing this: a fixture whose confirmed colour had exactly
# one star merged and reported nothing, and only stopped doing so once the
# colour covered two. The save that prompted all this escaped absorption
# purely because its confirmed colour had several stars.
#
# Not fixed here. Detecting it means comparing player marks against the
# ground truth a merge just imported, which is a different question from
# "is this set empty" and belongs with the identity work in Phase 3.
var _contradictions: Array[Dictionary] = []


func _detect_contradictions() -> void:
    _contradictions.clear()
    var all_notes: Array = _host._widgets._distinct_note_names()

    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var who: String = _record_display_name(i)

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
        # d4bebd5. The merge half is still open: _merge_match_records
        # unions two records' state, and a mark the union drops is gone
        # before anything here can compare it.
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
        return "The star that fires %s" % _ordinal(lo)
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
    var has_position: bool = false
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo == seq_pos and hi == seq_pos:
            has_position = true
            var note: String = _displayable_pitch_for_record(i)
            if note != "":
                return {"has_position": true, "pitch_known": true, "note_name": note}
    return {"has_position": has_position, "pitch_known": false, "note_name": ""}


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
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo != seq_pos or hi != seq_pos:
            continue
        var confirmed: int = -1
        var eliminated_count: int = 0
        var remaining: int = -1
        for ci in _host.COLOR_NAME_LABELS.size():
            var state: int = _effective_color_state(i, ci)
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


## Clue texts the player has right-clicked into Used Up. Player state, so it
## round-trips through the save; reversible, so a misclick costs nothing.
##
## Deliberately NOT computed from coverage. The utility categorisation this
## replaced was the engine GUESSING how much of a clue the player had
## absorbed, and it was wrong in both directions repeatedly — see the DEV
## SPEC above _populate_clue_markers() in constellation_puzzle_widgets.gd.
var _retired_clues: Dictionary = {}


func is_clue_retired(text: String) -> bool:
    return _retired_clues.has(text)


## Returns the new state, so the caller can rebuild without re-querying.
func toggle_clue_retired(text: String) -> bool:
    if text == "":
        return false
    if _retired_clues.has(text):
        _retired_clues.erase(text)
    else:
        _retired_clues[text] = true
    _save_puzzle_notes()
    return _retired_clues.has(text)


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
    # Player state, not derived: which clues they right-clicked into Used Up.
    # Keyed by clue TEXT rather than index, because clue order is not a
    # stable identifier across a cache regeneration.
    notes["retired_clues"] = _retired_clues.keys()
    # protected_names / user_blocks are gone as separate note fields — the
    # star widget's protect and manual-block flags now live on each star's
    # own record, so they round-trip inside match_records above.
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
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "degree_states": {},
        "name_states": {},
        "manual_name_blocks": {},
        "manual_pitch_blocks": {},
        "manual_color_blocks": {},
        "protected_pitch_notes": {},
        "protected_color_idxs": {},
        "protected_staff_names": {},
        "pitch_revealed": false,
        "star_elim": {},
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": "",
    }
    for k in overrides:
        r[k] = overrides[k]
    return r


func _get_or_create_match_record_for_color_slot(color_idx: int, position_in_group: int) -> int:
    var label: String = "%s %s" % [_host.COLOR_NAME_LABELS[color_idx], _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("color_slot_label", "")) == label:
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("color_slot_label", "")) != "":
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
    # FIRST created — if the Sort:Pitch tab was opened (creating a blank
    # placeholder record for e.g. "G4 A") before this star was ever
    # listened to, that placeholder is permanently locked in from then on
    # by the label-match lookup that always runs first, and this newly-
    # confirmed record never gets linked to it. Only safe to fix by
    # merging when this note has EXACTLY one star (_pitch_star_count==1):
    # for a shared note, the "A"/"B" slot lettering is arbitrary discovery
    # order with no way to tell which physical letter this specific star
    # belongs to from a single confirm alone — merging there would be
    # unsound. Called only from the Listen click handler (a deliberate,
    # low-frequency player action), never from the passive
    # _full_propagation_refresh path, so this is the one place in the
    # merge-vs-query tradeoff explored earlier where a merge is both safe
    # and necessary — there's no live-query equivalent that can make a
    # blank slot record's OWN star_idx exist.
    if _pitch_star_count(note_name) != 1:
        return record_idx
    var freq: float = _host._widgets._freq_for_note_name(note_name)
    if freq < 0.0:
        return record_idx
    var slot_idx: int = _get_or_create_match_record_for_pitch_slot(freq, 0)
    if slot_idx != record_idx:
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


func _find_match_record_by_exact_seq(seq: int) -> int:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if int(r["seq_lo"]) > 0 and int(r["seq_lo"]) == int(r["seq_hi"]) and int(r["seq_lo"]) == seq:
            return i
    return -1


func _find_match_record_by_star_idx(star_idx: int) -> int:
    if star_idx < 0:
        return -1
    for i in _match_records.size():
        if int(_match_records[i]["star_idx"]) == star_idx:
            return i
    return -1




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

    for protect_key in ["protected_pitch_notes", "protected_color_idxs", "protected_staff_names", "manual_name_blocks", "manual_pitch_blocks", "manual_color_blocks"]:
        var target_protect: Dictionary = target.get(protect_key, {})
        var source_protect: Dictionary = source.get(protect_key, {})
        for pk in source_protect:
            target_protect[pk] = true
        target[protect_key] = target_protect

    if int(target["star_idx"]) < 0 and int(source["star_idx"]) >= 0:
        target["star_idx"] = source["star_idx"]

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
    _reset_derived()
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

        # Built on _new_match_record() rather than as its own literal, so a
        # save written before some field existed comes back carrying that
        # field's current default instead of missing it entirely — and so
        # adding a field never again means remembering to edit this list.
        _match_records.append(_new_match_record({
            "name": str(e.get("name", "")),
            "seq_lo": _coerce_int(e.get("seq_lo"), 0), "seq_hi": _coerce_int(e.get("seq_hi"), 0),
            "seq_candidates": seq_candidates,
            "color_states": color_states,
            "pitch_states": pitch_states,
            "degree_states": degree_states,
            "name_states": name_states,
            "manual_name_blocks": manual_name_blocks,
            "manual_pitch_blocks": manual_pitch_blocks,
            "manual_color_blocks": manual_color_blocks,
            "protected_pitch_notes": protected_pitch_notes,
            "protected_color_idxs": protected_color_idxs,
            "protected_staff_names": protected_staff_names,
            "pitch_revealed": _coerce_bool(e.get("pitch_revealed"), false),
            "star_elim": star_elim,
            "star_idx": _coerce_int(e.get("star_idx"), -1),
            "color_slot_label": str(e.get("color_slot_label", "")),
            "pitch_slot_label": str(e.get("pitch_slot_label", "")),
            "degree_slot_label": str(e.get("degree_slot_label", "")),
        }))


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
            (int(_host._pitch_rank_solution[int(s2)]) + 1) if int(s2) < _host._pitch_rank_solution.size() else -1,
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



func _compressed_possible_positions_str(record_idx: int) -> String:
    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return ""
    if candidates.size() == _host._star_count:
        return ""
    candidates.sort()
    if candidates.size() == 1:
        return str(candidates[0])

    var segments: Array = []
    var seg_start: int = candidates[0]
    var prev: int = candidates[0]
    for idx in range(1, candidates.size()):
        var c: int = candidates[idx]
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
    if star_idx >= 0:
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
    if not collapse_soft:
        return soft
    match soft:
        3: return 2
        4: return 0
        _: return soft


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

    for label_key in ["color_slot_label", "pitch_slot_label", "degree_slot_label"]:
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
            var i_stub: bool = _record_is_unconfirmed_star_widget_stub(i)
            var j_stub: bool = _record_is_unconfirmed_star_widget_stub(j)
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
    var r: Dictionary = _match_records[record_idx]
    var explicit: Array = r.get("seq_candidates", [])
    var base: Array = []
    if not explicit.is_empty():
        base = explicit.duplicate()
    else:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo <= 0:
            lo = 1
        if hi <= 0:
            hi = _host._star_count
        for p in range(lo, hi + 1):
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

    for p in at_position:
        var group: Array = at_position[p]
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

    # Deliberately does NOT invalidate _distinct_pair_cache /
    # _distinct_profile_cache the way _settle_derived_eliminations does.
    # Everything downstream of this pass reads the derived layer through
    # _effective_*_state, which consults it directly and never those caches,
    # and the fixpoint loop clears them at the end of every round anyway. A
    # mid-round clear here only costs a full re-warm (measured at ~590 ms
    # cold on a full board) to buy a conclusion the next round reaches for
    # free — it made a 57-record refresh 312 ms -> 482 ms on its own.


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
            ["pitch_states", "pitch_states"], ["degree_states", "degree_states"]]:
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

enum Axis { NAME, PITCH, COLOR, DEGREE }

## Axes carrying a shared (non-alldiff) value, in the order the fixpoint
## has always run them. Name is excluded: it is alldiff and takes the
## single-confirmer path instead.
const CLIQUE_AXES: Array = [Axis.PITCH, Axis.COLOR, Axis.DEGREE]


func _axis_states_key(axis: int) -> String:
    match axis:
        Axis.NAME:   return "name_states"
        Axis.PITCH:  return "pitch_states"
        Axis.COLOR:  return "color_states"
        Axis.DEGREE: return "degree_states"
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
    return out


func _axis_state(axis: int, record_idx: int, value) -> int:
    match axis:
        Axis.NAME:   return _effective_name_state(record_idx, str(value))
        Axis.PITCH:  return _effective_pitch_state(record_idx, str(value))
        Axis.COLOR:  return _effective_color_state(record_idx, int(value))
        Axis.DEGREE: return _effective_degree_state(record_idx, int(value))
    return 0


## How many stars actually carry this value — the incidence the clique must
## reach before the value can be ruled out anywhere else.
func _axis_incidence(axis: int, value) -> int:
    match axis:
        Axis.PITCH:  return _pitch_star_count(str(value))
        Axis.COLOR:  return _color_star_count(int(value))
        Axis.DEGREE: return _degree_star_count(int(value))
    return 0


func _axis_clique_key(axis: int, value) -> String:
    match axis:
        Axis.PITCH:  return "P:" + str(value)
        Axis.COLOR:  return "C:%d" % int(value)
        Axis.DEGREE: return "D:%d" % int(value)
    return ""


## Does this record count as a confirmer of `value`? Pitch alone needs a
## guard: an auto-created star-widget record holds a star_idx it never
## earned, so its ground-truth note must not count until Listen has
## actually revealed it. Colour and Degree are "given" axes — painted on
## the map — so their ground-truth tier is no leak.
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
# Also note what's gone: no ground-truth lookup (pitch_rank_solution /
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
            if star >= _host._pitch_rank_solution.size():
                return 0
            var pos: int = int(_host._pitch_rank_solution[star]) + 1
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
            if star >= _host._pitch_rank_solution.size():
                return ""
            return "S:%d" % (int(_host._pitch_rank_solution[star]) + 1)
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
    var out: Array = []
    for s in _host._star_count:
        var v
        if cat == ConstellationLogicPuzzle.Category.COLOR:
            if s >= _host._star_colors.size():
                continue
            v = int(_host._star_colors[s])
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
## pitch_rank_solution); player-side positions are 1-based, hence the +1
## on every crossing.
func _disclosure_satisfied(f: Dictionary) -> bool:
    var kind: String = str(f.get("kind", ""))
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
    return false


## Kinds _disclosure_satisfied() can actually rule on. Anything else (today
## only "flavor", which asserts nothing) must not enter the denominator —
## counting an unscoreable disclosure as unmet would pin its clue below
## 1.0 forever, which is exactly the failure mode raw `cells` had.
const SCOREABLE_DISCLOSURE_KINDS: Array = [
    "ordinal_exact", "ordinal_neg", "ordinal_cmp", "ordinal_chain",
    "ordinal_adjacent", "ordinal_offset", "ordinal_range",
    "ordinal_either_or", "ordinal_extreme", "ordinal_count_before",
    "values_all_different", "values_same", "descriptor_either_or",
    # CACHE_VERSION 6 content, added 2026-08-12. Only present on clues
    # generated after that date — older saves' distance clues carry no
    # distance disclosure and score exactly as they did before.
    "distance_hop",
]


func _clue_coverage(cells: Array, terms: Array = [], disclosures: Array = []) -> Dictionary:
    var covered: int = 0
    var total: int = 0
    for d in disclosures:
        if not (d is Dictionary):
            continue
        if not SCOREABLE_DISCLOSURE_KINDS.has(str((d as Dictionary).get("kind", ""))):
            continue
        total += 1
        if _disclosure_satisfied(d):
            covered += 1
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


func _exclusive_display_lo(inclusive_lo: int, inclusive_hi: int) -> int:
    if inclusive_lo <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return inclusive_lo
    return inclusive_lo - 1


func _exclusive_display_hi(inclusive_lo: int, inclusive_hi: int) -> int:
    if inclusive_hi <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return inclusive_hi
    var shown: int = inclusive_hi + 1
    return 0 if shown > _host._star_count else shown


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

    var r: Dictionary = _match_records[record_idx]
    var out: Array = []
    var pinned: int = _effective_star_idx(record_idx)
    if pinned >= 0 and pinned < _host._star_count:
        out = [pinned]
        _candidate_star_cache[record_idx] = out
        return out

    for s in _host._star_count:
        if _star_elim_state_for_record(record_idx, s) == 2:
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
        var owners: Dictionary = {}
        for oi in _records_holding_descriptor(
                ConstellationLogicPuzzle.Category.NAME, int(claimed[s])):
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
                and _host._pitch_rank_solution.size() != _host._star_count:
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
            # A value with no record at all cannot reach here — with nothing
            # constraining it, its row is every star, so it would be an
            # owner of every column and never the unique owner of one. The
            # only way past that is a puzzle of one star, which the loop
            # above handles anyway. So no record is created here: doing that
            # mid-fixpoint would resize _match_records underneath the pass
            # that is iterating it.
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
    var wrote: bool = false
    var key: String = "%d:%d" % [cat, star]
    var prev: Array = _derived_descriptor_stars.get(key, [])
    if prev.is_empty() or allowed.size() < prev.size():
        _derived_descriptor_stars[key] = allowed.duplicate()
        if prev.is_empty() or allowed.size() < prev.size():
            wrote = true

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
