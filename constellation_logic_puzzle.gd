class_name ConstellationLogicPuzzle
extends RefCounted
# ============== CONSTELLATION LOGIC PUZZLE — FORMS/CELLS ARCHITECTURE ==============
# Ground-up replacement generator for constellation_logic_puzzle.gd's clue
# generation layer, built on the corrected three-tier model (2026-07-20):
#
#   1. RECORD ARRAY (upstream of everything, produced by ground-truth
#      generation below): every pair of two specific Star Characteristics
#      (Name/Sequence/Color/Pitch/Distance value-tuples, including Color/
#      Pitch sub-ranks so grouped values behave as a nested mini zebra-grid)
#      is a CELL, graded True or False depending on whether both actually
#      co-occur on the same star. Every cell starts "unused."
#   2. FORMS (22 abstract templates, structural shells with typed Star-
#      Characteristic node slots — NOT yet built in this file, pending the
#      finalized form table). A Form's nodes are filled by WEIGHTED RANDOM
#      CELL SAMPLING: biased toward True cells over False (more information
#      per cell, though False cells are never "decorative" — they still
#      carry real, sound, single-referent constraint, just non-cascading),
#      and CHAIN-CONSTRAINED so exactly one node's cell must be "used"
#      already (linking to the previous clue — skipped only for the very
#      first clue), with every other node drawn from "unused" cells.
#   3. KIND is DERIVED, never assigned upstream: once a Form's nodes are
#      filled with actual cell content, "kind" is just a label describing
#      which categories ended up in which nodes — consumed only by grammar
#      formation (phrasing template selection). Kind is never a dispatch
#      key generation branches on to decide what to sample.
#   4. CLUE is a filled Form run through grammar formation/checking to
#      produce correct English text for the player.
#
# BLOAT CONTROL (two methods, per user direction 2026-07-20):
#   (1) ZebraTutor pass: after each committed clue, run the propagation
#       engine below and flip every cell that becomes DERIVABLE (not merely
#       directly sampled) from "unused" to "used" — this is what makes
#       exhausting the unused-cell pool converge with actual solvability,
#       rather than "coverage" and "sufficiency" being unrelated properties.
#       This is why the propagation engine survives wholesale from the old
#       file: it graduates from "downstream verifier" to the literal engine
#       driving what counts as used/unused.
#   (2) (reserved — second bloat-control method not yet specified)
#
# WHAT'S PORTED FROM constellation_logic_puzzle.gd, VERBATIM OR NEAR-VERBATIM:
#   - Ground-truth generation (stars/colors/pitches/distances/names/sub-ranks)
#   - Sequence-axis propagation/solving engine (arc-consistency, forward-
#     checking backtrack) — the kind-string matches inside it are STRUCTURAL
#     dispatch (exact/negative/comparison shape), not per-kind bespoke logic,
#     so it ported cleanly; it's the live Phase C uniqueness gate today
#     (_solve(), called from _generate_clues_forms_attempt()).
#   - Generic helpers: shuffle, pick-from-domain/pick-star, alphabetical-rank,
#     note-name-for-frequency.
#
# REMOVED, 2026-07-25 (confirmed dead, not pending work): the ported
# Pitch-axis solving engine (_solve_pitch and its ~15 supporting functions)
# and the Sequence-side possibility-grid front-end + four domain-min/max/
# forced-value/any-in-range helpers. None had any caller in the live Forms
# pipeline — every Form builder that uses Pitch as a content/labeling axis
# explicitly skips emitting a solver fact for it, because Pitch carries no
# uniqueness requirement (fully recoverable via Listen — see
# constellation_puzzle_category_facts_CHECK_FIRST memory, and the comment
# above _seq_fact_for_label further down this file). This was true even in
# the pre-Forms version of this file; the Pitch solver was carried along
# during the port because it happened to port cleanly, not because the
# Forms model needs it. Building Pitch-clue solving out would be a
# regression to the old per-axis-solver architecture this rewrite replaced.
#   - Public API shape (setup/is_generation_complete/generate_clues_async/
#     get_form_clue_texts/check_solution) and the cache-serialization OUTER
#     shell.
#
# DELIBERATELY NOT PORTED, PENDING WORK:
#   - Name-axis solving (_apply_one_name_filter/_apply_name_single_dot_
#     filters/_name_arcs_from_clues/_name_arc_predicate/_name_arc_consistency/
#     _possibility_grid_for_name_clues/_solve_names/_backtrack_fc_names in the
#     old file): this is ~560 lines entirely keyed on the OLD per-kind kind-
#     strings with bespoke logic per kind (unlike the Sequence/Pitch engine's
#     structural-only dispatch) — it cannot be separated from the old kind
#     system, so it needs a genuine rewrite once the new Kind field-shapes
#     are known from the finalized Forms table, not a mechanical port.
#   - The entire kind-string-keyed generation apparatus (_sample_and_build
#     and ~40 per-kind bodies, _category_kinds/PRIMER_ELIGIBLE_KINDS/
#     STRUCTURAL_KINDS, _primer_category_min/_attempts_for_category/
#     _force_primer_coverage, _try_pick_for_category, generate_clues_by_
#     primer_type's Phase A/B loop): superseded outright by the Forms/Cells
#     pipeline; no port, no adaptation.
#   - _score_clue_difficulty: repurposed per user direction as a data-
#     collection hook for future per-Form player-enjoyment tracking, not a
#     trim-ordering key (there is no trim pass anymore) — not yet rebuilt.
#   - The 22 Forms themselves, the record-array/cell data structure, the
#     weighted+chained sampling loop, and grammar formation are NEW and not
#     yet written — blocked on the finalized Forms table (names only are
#     confirmed so far: Exact Identity, Single Negation, Dual Negation,
#     Disjunction, Pairwise Order, Exact Offset, Adjacency, Range, Group
#     Order, Count, Extreme, Equality Pair, Mutual Exclusion, Group
#     Comparison, Distance Existential, Distance Extreme, Betweenness,
#     Degree Fact, Non-Adjacency, Cross-Domain Bridge, Pseudo-True Pair
#     Aligned, Pseudo-True Pair Staggered).
# ========================================================================


# ==================================================
# GROUND TRUTH GENERATION — ported verbatim, upstream of all three tiers
# ==================================================
enum StarColor { BLUE, WHITE, YELLOW_ORANGE, RED }
enum Category { NAME, SEQUENCE, COLOR, PITCH, DISTANCE, POSITION }
# POSITION is deliberately NOT in BIJECTIVE_CATEGORIES and never will be by
# the same route NAME/COLOR/PITCH are: putting it there would make the
# clue-selection pool (_random_bijective_category_pair,
# _sample_grid_cell_maybe_chained) eligible to draw it as a clue subject,
# and _characteristic_label() has no branch for it — falls through to
# `return "?"`, a silently broken clue, not a crash. Confirmed by reading
# both call sites before adding this line.
#
# It doesn't need that route. Per the Phase 0 measurement
# (generator_ships_unsolvable_puzzles.md), the position-axis closure is a
# NEW CONSUMER of rendered clue chars, structurally identical to how
# _solve() already handles SEQUENCE: its own possibility grid, fed by
# facts parsed OUT of the clues, never touching _matrix or
# BIJECTIVE_CATEGORIES. POSITION exists here only so that solver has a
# name to reference instead of a bare int. Appended at the END so no
# existing enum value's int shifts — cached chosen_form_clues store "cat"
# as a raw int, and a mid-list insert would silently misread a stale
# cache's old category as the wrong new one.
const COLOR_NAMES           := ["Blue", "White", "Yellow", "Red"]
const SEQ_WORD_EARLIER      := "earlier"
const SEQ_WORD_LATER        := "later"
const FRAME_BUDGET_MSEC     := 2       # max ms of work per frame during async gen
const MAX_BACKTRACK_NODES := 50000   # hard ceiling on recursive nodes explored per
                                       # solve() call, shared across all three solvers.
                                       # Without this, a hard-to-disambiguate clue set
                                       # can make backtracking explore an exponential
                                       # number of partial assignments and hang the main
                                       # thread. This converts that failure mode into
                                       # "solve() returns fewer than cap solutions,"
                                       # which every caller already treats the same way
                                       # as genuinely-not-unique-yet.
var _backtrack_nodes_remaining: int = 0
const NOTE_LETTER_NAMES: Array[String] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
]
 
static func note_name_for_freq(freq: float) -> String:
    if freq <= 0.0:
        return "?"
    var semitones_from_a4: float = 12.0 * log(freq / 440.0) / log(2.0)
    var midi_note: int = int(round(semitones_from_a4)) + 69
    var letter: String = NOTE_LETTER_NAMES[((midi_note % 12) + 12) % 12]
    var octave: int = int(floor(midi_note / 12.0)) - 1
    return "%s%d" % [letter, octave]
 
 
static func _ordinal(n: int) -> String:
    var mod100: int = n % 100
    if mod100 >= 11 and mod100 <= 13:
        return "%dth note" % n
    match n % 10:
        1: return "%dst note" % n
        2: return "%dnd note" % n
        3: return "%drd note" % n
        _: return "%dth note" % n
 
 
# ── Puzzle state ─────────────────────────────────────────────────────────
var star_count: int = 0
var constellation_id: int = -1
var player_seed_used: int = 0          # stored so cache-validity check is possible
var proximity: Array[Array] = []       # proximity[i] = Array[int]
var star_degrees: Array[int] = []      # star_degrees[i] = proximity[i].size(), computed once
var _max_degree: int = 0
var _min_degree: int = 0
var star_colors: Array[int] = []       # star_colors[i] = StarColor int (visible, per-player)
var _color_sub_rank: Array[int] = []   # star_colors[i]-relative sub-rank (0,1,2.. -> "A","B","C") so any star is referenceable, not just singleton colors
var star_names: Array[String] = []     # star_names[i] = procedural name (per-constellation)
var pitch_rank_solution: Array[int] = [] # pitch_rank_solution[i] = melody step for star i
 
# ── Internal clue representation ─────────────────────────────────────────
# Clues are stored as plain Dictionaries rather than Callables so they
# can be serialized to the save cache. The solver reconstructs comparison
# predicates from the stored fields at solve-time.
# Schema:
#   comparison:  {"kind":"ordinal_cmp",     "a":int, "b":int, "a_gt_b":bool, "text":String}
#   adjacent-seq:{"kind":"ordinal_adjacent", "a":int, "b":int, "text":String}  (a fires immediately after b)
#   extreme:     {"kind":"ordinal_extreme", "s":int, "neighbors":[int,...], "want_lowest":bool, "text":String}
#   flavor:      {"kind":"flavor",  "text":String}
var _final_clues: Array[Dictionary] = []
var _generation_complete: bool = false
 
# ── Real-pitch + graph-distance data (known info, used for flavor clues only) ──
var star_pitch_index: Array[int] = []     # star_pitch_index[i] = pitch-table index for star i
var _pitch_sub_rank: Array[int] = []      # frequency-rank-relative sub-rank (0,1,2.. -> "A","B","C") — grouped by actual pitch (_pitch_freq_rank), not raw star_pitch_index; same purpose as _color_sub_rank
var _pitch_freqs: Array[float] = []       # this constellation's Hz table, indexed by pitch index
var _distances: Array[Array] = []         # _distances[a][b] = shortest graph-hop count, -1 if unreachable
var _alph_rank: Array[int] = []   # star_index -> alphabetical rank among star_names, 0..star_count-1
 
# ── Pitch CSP domain — parallel to the Sequence-rank domain above, but NOT
# alldiff: multiple stars can legitimately share a pitch class. ──────────
var pitch_count: int = 0                # distinct pitch classes = _pitch_freqs.size()
var _pitch_freq_rank: Array[int] = []   # pitch_index -> ascending-frequency rank, ties share a rank

## Colour reshuffles allowed while searching for an assignment that leaves
## no two positions interchangeable (see _separate_indistinguishable_
## positions). Measured need is tiny — the largest class pitch and topology
## leave unseparated is 2, against 4 colours, so a redraw succeeds almost
## immediately — but the cap keeps a pathological new constellation from
## spinning instead of reporting.
const COLOR_SEPARATION_ATTEMPTS: int = 24

## Diagnostics for that search; read by tests, not by generation.
var _color_reshuffles_used: int = 0
var _color_separation_failed: bool = false

var _rng := RandomNumberGenerator.new()

# Injected only so generate_clues_forms() can yield a frame between
# generation attempts instead of blocking — same reason ArchonPokeMinigame
# etc. take a host reference. Optional: null is safe (generation just runs
# fully synchronously, as it always used to), so no existing caller breaks.
var _host: Node = null


# ==================================================
# SETUP — call before generate_clues_async()
# ==================================================
func setup(p_star_count: int, line_pairs: Array, correct_star_sequence: Array,
        p_player_seed: int, p_constellation_id: int,
        name_theme: Dictionary = {}, p_star_pitch_index: Array = [],
        p_pitch_freqs: Array = [], p_host: Node = null) -> void:
    star_count       = p_star_count
    constellation_id = p_constellation_id
    _host            = p_host
    player_seed_used = p_player_seed
    _generation_complete = false
    _final_clues.clear()

    # Offset seed so color assignment never shares RNG stream with
    # get_note_assignment() or ConstellationStarNamer.
    _rng.seed = p_player_seed ^ (p_constellation_id * 0x9E3779B9) ^ 0x4C50_5A5A
 
    _build_proximity(line_pairs)
    _compute_distances()
    _compute_star_degrees()
    _assign_colors_balanced()
    # _color_sub_rank is NOT derived here any more: colour may still be
    # reshuffled by _separate_indistinguishable_positions() once the pitch
    # data is in (it is assigned below this point), and a sub-rank taken
    # from a superseded colouring would be silently wrong.
    _set_pitch_ranks_from_sequence(correct_star_sequence)
    star_names = ConstellationStarNamer.generate_names(
        star_count, p_constellation_id, name_theme)
    _shuffle_star_names_for_player()

    star_pitch_index = []
    for v in p_star_pitch_index:
        star_pitch_index.append(int(v))
    _pitch_freqs = []
    for v in p_pitch_freqs:
        _pitch_freqs.append(float(v))

    # Pitch CSP domain setup: distinct pitch-class count and a stable
    # ascending-frequency rank per pitch index (ties share a rank), used by
    # the pitch propagator for bound-consistency the same way star ranks are
    # used by the Sequence propagator. Computed BEFORE _pitch_sub_rank
    # (moved below _pitch_freq_rank, was previously computed from the raw,
    # frequency-meaningless star_pitch_index instead) so sub-ranks group
    # stars that actually share a pitch, not stars that happen to share an
    # arbitrary table slot — those aren't the same grouping in general.
    pitch_count = _pitch_freqs.size()
    _compute_pitch_freq_rank()

    # HERE, not up beside _assign_colors_balanced(): this needs the pitch
    # data assigned just above, because a position's observable identity is
    # colour AND pitch together. Placed earlier it read empty pitch arrays
    # and separated nothing.
    _separate_indistinguishable_positions()
    # Derived AFTER the filter, since it may have recoloured.
    _color_sub_rank = _assign_sub_ranks_within_groups(star_colors)
    var pitch_freq_rank_per_star: Array = []
    for s in star_count:
        pitch_freq_rank_per_star.append(_pitch_freq_rank[star_pitch_index[s]])
    _pitch_sub_rank = _assign_sub_ranks_within_groups(pitch_freq_rank_per_star)
 
 
func _compute_pitch_freq_rank() -> void:
    _pitch_freq_rank = []
    _pitch_freq_rank.resize(pitch_count)
    var order: Array = []
    for p in pitch_count:
        order.append(p)
    order.sort_custom(func(a, b): return _pitch_freqs[a] < _pitch_freqs[b])
    var rank: int = 0
    for i in order.size():
        if i > 0 and not is_equal_approx(_pitch_freqs[order[i]], _pitch_freqs[order[i - 1]]):
            rank += 1
        _pitch_freq_rank[order[i]] = rank
 
 
func _compute_distances() -> void:
    _distances = []
    for i in star_count:
        var dist: Array = []
        dist.resize(star_count)
        for j in star_count:
            dist[j] = -1
        dist[i] = 0
        var queue: Array = [i]
        var qi: int = 0
        while qi < queue.size():
            var cur: int = queue[qi]
            qi += 1
            for n in proximity[cur]:
                var ni: int = int(n)
                if dist[ni] == -1:
                    dist[ni] = dist[cur] + 1
                    queue.append(ni)
        _distances.append(dist)
 
 
func _build_proximity(line_pairs: Array) -> void:
    proximity.clear()
    proximity.resize(star_count)
    for i in star_count:
        proximity[i] = []
    var i: int = 0
    while i < line_pairs.size() - 1:
        # line_pairs is a raw def field on player/patron constellations —
        # its outer Array type is guaranteed by the caller (root_ui.gd) but
        # not its elements. The global int() constructor crashes outright
        # on a Dictionary/Array element (confirmed this session); coerce to
        # a sentinel that the bounds check below excludes instead.
        var raw_a = line_pairs[i]
        var raw_b = line_pairs[i + 1]
        var a: int = int(raw_a) if typeof(raw_a) in [TYPE_INT, TYPE_FLOAT] else -1
        var b: int = int(raw_b) if typeof(raw_b) in [TYPE_INT, TYPE_FLOAT] else -1
        if a >= 0 and a < star_count and b >= 0 and b < star_count:
            if not proximity[a].has(b):
                proximity[a].append(b)
            if not proximity[b].has(a):
                proximity[b].append(a)
        i += 2


func _compute_star_degrees() -> void:
    star_degrees.clear()
    _max_degree = 0
    _min_degree = star_count
    for i in star_count:
        var deg: int = proximity[i].size()
        star_degrees.append(deg)
        if deg > _max_degree:
            _max_degree = deg
        if deg < _min_degree:
            _min_degree = deg


func _assign_colors_balanced() -> void:
    var deck: Array[int] = []
    for i in star_count:
        deck.append(i % 4)
    for i in range(deck.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp: int = deck[i]
        deck[i] = deck[j]
        deck[j] = tmp
    star_colors = deck


## Reshuffles colour until no two POSITIONS are interchangeable.
##
## THE BUG THIS PREVENTS. If two map positions look identical in everything
## the player can observe — visible colour, audible pitch, and hop distances
## — then every clue predicate over observables gives the same answer for
## both. Swapping them yields a second, equally consistent solution, the
## puzzle has no unique answer, and the player correctly cannot finish it.
## In play that is indistinguishable from a propagation bug.
##
## Measured 2026-08-14 across 24 puzzles per constellation, varying both the
## pitch assignment and the colour assignment: Archon 2, Bellows 1, and zero
## for the three fully connected constellations. It concentrates where
## topology is weak — Archon is three isolated triangles plus a 6-cycle
## (23% of star pairs reachable), Bellows has four isolated single stars.
##
## WHY COLOUR IS THE LEVER. Topology is authored art. The pitch LIST and its
## order are the musical theme and must not change. Colour is the one thing
## free to move, and it is enough: the largest class that pitch and topology
## leave unseparated is 2, against 4 colours.
##
## WHY REFINEMENT AND NOT PAIRWISE COMPARISON. Comparing pairs of positions
## by (colour, pitch, distance row) only finds TRANSPOSITIONS. Three
## positions in an isolated triangle have three different distance rows, so
## pairwise passes them, while a 3-cycle rotation is still an automorphism
## and the puzzle still has multiple solutions. Colour refinement — label by
## observables, then repeatedly refine by the multiset of neighbours'
## labels — catches cycles of any length. On the measured sample the two
## agreed, so this is correctness, not a bigger number.
##
## Labels deliberately exclude NAME and SEQUENCE: those are what the player
## is solving for. Including them would prove separability using the answer.
func _separate_indistinguishable_positions() -> void:
    if star_count <= 1:
        return
    for attempt in COLOR_SEPARATION_ATTEMPTS:
        if _observables_separate_every_position():
            if attempt > 0:
                _color_reshuffles_used = attempt
            return
        _assign_colors_balanced()
    # Unreachable on the authored constellations (largest unseparated class
    # is 2, and 4 colours are available), so this is a data alarm rather
    # than a fallback: a new constellation whose pitch and topology leave
    # 5+ positions identical cannot be made solvable by recolouring, and
    # needs its art or note data changed.
    _color_separation_failed = true
    push_warning(
        "ConstellationLogicPuzzle [%d]: could not find a colour assignment that "
        % constellation_id
        + "separates every position after %d attempts — this constellation's "
        % COLOR_SEPARATION_ATTEMPTS
        + "pitch/topology data may make unique solutions impossible.")


## True when the player's observable value space distinguishes every
## position from every other.
func _observables_separate_every_position() -> bool:
    var labels: Array = []
    for s in star_count:
        # FREQUENCY, not the raw pitch index: two table slots can carry the
        # same frequency, and two stars the player hears as the same note
        # are not distinguishable by ear whatever their index says.
        labels.append("%d/%f" % [int(star_colors[s]), _freq_for_star(s)])
    # Iterative refinement: a position's label absorbs the multiset of its
    # neighbours' labels until the partition stops changing.
    for _round in star_count:
        var sig: Array = []
        for s2 in star_count:
            var neigh: Array = []
            for n in proximity[s2]:
                neigh.append(str(labels[int(n)]))
            neigh.sort()
            sig.append("%s|%s" % [str(labels[s2]), ",".join(neigh)])
        var seen: Dictionary = {}
        var next_labels: Array = []
        for s3 in star_count:
            var key: String = str(sig[s3])
            if not seen.has(key):
                seen[key] = str(seen.size())
            next_labels.append(str(seen[key]))
        if str(next_labels) == str(labels):
            break
        labels = next_labels
    var used: Dictionary = {}
    for s4 in star_count:
        if used.has(str(labels[s4])):
            return false
        used[str(labels[s4])] = true
    return true


static func _sub_rank_letter(n: int) -> String:
    # 0 -> "A", 1 -> "B", ... 25 -> "Z", 26 -> "AA", matching how star_count
    # is small enough that a single letter almost always suffices, but this
    # doesn't silently break if a group ever exceeds 26.
    var s: String = ""
    var v: int = n
    while true:
        s = char(65 + (v % 26)) + s
        @warning_ignore("integer_division")
        v = v / 26 - 1
        if v < 0:
            break
    return s


func _assign_sub_ranks_within_groups(values: Array) -> Array[int]:
    # Shared helper for any "one value shared by multiple stars" category
    # (Color, Pitch): groups stars by their value, shuffles each group with
    # the same seeded _rng already used for colors/names, and assigns each
    # star a stable position within its group — so "Blue-B" or "A4-C" is a
    # genuine, reproducible per-star identifier, not just a lucky singleton.
    var groups: Dictionary = {}
    for i in values.size():
        var v = values[i]
        if not groups.has(v):
            groups[v] = []
        groups[v].append(i)
    var sub_rank: Array[int] = []
    sub_rank.resize(values.size())
    for v in groups.keys():
        var members: Array = groups[v]
        _shuffle_array(members)
        for pos in members.size():
            sub_rank[int(members[pos])] = pos
    return sub_rank


func _shuffle_star_names_for_player() -> void:
    # The name POOL is fixed per constellation_id (lore — same set of names
    # for every player, per ConstellationStarNamer), but WHICH star gets
    # WHICH name must still be randomized per-player, same as color, or the
    # Name axis is solved once per constellation and memorized forever.
    for i in range(star_names.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp: String = star_names[i]
        star_names[i] = star_names[j]
        star_names[j] = tmp


func _set_pitch_ranks_from_sequence(correct_star_sequence: Array) -> void:
    pitch_rank_solution = []
    pitch_rank_solution.resize(star_count)
    for i in star_count:
        pitch_rank_solution[i] = -1
 
    # Record each star's FIRST-occurrence step. Some constellations reuse a
    # star across multiple melody steps (more steps than stars — e.g. Spark's
    # 16-step Hallelujah Chorus over 7 stars), so we rank stars by first-fire
    # ORDER rather than trusting raw step numbers. That keeps
    # pitch_rank_solution a clean 0..star_count-1 permutation no matter how
    # many times a star repeats later in the sequence.
    var first_step: Array = []
    first_step.resize(star_count)
    for i in star_count:
        first_step[i] = -1
 
    for step in correct_star_sequence.size():
        var star_idx: int = int(correct_star_sequence[step])
        if star_idx < 0 or star_idx >= star_count:
            continue
        if first_step[star_idx] == -1:
            first_step[star_idx] = step
 
    # Stars that never fire (shouldn't happen with valid content) sort last,
    # by star index, so malformed data degrades gracefully instead of crashing.
    var order: Array = []
    for i in star_count:
        order.append(i)
    order.sort_custom(func(a, b):
        var fa: int = first_step[a]
        var fb: int = first_step[b]
        if fa == -1 and fb == -1:
            return a < b
        if fa == -1:
            return false
        if fb == -1:
            return true
        return fa < fb)
 
    for rank in order.size():
        pitch_rank_solution[order[rank]] = rank
 
    var missing: bool = false
    for i in star_count:
        if first_step[i] == -1:
            missing = true
    if missing:
        push_warning("ConstellationLogicPuzzle [%d]: some stars never fire in correct_star_sequence — check puzzle_sequence content." % constellation_id)


# ==================================================
# SEQUENCE-AXIS PROPAGATION + SOLVER — ported verbatim
# ==================================================
# Kind-string matches below (ordinal_exact/ordinal_neg/ordinal_cmp/etc) are
# STRUCTURAL dispatch — "this clue has an exact-identity shape," "this clue
# has a comparison shape" — not per-kind bespoke logic. This is the live
# Phase C uniqueness gate for the Forms pipeline (see header, ~51-66); there
# is no Pitch-axis equivalent — that solver was confirmed dead code and
# deleted 2026-07-25 (Pitch needs no uniqueness proof, unlike Sequence).
func _init_possibility_grid() -> Array:
    var grid: Array = []
    for i in star_count:
        var row: Array = []
        row.resize(star_count)
        for r in star_count:
            row[r] = true
        grid.append(row)
    return grid
 
 
func _expand_clues_to_cmp(clues: Array[Dictionary]) -> Array[Dictionary]:
    var expanded: Array[Dictionary] = []
    for clue in clues:
        match clue["kind"]:
            "ordinal_cmp":
                expanded.append({"a": clue["a"], "b": clue["b"], "a_gt_b": clue["a_gt_b"]})
            "ordinal_chain":
                # Three-star chain (lo < mid < hi) decomposes into two plain
                # ordinal_cmp arcs — the bound-propagation machinery below
                # needs no new logic, just two entries instead of one.
                expanded.append({"a": clue["mid"], "b": clue["a"], "a_gt_b": true})
                expanded.append({"a": clue["b"], "b": clue["mid"], "a_gt_b": true})
            "ordinal_group_cmp_color", "ordinal_group_cmp_tone":
                # One clause, one arc per (subject, same-colored/toned target)
                # pair: the CATEGORY (color or tone) multiplies the
                # constraint, and merged multi-subject clues (see
                # _merge_group_cmp_kind) multiply it again per subject —
                # every subject independently satisfies the same
                # "before/after every target" relation. Identical expansion
                # logic for both kinds — only which category grouped the
                # targets differs, and that's already baked into "targets"
                # by the caller.
                var s_first: bool = clue["s_first"]
                for gs in clue["subjects"]:
                    for t in clue["targets"]:
                        if s_first:
                            expanded.append({"a": int(t), "b": int(gs), "a_gt_b": true})
                        else:
                            expanded.append({"a": int(gs), "b": int(t), "a_gt_b": true})
            "ordinal_extreme":
                var s: int = clue["s"]
                var want_lowest: bool = clue["want_lowest"]
                for n in clue["neighbors"]:
                    if want_lowest:
                        expanded.append({"a": int(n), "b": s, "a_gt_b": true})
                    else:
                        expanded.append({"a": s, "b": int(n), "a_gt_b": true})
    return expanded
 
 
## Scans one star's boolean possibility row and returns (min index where
## true, max index where true) in one pass, or (-1, -1) if none are true.
## _propagate re-derives exactly this "domain bounds" a handful of times
## per fixed-point iteration (comparison arcs, then twice more per
## cardinality-arc neighbor) — this is the one shared shape underneath all
## of them.
static func get_domain_bounds(domain_row: Array) -> Vector2i:
    var mn: int = -1
    var mx: int = -1
    for r in domain_row.size():
        if domain_row[r]:
            if mn == -1:
                mn = r
            mx = r
    return Vector2i(mn, mx)


func _propagate(possible: Array, cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary],
        count_clues: Array[Dictionary]) -> bool:
    # Arc-consistency fixed-point pass. Mutates `possible` in place.
    # Returns false immediately on contradiction (a star with zero remaining ranks).
    var changed: bool = true
    while changed:
        changed = false
 
        # --- Comparison arcs: bound propagation via min/max, O(star_count) per arc. ---
        for clue in cmp_clues:
            var a: int = clue["a"]
            var b: int = clue["b"]
            var a_gt_b: bool = clue["a_gt_b"]
            var hi: int = a if a_gt_b else b
            var lo: int = b if a_gt_b else a
 
            var min_lo: int = get_domain_bounds(possible[lo]).x
            if min_lo == -1:
                return false
 
            for r in star_count:
                if possible[hi][r] and r <= min_lo:
                    possible[hi][r] = false
                    changed = true
 
            var hi_bounds: Vector2i = get_domain_bounds(possible[hi])
            var max_hi: int = hi_bounds.y
            if hi_bounds.x == -1:
                return false
 
            for r in star_count:
                if possible[lo][r] and r >= max_hi:
                    possible[lo][r] = false
                    changed = true
 
        # --- Offset arcs: a fires exactly `offset` steps after b. adj_seq
        # clues omit "offset" (defaults to 1, original behavior unchanged);
        # offset_seq clues carry an explicit arbitrary offset. ---
        for clue in adj_clues:
            var a2: int = clue["a"]
            var b2: int = clue["b"]
            var off: int = int(clue.get("offset", 1))
            for r in star_count:
                if possible[a2][r]:
                    var br: int = r - off
                    var supported: bool = br >= 0 and br < star_count and possible[b2][br]
                    if not supported:
                        possible[a2][r] = false
                        changed = true
            for r in star_count:
                if possible[b2][r]:
                    var ar: int = r + off
                    var supported2: bool = ar >= 0 and ar < star_count and possible[a2][ar]
                    if not supported2:
                        possible[b2][r] = false
                        changed = true
 
        # --- Cardinality arcs (count_before): exactly k of s's neighbors fire
        # before s. Two directions: (a) prune ranks of s where the achievable
        # before-count can't hit k; (b) once s is pinned, force or forbid the
        # straddling neighbors as the count demands. ---
        for clue in count_clues:
            var s3: int = clue["s"]
            var k3: int = clue["k"]
            var nbrs: Array = clue["neighbors"]
 
            for r in star_count:
                if not possible[s3][r]:
                    continue
                var must_before: int = 0
                var can_before: int = 0
                for n in nbrs:
                    var n_bounds: Vector2i = get_domain_bounds(possible[int(n)])
                    var mn: int = n_bounds.x
                    var mx: int = n_bounds.y
                    if mx == -1:
                        return false
                    if mx < r:
                        must_before += 1
                        can_before += 1
                    elif mn < r:
                        can_before += 1
                if must_before > k3 or can_before < k3:
                    possible[s3][r] = false
                    changed = true
 
            var s_count: int = 0
            var s_rank: int = -1
            for r in star_count:
                if possible[s3][r]:
                    s_count += 1
                    s_rank = r
            if s_count == 0:
                return false
            if s_count == 1:
                var must_before2: int = 0
                var straddlers: Array = []
                for n in nbrs:
                    var n2_bounds: Vector2i = get_domain_bounds(possible[int(n)])
                    var mn2: int = n2_bounds.x
                    var mx2: int = n2_bounds.y
                    if mx2 == -1:
                        return false
                    if mx2 < s_rank:
                        must_before2 += 1
                    elif mn2 < s_rank and mx2 >= s_rank:
                        straddlers.append(int(n))
                if must_before2 > k3 or must_before2 + straddlers.size() < k3:
                    return false
                if must_before2 == k3:
                    for n2 in straddlers:
                        for rr in s_rank:
                            if possible[n2][rr]:
                                possible[n2][rr] = false
                                changed = true
                elif must_before2 + straddlers.size() == k3:
                    for n2 in straddlers:
                        for rr in range(s_rank, star_count):
                            if possible[n2][rr]:
                                possible[n2][rr] = false
                                changed = true
 
        # --- Alldiff / uniqueness projection: a singleton star claims its rank exclusively. ---
        for i in star_count:
            var count_i: int = 0
            var only_r: int = -1
            for r in star_count:
                if possible[i][r]:
                    count_i += 1
                    only_r = r
            if count_i == 0:
                return false
            if count_i == 1:
                for j in star_count:
                    if j != i and possible[j][only_r]:
                        possible[j][only_r] = false
                        changed = true
 
    return true
 
 
func _all_singleton(possible: Array) -> bool:
    for i in star_count:
        var count_i: int = 0
        for r in star_count:
            if possible[i][r]:
                count_i += 1
        if count_i != 1:
            return false
    return true
 
 
func _extract_singleton_solution(possible: Array) -> Array:
    var solution: Array = []
    solution.resize(star_count)
    for i in star_count:
        for r in star_count:
            if possible[i][r]:
                solution[i] = r
                break
    return solution
 
 
func _possible_to_domains(possible: Array) -> Array:
    var domains: Array = []
    for i in star_count:
        var d: Array = []
        for r in star_count:
            if possible[i][r]:
                d.append(r)
        domains.append(d)
    return domains
 
 
# ==================================================
# SOLVER — arc-consistency propagation, with MRV fallback
# ==================================================
# Internal representation during solving: domains is an Array[Array[int]]
# (mutable copy per recursion level), assignment is Array[int] (-1 = unset).
# Returns Array of solutions found (each solution is an Array[int]).
# Stops after `cap` solutions — generation only needs "unique" vs "not".
 
func _apply_exact_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        if clue["kind"] != "ordinal_exact":
            continue
        var s: int = clue["s"]
        var r: int = clue["r"]
        if not possible[s][r]:
            return false
        for rr in star_count:
            if rr != r:
                possible[s][rr] = false
    return true
 
 
func _apply_negative_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        match clue["kind"]:
            "value_out_set":
                var vos: int = clue["s"]
                for ex in clue["excluded"]:
                    possible[vos][int(ex)] = false
            "ordinal_neg":
                var s: int = clue["s"]
                var r: int = clue["r"]
                possible[s][r] = false
            "proximity_neg_adjacent":
                var s2: int = clue["s"]
                var r2: int = clue["r"]
                for n in proximity[s2]:
                    possible[int(n)][r2] = false
            "ordinal_neither_nor":
                var ns1: int = clue["s1"]
                var ns2: int = clue["s2"]
                var nr: int = clue["r"]
                possible[ns1][nr] = false
                possible[ns2][nr] = false
            "unique_list_n":
                for part in clue["participants"]:
                    if int(part["cat"]) == Category.SEQUENCE:
                        if str(part.get("sign", "pos")) == "neg":
                            # Negative form: excludes 1-2 ranks from THIS
                            # star's own domain (same shape as ordinal_neg)
                            # rather than excluding others from one exact
                            # rank — there's no single "dr" to sweep with.
                            var neg_star: int = int(part["star"])
                            for er in part.get("excluded_ranks", []):
                                possible[neg_star][int(er)] = false
                            continue
                        var dr: int = int(part["rank"])
                        var seq_star: int = int(part["star"])
                        for other in clue["participants"]:
                            if int(other["star"]) == seq_star:
                                continue
                            possible[int(other["star"])][dr] = false
    for i in star_count:
        var any_possible: bool = false
        for r in star_count:
            if possible[i][r]:
                any_possible = true
                break
        if not any_possible:
            return false
    return true
 
 
func _apply_range_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        match str(clue.get("kind", "")):
            "value_in_set":
                # Category-agnostic: whatever "s" and "star_count" mean to
                # the caller (Sequence rank, or a NAME closure's position
                # candidate — see _solve_name_closure), this just restricts
                # row s to the given column set. No ordering assumed.
                var vis: int = clue["s"]
                var allowed: Array = clue["allowed"]
                for r0 in star_count:
                    if not (r0 in allowed):
                        possible[vis][r0] = false
            "ordinal_range":
                var s: int = clue["s"]
                var lo: int = clue["lo"]
                var hi: int = clue["hi"]
                for r in star_count:
                    if r < lo or r > hi:
                        possible[s][r] = false
            "ordinal_either_or":
                var es: int = clue["s"]
                var r1: int = clue["r1"]
                var r2: int = clue["r2"]
                for r in star_count:
                    if r != r1 and r != r2:
                        possible[es][r] = false
            "ordinal_unaligned":
                var us1: int = clue["s1"]
                var us2: int = clue["s2"]
                var ur1: int = clue["r1"]
                var ur2: int = clue["r2"]
                for r in star_count:
                    if r != ur1 and r != ur2:
                        possible[us1][r] = false
                        possible[us2][r] = false
    for i in star_count:
        var any_left: bool = false
        for r in star_count:
            if possible[i][r]:
                any_left = true
                break
        if not any_left:
            return false
    return true
 
 
func _validate_count_clues(solution: Array, count_clues: Array[Dictionary]) -> bool:
    for clue in count_clues:
        var s: int = clue["s"]
        var k: int = clue["k"]
        var before: int = 0
        for n in clue["neighbors"]:
            if int(solution[int(n)]) < int(solution[s]):
                before += 1
        if before != k:
            return false
    return true
 
 
func _solve(clues: Array[Dictionary], cap: int = 2, rank_restriction: Array = []) -> Array:
    var expanded_cmp: Array[Dictionary] = _expand_clues_to_cmp(clues)
    var adj_clues: Array[Dictionary] = []
    var count_clues: Array[Dictionary] = []
    for clue in clues:
        if clue["kind"] == "ordinal_adjacent" or clue["kind"] == "ordinal_offset":
            adj_clues.append(clue)
        elif clue["kind"] == "ordinal_count_before":
            count_clues.append(clue)
 
    var possible: Array = _init_possibility_grid()
    if not rank_restriction.is_empty():
        for i in star_count:
            for r in star_count:
                if not rank_restriction[i][r]:
                    possible[i][r] = false
    if not _apply_exact_clues(possible, clues):
        return []
    if not _apply_negative_clues(possible, clues):
        return []
    if not _apply_range_clues(possible, clues):
        return []
    var consistent: bool = _propagate(possible, expanded_cmp, adj_clues, count_clues)
    if not consistent:
        return []
    # Phase 4: layer naked-subset on top (Sequence is alldiff — sound, see
    # _naked_subset_pass's guard). Can only resolve MORE puzzles via pure
    # propagation than before, reducing how often the backtracking fallback
    # below is needed — never changes the correctness of what it proves.
    var nb_changed: bool = true
    while nb_changed:
        nb_changed = false
        if _naked_subset_pass(possible, star_count, true):
            nb_changed = true
            if not _propagate(possible, expanded_cmp, adj_clues, count_clues):
                return []

    if _all_singleton(possible):
        var sol: Array = _extract_singleton_solution(possible)
        if not _validate_count_clues(sol, count_clues):
            return []
        return [sol]
 
    var solutions: Array = []
    var assignment: Array = []
    assignment.resize(star_count)
    for i in star_count:
        assignment[i] = -1
 
    var init_domains: Array = _possible_to_domains(possible)
    _backtrack_nodes_remaining = MAX_BACKTRACK_NODES
    _backtrack_fc(assignment, init_domains, expanded_cmp, adj_clues, count_clues, solutions, cap)
    return solutions
 
 
func _backtrack_fc(assignment: Array, domains: Array,
        cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary],
        count_clues: Array[Dictionary], solutions: Array, cap: int) -> void:
    if solutions.size() >= cap:
        return
    _backtrack_nodes_remaining -= 1
    if _backtrack_nodes_remaining <= 0:
        if _backtrack_nodes_remaining == 0:
            push_warning("ConstellationLogicPuzzle [%d]: backtracking node budget exhausted (sequence) — aborting search early." % constellation_id)
            _backtrack_nodes_remaining -= 1
        return
 
    var var_idx: int = -1
    var best_size: int = star_count + 1
    for i in star_count:
        if assignment[i] == -1:
            var sz: int = domains[i].size()
            if sz < best_size:
                best_size = sz
                var_idx = i
 
    if var_idx == -1:
        # Leaf: forward checking doesn't track cardinality constraints, so
        # every complete assignment must pass count validation here before
        # it counts as a solution.
        if _validate_count_clues(assignment, count_clues):
            solutions.append(assignment.duplicate())
        return
 
    for val in domains[var_idx]:
        assignment[var_idx] = val
        var new_doms_result = _forward_check(var_idx, val, domains, cmp_clues, adj_clues)
        if new_doms_result != null:
            _backtrack_fc(assignment, new_doms_result, cmp_clues, adj_clues, count_clues, solutions, cap)
        assignment[var_idx] = -1
        if solutions.size() >= cap:
            return
 
 
func _forward_check(var_idx: int, val: int, domains: Array,
        cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary]):
    # Returns a new domains Array with propagated reductions, or null on wipeout.
    var nd: Array = []
    for i in star_count:
        nd.append(domains[i].duplicate())
    nd[var_idx] = [val]
 
    # Alldiff: remove val from all other unassigned domains.
    for i in star_count:
        if i != var_idx:
            var idx: int = nd[i].find(val)
            if idx != -1:
                nd[i].remove_at(idx)
                if nd[i].is_empty():
                    return null
 
    # Comparison propagation for cmp clues touching var_idx.
    for clue in cmp_clues:
        var a: int = clue["a"]
        var b: int = clue["b"]
        var a_gt_b: bool = clue["a_gt_b"]
        if a == var_idx:
            var new_b: Array = []
            for v in nd[b]:
                if a_gt_b and v < val:
                    new_b.append(v)
                elif not a_gt_b and v > val:
                    new_b.append(v)
            if new_b.is_empty():
                return null
            nd[b] = new_b
        elif b == var_idx:
            var new_a: Array = []
            for v in nd[a]:
                if a_gt_b and v > val:
                    new_a.append(v)
                elif not a_gt_b and v < val:
                    new_a.append(v)
            if new_a.is_empty():
                return null
            nd[a] = new_a
 
    # Offset propagation: clue's "a" fires exactly "offset" steps after "b"
    # (offset defaults to 1 for adj_seq, explicit for offset_seq).
    for clue in adj_clues:
        var a: int = clue["a"]
        var b: int = clue["b"]
        var off2: int = int(clue.get("offset", 1))
        if a == var_idx:
            var new_b: Array = []
            for v in nd[b]:
                if v == val - off2:
                    new_b.append(v)
            if new_b.is_empty():
                return null
            nd[b] = new_b
        elif b == var_idx:
            var new_a: Array = []
            for v in nd[a]:
                if v == val + off2:
                    new_a.append(v)
            if new_a.is_empty():
                return null
            nd[a] = new_a

    return nd
 
 


func _naked_subset_pass(grid: Array, domain_size: int, alldiff: bool) -> bool:
    # Naked pair/triple elimination, generalizing the singleton-only
    # "alldiff claims exclusivity" projection already used elsewhere in this
    # file (K=1). If exactly K dots' remaining domains are all subsets of
    # the SAME K-sized value set, those K values are used up by exactly
    # those K dots and can be eliminated from every other dot's domain.
    # Bounded to K=2 (pairs) and K=3 (triples) — an exhaustive K=2..N search
    # is combinatorially expensive for no practical benefit; pairs/triples
    # catch the overwhelming majority of real cases in logic-grid solving.
    #
    # SOUNDNESS REQUIRES alldiff: the "K values are used up by exactly K
    # dots" argument only holds when each value can be claimed by at most
    # one dot. For a non-alldiff domain (Pitch, Color, Degree — multiple
    # dots CAN legitimately share a value), this technique is simply wrong:
    # a third dot sharing the same pitch as two others is completely valid,
    # and eliminating it would falsely rule out a real possibility. Guarded
    # here, not just at the call site, so misuse fails safe rather than
    # silently over-eliminating.
    if not alldiff:
        return false
    var changed_any: bool = false
    var domains: Array = []
    for d in star_count:
        var dom: Array = []
        for v in domain_size:
            if grid[d][v]:
                dom.append(v)
        domains.append(dom)

    # Naked pairs: two different dots share the identical 2-value domain.
    for d1 in star_count:
        if domains[d1].size() != 2:
            continue
        for d2 in range(d1 + 1, star_count):
            if domains[d2].size() != 2:
                continue
            if domains[d1][0] != domains[d2][0] or domains[d1][1] != domains[d2][1]:
                continue
            var v1: int = domains[d1][0]
            var v2: int = domains[d1][1]
            for d3 in star_count:
                if d3 == d1 or d3 == d2:
                    continue
                if grid[d3][v1]:
                    grid[d3][v1] = false
                    domains[d3].erase(v1)
                    changed_any = true
                if grid[d3][v2]:
                    grid[d3][v2] = false
                    domains[d3].erase(v2)
                    changed_any = true

    # Naked triples: three dots whose domains (each size 2 or 3) union to
    # exactly one 3-value set.
    for d1 in star_count:
        if domains[d1].size() < 2 or domains[d1].size() > 3:
            continue
        for d2 in range(d1 + 1, star_count):
            if domains[d2].size() < 2 or domains[d2].size() > 3:
                continue
            for d3 in range(d2 + 1, star_count):
                if domains[d3].size() < 2 or domains[d3].size() > 3:
                    continue
                var union_vals: Dictionary = {}
                for v in domains[d1]:
                    union_vals[v] = true
                for v in domains[d2]:
                    union_vals[v] = true
                for v in domains[d3]:
                    union_vals[v] = true
                if union_vals.size() != 3:
                    continue
                for d4 in star_count:
                    if d4 == d1 or d4 == d2 or d4 == d3:
                        continue
                    for v in union_vals.keys():
                        if grid[d4][v]:
                            grid[d4][v] = false
                            domains[d4].erase(v)
                            changed_any = true
    return changed_any


 
 


# ==================================================
# GENERIC HELPERS — ported verbatim (RNG, alphabetical rank, sampling)
# ==================================================
func _compute_alph_rank() -> void:
    _alph_rank = []
    _alph_rank.resize(star_count)
    var order: Array = []
    for i in star_count:
        order.append(i)
    order.sort_custom(func(a, b): return star_names[a] < star_names[b])
    for rank in order.size():
        _alph_rank[order[rank]] = rank
 
 
## _build_alph_extreme_pool deleted 2026-07-19 — label_extreme_ordinal_color
## is now built by _sample_alph_extreme.


func _shuffle_array(arr: Array) -> void:
    for i in range(arr.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp
 
 
func _shuffle_dict_array(arr: Array[Dictionary]) -> void:
    for i in range(arr.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp: Dictionary = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp
 
 
# ==================================================
# GENERATION ENTRY POINT — matches root_ui.gd's calling convention
# (puzzle.generate_clues_async.call_deferred(), then listens for
# generation_complete).
#
# FIXED 2026-07-27 — generate_clues_forms() used to be fully synchronous
# despite the "_async" name: call_deferred() only defers *when* it starts,
# not how long it blocks once running. With 4 constellations now pre-
# generated one per prestige-cycle (see root_ui.gd's _on_*_prestige_complete
# handlers), the harder/larger later constellations needing multiple
# uniqueness-retry attempts (MAX_GENERATION_ATTEMPTS, below) could stall
# the whole game for several seconds right after a prestige dialogue. Since
# there's a full prestige cycle's worth of real time before the result is
# actually needed, generate_clues_forms() now yields a frame between
# attempts (when a host is available — see _host above) so generation
# happens spread across frames instead of blocking one. Deliberately NOT
# touched: the attempt's own internal Forms/tier logic — only the
# already-existing, already-instrumented outer retry-loop boundary yields.
# ==================================================
# Check puzzle.is_generation_complete() before reading get_form_clue_texts().

signal generation_complete(constellation_id: int)

func is_generation_complete() -> bool:
    return _generation_complete


func generate_clues_async() -> void:
    await generate_clues_forms()
    generation_complete.emit(constellation_id)

 


# ==================================================
# VALIDATION HELPER — ported verbatim
# ==================================================
func check_solution(candidate: Array) -> bool:
    if candidate.size() != star_count:
        return false
    for i in star_count:
        # No current caller (confirmed dead code, kept as a validation
        # utility) — but candidate's elements are untyped, and the global
        # int() constructor crashes outright on a Dictionary/Array element
        # rather than raising a catchable error. _coerce_int() defaults to
        # 0 for a wrong-typed element instead.
        if _coerce_int(candidate[i], 0) != pitch_rank_solution[i]:
            return false
    return true


# ==================================================
# CACHE SERIALIZATION
# ==================================================
# version 2: chosen_form_clues (the Forms-architecture clue set — each entry
# {form_id, form_name, text, characteristics}) now round-trips. Old caches
# (version 1, header-only, predating the Forms clue set entirely) are
# invalidated below and regenerated — there is nothing meaningful to migrate
# from a cache that never stored a clue set at all.
# version 3: each chosen_form_clues entry also carries "chars" — the raw
# {cat, star[, ref]} node list the clue's text was built from (previously
# discarded down to coarse "characteristics" tab tags before caching).
# version 4: each entry also carries "cells" — the clue's actual ASSERTIONS,
# converted from its grid_updates into star space. "chars" only records
# which entities a clue MENTIONS; two clues asserting opposite things
# ("X is 7th" vs "neither X nor Y is 7th") have identical chars, so coverage
# built on chars structurally cannot tell a confirm from an elimination.
# A cell is {cat_a, star_a, cat_b, star_b, is_true} meaning "the star
# identified via cat_a and the star identified via cat_b are (is_true) or
# are not (not is_true) the same star" — see _build_matrix()'s
# `is_true: star_a == star_b`. Persisted in star space rather than the
# matrix's own per-category value indices because _cat_value_to_star (the
# bijection those indices are relative to) is generator-internal and never
# cached; star indices are what the overlay already has for every other
# cached field. See ConstellationPuzzleDeduction._clue_coverage().
# version 5: each entry also carries "search_terms" — the values the clue's
# text VISIBLY states, as "N:"/"S:"/"C:"/"P:"/"H:" prefixed tokens, recorded
# by _characteristic_label() as it renders them. Neither "chars" nor "cells"
# can serve the Clues SEARCH tab: chars lists nodes a Form may never render
# (Range's Sequence node, Pairwise Order's axis nodes), and hop amounts are
# computed from _distances, which is generator-internal and never cached.
# version 6: each entry also carries "disclosures" — the clue's solver_facts,
# i.e. what it actually TELLS the player, in a typed constraint vocabulary
# (ordinal_cmp / ordinal_range / all_different / ...). Cells cannot express
# relational content at all (a cell only says "same star / different star"),
# so ~78%% of clues had nothing coverage could score. See
# ConstellationPuzzleDeduction._disclosure_satisfied().
#
# version 7: distance_hop disclosures also carry ref_cat/target_cat, the
# categories each end was DESCRIBED under. A version-6 distance clue records
# only two solution star indices, which the deduction side cannot soundly
# reason from — see the note on Form 15's value_facts. Bumped rather than
# defaulted because a half-populated distance clue would silently derive
# nothing while looking fully wired; _load_cache() rejects the whole cache on
# a version mismatch, so those puzzles regenerate.
const CACHE_VERSION: int = 7

# get_puzzle_cache() only guarantees the outer Dictionary it returns is a
# real Dictionary — the save-derived fields inside it aren't typed-checked
# at all. The global int()/bool() constructors crash outright on a
# Dictionary/Array value (confirmed this session), and a typed `Dictionary`
# variable assignment from a wrong-typed element (e.g. a chosen_form_clues
# entry that isn't a Dictionary) hangs rather than raising a catchable
# error — every field read in from_cache_dict() below is routed through
# one of these first.
func _coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


func _coerce_bool(val, default: bool) -> bool:
    if typeof(val) == TYPE_BOOL:
        return val
    return default


func _coerce_array(val, default: Array) -> Array:
    if typeof(val) == TYPE_ARRAY:
        return val
    return default


func to_cache_dict() -> Dictionary:
    return {
        "version":             CACHE_VERSION,
        "constellation_id":    constellation_id,
        "player_seed_used":    player_seed_used,
        "star_count":          star_count,
        "star_colors":         star_colors.duplicate(),
        "star_degrees":        star_degrees.duplicate(),
        "star_names":          star_names.duplicate(),
        "pitch_rank_solution": pitch_rank_solution.duplicate(),
        "generation_complete": _generation_complete,
        "pitch_count":         pitch_count,
        "pitch_freq_rank":     _pitch_freq_rank.duplicate(),
        "chosen_form_clues":   chosen_form_clues.duplicate(true),
    }


func from_cache_dict(data: Dictionary) -> bool:
    if _coerce_int(data.get("version"), 0) != CACHE_VERSION:
        push_warning("ConstellationLogicPuzzle: cache version mismatch, ignoring cached data.")
        return false
    constellation_id    = _coerce_int(data.get("constellation_id"), -1)
    player_seed_used    = _coerce_int(data.get("player_seed_used"), 0)
    star_count          = _coerce_int(data.get("star_count"), 0)
    _generation_complete = _coerce_bool(data.get("generation_complete"), false)

    star_colors = []
    for v in _coerce_array(data.get("star_colors"), []):
        star_colors.append(_coerce_int(v, 0))

    star_degrees = []
    for v in _coerce_array(data.get("star_degrees"), []):
        star_degrees.append(_coerce_int(v, 0))

    star_names = []
    for v in _coerce_array(data.get("star_names"), []):
        star_names.append(str(v))

    pitch_rank_solution = []
    for v in _coerce_array(data.get("pitch_rank_solution"), []):
        pitch_rank_solution.append(_coerce_int(v, 0))

    pitch_count = _coerce_int(data.get("pitch_count"), 0)
    _pitch_freq_rank = []
    for v in _coerce_array(data.get("pitch_freq_rank"), []):
        _pitch_freq_rank.append(_coerce_int(v, 0))

    chosen_form_clues = []
    for raw_clue in _coerce_array(data.get("chosen_form_clues"), []):
        if not (raw_clue is Dictionary):
            continue
        var rc: Dictionary = raw_clue
        var tags: Array[String] = []
        for t in _coerce_array(rc.get("characteristics"), []):
            tags.append(str(t))
        var loaded_chars: Array = []
        for raw_ch in _coerce_array(rc.get("chars"), []):
            if not (raw_ch is Dictionary):
                continue
            var ch: Dictionary = raw_ch
            var coerced_ch: Dictionary = {
                "cat":  _coerce_int(ch.get("cat"), -1),
                "star": _coerce_int(ch.get("star"), -1),
            }
            if ch.has("ref"):
                coerced_ch["ref"] = _coerce_int(ch.get("ref"), -1)
            loaded_chars.append(coerced_ch)
        var loaded_cells: Array = []
        for raw_cell in _coerce_array(rc.get("cells"), []):
            if not (raw_cell is Dictionary):
                continue
            var cl: Dictionary = raw_cell
            loaded_cells.append({
                "cat_a":  _coerce_int(cl.get("cat_a"), -1),
                "star_a": _coerce_int(cl.get("star_a"), -1),
                "cat_b":  _coerce_int(cl.get("cat_b"), -1),
                "star_b": _coerce_int(cl.get("star_b"), -1),
                "is_true": _coerce_bool(cl.get("is_true"), false),
            })
        var loaded_terms: Array = []
        for raw_term in _coerce_array(rc.get("search_terms"), []):
            loaded_terms.append(str(raw_term))
        chosen_form_clues.append({
            "form_id":         _coerce_int(rc.get("form_id"), 0),
            "form_name":       str(rc.get("form_name", "")),
            "text":            str(rc.get("text", "")),
            "characteristics": tags,
            "chars":           loaded_chars,
            "cells":           loaded_cells,
            "search_terms":    loaded_terms,
            "disclosures":     _coerce_array(rc.get("disclosures"), []).duplicate(true),
        })

    return star_count > 0 and _generation_complete


# ==================================================
# NAME-AXIS SOLVING — NOT PORTED, PENDING REWRITE
# ==================================================
# The old file's _apply_one_name_filter (~420 lines) plus its neighbors
# (_apply_name_single_dot_filters, _name_arcs_from_clues, _name_arc_
# predicate, _name_arc_consistency, _validate_between_clues,
# _possibility_grid_for_name_clues, _solve_names, _backtrack_fc_names) are
# ENTIRELY keyed on the old per-kind kind-strings with bespoke logic per
# kind — unlike the Sequence/Pitch engine above, this isn't structural
# dispatch that can be mechanically re-keyed. It has to be rewritten once
# the finalized Forms table determines what field shapes the new, derived
# Name-axis-relevant Kinds actually produce. Also depends on
# _naked_subset_pass, which lived in the old file's Phase-3 unified-grid
# scaffolding (never wired into live generation there either) — worth
# revisiting once the record array below is defined, since it may turn out
# to be the same structure, or may not be needed in the same shape at all.




# ==================================================
# RECORD ARRAY — Category bijections + Distance relation
# ==================================================
# Five categories participate identically: Name/Sequence are already
# bijective with star; Color/Pitch become bijective via their existing
# sub-ranks (Task #8); Distance is deliberately NOT reduced to a per-star
# bijection — it stays a direct relation read off the existing _distances
# matrix, per the established resolution that trying to force it into a
# single-scalar-per-star shape is the wrong move; naming its target star
# directly (see Characteristic below) already removes the ambiguity a raw
# hop-count alone would have, without needing a parallel sub-rank scheme.

var _cat_star_to_value: Array = []   # [Category] -> Array[int] star -> value_index (Distance slot unused)
var _cat_value_to_star: Array = []   # [Category] -> Array[int] value_index -> star (Distance slot unused)

func _build_record_array() -> void:
    _cat_star_to_value.resize(5)
    _cat_value_to_star.resize(5)

    var name_order: Array = []
    for s in star_count:
        name_order.append(s)
    _cat_value_to_star[Category.NAME] = name_order
    _cat_star_to_value[Category.NAME] = name_order.duplicate()

    var seq_value_to_star: Array = []
    seq_value_to_star.resize(star_count)
    for s in star_count:
        seq_value_to_star[pitch_rank_solution[s]] = s
    _cat_value_to_star[Category.SEQUENCE] = seq_value_to_star
    _cat_star_to_value[Category.SEQUENCE] = pitch_rank_solution.duplicate()

    var color_s2v: Array = _rank_by_raw_and_subrank(star_colors, _color_sub_rank)
    _cat_star_to_value[Category.COLOR] = color_s2v
    _cat_value_to_star[Category.COLOR] = _invert_bijection(color_s2v)

    # Sorted by actual frequency rank (with the random sub-rank tie-break),
    # NOT raw star_pitch_index — that raw table slot carries no frequency
    # meaning at all (see user correction, 2026-07-21: an artifact of the
    # earlier Simon-says-style constellation data, never a real ordering).
    # _order_value() deliberately keeps reading the tie-preserving
    # _pitch_freq_rank directly rather than this bijection — the matrix
    # needs every star in a unique cell, but strict-order clues (Betweenness
    # etc.) need genuine ties to stay visible so they can be rejected.
    var pitch_freq_rank_per_star2: Array = []
    for s in star_count:
        pitch_freq_rank_per_star2.append(_pitch_freq_rank[star_pitch_index[s]])
    var pitch_s2v: Array = _rank_by_raw_and_subrank(pitch_freq_rank_per_star2, _pitch_sub_rank)
    _cat_star_to_value[Category.PITCH] = pitch_s2v
    _cat_value_to_star[Category.PITCH] = _invert_bijection(pitch_s2v)


func _rank_by_raw_and_subrank(raw_values: Array, sub_ranks: Array) -> Array:
    var order: Array = []
    for s in star_count:
        order.append(s)
    order.sort_custom(func(a, b):
        if raw_values[a] != raw_values[b]:
            return raw_values[a] < raw_values[b]
        return sub_ranks[a] < sub_ranks[b])
    var star_to_value: Array = []
    star_to_value.resize(star_count)
    for i in order.size():
        star_to_value[order[i]] = i
    return star_to_value


func _invert_bijection(star_to_value: Array) -> Array:
    var value_to_star: Array = []
    value_to_star.resize(star_to_value.size())
    for s in star_to_value.size():
        value_to_star[star_to_value[s]] = s
    return value_to_star


func _freq_for_star(s: int) -> float:
    return _pitch_freqs[star_pitch_index[s]]


func _group_size(cat: int, star: int) -> int:
    # How many stars share this star's raw value in the given category —
    # 1 for Name/Sequence (always singleton), variable for Color/Pitch.
    match cat:
        Category.COLOR:
            var n: int = 0
            for c in star_colors:
                if c == star_colors[star]:
                    n += 1
            return n
        Category.PITCH:
            var n2: int = 0
            for pi in star_pitch_index:
                if pi == star_pitch_index[star]:
                    n2 += 1
            return n2
    return 1


func _category_uniquely_labels(cat: int, star: int) -> bool:
    # _characteristic_label's Color/Pitch branches append a sub-rank letter
    # ("marked B") whenever _group_size > 1, to keep the LABEL itself
    # unambiguous — but that letter is pure internal bookkeeping
    # (_color_sub_rank/_pitch_sub_rank), never drawn or exposed anywhere in
    # constellation_overlay.gd or constellation_study_overlay.gd (confirmed
    # by grep — no draw_string call references them at all). A clue
    # identifying a star as "the white star marked B" is unverifiable by a
    # real player, who has no way to see which white star is "B" versus
    # "A". Name and Sequence are always safe (alldiff, group size 1);
    # Color/Pitch are only safe to use as an IDENTITY label for a star
    # whose raw value happens to be unique among all stars — not as a
    # comparison/equality/group AXIS, which never needs to address one
    # specific group member and so isn't affected by this at all.
    return _group_size(cat, star) <= 1


## Names the set of stars sharing `star`'s raw Colour/Pitch value.
##
## The article is not cosmetic here. "a star that plays B4" tells the
## player there may be others; "the star that plays B4" tells them there is
## exactly one, which is a different and usually decisive fact. "every star
## that plays B4" implies a group the same way. When the value is a
## singleton, both readings actively mislead — the clue describes a
## one-star set as though the player still had to work out which member is
## meant.
##
## Nothing is leaked by saying "the": the pitch checklist already shows an
## incidence count per note (staff_popup.add_pitch_row -> show_count), so
## how many stars carry each note is public from the start. The indefinite
## article was contradicting the UI, not protecting anything.
##
## _characteristic_label and the DISTANCE branch already choose their
## article from _group_size; these Forms hardcoded theirs, which is the bug
## this exists to remove.
##
## `universal` picks the plural-set phrasing ("every ...") over the
## existential one ("a ..."); singletons collapse to "the ..." either way.
func _group_noun_phrase(cat: int, star: int, universal: bool) -> String:
    var singleton: bool = _group_size(cat, star) <= 1
    if cat == Category.COLOR:
        var cname: String = COLOR_NAMES[star_colors[star]].to_lower()
        if singleton:
            return "the %s star" % cname
        return ("every %s star" % cname) if universal else ("a %s star" % cname)
    var pname: String = note_name_for_freq(_freq_for_star(star))
    if singleton:
        return "the star that plays %s" % pname
    return ("every star that plays %s" % pname) if universal else ("a star that plays %s" % pname)


# A Characteristic is {"cat": Category, "star": int} for NAME/SEQUENCE/
# COLOR/PITCH — "star" fully resolves the value via the bijections above.
# DISTANCE is {"cat": Category.DISTANCE, "star": int, "ref": int}: "star" is
# the already-named target, "ref" the anchor, value = _distances[ref][star].
#
# A Cell pairs two Characteristics from two DIFFERENT categories:
# {"a": Characteristic, "b": Characteristic}. Truth = a.star == b.star —
# uniform across all five categories, since every Characteristic resolves
# to exactly one target star regardless of which category produced it.

func _characteristic_key(ch: Dictionary) -> String:
    if int(ch["cat"]) == Category.DISTANCE:
        return "D:%d:%d" % [int(ch["ref"]), int(ch["star"])]
    return "%d:%d" % [int(ch["cat"]), int(ch["star"])]


func _characteristic_from_key(key: String) -> Dictionary:
    var parts: PackedStringArray = key.split(":")
    if parts[0] == "D":
        return {"cat": Category.DISTANCE, "ref": int(parts[1]), "star": int(parts[2])}
    return {"cat": int(parts[0]), "star": int(parts[1])}


# Search terms rendered by _characteristic_label() for the clue currently
# being built. This function is the ONE place a visible star reference is
# produced, which is what makes it the correct source for "explicitly used
# in clues": the `chars` node list is not, because several Forms carry
# nodes they never render (Form 8/Range's Sequence node is bookkeeping
# only; Pairwise Order's axis nodes are never individually rendered), and
# hop amounts appear nowhere in cached data at all.
#
# Reset before each Form attempt and harvested only when a clue actually
# commits — see generate_clues_forms()'s attempt loop.
var _rendered_terms: Dictionary = {}


func _note_rendered_term(kind: String, value) -> void:
    _rendered_terms["%s:%s" % [kind, str(value)]] = true


## For the GROUP phrasings a few Forms build themselves rather than through
## _characteristic_label ("every blue star", "a star that plays A#4", "the
## blue stars"). Those state a colour or a pitch just as explicitly as a
## label does, and were invisible to the search sets until this existed —
## caught by a harness that found the Colour and Hop sets coming back
## completely empty on a real puzzle.
func _note_group_value_term(cat: int, star: int) -> void:
    if cat == Category.COLOR:
        _note_rendered_term("C", COLOR_NAMES[star_colors[star]])
    elif cat == Category.PITCH:
        _note_rendered_term("P", note_name_for_freq(_freq_for_star(star)))


func _characteristic_label(ch: Dictionary) -> String:
    # Always a uniquely-resolving descriptor (sub-rank included whenever the
    # raw group has more than one member) — a Characteristic always refers
    # to exactly one star by construction, so "the" is always correct here;
    # the definite/indefinite distinction matters for OTHER text (group
    # descriptions, decoy values) built elsewhere, not for this function.
    var s: int = int(ch["star"])
    match int(ch["cat"]):
        Category.NAME:
            _note_rendered_term("N", star_names[s])
            return star_names[s]
        Category.SEQUENCE:
            _note_rendered_term("S", pitch_rank_solution[s] + 1)
            return "the star that fires %s" % _ordinal(pitch_rank_solution[s] + 1)
        Category.COLOR:
            # The sub-rank letter ("marked B") is internal bookkeeping with
            # no player-facing meaning, so the searchable term is the colour
            # itself either way.
            _note_rendered_term("C", COLOR_NAMES[star_colors[s]])
            if _group_size(Category.COLOR, s) <= 1:
                return "the %s star" % COLOR_NAMES[star_colors[s]].to_lower()
            return "the %s star marked %s" % [COLOR_NAMES[star_colors[s]].to_lower(), _sub_rank_letter(_color_sub_rank[s])]
        Category.PITCH:
            var pname: String = note_name_for_freq(_freq_for_star(s))
            _note_rendered_term("P", pname)
            if _group_size(Category.PITCH, s) <= 1:
                return "the star that plays %s" % pname
            return "the star that plays %s marked %s" % [pname, _sub_rank_letter(_pitch_sub_rank[s])]
        Category.DISTANCE:
            var ref: int = int(ch["ref"])
            var d: int = _distances[ref][s]
            var article: String = "the" if _stars_at_distance(ref, d).size() <= 1 else "a"
            # This phrasing states TWO searchable things: the hop amount and
            # the reference star's name ("a star 2 hops from Theryis"), so a
            # search for that name must find this clue.
            _note_rendered_term("H", d)
            _note_rendered_term("N", star_names[ref])
            return "%s star %d %s from %s" % [article, d, _hop_word(d), star_names[ref]]
    return "?"


func _hop_word(d: int) -> String:
    return "hop" if d == 1 else "hops"


func _stars_at_distance(ref: int, d: int) -> Array:
    var out: Array = []
    for s in star_count:
        if s != ref and _distances[ref][s] == d:
            out.append(s)
    return out


# ==================================================
# USED/UNUSED CHARACTERISTIC TRACKING + SAMPLING PRIMITIVES
# ==================================================

var _used_characteristics: Dictionary = {}

func _is_used(ch: Dictionary) -> bool:
    return _used_characteristics.has(_characteristic_key(ch))


func _mark_used(ch: Dictionary) -> void:
    _used_characteristics[_characteristic_key(ch)] = true


func _unused_pool_size() -> int:
    # Termination signal for the main loop (Step 13): total Unused cells
    # across every actual cell in the matrix — every bijective category
    # pair's full star_count x star_count grid — not the coarser per-
    # Characteristic count this used to read. Distance stays on its own
    # separate per-target-star tracking (it isn't part of the matrix at
    # all — a relation, not a bijective category — so "D:*:N" in
    # _used_characteristics is still the right mechanism for it).
    var count: int = 0
    for key in _matrix.keys():
        var rows: Array = _matrix[key]
        for row in rows:
            for cell in row:
                if not bool(cell["used"]):
                    count += 1
    for s in star_count:
        if not _used_characteristics.has("D:*:%d" % s):
            count += 1
    return count


func _mark_distance_used_for_star(target_star: int) -> void:
    # Distance's termination-counting unit: once ANY distance-fact naming
    # this star as the target has been asserted, that star's Distance slot
    # counts used — regardless of which reference star was involved. Keeps
    # Distance's pool the same star_count size as the other four categories
    # instead of the much larger full (ref, target) combinatorial space.
    _used_characteristics["D:*:%d" % target_star] = true


var _last_clue_nodes: Array = []
# Step 9, corrected: chaining draws from the Category-Value pairs
# INSTALLED INTO NODES for the immediately-previous clue specifically —
# not the accumulated Used history. Those are different pools: the
# ZebraTutor pass (Step 7) marks a cell Used whenever it's derivable from
# a clue (cascade-resolved rows/columns, or a sampled cell's other side
# that was never actually installed into a node), which is generally much
# larger than what one clue's Form template actually displayed to the
# player. _last_clue_nodes holds only the latter — set after each clue
# commits, to that clue's own "chars" list (see generate_clues_forms()).

func _pick_chain_characteristic() -> Dictionary:
    if _last_clue_nodes.is_empty():
        return {}   # the very first clue has no previous clue to chain from
    return _last_clue_nodes[_rng.randi_range(0, _last_clue_nodes.size() - 1)]




func _commit_characteristics(chars: Array) -> void:
    for ch in chars:
        if int(ch["cat"]) == Category.DISTANCE:
            _mark_distance_used_for_star(int(ch["star"]))
        else:
            _mark_used(ch)


# ==================================================
# ARRAY/MATRIX — an actual pre-built, persistent structure
# ==================================================
# Populated ONCE, upfront, as real stored data — not computed on demand.
# For every pair of the four bijective categories, a star_count x
# star_count array of cell Dictionaries, each holding its own True/False
# (fixed at build time from ground truth) and Used/Unused (mutable,
# starts Unused, flips as clues reveal or derive it) fields. This is the
# literal matrix, built once by _build_matrix() and read/written directly
# everywhere after — no lazy recomputation, no parallel tracker.

const BIJECTIVE_CATEGORIES: Array = [Category.NAME, Category.SEQUENCE, Category.COLOR, Category.PITCH]
var _matrix: Dictionary = {}   # "loCat:hiCat" -> Array[star_count][star_count] of {"is_true":bool, "used":bool}

func _pair_key(cat_a: int, cat_b: int) -> String:
    var lo: int = mini(cat_a, cat_b)
    var hi: int = maxi(cat_a, cat_b)
    return "%d:%d" % [lo, hi]


func _build_matrix() -> void:
    _matrix = {}
    for i in BIJECTIVE_CATEGORIES.size():
        for j in range(i + 1, BIJECTIVE_CATEGORIES.size()):
            var ca: int = int(BIJECTIVE_CATEGORIES[i])
            var cb: int = int(BIJECTIVE_CATEGORIES[j])
            var rows: Array = []
            rows.resize(star_count)
            for v1 in star_count:
                var row: Array = []
                row.resize(star_count)
                var star_a: int = int(_cat_value_to_star[ca][v1])
                for v2 in star_count:
                    var star_b: int = int(_cat_value_to_star[cb][v2])
                    row[v2] = {"is_true": star_a == star_b, "used": false}
                rows[v1] = row
            _matrix[_pair_key(ca, cb)] = rows


func _matrix_cell(cat_a: int, val_a: int, cat_b: int, val_b: int) -> Dictionary:
    var rows: Array = _matrix[_pair_key(cat_a, cat_b)]
    var row: int = val_a if cat_a < cat_b else val_b
    var col: int = val_b if cat_a < cat_b else val_a
    return rows[row][col]


## Weight given to Category.NAME specifically, at the handful of category-
## draw sites inside the Forms that feed the NAME closure (Exact Identity,
## Single Negation, Group Order, Equality Pair — see the bias_name
## parameter each takes). Found necessary by the coverage audit
## (generator_ships_unsolvable_puzzles.md): 40% of untouched singleton-
## pitch stars WERE disclosed by a closure-feeding Form, just not paired
## with NAME that specific draw. A real weighted random pick, not a
## best-first ranking — same distinction MUTEX_REPEAT_CATEGORY_WEIGHT's
## own comment makes: always picking the highest-weighted option would
## make every draw from these Forms look the same, trading clue variety
## for closure coverage instead of just improving the odds. Scoped to
## these specific call sites via an opt-in parameter, never touching the
## shared helpers' behavior for the ~15 OTHER Forms that also call them.
const CLOSURE_NAME_BIAS_WEIGHT := 2.0

## Weighted-random pick from `items` (single pick, no removal — unlike
## _mutex_weighted_pick_remove, nothing here drains a pool across
## multiple draws). Returns items[items.size()-1] on float-rounding
## fallback, same convention as _mutex_weighted_pick_remove.
func _weighted_pick(items: Array, weights: Array) -> int:
    var total: float = 0.0
    for w in weights:
        total += float(w)
    var roll: float = _rng.randf() * total if total > 0.0 else 0.0
    var acc: float = 0.0
    for i in items.size():
        acc += float(weights[i])
        if roll < acc:
            return int(items[i])
    return int(items[items.size() - 1])


## Weighted pick over {NAME, SEQUENCE, COLOR, PITCH} \ {exclude}, favoring
## NAME by CLOSURE_NAME_BIAS_WEIGHT. Shared by both identity-cell samplers'
## bias_name paths — same pool, same weighting, one place to retune.
func _weighted_category_excluding(exclude: int) -> int:
    var pool: Array = []
    for c in [Category.NAME, Category.SEQUENCE, Category.COLOR, Category.PITCH]:
        if int(c) != exclude:
            pool.append(c)
    var weights: Array = []
    for c2 in pool:
        weights.append(CLOSURE_NAME_BIAS_WEIGHT if int(c2) == Category.NAME else 1.0)
    return _weighted_pick(pool, weights)


func _random_bijective_category_pair(bias_name: bool = false) -> Array:
    var pool: Array = BIJECTIVE_CATEGORIES.duplicate()
    if not bias_name:
        _shuffle_array(pool)
        return [pool[0], pool[1]]
    var weights: Array = []
    for c in pool:
        weights.append(CLOSURE_NAME_BIAS_WEIGHT if int(c) == Category.NAME else 1.0)
    var first: int = _weighted_pick(pool, weights)
    pool.erase(first)
    _shuffle_array(pool)
    return [first, pool[0]]


func _sample_grid_cell_from_chain(chain_cat: int, chain_star: int, other_cat: int) -> Dictionary:
    # Step 9/10: one side is the chain characteristic reused AS-IS from the
    # previous clue's nodes (not resampled), the other side is a randomly-
    # picked Unused cell along that fixed row/column — still no steering
    # toward True or False on the fresh side. Both sides get rendered via
    # _characteristic_label by every caller of this (Forms 1/2/4), so both
    # must uniquely label their star — chain_star's own check guards
    # against a REUSED node that was only ever bookkeeping in its original
    # clue (e.g. Pairwise Order's axis_a/axis_b are never individually
    # rendered there, so were never checked at the time they were picked).
    if not _category_uniquely_labels(chain_cat, chain_star):
        return {}
    var chain_val: int = int(_cat_star_to_value[chain_cat][chain_star])
    var candidates: Array = []
    for v in star_count:
        if not bool(_matrix_cell(chain_cat, chain_val, other_cat, v)["used"]) and _category_uniquely_labels(other_cat, int(_cat_value_to_star[other_cat][v])):
            if _prefer_true_cells and not bool(_matrix_cell(chain_cat, chain_val, other_cat, v)["is_true"]):
                continue
            candidates.append(v)
    if candidates.is_empty():
        return {}
    var other_val: int = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
    return {
        "cat_a": chain_cat, "val_a": chain_val, "star_a": chain_star,
        "cat_b": other_cat, "val_b": other_val, "star_b": int(_cat_value_to_star[other_cat][other_val]),
        "is_true": bool(_matrix_cell(chain_cat, chain_val, other_cat, other_val)["is_true"]),
    }


func _sample_grid_cell_maybe_chained(chain: Dictionary, bias_name: bool = false) -> Dictionary:
    # Chaining is the standard case, not an occasional preference — every
    # clue after the first reuses one node from the immediately-previous
    # clue (Step 9). Falls back to a fresh, unchained pair only when there
    # is no previous clue yet, or the chain's own category has nothing
    # left to pair against.
    if not chain.is_empty() and int(chain["cat"]) != Category.DISTANCE:
        var chain_cat: int = int(chain["cat"])
        var other_pool: Array = []
        for c in BIJECTIVE_CATEGORIES:
            if int(c) != chain_cat:
                other_pool.append(c)
        _shuffle_array(other_pool)
        # Trying NAME first (when eligible) costs nothing and loses no
        # variety — this is an ORDERED ATTEMPT LIST, not a final pick; if
        # NAME fails (already used/no candidates) every other option still
        # gets tried in its shuffled order exactly as before. Unlike the
        # fresh-pair case below, no soft weighting needed here.
        if bias_name and other_pool.has(Category.NAME):
            other_pool.erase(Category.NAME)
            other_pool.push_front(Category.NAME)
        for other_cat in other_pool:
            var cell: Dictionary = _sample_grid_cell_from_chain(chain_cat, int(chain["star"]), int(other_cat))
            if not cell.is_empty():
                return cell
    var pair: Array = _random_bijective_category_pair(bias_name)
    return _sample_grid_cell(int(pair[0]), int(pair[1]))


func _sample_grid_cell(cat_a: int, cat_b: int) -> Dictionary:
    # Purely random cell pick — no steering toward True or False. Whatever
    # status ALREADY STORED in the matrix for the randomly-landed cell is
    # what gets reported; grammar phrases it "is"/"is not" as a
    # CONSEQUENCE, never as an input the sampler aims for. Both sides get
    # rendered via _characteristic_label by every caller (Forms 1/2/4), so
    # both must uniquely label their star — a Color/Pitch value shared by
    # 2+ stars would otherwise render as "marked B", a sub-rank letter that
    # exists purely as internal matrix bookkeeping and is never shown to
    # the player anywhere in the game (no draw_string call references it
    # in constellation_overlay.gd or constellation_study_overlay.gd).
    var candidates: Array = []
    for v1 in star_count:
        for v2 in star_count:
            if not bool(_matrix_cell(cat_a, v1, cat_b, v2)["used"]) \
            and _category_uniquely_labels(cat_a, int(_cat_value_to_star[cat_a][v1])) \
            and _category_uniquely_labels(cat_b, int(_cat_value_to_star[cat_b][v2])):
                if _prefer_true_cells and not bool(_matrix_cell(cat_a, v1, cat_b, v2)["is_true"]):
                    continue
                candidates.append([v1, v2])
    if candidates.is_empty():
        return {}
    var pick: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
    var val_a: int = int(pick[0])
    var val_b: int = int(pick[1])
    var is_true: bool = bool(_matrix_cell(cat_a, val_a, cat_b, val_b)["is_true"])
    return {
        "cat_a": cat_a, "val_a": val_a, "star_a": int(_cat_value_to_star[cat_a][val_a]),
        "cat_b": cat_b, "val_b": val_b, "star_b": int(_cat_value_to_star[cat_b][val_b]),
        "is_true": is_true,
    }


## Marks the ONE cell a clue actually stated. Nothing else.
##
## This used to cascade: on a True cell it also marked that cell's whole
## row and column Used, reasoning that "bijection guarantees exactly one
## True per row and column, so every other cell involving val_a or val_b
## is ALREADY known False." That reasoning is about the SOLUTION, and it
## was used to decide what the PLAYER can derive — a ground-truth fact
## driving a knowledge claim, which is the tier error this project's whole
## matrix-up discipline exists to prevent, committed in the generator where
## the lint does not scan.
##
## It was wrong on its own terms too. The cascade is only sound when the
## player LEARNS the True cell, and almost no Form discloses one: 1542 of
## 1547 True cells emitted across 886 measured clues are (identity, axis)
## pairs whose axis side is never rendered. Pairwise Order says so in its
## own comment ("axis_a/axis_b ... are never textually disclosed as exact
## values") while emitting exactly those cells; Group Membership calls its
## pair "TAUTOLOGICAL self-identity markers". Only Exact Identity renders
## both sides — 5 clues of 886.
##
## `used` is the generator's record of WHAT HAS BEEN SAID, not a model of
## what the player knows. Populating it from the answer key made the
## generator refuse to state facts the player could legitimately still
## learn, which is what collapsed the clue budget to ~2.5x star_count and
## produced every "the Form set cannot express this" result measured
## against it.
##
## The per-CHARACTERISTIC _mark_used calls below are a different mechanism
## on a different pool (_used_characteristics, for chain/repeat steering),
## not a cell-status marking, and are deliberately left exactly as they
## were.
func _apply_grid_cell_result(cat_a: int, val_a: int, cat_b: int, val_b: int, is_true: bool) -> void:
    _matrix_cell(cat_a, val_a, cat_b, val_b)["used"] = true
    if not is_true:
        return
    _mark_used({"cat": cat_a, "star": int(_cat_value_to_star[cat_a][val_a])})
    _mark_used({"cat": cat_b, "star": int(_cat_value_to_star[cat_b][val_b])})


## _grid_zebratutor_pass was REMOVED here 2026-08-18. It ran naked-single
## and naked-subset elimination over the matrix and marked the results
## Used, so the generator would not spend a clue on something already
## derivable. It got derivability wrong in two ways, both the same tier
## error as the True-cell cascade (see the note above
## _apply_grid_cell_result):
##
##   - `used` is ONE BIT conflating "disclosed True", "disclosed False"
##     and "merely touched as bookkeeping", so the pass recovered the
##     missing polarity by reading GROUND TRUTH:
##         row_possible.append((not cell["used"]) or cell["is_true"])
##     `not used` already covers unstated cells, so `or is_true` only ever
##     fired for USED cells — it was consulting the answer key to learn
##     what a clue had asserted.
##   - its naked-single half was unsound outright: "one unused cell left
##     in this row, therefore forced True" is false whenever the row's
##     True cell was among the stated ones (the remainder is then FALSE),
##     and it passed is_true:true unconditionally without checking.
##
## Measured before removing — 20 puzzles per arm, identical seeds, the
## only difference being whether the pass ran:
##
##     cells it marked   688 -> 0        full closures    0 -> 1
##     closure median     29 -> 12       closure mean   246 -> 15
##     closure worst    2848 -> 54       clues/puzzle   258 -> 289
##     seq_unique, contradictions and Forms-firing all unchanged
##
## So it was neither inert nor load-bearing — it was HARMFUL. It spent 688
## cells per 20 puzzles telling the generator not to state facts, on a
## derivability model that read the solution. The unused pool ended at the
## same size either way; with the pass gone that budget goes to real
## clues instead of phantom derivations.
##
## If a redundancy filter is wanted later it needs a tri-state cell
## (unstated / disclosed_true / disclosed_false) so derivability is
## computed from what was actually DISCLOSED, with no ground-truth read —
## and it must stay a SEPARATE derived view, never written back onto the
## record of what has been said.


# ==================================================
# ORDERABLE-AXIS HELPERS — shared by Pairwise Order/Offset/Adjacency/Range/
# Extreme/Betweenness/Group Comparison, which all need "compare two stars'
# values on some category" rather than a plain True/False identity check.
# ==================================================

func _orderable_categories() -> Array:
    # Color deliberately excluded: its record-array bijection index is a
    # coding artifact (sorted by raw enum value, then sub-rank) with no
    # player-observable "greater/lesser" meaning, unlike Sequence (temporal)
    # or Pitch (audibly verifiable via Listen) — a Color comparison clue
    # would be grammatically fine but semantically unsolvable/arbitrary.
    # Color still participates elsewhere via equality/group-membership
    # (Forms 9, 12, 13, 20), just never as a comparison axis.
    return [Category.SEQUENCE, Category.PITCH]


func _order_value(cat: int, star: int) -> int:
    # A star's position on an orderable axis. Sequence: its rank directly.
    # Pitch: ascending-frequency rank (ties share a rank, same structure the
    # pitch solver already uses).
    match cat:
        Category.SEQUENCE:
            return pitch_rank_solution[star]
        Category.PITCH:
            return _pitch_freq_rank[star_pitch_index[star]]
    return 0


func _order_word(cat: int, a_gt_b: bool) -> String:
    match cat:
        Category.SEQUENCE:
            return SEQ_WORD_LATER if a_gt_b else SEQ_WORD_EARLIER
        Category.PITCH:
            return "higher" if a_gt_b else "lower"
    return "greater" if a_gt_b else "lesser"


## The verb carries the AXIS. That is the whole job it does, and Pitch used
## to shirk it: the bare "is" names nothing.
##
## It went unnoticed because every other Form pairs the verb with an
## axis-bearing comparative — "is higher than", "is exactly 2 pitch ranks
## higher than" — which disambiguates on its own. Betweenness does not:
##
##     "Helios is between Nyxaos and the star that fires 5th note."
##
## is a claim about PITCH RANK with nothing in the sentence saying so, and
## one of its three labels is a Sequence descriptor actively pulling the
## reader the wrong way. Reported 2026-08-14.
##
## "is pitched" fixes it in the verb rather than by bolting a qualifier onto
## one Form, and gives Pitch the exact parallel Sequence already had:
##
##     Chroneeia fires between A and B.      Helios is pitched between A and B.
##     Chroneeia fires later than X.         Helios is pitched higher than X.
##
## Only Sequence and Pitch are orderable (see _orderable_categories — Colour
## is deliberately excluded), so the fallthrough IS the Pitch case.
## Connector for Betweenness's two CHAIN phrasings ("X … A, which … B").
##
## These hardcoded "before"/"after" for every axis, so a Pitch clue read
## "Helios is before Keriion" — a temporal word for a frequency ordering,
## wrong since the Form was written. It stayed invisible while the Pitch verb
## was the bare "is"; changing that to "is pitched" turned it into the
## audibly wrong "is pitched before", which is how it was finally noticed —
## by reading the rendered sentences instead of reasoning about them.
##
## Sequence keeps before/after (genuinely temporal). Pitch takes the same
## comparatives _order_word already uses everywhere else, so the whole clue
## set speaks one vocabulary: lower/higher.
func _order_chain_word(cat: int, descending: bool) -> String:
    match cat:
        Category.SEQUENCE:
            return "after" if descending else "before"
    return "higher than" if descending else "lower than"


func _order_verb(cat: int) -> String:
    match cat:
        Category.SEQUENCE:
            return "fires"
    return "is pitched"


func _order_unit(cat: int, count: int) -> String:
    # Exact Offset's "exactly N ___ later/higher than" needs a unit noun.
    # count is always abs(offset), which the 0 guard in
    # _build_form_exact_offset already keeps >= 1.
    #
    # "step" for BOTH axes as of 2026-08-14. It used to be "pitch rank" for
    # Pitch, because — as the old comment here said — "steps" on its own
    # said nothing about what was being counted on that axis. _order_verb
    # now says it: "is pitched exactly 2 steps higher than" carries the axis
    # in the verb, and "is pitched exactly 2 pitch ranks higher" says it
    # twice.
    #
    # So this depends on the verb. If _order_verb ever stops naming the axis
    # for Pitch, this has to go back to "pitch rank" or the sentence loses
    # it entirely.
    var singular: String = "step"
    return singular if count == 1 else singular + "s"


func _non_distance_category() -> int:
    return [Category.NAME, Category.SEQUENCE, Category.COLOR, Category.PITCH][_rng.randi_range(0, 3)]


func _is_hidden_category(cat: int) -> bool:
    # Name and Sequence are the only two axes genuinely unknown to the
    # player — Color is painted on the map and Pitch is fully recoverable
    # via the Listen mechanic, both zero-deduction "given" information once
    # looked at. A Distance-anchored clue (Forms 15/16/19) where every
    # labeled star is drawn from Color/Pitch is entirely re-derivable by
    # looking at the map — true, but contributes nothing a player couldn't
    # already see, and reads as a non-clue. Require at least one labeled
    # star per Distance-anchored clue to come from a hidden axis.
    return cat == Category.NAME or cat == Category.SEQUENCE


# ==================================================
# SOLVER FACTS — what a clue's rendered text actually discloses about the
# Sequence axis, for the Phase C uniqueness check (see generate_clues_forms).
# Pitch needs no equivalent: it carries no uniqueness requirement (fully
# recoverable via Listen — see constellation_puzzle_category_facts_CHECK_
# FIRST memory). These are NOT persisted to chosen_form_clues/cache; they're
# only needed transiently while generating, to prove the shown clue set
# pins Sequence (and, via _name_reveal_facts, Name) to one solution.
#
# CRITICAL: a clue's "chars" array (used for Used-marking/chaining) is NOT
# the same thing as what's textually disclosed — chars records everything
# TOUCHED, including identity-anchor cells used only to pick a star for a
# comparison-shaped clue, which are never actually rendered into the text
# (e.g. Pairwise Order's axis_a/axis_b nodes back the "fires later/higher"
# comparison itself, not a separate exact-value disclosure). Emitting an
# ordinal_exact fact from a merely-touched cell would silently reintroduce
# the ground-truth-leak bug class this refactor exists to fix — one level
# more subtle (leaking bookkeeping as if it were disclosure). Only call
# _seq_fact_for_label on a characteristic that is ACTUALLY passed through
# _characteristic_label(...) in the clue's own text-construction line —
# _characteristic_label renders Category.SEQUENCE as "the star that fires
# Nth", so any such call genuinely discloses that star's exact rank,
# independent of which Form produced it.
# ==================================================

func _capitalize_first(s: String) -> String:
    if s.is_empty():
        return s
    return s[0].to_upper() + s.substr(1)


func _seq_fact_for_label(ch: Dictionary) -> Array:
    if int(ch["cat"]) != Category.SEQUENCE:
        return []
    var s: int = int(ch["star"])
    return [{"kind": "ordinal_exact", "s": s, "r": pitch_rank_solution[s]}]


func _validate_sequence_fact(f: Dictionary) -> String:
    # Every solver_fact is supposed to be derivable straight from ground
    # truth (see the header note above _seq_fact_for_label) — if _solve()
    # ever reports 0 solutions, that means one of them is actually wrong,
    # not that the puzzle is contradictory (every fact here is asserted
    # about a REAL constellation, which always has at least one consistent
    # assignment: the true one). This check pinpoints exactly which fact
    # and why, rather than leaving a bare "0 solutions" to debug blind.
    match str(f.get("kind", "")):
        "ordinal_exact":
            var s: int = int(f["s"])
            var r: int = int(f["r"])
            if pitch_rank_solution[s] != r:
                return "ordinal_exact s=%d claims rank=%d but true rank=%d" % [s, r, pitch_rank_solution[s]]
        "ordinal_neg":
            var s2: int = int(f["s"])
            var r2: int = int(f["r"])
            if pitch_rank_solution[s2] == r2:
                return "ordinal_neg s=%d claims rank!=%d but true rank IS %d" % [s2, r2, pitch_rank_solution[s2]]
        "ordinal_cmp":
            var a: int = int(f["a"])
            var b: int = int(f["b"])
            var a_gt_b: bool = bool(f["a_gt_b"])
            var actual: bool = pitch_rank_solution[a] > pitch_rank_solution[b]
            if actual != a_gt_b:
                return "ordinal_cmp a=%d b=%d claims a_gt_b=%s but true ranks are %d,%d" % [a, b, str(a_gt_b), pitch_rank_solution[a], pitch_rank_solution[b]]
        "ordinal_chain":
            var ca: int = int(f["a"])
            var cmid: int = int(f["mid"])
            var cb: int = int(f["b"])
            if not (pitch_rank_solution[ca] < pitch_rank_solution[cmid] and pitch_rank_solution[cmid] < pitch_rank_solution[cb]):
                return "ordinal_chain a=%d mid=%d b=%d claims a<mid<b but true ranks are %d,%d,%d" % [ca, cmid, cb, pitch_rank_solution[ca], pitch_rank_solution[cmid], pitch_rank_solution[cb]]
        "ordinal_adjacent", "ordinal_offset":
            var oa: int = int(f["a"])
            var ob: int = int(f["b"])
            var off: int = int(f.get("offset", 1))
            if pitch_rank_solution[oa] != pitch_rank_solution[ob] + off:
                return "%s a=%d b=%d offset=%d claims a=b+offset but true ranks are %d,%d" % [str(f["kind"]), oa, ob, off, pitch_rank_solution[oa], pitch_rank_solution[ob]]
        "ordinal_range":
            var rs: int = int(f["s"])
            var lo: int = int(f["lo"])
            var hi: int = int(f["hi"])
            if pitch_rank_solution[rs] < lo or pitch_rank_solution[rs] > hi:
                return "ordinal_range s=%d claims rank in [%d,%d] but true rank=%d" % [rs, lo, hi, pitch_rank_solution[rs]]
        "ordinal_either_or":
            var es: int = int(f["s"])
            var r1: int = int(f["r1"])
            var r2: int = int(f["r2"])
            if pitch_rank_solution[es] != r1 and pitch_rank_solution[es] != r2:
                return "ordinal_either_or s=%d claims rank in {%d,%d} but true rank=%d" % [es, r1, r2, pitch_rank_solution[es]]
        "ordinal_extreme":
            var xs: int = int(f["s"])
            var want_lowest: bool = bool(f["want_lowest"])
            for n in f["neighbors"]:
                var nn: int = int(n)
                if want_lowest and pitch_rank_solution[nn] <= pitch_rank_solution[xs]:
                    return "ordinal_extreme s=%d (want_lowest) neighbor=%d violates: neighbor true rank %d <= subject true rank %d" % [xs, nn, pitch_rank_solution[nn], pitch_rank_solution[xs]]
                if not want_lowest and pitch_rank_solution[nn] >= pitch_rank_solution[xs]:
                    return "ordinal_extreme s=%d (want_highest) neighbor=%d violates: neighbor true rank %d >= subject true rank %d" % [xs, nn, pitch_rank_solution[nn], pitch_rank_solution[xs]]
        "ordinal_count_before":
            var cs: int = int(f["s"])
            var k: int = int(f["k"])
            var before: int = 0
            for n2 in f["neighbors"]:
                if pitch_rank_solution[int(n2)] < pitch_rank_solution[cs]:
                    before += 1
            if before != k:
                return "ordinal_count_before s=%d claims k=%d but actual true before-count=%d" % [cs, k, before]
    return ""


# ==================================================
# NAME CLOSURE FACTS — Phase 2 of the position-axis migration
# ==================================================
# What a clue's rendered text discloses about the NAME axis, same
# discipline as _seq_fact_for_label above: only call this on characteristics
# that were ACTUALLY DISCLOSED in the clue's own text line, never on
# grid_updates/chars alone — those include touched-but-unrendered
# bookkeeping (Pairwise Order's axis_a/axis_b, Equality Pair's axis_a/
# axis_b) that would silently reintroduce the same ground-truth-leak class
# this whole migration exists to close, one level more subtle for landing
# on a bijection-position value instead of a rank.
#
# "Disclosed" has TWO legitimate shapes, not one — a characteristic passed
# through _characteristic_label() (an individual star's identity), or one
# whose raw value is named directly in a GROUP-descriptive phrase like
# _group_noun_phrase or Cross-Domain Bridge/Group Membership's group_phrase
# ("the blue stars"). The second shape never goes through
# _characteristic_label at all — it can't, Colour/Pitch are rarely unique —
# but the raw value is still genuinely stated in the text, which is the
# actual test, not which function happened to render it.
#
# group_key is the OBSERVING star's raw value under cat, never a resolved
# position list — same choice distance_hop made for ref_cat/target_cat, and
# for the same reason: it lets any consumer (this generator's own closure
# below, or a future player-side reader) reconstruct the actual membership
# from ITS OWN knowledge tier, rather than trusting a pre-resolved list.

func _name_group_key(cat: int, star: int) -> int:
    match cat:
        Category.COLOR:
            return int(star_colors[star])
        Category.PITCH:
            return int(star_pitch_index[star])
        Category.SEQUENCE:
            return int(pitch_rank_solution[star])
    return -1


func _name_group_facts(ch_a: Dictionary, ch_b: Dictionary, is_true: bool) -> Array:
    # Exactly one side must be Category.NAME — NAME-vs-NAME and
    # non-NAME-vs-non-NAME both disclose nothing about which position a
    # name belongs to. Distance is ternary (no single group_key) and
    # excluded, same as _seq_fact_for_label excludes non-Sequence cats.
    var a_is_name: bool = int(ch_a["cat"]) == Category.NAME
    var b_is_name: bool = int(ch_b["cat"]) == Category.NAME
    if a_is_name == b_is_name:
        return []
    var name_ch: Dictionary = ch_a if a_is_name else ch_b
    var obs_ch: Dictionary = ch_b if a_is_name else ch_a
    var obs_cat: int = int(obs_ch["cat"])
    if obs_cat != Category.COLOR and obs_cat != Category.PITCH and obs_cat != Category.SEQUENCE:
        return []
    return [{
        "kind": "name_group" if is_true else "name_group_neg",
        "name_star": int(name_ch["star"]),
        "cat": obs_cat,
        "group_key": _name_group_key(obs_cat, int(obs_ch["star"])),
    }]


func _validate_name_group_fact(f: Dictionary) -> String:
    var s: int = int(f["name_star"])
    var cat: int = int(f["cat"])
    var key: int = int(f["group_key"])
    var actual: int = _name_group_key(cat, s)
    var kind: String = str(f.get("kind", ""))
    if kind == "name_group" and actual != key:
        return "name_group name_star=%d cat=%d claims group_key=%d but true=%d" % [s, cat, key, actual]
    if kind == "name_group_neg" and actual == key:
        return "name_group_neg name_star=%d cat=%d claims group_key!=%d but true group_key IS %d" % [s, cat, key, actual]
    return ""


## Group Order's claim (form_id 9): subject's RANK precedes/follows EVERY
## member of a Colour/Pitch group — a range restriction, not the "belongs
## to this group" shape name_group/name_group_neg cover. Different claim,
## different kind, on purpose: forcing it through the membership shape
## would either lose the ordinal content or misrepresent it as exact
## membership, neither of which is what the clue actually asserts.
func _name_order_vs_group_facts(subject_id: Dictionary, group_def_ch: Dictionary, precedes: bool) -> Array:
    if int(subject_id["cat"]) != Category.NAME:
        return []
    var obs_cat: int = int(group_def_ch["cat"])
    if obs_cat != Category.COLOR and obs_cat != Category.PITCH:
        return []
    return [{
        "kind": "name_precedes_group" if precedes else "name_follows_group",
        "name_star": int(subject_id["star"]),
        "cat": obs_cat,
        "group_key": _name_group_key(obs_cat, int(group_def_ch["star"])),
    }]


func _validate_name_order_vs_group_fact(f: Dictionary) -> String:
    var s: int = int(f["name_star"])
    var cat: int = int(f["cat"])
    var key: int = int(f["group_key"])
    var kind: String = str(f.get("kind", ""))
    var subj_rank: int = int(pitch_rank_solution[s])
    for m in star_count:
        if _name_group_key(cat, m) != key:
            continue
        var member_rank: int = int(pitch_rank_solution[m])
        if kind == "name_precedes_group" and subj_rank >= member_rank:
            return "name_precedes_group name_star=%d cat=%d group_key=%d claims subject precedes every member but subject rank=%d >= member %d rank=%d" % [s, cat, key, subj_rank, m, member_rank]
        if kind == "name_follows_group" and subj_rank <= member_rank:
            return "name_follows_group name_star=%d cat=%d group_key=%d claims subject follows every member but subject rank=%d <= member %d rank=%d" % [s, cat, key, subj_rank, m, member_rank]
    return ""


## Cross-Domain Bridge's claim (form_id 20): the subject is the Sequence-
## EXTREME member OF a Colour/Pitch group — "Among the blue stars, the
## earliest-firing one is X." Strictly stronger than name_group's plain
## membership: a group's extreme member is a SINGLE position once the
## Sequence solution is known, so this PINS a name rather than narrowing
## it. Exact pins are the scarcest thing the closure gets (measured ~6-8%
## of names), which is why this Form was worth its own fact kind.
##
## DELIBERATELY NOT name_precedes_group, and the difference is not
## cosmetic: that kind means "precedes every member of the group," and
## _validate_name_order_vs_group_fact loops over EVERY member requiring
## subj_rank < member_rank. Here the subject IS a member, so the m ==
## subject comparison would test its rank against itself and fire a
## spurious INCONSISTENT NAME-ORDER FACT on every single clue. The
## validator below skips m == s for exactly that reason.
func _name_extreme_in_group_facts(name_ch: Dictionary, group_def_ch: Dictionary, want_lowest: bool) -> Array:
    if int(name_ch["cat"]) != Category.NAME:
        return []
    var obs_cat: int = int(group_def_ch["cat"])
    if obs_cat != Category.COLOR and obs_cat != Category.PITCH:
        return []
    return [{
        "kind": "name_extreme_in_group",
        "name_star": int(name_ch["star"]),
        "cat": obs_cat,
        "group_key": _name_group_key(obs_cat, int(group_def_ch["star"])),
        "want_lowest": want_lowest,
    }]


func _validate_name_extreme_in_group_fact(f: Dictionary) -> String:
    var s: int = int(f["name_star"])
    var cat: int = int(f["cat"])
    var key: int = int(f["group_key"])
    var want_lowest: bool = bool(f["want_lowest"])
    var own_key: int = _name_group_key(cat, s)
    if own_key != key:
        return "name_extreme_in_group name_star=%d cat=%d claims to be the extreme OF group_key=%d but its own group_key is %d" % [s, cat, key, own_key]
    var subj_rank: int = int(pitch_rank_solution[s])
    for m in star_count:
        if m == s or _name_group_key(cat, m) != key:
            continue
        var member_rank: int = int(pitch_rank_solution[m])
        if want_lowest and subj_rank > member_rank:
            return "name_extreme_in_group name_star=%d cat=%d group_key=%d claims EARLIEST but member %d has rank %d < subject rank %d" % [s, cat, key, m, member_rank, subj_rank]
        if not want_lowest and subj_rank < member_rank:
            return "name_extreme_in_group name_star=%d cat=%d group_key=%d claims LATEST but member %d has rank %d > subject rank %d" % [s, cat, key, m, member_rank, subj_rank]
    return ""


## distance_hop (Forms 15 and 19) read as a NAME-closure constraint. The
## fact is a claim about DESCRIPTORS — "the star this ref_cat descriptor
## denotes is `hops` hops from SOME star in target_cat's group" — so it
## says something about a NAME's position only when ref_cat is NAME, and
## then it restricts that name to the positions lying exactly `hops` from
## some member of the group.
##
## Generator star indices ARE positions, so the true assignment maps
## name_star -> name_star and validation is a direct _distances lookup.
##
## NEGATION IS NOT THE MIRROR IMAGE, and getting it backwards yields
## unsolvable puzzles that look healthy (recorded in the hop-clue
## framework's own notes). "Not `hops` from SOME member" is ambiguous for
## a multi-member group — existential or universal — so the closure below
## only consumes a negated fact when the group is a SINGLETON, which is
## exactly what Form 19 guarantees via its _category_uniquely_labels
## filter on value_cat. The two readings coincide there.
func _validate_distance_hop_name_fact(f: Dictionary) -> String:
    var ref_star: int = int(f["ref"])
    var target: int = int(f["target"])
    var target_cat: int = int(f["target_cat"])
    var hops: int = int(f["hops"])
    var negated: bool = bool(f.get("negated", false))
    var tkey: int = _name_group_key(target_cat, target)
    if tkey == -1:
        return ""   # target_cat has no group notion (Name/Distance) — not consumed
    var hit: bool = false
    for q in star_count:
        if _name_group_key(target_cat, q) != tkey:
            continue
        if int(_distances[ref_star][q]) == hops:
            hit = true
            break
    if negated and hit:
        return "distance_hop(negated) ref=%d claims NOT %d hops from any member of target_cat=%d group %d, but one is" % [ref_star, hops, target_cat, tkey]
    if not negated and not hit:
        return "distance_hop ref=%d claims %d hops from a member of target_cat=%d group %d, but none is at that distance" % [ref_star, hops, target_cat, tkey]
    return ""


## Equality Pair's claim ("X and Y share the same axis value," axis never
## named) only tells the NAME closure something when EXACTLY one side is
## NAME. The other side's star is already a concrete, known index — this
## is generator-tier code, so a Sequence/Pitch id_cat only hides that
## star's identity from the PLAYER, never from the code computing this
## fact — so its raw axis value is directly readable RIGHT NOW, no
## resolution needed downstream (unlike the Sequence-anchored name_group
## branch in _solve_name_closure, whose group_key is a RANK and needs
## rank_to_star at CONSUMPTION time — this one is a concrete star index
## the whole way through, so it emits a plain "name_group" fact and needs
## no new closure-side code at all).
##
## When BOTH sides are NAME, both positions are genuinely unknown and this
## degenerates into a MUTUAL "same group" constraint — neither
## value_in_set nor value_out_set can express "domain(A) narrows domain(B)
## once A collapses," and _solve()'s existing arc-consistency passes
## (_propagate/_naked_subset_pass) are order-shaped, not equivalence-
## class-shaped. Deliberately deferred, not silently dropped — a
## same-group propagation pass is real, separate work.
func _name_same_axis_facts(id_a: Dictionary, id_b: Dictionary, axis: int, star_a: int, star_b: int) -> Array:
    var a_is_name: bool = int(id_a["cat"]) == Category.NAME
    var b_is_name: bool = int(id_b["cat"]) == Category.NAME
    if a_is_name and b_is_name:
        # Both positions genuinely unknown — no group_key to compute at
        # all, unlike the one-side case below. See _propagate_same_group.
        return [{"kind": "name_same_group", "name_star_a": star_a, "name_star_b": star_b, "cat": axis}]
    if a_is_name == b_is_name:
        return []
    var name_star: int = star_a if a_is_name else star_b
    var known_star: int = star_b if a_is_name else star_a
    return [{
        "kind": "name_group",
        "name_star": name_star,
        "cat": axis,
        "group_key": _name_group_key(axis, known_star),
    }]


func _validate_name_same_group_fact(f: Dictionary) -> String:
    var a: int = int(f["name_star_a"])
    var b: int = int(f["name_star_b"])
    var cat: int = int(f["cat"])
    var ka: int = _name_group_key(cat, a)
    var kb: int = _name_group_key(cat, b)
    if ka != kb:
        return "name_same_group name_star_a=%d name_star_b=%d cat=%d claims same group but true group_keys are %d and %d" % [a, b, cat, ka, kb]
    return ""


## Same-group EQUIVALENCE propagation — the both-sides-NAME case
## _name_same_axis_facts defers. name_star_a's and name_star_b's positions
## must share the same raw `cat` value, but WHICH value is unknown (no
## group_key at all, unlike name_group), so this can't be expressed as a
## per-row value_in_set/value_out_set restriction. Domain-level
## reachability pruning: remove a candidate position from one row only
## when NO position remains in the OTHER row's domain sharing its group,
## repeated to a fixpoint (narrowing one row can enable narrowing the
## other, and chains transitively across multiple pairs for free — no
## separate transitive-closure logic needed).
##
## SOUND but NOT COMPLETE, and that gap is deliberately safe rather than
## papered over: this never teaches _solve()'s own backtracking about the
## constraint, so its cap-limited search could in principle report a
## second "solution" that actually violates same-group and isn't real.
## That is NOT a false positive, though — every fact fed into _solve() is
## validated against ground truth first, so the TRUE assignment is always
## among whatever _solve() finds; if it finds exactly one, that one IS the
## true assignment, full stop. The only failure direction is UNDER-
## claiming uniqueness (reporting >1 for a puzzle that IS actually
## unique), the safe direction for a rejection gate — never over-claiming.
func _propagate_same_group(possible: Array, pairs: Array) -> bool:
    var changed: bool = true
    while changed:
        changed = false
        for pair in pairs:
            var pd: Dictionary = pair
            var a: int = int(pd["a"])
            var b: int = int(pd["b"])
            var cat: int = int(pd["cat"])
            var groups_b: Dictionary = {}
            for rb in star_count:
                if possible[b][rb]:
                    groups_b[_name_group_key(cat, rb)] = true
            for ra in star_count:
                if possible[a][ra] and not groups_b.has(_name_group_key(cat, ra)):
                    possible[a][ra] = false
                    changed = true
            var groups_a: Dictionary = {}
            for ra2 in star_count:
                if possible[a][ra2]:
                    groups_a[_name_group_key(cat, ra2)] = true
            for rb2 in star_count:
                if possible[b][rb2] and not groups_a.has(_name_group_key(cat, rb2)):
                    possible[b][rb2] = false
                    changed = true
    for i in star_count:
        var any_left: bool = false
        for r in star_count:
            if possible[i][r]:
                any_left = true
                break
        if not any_left:
            return false
    return true


## Converts a Form's grid_updates (matrix cells, addressed by each
## category's own bijective value index) into the star-space form that gets
## cached — see CACHE_VERSION 4's comment for why the conversion happens
## here at generation time rather than in the consumer. Distance is not a
## bijective category and has no matrix grid, so a cell naming it (no Form
## currently emits one) is dropped rather than mis-indexed.
func _cells_for_cache(grid_updates: Array) -> Array:
    var out: Array = []
    for gu in grid_updates:
        if not (gu is Dictionary):
            continue
        var cell: Dictionary = gu
        var ca: int = int(cell.get("cat_a", -1))
        var cb: int = int(cell.get("cat_b", -1))
        if not (ca in BIJECTIVE_CATEGORIES) or not (cb in BIJECTIVE_CATEGORIES):
            continue
        var va: int = int(cell.get("val_a", -1))
        var vb: int = int(cell.get("val_b", -1))
        if va < 0 or va >= star_count or vb < 0 or vb >= star_count:
            continue
        out.append({
            "cat_a":  ca,
            "star_a": int(_cat_value_to_star[ca][va]),
            "cat_b":  cb,
            "star_b": int(_cat_value_to_star[cb][vb]),
            "is_true": bool(cell.get("is_true", false)),
        })
    return out


func _clue_characteristics(chars: Array) -> Array[String]:
    # Replaces the old kind-string -> static-table indirection (_kind_ui_tabs)
    # with a tag computed straight from a clue's actual node composition —
    # Kind is derived, not fixed, in this architecture, so the same Form can
    # touch different categories on different draws. "NameClues" mirrors the
    # old table's pattern: every legacy kind tagged NameClues was one whose
    # participants included a Name node.
    var tags: Array[String] = []
    var has_name: bool = false
    for c in chars:
        var cat: int = int(c["cat"])
        match cat:
            Category.NAME:
                has_name = true
            Category.SEQUENCE:
                if not ("Sequence" in tags):
                    tags.append("Sequence")
            Category.PITCH:
                if not ("Pitch" in tags):
                    tags.append("Pitch")
            Category.COLOR:
                if not ("Color" in tags):
                    tags.append("Color")
            Category.DISTANCE:
                if not ("Proximity" in tags):
                    tags.append("Proximity")
    if has_name:
        tags.append("NameClues")
    return tags


# ==================================================
# FORMS REGISTRY — 22 abstract templates
# ==================================================
const FORM_NAMES := {
    1: "Exact Identity", 2: "Single Negation", 3: "Dual Negation",
    4: "Disjunction", 5: "Pairwise Order", 6: "Exact Offset",
    7: "Adjacency", 8: "Range", 9: "Group Order", 10: "Count",
    11: "Extreme", 12: "Equality Pair", 13: "Mutual Exclusion",
    14: "Group Comparison", 15: "Distance Existential", 16: "Distance Extreme",
    17: "Betweenness", 18: "Degree Fact", 19: "Non-Adjacency",
    20: "Cross-Domain Bridge", 21: "Pseudo-True Pair (Aligned)",
    22: "Pseudo-True Pair (Staggered)", 23: "Group Membership",
}

const AUTOMATED_FORM_IDS: Array[int] = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23,
]
# Form 18 (Degree Fact) deliberately excluded from automatic generation —
# Degree stays hand-tuned per constellation (topology varies too much; some
# constellations put every star at the same degree, giving it zero
# discriminating power there), per the standing exclusion rule established
# earlier this session.


func _build_form(form_id: int, chain: Dictionary) -> Dictionary:
    match form_id:
        1: return _build_form_exact_identity(chain)
        2: return _build_form_single_negation(chain)
        3: return _build_form_dual_negation(chain)
        4: return _build_form_disjunction(chain)
        5: return _build_form_pairwise_order(chain)
        6: return _build_form_exact_offset(chain)
        7: return _build_form_adjacency(chain)
        8: return _build_form_range(chain)
        9: return _build_form_group_order(chain)
        10: return _build_form_count(chain)
        11: return _build_form_extreme(chain)
        12: return _build_form_equality_pair(chain)
        13: return _build_form_mutual_exclusion(chain)
        14: return _build_form_group_comparison(chain)
        15: return _build_form_distance_existential(chain)
        16: return _build_form_distance_extreme(chain)
        17: return _build_form_betweenness(chain)
        19: return _build_form_non_adjacency(chain)
        20: return _build_form_cross_domain_bridge(chain)
        21: return _build_form_pseudo_true_pair_aligned(chain)
        22: return _build_form_pseudo_true_pair_staggered(chain)
        23: return _build_form_group_membership(chain)
    return {}


# ── Shape A: single-cell fact (Forms 1, 2, 4, 8) ─────────────────────────

func _build_form_exact_identity(chain: Dictionary) -> Dictionary:
    # Purely random landing (no steering toward True) on whichever cell
    # results from chaining (Step 9/10) or, absent a previous clue, a
    # fresh category pair. Most random landings are False (only star_count
    # of star_count^2 cells are True) — that's expected and correct; a
    # False landing just means THIS attempt isn't an Exact Identity
    # instance, and the main loop moves on. The grid mutation itself is
    # deferred to generate_clues_forms(), after the dedup check, so a
    # discarded attempt never corrupts Used/Unused bookkeeping for a cell
    # that was never actually shown to the player.
    var cell: Dictionary = _sample_grid_cell_maybe_chained(chain, true)
    if cell.is_empty() or not bool(cell["is_true"]):
        return {}
    var ch_a: Dictionary = {"cat": int(cell["cat_a"]), "star": int(cell["star_a"])}
    var ch_b: Dictionary = {"cat": int(cell["cat_b"]), "star": int(cell["star_b"])}
    var text: String = "%s is %s." % [_characteristic_label(ch_a), _characteristic_label(ch_b)]
    var solver_facts: Array = _seq_fact_for_label(ch_a) + _seq_fact_for_label(ch_b)
    var value_facts: Array = _name_group_facts(ch_a, ch_b, true)
    return {"chars": [ch_a, ch_b], "text": text, "grid_updates": [cell], "solver_facts": solver_facts, "value_facts": value_facts}


func _build_form_single_negation(chain: Dictionary) -> Dictionary:
    # Same purely-random landing as Exact Identity, just needing a False
    # cell instead of a True one — no steering either direction.
    var cell: Dictionary = _sample_grid_cell_maybe_chained(chain, true)
    if cell.is_empty() or bool(cell["is_true"]):
        return {}
    var ch_a: Dictionary = {"cat": int(cell["cat_a"]), "star": int(cell["star_a"])}
    var ch_b: Dictionary = {"cat": int(cell["cat_b"]), "star": int(cell["star_b"])}
    var text: String = "%s is not %s." % [_characteristic_label(ch_a), _characteristic_label(ch_b)]
    # Two facts, when the axis participates: the label itself discloses an
    # exact rank for whichever side is Sequence-categorized (ch's label is
    # "the star that fires Nth" regardless of the negation wrapped around
    # it); separately, "A is not B" with A's exact rank already known means
    # B's rank is provably NOT that value — a real negative fact on the
    # OTHER star. cat_a and cat_b are always different categories (cross-
    # category cell), so at most one side is ever Sequence.
    var solver_facts: Array = _seq_fact_for_label(ch_a) + _seq_fact_for_label(ch_b)
    if int(ch_a["cat"]) == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_neg", "s": int(ch_b["star"]), "r": int(cell["val_a"])})
    elif int(ch_b["cat"]) == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_neg", "s": int(ch_a["star"]), "r": int(cell["val_b"])})
    var value_facts: Array = _name_group_facts(ch_a, ch_b, false)
    return {"chars": [ch_a, ch_b], "text": text, "grid_updates": [cell], "solver_facts": solver_facts, "value_facts": value_facts}


func _build_form_disjunction(chain: Dictionary) -> Dictionary:
    # Matrix-based, per Steps 3/4/9/10: one cell sampled purely randomly
    # (chained when available) fixes the subject's row and which category
    # supplies the two candidate options. Bijection guarantees exactly one
    # True column per row — so whichever the random draw landed on, the
    # OTHER option is never itself "sampled toward an outcome": if the
    # draw was already True, the decoy is a random pick among the
    # remaining (guaranteed-False) columns in that same row; if the draw
    # was False, the True option is simply the row's one true column,
    # looked up directly off the bijection (a ground-truth fact, not
    # something requiring a second random sample).
    var cell: Dictionary = _sample_grid_cell_maybe_chained(chain)
    if cell.is_empty():
        return {}
    var cat_a: int = int(cell["cat_a"])
    var val_a: int = int(cell["val_a"])
    var cat_b: int = int(cell["cat_b"])
    var val_b: int = int(cell["val_b"])
    var star_a: int = int(cell["star_a"])
    var true_val_b: int = int(_cat_star_to_value[cat_b][star_a])
    # true_ch below always ends up labeling star_a itself via cat_b (true_val_b
    # is DEFINED as star_a's own cat_b value, so the inverse bijection lookup
    # always returns star_a) — regardless of which branch below runs. The
    # earlier _sample_grid_cell fix only checked whichever value was actually
    # SAMPLED, which is star_a's true value in the True-cell branch (same
    # star, redundant-but-harmless) but is the DECOY in the False-cell
    # branch — never checking star_a's own cat_b-uniqueness in that case,
    # which is exactly the gap that let "the star that plays C5 marked B"
    # through as a TRUE option.
    if not _category_uniquely_labels(cat_b, star_a):
        return {}
    var decoy_val_b: int
    if val_b == true_val_b:
        var candidates: Array = []
        for v in star_count:
            if v != true_val_b and not bool(_matrix_cell(cat_a, val_a, cat_b, v)["used"]) and _category_uniquely_labels(cat_b, int(_cat_value_to_star[cat_b][v])):
                candidates.append(v)
        if candidates.is_empty():
            return {}
        decoy_val_b = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
    else:
        decoy_val_b = val_b
        if bool(_matrix_cell(cat_a, val_a, cat_b, true_val_b)["used"]):
            return {}
    var subject_ch: Dictionary = {"cat": cat_a, "star": star_a}
    var true_ch: Dictionary = {"cat": cat_b, "star": int(_cat_value_to_star[cat_b][true_val_b])}
    var decoy_ch: Dictionary = {"cat": cat_b, "star": int(_cat_value_to_star[cat_b][decoy_val_b])}
    var opts: Array = [true_ch, decoy_ch]
    _shuffle_array(opts)
    var text: String = "%s is either %s or %s." % [_characteristic_label(subject_ch), _characteristic_label(opts[0]), _characteristic_label(opts[1])]
    # Every label actually rendered discloses its own exact rank when
    # Sequence-categorized (true_ch/decoy_ch's OWN ranks are disclosed by
    # naming them, regardless of which one turns out to be the subject's
    # real match) — but do NOT also claim the disjunction resolves WHICH
    # one the subject is; that's exactly the ambiguity "either/or" leaves
    # open, captured separately only when cat_b is Sequence.
    var solver_facts: Array = _seq_fact_for_label(subject_ch) + _seq_fact_for_label(true_ch) + _seq_fact_for_label(decoy_ch)
    if cat_b == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_either_or", "s": star_a, "r1": true_val_b, "r2": decoy_val_b})
    # The disjunction itself, on ANY axis — the above only captures it when
    # cat_b is Sequence, which left every Colour/Pitch/Name disjunction with
    # no scoreable content at all. Rides in value_facts so the CSP's input is
    # untouched; see Form 13.
    var value_facts: Array = [{
        "kind": "descriptor_either_or",
        "cat_a": cat_a, "star_a": star_a, "cat_b": cat_b,
        "s1": int(_cat_value_to_star[cat_b][true_val_b]),
        "s2": int(_cat_value_to_star[cat_b][decoy_val_b]),
    }]
    return {
        "value_facts": value_facts,
        "chars": [subject_ch, true_ch, decoy_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": cat_a, "val_a": val_a, "cat_b": cat_b, "val_b": true_val_b, "is_true": true},
            {"cat_a": cat_a, "val_a": val_a, "cat_b": cat_b, "val_b": decoy_val_b, "is_true": false},
        ],
        "solver_facts": solver_facts,
    }


func _build_form_range(chain: Dictionary) -> Dictionary:
    # Sequence-only first pass: subject's true rank constrained to a
    # contiguous first/last-N window. Other orderable axes (Pitch/Color)
    # would need their own "first/last N" phrasing — deferred. Single-cell
    # form (one TRUE cell gives both the identity label and the rank),
    # same shape as Forms 1/2 rather than the two-cell Forms 5-7. Note:
    # generalized the identity label from a fixed Name to the same random
    # non-axis category the other migrated Forms use, for consistency —
    # flagging since it's a small behavior change, not just a mechanical port.
    var a: Dictionary = _sample_identity_axis_cell(Category.SEQUENCE, chain, -1)
    if a.is_empty():
        return {}
    var subject_star: int = int(a["star"])
    var r: int = _order_value(Category.SEQUENCE, subject_star)
    var want_first: bool = _rng.randf() < 0.5
    @warning_ignore("integer_division")
    var n: int = mini(star_count, 2 + _rng.randi_range(0, maxi(1, star_count / 3)))
    var fits: bool = (r < n) if want_first else (r >= star_count - n)
    if not fits:
        want_first = not want_first
        fits = (r < n) if want_first else (r >= star_count - n)
        # r can fall in neither window (e.g. r=10 of 15 with n=2 — not
        # among the first 2 or the last 2) — flipping want_first only
        # rescues the case where r was simply checked against the WRONG
        # window, not the case where it's genuinely in the untouched
        # middle. The old code assumed the flip always fixed it and
        # asserted a false range claim when it didn't (caught by
        # _validate_sequence_fact reporting e.g. "s=12 claims rank in
        # [0,1] but true rank=10") — bail out like every other Form does
        # on an infeasible draw, rather than shipping a false fact.
        if not fits:
            return {}
    var id_ch: Dictionary = {"cat": int(a["id_cat"]), "star": subject_star}
    var seq_ch: Dictionary = {"cat": Category.SEQUENCE, "star": subject_star}
    var word: String = "first" if want_first else "last"
    var text: String = "%s is among the %s %d." % [_characteristic_label(id_ch), word, n]
    # Only id_ch is ever rendered via _characteristic_label — seq_ch is
    # bookkeeping (chars/chaining) only, never itself disclosed as an exact
    # rank. What's actually asserted is range membership, not an exact value.
    var lo: int = 0 if want_first else star_count - n
    var hi: int = n - 1 if want_first else star_count - 1
    var solver_facts: Array = _seq_fact_for_label(id_ch)
    solver_facts.append({"kind": "ordinal_range", "s": subject_star, "lo": lo, "hi": hi})
    return {
        "chars": [id_ch, seq_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": Category.SEQUENCE, "val_b": int(a["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


# ── Shape B: two-star relational fact (Forms 5, 6, 7, 12) ────────────────


func _sample_identity_axis_cell(axis_cat: int, chain: Dictionary, exclude_star: int, bias_name: bool = false) -> Dictionary:
    # Establishes one star's identity for a comparison-shaped Form (Pairwise
    # Order and similar): a TRUE cell pairing some other category against
    # axis_cat. This is NOT the same "steering" Forms 1/2 avoid — no
    # player-facing is/is-not assertion is being decided here, only which
    # physical star an identity label refers to, a prerequisite before the
    # actual clue content (a pure ground-truth comparison, zero steering)
    # gets built. Picking directly among candidate stars lands on the same
    # distribution random-sample-and-discard-on-False would converge to
    # (exactly one column per row is True, so uniform-over-stars is
    # uniform-over-True-cells) without the wasted draws — with two such
    # cells needed per clue here, discard-based sampling would fail this
    # Form almost every attempt and likely exhaust the main loop's stall
    # budget before ever succeeding once.
    if not chain.is_empty() and int(chain["cat"]) != Category.DISTANCE and int(chain["cat"]) != axis_cat and int(chain["star"]) != exclude_star:
        var chain_star: int = int(chain["star"])
        var chain_cat: int = int(chain["cat"])
        if _category_uniquely_labels(chain_cat, chain_star):
            var chain_val: int = int(_cat_star_to_value[chain_cat][chain_star])
            var true_axis_val: int = int(_cat_star_to_value[axis_cat][chain_star])
            if not bool(_matrix_cell(chain_cat, chain_val, axis_cat, true_axis_val)["used"]):
                return {"id_cat": chain_cat, "id_val": chain_val, "axis_val": true_axis_val, "star": chain_star}
    # Single, final-commitment draw (no fallback to a different id_cat if
    # candidates comes back empty below), so a soft weighted pick when
    # biased — not the chained path's costless try-NAME-first above,
    # since picking NAME here and having it fail closes off this whole
    # attempt rather than falling through to the next candidate.
    var id_cat: int = _weighted_category_excluding(axis_cat) if bias_name else _non_distance_category()
    while id_cat == axis_cat:
        id_cat = _weighted_category_excluding(axis_cat) if bias_name else _non_distance_category()
    var candidates: Array = []
    for s in star_count:
        if s == exclude_star or not _category_uniquely_labels(id_cat, s):
            continue
        var id_val: int = int(_cat_star_to_value[id_cat][s])
        var axis_val: int = int(_cat_star_to_value[axis_cat][s])
        if not bool(_matrix_cell(id_cat, id_val, axis_cat, axis_val)["used"]):
            candidates.append(s)
    if candidates.is_empty():
        return {}
    var star: int = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
    return {"id_cat": id_cat, "id_val": int(_cat_star_to_value[id_cat][star]), "axis_val": int(_cat_star_to_value[axis_cat][star]), "star": star}


func _build_form_pairwise_order(chain: Dictionary) -> Dictionary:
    var axis: int = _orderable_categories()[_rng.randi_range(0, 1)]
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var star_a: int = int(a["star"])
    var b: Dictionary = _sample_identity_axis_cell(axis, {}, star_a)   # only one node chains per Step 9 — star_b is always fresh
    if b.is_empty():
        return {}
    var star_b: int = int(b["star"])
    # _order_value, not the matrix's own bijection index, is what actually
    # determines direction — Pitch's matrix bijection (raw index + sub-
    # rank) and its true frequency-rank ordering (with ties) are different
    # numberings; comparing the wrong one would silently misorder Pitch
    # clues even though the matrix bookkeeping itself stayed correct.
    var val_a: int = _order_value(axis, star_a)
    var val_b: int = _order_value(axis, star_b)
    # Distinct STARS is not distinct RANKS. star_b is only sampled to differ
    # from star_a, but Pitch ranks tie whenever two stars play the same note
    # (constellation 0 has 15 stars across 10 notes), and a tie fell through
    # to `a_gt_b = false` and rendered a strict "is lower than" — a flatly
    # false clue, and one a correct solver uses to eliminate the true
    # solution. Same guard, same reason, as Betweenness and Exact Offset.
    # Sequence is a permutation and never ties, so this only fires on Pitch.
    if val_a == val_b:
        return {}
    var a_gt_b: bool = val_a > val_b
    var id_a: Dictionary = {"cat": int(a["id_cat"]), "star": star_a}
    var id_b: Dictionary = {"cat": int(b["id_cat"]), "star": star_b}
    var axis_a: Dictionary = {"cat": axis, "star": star_a}
    var axis_b: Dictionary = {"cat": axis, "star": star_b}
    var text: String = "%s %s %s than %s." % [_characteristic_label(id_a), _order_verb(axis), _order_word(axis, a_gt_b), _characteristic_label(id_b)]
    # id_a/id_b are the only labels actually rendered — axis_a/axis_b back
    # the comparison itself but are never textually disclosed as exact
    # values (see the header note on _seq_fact_for_label). The comparison
    # only matters to the Sequence solve when axis IS Sequence; a Pitch-axis
    # comparison discloses nothing Sequence-relevant.
    var solver_facts: Array = _seq_fact_for_label(id_a) + _seq_fact_for_label(id_b)
    if axis == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_cmp", "a": star_a, "b": star_b, "a_gt_b": a_gt_b})
    return {
        "chars": [id_a, id_b, axis_a, axis_b],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": int(b["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


func _build_form_exact_offset(chain: Dictionary) -> Dictionary:
    var axis: int = Category.SEQUENCE if _rng.randf() < 0.7 else Category.PITCH
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var star_a: int = int(a["star"])
    var b: Dictionary = _sample_identity_axis_cell(axis, {}, star_a)   # only one node chains per Step 9 — star_b is always fresh
    if b.is_empty():
        return {}
    var star_b: int = int(b["star"])
    var offset: int = _order_value(axis, star_a) - _order_value(axis, star_b)
    if offset == 0:
        return {}   # Pitch can genuinely tie — "exactly 0 steps apart" isn't a meaningful Exact Offset clue.
    var id_a: Dictionary = {"cat": int(a["id_cat"]), "star": star_a}
    var id_b: Dictionary = {"cat": int(b["id_cat"]), "star": star_b}
    var axis_a: Dictionary = {"cat": axis, "star": star_a}
    var axis_b: Dictionary = {"cat": axis, "star": star_b}
    var dir_word: String = _order_word(axis, offset > 0)
    var text: String = "%s %s exactly %d %s %s than %s." % [_characteristic_label(id_a), _order_verb(axis), abs(offset), _order_unit(axis, abs(offset)), dir_word, _characteristic_label(id_b)]
    var solver_facts: Array = _seq_fact_for_label(id_a) + _seq_fact_for_label(id_b)
    if axis == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_offset", "a": star_a, "b": star_b, "offset": offset})
    return {
        "chars": [id_a, id_b, axis_a, axis_b],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": int(b["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


func _identity_cell_for_known_star(star: int, axis_cat: int, bias_name: bool = false) -> Dictionary:
    # Like _sample_identity_axis_cell, but for a star whose identity is
    # already pinned by something OTHER than a free random pick — e.g.
    # Adjacency's target star, determined by an exact rank offset rather
    # than chosen among remaining candidates. Same TRUE-cell requirement:
    # the (id_cat, axis_cat) pairing for this star must not already be
    # Used, or this attempt fails and the main loop moves on.
    var id_cat: int = _weighted_category_excluding(axis_cat) if bias_name else _non_distance_category()
    while id_cat == axis_cat or not _category_uniquely_labels(id_cat, star):
        id_cat = _weighted_category_excluding(axis_cat) if bias_name else _non_distance_category()
    var id_val: int = int(_cat_star_to_value[id_cat][star])
    var axis_val: int = int(_cat_star_to_value[axis_cat][star])
    if bool(_matrix_cell(id_cat, id_val, axis_cat, axis_val)["used"]):
        return {}
    return {"id_cat": id_cat, "id_val": id_val, "axis_val": axis_val, "star": star}


func _build_form_adjacency(chain: Dictionary) -> Dictionary:
    var axis: int = Category.SEQUENCE
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var star_a: int = int(a["star"])
    var val_a: int = _order_value(axis, star_a)
    var want_next: bool = _rng.randf() < 0.5
    var target_val: int = val_a + 1 if want_next else val_a - 1
    if target_val < 0 or target_val >= star_count:
        want_next = not want_next
        target_val = val_a + 1 if want_next else val_a - 1
        if target_val < 0 or target_val >= star_count:
            return {}
    var star_b: int = int(_cat_value_to_star[Category.SEQUENCE][target_val])
    var b: Dictionary = _identity_cell_for_known_star(star_b, axis)
    if b.is_empty():
        return {}
    var id_a: Dictionary = {"cat": int(a["id_cat"]), "star": star_a}
    var id_b: Dictionary = {"cat": int(b["id_cat"]), "star": star_b}
    var axis_a: Dictionary = {"cat": axis, "star": star_a}
    var axis_b: Dictionary = {"cat": axis, "star": star_b}
    var word: String = "after" if want_next else "before"
    var text: String = "%s fires immediately %s %s." % [_characteristic_label(id_a), word, _characteristic_label(id_b)]
    var solver_facts: Array = _seq_fact_for_label(id_a) + _seq_fact_for_label(id_b)
    var higher_star: int = star_a if val_a > target_val else star_b
    var lower_star: int = star_b if val_a > target_val else star_a
    solver_facts.append({"kind": "ordinal_adjacent", "a": higher_star, "b": lower_star, "offset": 1})
    return {
        "chars": [id_a, id_b, axis_a, axis_b],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": int(b["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


func _build_form_equality_pair(chain: Dictionary) -> Dictionary:
    # Only Color/Pitch can meaningfully hold an equality (Name/Sequence are
    # alldiff, so two stars can never share a value there by construction).
    # star_b is a specific, predetermined star (whichever else shares
    # star_a's raw value), same shape as Form 7's target — not freely
    # chosen among all remaining candidates like Forms 5/6.
    var axis: int = Category.COLOR if _rng.randf() < 0.5 else Category.PITCH
    var raw_of: Callable = func(s): return star_colors[s] if axis == Category.COLOR else star_pitch_index[s]
    # bias_name on both draws: this Form is the biggest closure-coverage
    # contributor by volume, and every one-side-NAME instance feeds a
    # name_group fact directly, every both-NAME instance feeds
    # _propagate_same_group — biasing EITHER side toward NAME raises the
    # rate of both outcomes over the current "neither side NAME" case,
    # which discloses nothing to the closure at all.
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1, true)
    if a.is_empty():
        return {}
    var star_a: int = int(a["star"])
    var raw_a = raw_of.call(star_a)
    var candidates: Array = []
    for s in star_count:
        if s != star_a and raw_of.call(s) == raw_a:
            candidates.append(s)
    if candidates.is_empty():
        return {}
    var star_b: int = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
    var b: Dictionary = _identity_cell_for_known_star(star_b, axis, true)
    if b.is_empty():
        return {}
    # Both ends must not be labelled off GIVEN axes. The identity picks are
    # excluded from `axis` but not from the OTHER given axis, so with
    # axis=Colour both labels could land on Pitch and produce
    #
    #     "The star that plays F5 and the star that plays E5 have the
    #      same color."
    #
    # — every part of which the player reads straight off the map once the
    # stars have been listened to. Reported as the first clue of a live
    # puzzle, 2026-08-13.
    #
    # Forms 5/8/10 may also carry pitch-labelled subjects and are fine,
    # because what they ASSERT is a Sequence fact. This Form asserts a given
    # axis too, so given labels leave no hidden content anywhere in it.
    # Same requirement _is_hidden_category already enforces for the
    # distance-anchored Forms — its docstring describes this exact failure;
    # it had simply never been applied here. Reject and let the caller retry
    # with a fresh draw.
    if not _is_hidden_category(int(a["id_cat"])) and not _is_hidden_category(int(b["id_cat"])):
        return {}
    var id_a: Dictionary = {"cat": int(a["id_cat"]), "star": star_a}
    var id_b: Dictionary = {"cat": int(b["id_cat"]), "star": star_b}
    var axis_a: Dictionary = {"cat": axis, "star": star_a}
    var axis_b: Dictionary = {"cat": axis, "star": star_b}
    var noun: String = "color" if axis == Category.COLOR else "pitch"
    var text: String = "%s and %s have the same %s." % [_characteristic_label(id_a), _characteristic_label(id_b), noun]
    # axis is always Color/Pitch here — no Sequence-relational content —
    # but id_cat (excluded only from axis, never from Sequence) can still
    # be Sequence, in which case its label directly discloses an exact rank.
    var solver_facts: Array = _seq_fact_for_label(id_a) + _seq_fact_for_label(id_b)
    var value_facts: Array = [{"kind": "values_same", "cat": axis, "a": star_a, "b": star_b}]
    value_facts.append_array(_name_same_axis_facts(id_a, id_b, axis, star_a, star_b))
    return {
        # See Form 13 for why value content rides in its own array.
        "value_facts": value_facts,
        "chars": [id_a, id_b, axis_a, axis_b],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": int(b["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


# ── Forms 3, 13, 14: comparison-axis derived from the FIRST participant's
# cell, per the corrected downstream-derivation principle — every
# subsequent participant's characteristic on that same axis must match. ──

func _build_form_dual_negation(chain: Dictionary) -> Dictionary:
    # V (the shared negated value) doesn't need its own identity cell — it's
    # a single, self-sufficient Characteristic (star_v's true value_cat
    # value), same as any Form 1/2 "value" side. X and Y each need a FALSE
    # cell pairing their own identity category against (value_cat, star_v's
    # value) — automatically guaranteed False by bijection for any star !=
    # star_v, same underlying fact Form 13's participants rely on, just
    # asserting the negative instead of requiring pairwise-distinct
    # positives. value_cat restricted to the four bijective categories (was
    # _random_category, which could hit Distance) — same class of fix as
    # Form 19's _non_distance_category() switch.
    var value_cat: int = _non_distance_category()
    var v_pool: Array = []
    for sv in star_count:
        if _category_uniquely_labels(value_cat, sv):
            v_pool.append(sv)
    if v_pool.is_empty():
        return {}
    var star_v: int = int(v_pool[_rng.randi_range(0, v_pool.size() - 1)])
    var v_val: int = int(_cat_star_to_value[value_cat][star_v])

    var s1: int = -1
    var id_cat1: int = -1
    if not chain.is_empty() and int(chain["cat"]) != Category.DISTANCE and int(chain["cat"]) != value_cat and int(chain["star"]) != star_v:
        var cs: int = int(chain["star"])
        var cc: int = int(chain["cat"])
        if _category_uniquely_labels(cc, cs):
            var cv: int = int(_cat_star_to_value[cc][cs])
            if not bool(_matrix_cell(cc, cv, value_cat, v_val)["used"]):
                s1 = cs
                id_cat1 = cc

    if s1 == -1:
        var pool: Array = []
        for s in star_count:
            if s != star_v:
                pool.append(s)
        _shuffle_array(pool)
        for cand in pool:
            var idc: int = _non_distance_category()
            while idc == value_cat:
                idc = _non_distance_category()
            if not _category_uniquely_labels(idc, int(cand)):
                continue
            var idv: int = int(_cat_star_to_value[idc][cand])
            if not bool(_matrix_cell(idc, idv, value_cat, v_val)["used"]):
                s1 = int(cand)
                id_cat1 = idc
                break
        if s1 == -1:
            return {}

    var id_cat2: int = _non_distance_category()
    while id_cat2 == value_cat:
        id_cat2 = _non_distance_category()
    var candidates2: Array = []
    for s in star_count:
        if s == s1 or s == star_v or not _category_uniquely_labels(id_cat2, s):
            continue
        var id_val2: int = int(_cat_star_to_value[id_cat2][s])
        if not bool(_matrix_cell(id_cat2, id_val2, value_cat, v_val)["used"]):
            candidates2.append(s)
    if candidates2.is_empty():
        return {}
    var s2: int = int(candidates2[_rng.randi_range(0, candidates2.size() - 1)])

    var false_val: Dictionary = {"cat": value_cat, "star": star_v}
    var id1: Dictionary = {"cat": id_cat1, "star": s1}
    var id2: Dictionary = {"cat": id_cat2, "star": s2}
    var text: String = "Neither %s nor %s is %s." % [_characteristic_label(id1), _characteristic_label(id2), _characteristic_label(false_val)]
    # All three labels are rendered directly. Additionally, if the shared
    # negated value is itself Sequence-categorized, "neither is V" means
    # both s1 and s2 provably do NOT hold V's rank (id_cat1/id_cat2 each
    # individually exclude value_cat, so at most one side of each pairing
    # is ever Sequence — the case handled here is disjoint from the label-
    # based exact facts, not double-counting them).
    var solver_facts: Array = _seq_fact_for_label(id1) + _seq_fact_for_label(id2) + _seq_fact_for_label(false_val)
    if value_cat == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_neg", "s": s1, "r": v_val})
        solver_facts.append({"kind": "ordinal_neg", "s": s2, "r": v_val})
    # NAME closure (Phase 2, thirteenth slice): "neither X nor Y is V" is
    # two INDEPENDENT False cells bundled into one clue — (id1, false_val)
    # and (id2, false_val) — each exactly the shape Single Negation already
    # feeds via _name_group_facts(ch_a, ch_b, false). Reused unchanged, one
    # call per pair; its own "exactly one side must be NAME" check already
    # returns [] for whichever pair doesn't qualify (both id1/id2 land on
    # NAME only if value_cat forced them off it, and false_val lands on
    # NAME only when value_cat==NAME, in which case id_cat1/id_cat2 are
    # guaranteed non-NAME by construction — so at most one of the three
    # labels is ever NAME per pair, never zero-vs-two ambiguity). No new
    # fact kind, no new validator: this is pure reuse.
    var value_facts: Array = _name_group_facts(id1, false_val, false) \
        + _name_group_facts(id2, false_val, false)
    return {
        "chars": [id1, id2, false_val],
        "text": text,
        "grid_updates": [
            {"cat_a": id_cat1, "val_a": int(_cat_star_to_value[id_cat1][s1]), "cat_b": value_cat, "val_b": v_val, "is_true": false},
            {"cat_a": id_cat2, "val_a": int(_cat_star_to_value[id_cat2][s2]), "cat_b": value_cat, "val_b": v_val, "is_true": false},
        ],
        "solver_facts": solver_facts,
        "value_facts": value_facts,
    }


## Category display-priority for grouping a mixed-category label list
## before sorting — Forms 13/14 (Mutual Exclusion, Group Comparison) can
## identify each participant via a DIFFERENT category, so a joined list
## isn't always homogeneous. Group by category first in this fixed order,
## then apply each group's own rule within it; anything outside the four
## covered categories (Distance) has no rule here and sorts last, keeping
## its original relative order.
const _LABEL_SORT_PRIORITY: Dictionary = {
    Category.NAME: 0, Category.SEQUENCE: 1, Category.COLOR: 2, Category.PITCH: 3,
}

## Comparator for _sort_labels_for_join() — split into its own named
## function rather than an inline lambda passed to sort_custom(): GDScript's
## inline `func(a, b): <block>` lambdas are indentation-delimited, not
## paren-delimited, and a multi-branch match statement nested inside one
## does not reliably terminate at a `)` written on the same line as its
## last arm — confirmed directly (this exact shape produced "Could not
## parse global class" on this file). A named method passed by reference
## (sort_custom(_label_sort_less_than)) sidesteps the ambiguity entirely.
func _label_sort_less_than(a: Dictionary, b: Dictionary) -> bool:
    var pa: int = int(_LABEL_SORT_PRIORITY.get(int(a["cat"]), 99))
    var pb: int = int(_LABEL_SORT_PRIORITY.get(int(b["cat"]), 99))
    if pa != pb:
        return pa < pb
    match int(a["cat"]):
        Category.NAME:
            return str(star_names[int(a["star"])]) > str(star_names[int(b["star"])])
        Category.SEQUENCE:
            return _order_value(Category.SEQUENCE, int(a["star"])) < _order_value(Category.SEQUENCE, int(b["star"]))
        Category.COLOR:
            return str(COLOR_NAMES[star_colors[int(a["star"])]]) < str(COLOR_NAMES[star_colors[int(b["star"])]])
        Category.PITCH:
            return _order_value(Category.PITCH, int(a["star"])) > _order_value(Category.PITCH, int(b["star"]))
    return false


## Sorts {cat:int, star:int, label:String} items for display in a joined
## clue list, per category: Name descending alphabetical, Sequence
## ascending (earliest star first), Color ascending alphabetical, Pitch
## descending by frequency (highest first) — deterministic instead of
## whatever order participants happened to get sampled in. Returns plain
## label strings, ready for _join_names_and().
func _sort_labels_for_join(items: Array) -> Array:
    var sorted_items: Array = items.duplicate()
    sorted_items.sort_custom(_label_sort_less_than)
    var out: Array = []
    for it in sorted_items:
        out.append(str(it["label"]))
    return out


func _join_names_and(labels: Array) -> String:
    if labels.size() == 1:
        return str(labels[0])
    if labels.size() == 2:
        return "%s and %s" % [labels[0], labels[1]]
    var head: Array = labels.slice(0, labels.size() - 1)
    return "%s, and %s" % [", ".join(head), labels[labels.size() - 1]]


# ── Form 13: Mutual Exclusion — N (3-5) stars, each independently
# identified via some category, pairwise proven to be DIFFERENT STARS.
# When the shared axis is Colour or Pitch the clue ALSO asserts N pairwise-
# different raw values on that axis — real information beyond "different
# stars," expressible only as a disclosure, since a cell can only ever say
# same-star/different-star, never same-value/different-value on a shared
# axis. When the axis is Name or Sequence — both alldiff over every star —
# "N different [axis]" IS EXACTLY "N different stars," nothing more and
# nothing less, so it reduces fully to cell facts with no disclosure at all.
#
# REWRITTEN 2026-08-12 to be matrix-native. The old version picked a random
# star, THEN a random identifying category, THEN checked whether that
# combination happened to be legal — discovery by rejection, up to 60
# times. This version computes, per star, exactly which categories are
# legal for it (Name/Sequence: always; Colour/Pitch: only when that star's
# value is one-of-a-kind here) and draws only from that known-legal set —
# nothing is ever picked and then thrown away. An unsatisfiable puzzle
# (not enough distinct-value stars on the chosen axis) is detected by
# COUNTING up front, once, rather than discovered through failed guesses;
# the Form simply returns {} for this axis and this attempt, and the
# existing outer tier-retry loop (shared by every Form, unchanged) tries
# again with a fresh draw. Full design discussion in project memory:
# [[constellation_puzzle_five_way_clue_design_resolved]].
#
# Cross-participant distinctness cells are new: the old Form never
# recorded "these two are different stars" as its own fact, only the
# per-participant identity-pinning cell. Adding it is sound for every
# axis (participants are always different stars, axis or no) and is what
# lets Name/Sequence work as an axis at all. Skipped only when two
# participants share the very same identifying category — Name(A) vs
# Name(B) already, trivially proves A != B the instant both are read, so
# there is nothing left to disclose there; this is also precisely how
# deliberate category-doubling costs a clue one pairwise fact out of many,
# never the clue itself.
## Colour's share is deliberately small. Verified 2026-08-12 across every
## defined constellation (13-18 stars, colour assigned via i%4): with only
## 4 colours and every star count well above 4, no colour can ever be a
## SINGLETON — pigeonhole guarantees at least ceil(star_count/4) >= 4 stars
## per colour, so _mutex_axis_groups(COLOR) returns 0 groups on every one
## of them today. Not a bug — Colour axis is genuinely, structurally
## unsatisfiable on the current roster, and a wasted draw just falls
## through to the outer tier-retry loop at no real cost. Kept nonzero
## rather than dropped entirely in case a future, smaller constellation
## (or a later Age) ever has few enough stars for a colour to go singleton.
const MUTEX_AXIS_WEIGHTS := {
    Category.COLOR: 0.05, Category.PITCH: 0.45,
    Category.NAME:  0.25, Category.SEQUENCE: 0.25,
}
# How strongly a participant's identifying-category draw favours a
# category ALREADY used earlier in this same clue, vs a fresh one — the
# deliberate-doubling control the 2026-07-21 TODO asked for (now resolved,
# see the design memory above). 1.0 would mean no bias at all; higher
# values make doubling more common. A real weighted RANDOM draw, not a
# best-first ranking, so a lower-weight option still sometimes wins, just
# less often.
#
# MEASURED 2026-08-12: this constant is NOT the main lever on how often
# tripling happens, and moving it (tried 3.0 and 1.6) barely changed the
# outcome — 81% -> 87% of generated clues had 3+ participants sharing a
# category either way. The real cause is the LEGAL id_cat POOL SIZE, which
# is small by construction: Colour can never be a legal identifier on any
# constellation currently in the game (same pigeonhole fact as
# MUTEX_AXIS_WEIGHTS's Colour note — every colour has >=4 stars, so none
# is ever singleton), so whenever axis=Pitch the only legal identifiers
# are {Name, Sequence} — exactly two buckets. Five participants into two
# buckets guarantees a bucket of >=3 by pigeonhole ALONE, before this
# weight does anything at all. Retune this if the pool ever grows (a
# smaller constellation, or Colour becoming reachable), not to chase the
# current tripling rate — it will not move much.
const MUTEX_REPEAT_CATEGORY_WEIGHT := 2.0

## Down-weights PITCH specifically in the SAME weighted pick, applied
## multiplicatively alongside MUTEX_REPEAT_CATEGORY_WEIGHT rather than
## replacing it — 2026-08-17, the non-feeding-Forms lead's SECOND attempt.
## The FIRST attempt (MUTEX_AXIS_WEIGHTS, retracted) targeted the wrong
## pathway: cutting axis=Pitch's frequency genuinely shrank ONE consumption
## route, but this per-participant id_cat pick is a SEPARATE, independent
## route — PITCH stays fully eligible here whenever a given participant
## happens to have singleton pitch, regardless of axis — and it turned out
## to be the DOMINANT one (measured: Mutex's own singleton-pitch
## disclosures went 36->60 under the axis-only fix, confirming this path
## absorbs whatever the axis path gives up). 0.5 mirrors
## CLOSURE_NAME_BIAS_WEIGHT's magnitude (2.0 favoring NAME there = 0.5
## disfavoring PITCH here), not re-derived from scratch — same "meaningful
## tilt, not deterministic" philosophy as every other bias weight in this
## file.
const MUTEX_PITCH_SCARCITY_WEIGHT := 0.5


func _mutex_pick_axis() -> int:
    var roll: float = _rng.randf()
    var acc: float = 0.0
    for cat in MUTEX_AXIS_WEIGHTS:
        acc += float(MUTEX_AXIS_WEIGHTS[cat])
        if roll < acc:
            return int(cat)
    return Category.PITCH   # float-rounding fallback, should not be reachable


## Stars grouped by raw value on `axis`, shuffled — a direct pick surface
## for distinct-value participant selection, never a discover-by-rejection
## loop. Name/Sequence: every star is its own singleton group, always (both
## are alldiff over every star in the puzzle). Colour/Pitch: only stars
## whose value is one-of-a-kind here get a group at all — the same
## unverifiable-label guard every other Form already respects
## (_category_uniquely_labels).
func _mutex_axis_groups(axis: int) -> Array:
    var groups: Dictionary = {}
    for s in star_count:
        if axis == Category.NAME or axis == Category.SEQUENCE:
            groups[s] = [s]
            continue
        if not _category_uniquely_labels(axis, s):
            continue
        var raw = star_colors[s] if axis == Category.COLOR else star_pitch_index[s]
        if not groups.has(raw):
            groups[raw] = []
        (groups[raw] as Array).append(s)
    var out: Array = groups.values()
    _shuffle_array(out)
    return out


## Categories legal to identify `star` with — excludes `axis` itself (a
## cell can't pair a category against itself) and, for Colour/Pitch, any
## category whose value isn't one-of-a-kind for this specific star.
func _mutex_legal_id_cats(star: int, axis: int) -> Array:
    var out: Array = []
    for cat in [Category.NAME, Category.SEQUENCE, Category.COLOR, Category.PITCH]:
        if cat == axis:
            continue
        if (cat == Category.COLOR or cat == Category.PITCH) and not _category_uniquely_labels(cat, star):
            continue
        out.append(cat)
    return out


## Weighted-random pick from `pool` (removed and returned), given a
## parallel `weights` array of the same size. A genuine random draw, not a
## best-first ranking — see MUTEX_REPEAT_CATEGORY_WEIGHT's own comment for
## why that distinction matters here.
func _mutex_weighted_pick_remove(pool: Array, weights: Array):
    var total: float = 0.0
    for w in weights:
        total += float(w)
    var roll: float = _rng.randf() * total if total > 0.0 else 0.0
    var acc: float = 0.0
    for i in pool.size():
        acc += float(weights[i])
        if roll < acc:
            var picked = pool[i]
            pool.remove_at(i)
            weights.remove_at(i)
            return picked
    var last: int = pool.size() - 1
    var picked_last = pool[last]
    pool.remove_at(last)
    weights.remove_at(last)
    return picked_last


func _build_form_mutual_exclusion(chain: Dictionary) -> Dictionary:
    var axis: int = _mutex_pick_axis()
    var groups: Array = _mutex_axis_groups(axis)
    if groups.size() < 3:
        return {}   # this puzzle's matrix doesn't support this axis right now — skip, nothing to negotiate
    var max_n: int = mini(5, groups.size())
    var n: int = maxi(3, mini(max_n, 3 + _rng.randi_range(0, 2)))

    var participants: Array = []   # each: {id_cat, id_val, axis_val, star}
    var id_cat_usage: Dictionary = {}   # id_cat(int) -> times used so far, for the repeat bias

    # Chain participant first, same priority every other Form gives it —
    # honours the shared "reuse the previous clue's own node" pacing.
    if not chain.is_empty() and int(chain["cat"]) != Category.DISTANCE and int(chain["cat"]) != axis \
            and _category_uniquely_labels(int(chain["cat"]), int(chain["star"])):
        var cs: int = int(chain["star"])
        var cc: int = int(chain["cat"])
        for gi in groups.size():
            if (groups[gi] as Array).has(cs):
                groups.remove_at(gi)
                break
        var cv: int = int(_cat_star_to_value[cc][cs])
        var av: int = int(_cat_star_to_value[axis][cs])
        if not bool(_matrix_cell(cc, cv, axis, av)["used"]):
            participants.append({"id_cat": cc, "id_val": cv, "axis_val": av, "star": cs})
            id_cat_usage[cc] = 1

    while participants.size() < n and not groups.is_empty():
        var group: Array = groups.pop_back()
        var s: int = int(group[_rng.randi_range(0, group.size() - 1)])
        var legal: Array = _mutex_legal_id_cats(s, axis)
        if legal.is_empty():
            continue   # cannot happen — Name/Sequence are always legal unless one of them IS axis, and axis is only ever one category — guarded anyway
        var weights: Array = []
        for cat in legal:
            var w: float = MUTEX_REPEAT_CATEGORY_WEIGHT if id_cat_usage.has(cat) else 1.0
            if int(cat) == Category.PITCH:
                w *= MUTEX_PITCH_SCARCITY_WEIGHT
            weights.append(w)
        var pool: Array = legal.duplicate()
        var chosen: int = -1
        while not pool.is_empty():
            var candidate: int = int(_mutex_weighted_pick_remove(pool, weights))
            var val2: int = int(_cat_star_to_value[candidate][s])
            var axis_val2: int = int(_cat_star_to_value[axis][s])
            if bool(_matrix_cell(candidate, val2, axis, axis_val2)["used"]):
                continue   # this specific cell is already claimed by an earlier clue this attempt — try this star's next-best legal category
            chosen = candidate
            break
        if chosen < 0:
            continue   # every legal identifier for this star is already claimed elsewhere this attempt — move to the next star
        var id_val: int = int(_cat_star_to_value[chosen][s])
        var axis_val: int = int(_cat_star_to_value[axis][s])
        participants.append({"id_cat": chosen, "id_val": id_val, "axis_val": axis_val, "star": s})
        id_cat_usage[chosen] = int(id_cat_usage.get(chosen, 0)) + 1

    if participants.size() < 3:
        return {}

    var chars: Array = []
    var label_items: Array = []
    var grid_updates: Array = []
    var solver_facts: Array = []
    for p in participants:
        var id_ch: Dictionary = {"cat": int(p["id_cat"]), "star": int(p["star"])}
        chars.append(id_ch)
        chars.append({"cat": axis, "star": int(p["star"])})
        label_items.append({"cat": int(p["id_cat"]), "star": int(p["star"]), "label": _characteristic_label(id_ch)})
        grid_updates.append({"cat_a": int(p["id_cat"]), "val_a": int(p["id_val"]), "cat_b": axis, "val_b": int(p["axis_val"]), "is_true": true})
        solver_facts.append_array(_seq_fact_for_label(id_ch))

    # Cross-participant distinctness — see the header comment above for why
    # this is sound for every axis and why same-id_cat pairs are skipped.
    var cross_cells: int = 0
    for i in participants.size():
        for j in range(i + 1, participants.size()):
            var pi: Dictionary = participants[i]
            var pj: Dictionary = participants[j]
            var cat_i: int = int(pi["id_cat"])
            var cat_j: int = int(pj["id_cat"])
            if cat_i == cat_j:
                continue
            grid_updates.append({
                "cat_a": cat_i, "val_a": int(pi["id_val"]),
                "cat_b": cat_j, "val_b": int(pj["id_val"]),
                "is_true": false,
            })
            cross_cells += 1

    var value_facts: Array = []
    var text: String
    if axis == Category.COLOR or axis == Category.PITCH:
        var noun: String = "colors" if axis == Category.COLOR else "pitches"
        text = "%s all have different %s." % [_join_names_and(_sort_labels_for_join(label_items)), noun]
        # The clue's ACTUAL extra content here is pairwise distinctness on
        # `axis` — which no cell can express — so it still needs a
        # disclosure, same as the pre-rewrite Form always required for
        # Colour/Pitch. Kept separate from solver_facts so the Sequence
        # uniqueness CSP's input stays untouched; the persist site merges
        # the two into "disclosures".
        var mx_stars: Array = []
        for p2 in participants:
            mx_stars.append(int(p2["star"]))
        value_facts.append({"kind": "values_all_different", "cat": axis, "stars": mx_stars})
    else:
        # Name/Sequence: nothing beyond "different stars" to disclose — the
        # cross-participant False cells above already carry it all.
        #
        # Which is exactly why zero of them means the clue says NOTHING.
        # Same-id_cat pairs are skipped above because two different Name
        # values are different stars BY CONSTRUCTION — Name is alldiff — so
        # when every participant is identified on the same axis, that loop
        # emits nothing and this branch adds no value_facts either:
        #
        #     "Theraion, Oryides, and Keriion are all different stars."
        #
        # A tautology, reported from a live puzzle 2026-08-14. The content
        # of this Form is CROSS-AXIS distinctness ("the star that fires 3rd
        # is not Oryides"), which is real information; within one alldiff
        # axis there is none to have. Reject and let the caller redraw.
        #
        # Deliberately counted rather than inferred from the id_cats: the
        # cells are the clue's actual content, so asking whether any exist
        # is asking the question directly instead of re-deriving the answer.
        if cross_cells == 0:
            return {}
        text = "%s are all different stars." % _join_names_and(_sort_labels_for_join(label_items))

    return {"chars": chars, "text": text, "grid_updates": grid_updates, "solver_facts": solver_facts, "value_facts": value_facts}


# ── Form 14: Group Comparison — multi-axis abstraction (explicit list of
# individually-referenced targets, not only an implicit shared-value group). ──

func _group_comparison_noun(axis: int) -> String:
    match axis:
        Category.SEQUENCE:
            return "sequence position"
        Category.PITCH:
            return "frequency"
    return "color rank"


func _build_form_group_comparison(chain: Dictionary) -> Dictionary:
    # Subject uses the free-choice pattern (Forms 5/6/8/10/11); each group
    # member is a specific, predetermined star (whichever passed the
    # greater/lesser filter), so it uses the Form 7/12 pattern instead —
    # its own TRUE identity-establishing cell via _identity_cell_for_known_star.
    var axis: int = _orderable_categories()[_rng.randi_range(0, 1)]
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var subject_star: int = int(a["star"])
    var subject_val: int = _order_value(axis, subject_star)
    var s_more: bool = _rng.randf() < 0.5
    var candidates: Array = []
    for s in star_count:
        if s == subject_star:
            continue
        var v: int = _order_value(axis, s)
        if s_more and v >= subject_val:
            continue
        if not s_more and v <= subject_val:
            continue
        candidates.append(s)
    if candidates.size() < 2:
        return {}
    _shuffle_array(candidates)
    var n: int = mini(4, candidates.size())
    var group_stars: Array = candidates.slice(0, n)

    var group_cells: Array = []
    for gs in group_stars:
        var g: Dictionary = _identity_cell_for_known_star(int(gs), axis)
        if g.is_empty():
            return {}
        group_cells.append(g)

    var subject_id: Dictionary = {"cat": int(a["id_cat"]), "star": subject_star}
    var subject_axis_ch: Dictionary = {"cat": axis, "star": subject_star}
    var chars: Array = [subject_id, subject_axis_ch]
    var label_items: Array = []
    var grid_updates: Array = [
        {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
    ]
    var solver_facts: Array = _seq_fact_for_label(subject_id)
    for g in group_cells:
        var gid: Dictionary = {"cat": int(g["id_cat"]), "star": int(g["star"])}
        var gaxis: Dictionary = {"cat": axis, "star": int(g["star"])}
        chars.append(gid)
        chars.append(gaxis)
        label_items.append({"cat": int(g["id_cat"]), "star": int(g["star"]), "label": _characteristic_label(gid)})
        grid_updates.append({"cat_a": int(g["id_cat"]), "val_a": int(g["id_val"]), "cat_b": axis, "val_b": int(g["axis_val"]), "is_true": true})
        solver_facts.append_array(_seq_fact_for_label(gid))
        if axis == Category.SEQUENCE:
            solver_facts.append({"kind": "ordinal_cmp", "a": subject_star, "b": int(g["star"]), "a_gt_b": s_more})
    var noun: String = _group_comparison_noun(axis)
    var word: String = "higher" if s_more else "lower"
    var text: String = "%s has a %s %s than %s." % [_characteristic_label(subject_id), word, noun, _join_names_and(_sort_labels_for_join(label_items))]
    return {"chars": chars, "text": text, "grid_updates": grid_updates, "solver_facts": solver_facts}


# ── Form 9: Group Order — direct case only (first pass): group = every
# star sharing one raw Color/Pitch value, derived downstream from a single
# sampled group-defining characteristic. The multi-axis explicit-list
# variant (like Group Comparison got) wasn't clarified for this specific
# Form, so it's deferred rather than guessed at. ─────────────────────────

func _build_form_group_order(chain: Dictionary) -> Dictionary:
    # Group derivation stays downstream, per the established principle: we
    # don't pick "a group," we sample a TRUE cell pairing group_cat against
    # some other random category, and the group falls out as "every star
    # sharing THAT star's raw group_cat value" — a trivial, no-choice
    # consequence of which cell landed, not an upstream decision.
    var group_cat: int = Category.COLOR if _rng.randf() < 0.5 else Category.PITCH
    # bias_name here too — def_star's OWN identity is pure bookkeeping
    # (never rendered, never produces a name_group fact; only
    # _note_group_value_term reads def_star, and that only handles
    # Colour/Pitch terms). Retracted-and-reasoned finding: giving Group
    # Order unconditional scheduling PRIORITY measured worse on singleton-
    # pitch coverage (32%->37%), and the suspected cause was exactly this
    # draw — when group_cat=Colour, id_cat could still land on Pitch and
    # spend a scarce singleton-pitch cell on bookkeeping that Equality
    # Pair (higher volume, already NAME-biased) could have turned into a
    # real fact instead. This narrows PITCH's odds here (1/3 uniform ->
    # 1/4 weighted) without touching WHEN Group Order runs at all.
    var g: Dictionary = _sample_identity_axis_cell(group_cat, chain, -1, true)
    if g.is_empty():
        return {}
    var def_star: int = int(g["star"])
    var raw_of: Callable = func(s): return star_colors[s] if group_cat == Category.COLOR else star_pitch_index[s]
    var raw_val = raw_of.call(def_star)
    var group_stars: Array = []
    for s in star_count:
        if raw_of.call(s) == raw_val:
            group_stars.append(s)
    var axis: int = Category.SEQUENCE
    var subject_star: int = -1
    var subj_id_cat: int = -1
    var subj_id_val: int = -1
    var subj_axis_val: int = -1
    if not chain.is_empty() and int(chain["cat"]) != Category.DISTANCE and int(chain["cat"]) != axis and not group_stars.has(int(chain["star"])) and _category_uniquely_labels(int(chain["cat"]), int(chain["star"])):
        var cs: int = int(chain["star"])
        var cc: int = int(chain["cat"])
        var cv: int = int(_cat_star_to_value[cc][cs])
        var av: int = int(_cat_star_to_value[axis][cs])
        if not bool(_matrix_cell(cc, cv, axis, av)["used"]):
            subject_star = cs
            subj_id_cat = cc
            subj_id_val = cv
            subj_axis_val = av
    if subject_star == -1:
        # Single, final-commitment draw (bails {} if candidates comes back
        # empty below, no retry with a different id_cat) — soft weighted
        # pick toward NAME, same rationale as Equality Pair's identity
        # draws: this is one of the closure-feeding Forms, and its subject
        # can only be NAME or Pitch here (axis=SEQUENCE excludes itself,
        # Colour never survives the uniqueness check below regardless).
        var id_cat: int = _weighted_category_excluding(axis)
        var candidates: Array = []
        for s in star_count:
            if group_stars.has(s) or not _category_uniquely_labels(id_cat, s):
                continue
            var id_val: int = int(_cat_star_to_value[id_cat][s])
            var axis_val: int = int(_cat_star_to_value[axis][s])
            if not bool(_matrix_cell(id_cat, id_val, axis, axis_val)["used"]):
                candidates.append(s)
        if candidates.is_empty():
            return {}
        subject_star = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
        subj_id_cat = id_cat
        subj_id_val = int(_cat_star_to_value[id_cat][subject_star])
        subj_axis_val = int(_cat_star_to_value[axis][subject_star])
    var subj_val: int = _order_value(axis, subject_star)
    var precedes: bool = true
    for gs in group_stars:
        if _order_value(axis, int(gs)) < subj_val:
            precedes = false
            break
    if not precedes:
        var follows: bool = true
        for gs2 in group_stars:
            if _order_value(axis, int(gs2)) > subj_val:
                follows = false
                break
        if not follows:
            return {}
    var subject_id: Dictionary = {"cat": subj_id_cat, "star": subject_star}
    var subject_axis: Dictionary = {"cat": axis, "star": subject_star}
    var group_def_ch: Dictionary = {"cat": group_cat, "star": def_star}
    _note_group_value_term(group_cat, def_star)
    # As above: "every star that plays X" implies a set, so a singleton
    # value collapses to "the star that plays X". Unlike Cross-Domain
    # Bridge, this Form has no group_stars.size() < 2 guard — it is
    # perfectly happy to build a one-member group — so the phrasing has to
    # handle it.
    var group_phrase: String = _group_noun_phrase(group_cat, def_star, true)
    var verb_word: String = "precedes" if precedes else "follows"
    var text: String = "%s %s %s." % [_characteristic_label(subject_id), verb_word, group_phrase]
    # Group members are never individually labeled (group_phrase is a raw
    # collective description, not built via _characteristic_label) — only
    # the disclosed relation matters: subject precedes/follows EVERY member.
    var solver_facts: Array = _seq_fact_for_label(subject_id)
    for gs3 in group_stars:
        solver_facts.append({"kind": "ordinal_cmp", "a": subject_star, "b": int(gs3), "a_gt_b": not precedes})
    var value_facts: Array = _name_order_vs_group_facts(subject_id, group_def_ch, precedes)
    return {
        "chars": [subject_id, subject_axis, group_def_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(g["id_cat"]), "val_a": int(g["id_val"]), "cat_b": group_cat, "val_b": int(g["axis_val"]), "is_true": true},
            {"cat_a": subj_id_cat, "val_a": subj_id_val, "cat_b": axis, "val_b": subj_axis_val, "is_true": true},
        ],
        "solver_facts": solver_facts,
        "value_facts": value_facts,
    }


# ── Forms 10, 11: local-neighborhood facts (map-adjacency via proximity[]) ──

func _build_form_extreme(chain: Dictionary) -> Dictionary:
    var axis: int = Category.SEQUENCE
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var subject_star: int = int(a["star"])
    var neighbors: Array = proximity[subject_star]
    if neighbors.is_empty():
        return {}
    var subj_val: int = _order_value(axis, subject_star)
    var want_lowest: bool = true
    for n in neighbors:
        if _order_value(axis, int(n)) < subj_val:
            want_lowest = false
            break
    if not want_lowest:
        var is_highest: bool = true
        for n2 in neighbors:
            if _order_value(axis, int(n2)) > subj_val:
                is_highest = false
                break
        if not is_highest:
            return {}
    var subject_id: Dictionary = {"cat": int(a["id_cat"]), "star": subject_star}
    var subject_axis: Dictionary = {"cat": axis, "star": subject_star}
    var word: String = "earliest" if want_lowest else "latest"
    var text: String = "%s is the %s to fire among its connected stars." % [_characteristic_label(subject_id), word]
    var solver_facts: Array = _seq_fact_for_label(subject_id)
    solver_facts.append({"kind": "ordinal_extreme", "s": subject_star, "want_lowest": want_lowest, "neighbors": neighbors})
    return {
        "chars": [subject_id, subject_axis],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


func _build_form_count(chain: Dictionary) -> Dictionary:
    var axis: int = Category.SEQUENCE
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var subject_star: int = int(a["star"])
    var neighbors: Array = proximity[subject_star]
    if neighbors.is_empty():
        return {}
    var subj_val: int = _order_value(axis, subject_star)
    var k: int = 0
    for n in neighbors:
        if _order_value(axis, int(n)) < subj_val:
            k += 1
    var subject_id: Dictionary = {"cat": int(a["id_cat"]), "star": subject_star}
    var subject_axis: Dictionary = {"cat": axis, "star": subject_star}
    var text: String = "Exactly %d of %s's connected stars fire before it." % [k, _characteristic_label(subject_id)]
    var solver_facts: Array = _seq_fact_for_label(subject_id)
    solver_facts.append({"kind": "ordinal_count_before", "s": subject_star, "k": k, "neighbors": neighbors})
    return {
        "chars": [subject_id, subject_axis],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


# ── Forms 15, 16, 19: Distance-anchored facts ────────────────────────────

func _build_form_distance_existential(chain: Dictionary) -> Dictionary:
    # No comparison axis here (unlike Forms 5-14) — subject_cat just plays
    # the axis-parameter role for _sample_identity_axis_cell so the subject
    # gets a real TRUE-cell identity establishment instead of a bare,
    # matrix-incompatible single-Characteristic pick.
    var subject_cat: int = _non_distance_category()
    var a: Dictionary = _sample_identity_axis_cell(subject_cat, chain, -1)
    if a.is_empty():
        return {}
    # prop_cat below is always Color/Pitch (given axes) — if the subject's
    # own label also lands on a given axis, the whole clue is re-derivable
    # from the map alone. Reject and let the caller retry with a fresh draw.
    if not _is_hidden_category(int(a["id_cat"])):
        return {}
    var subject_star: int = int(a["star"])
    var prop_cat: int = Category.COLOR if _rng.randf() < 0.5 else Category.PITCH
    var candidates: Array = []
    for s in star_count:
        if s != subject_star and _distances[subject_star][s] != -1:
            candidates.append(s)
    if candidates.is_empty():
        return {}
    var target: int = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
    var hop: int = _distances[subject_star][target]
    _note_group_value_term(prop_cat, target)
    # Article chosen from the group size, not hardcoded — "a star that
    # plays B4" when exactly one star plays B4 told the player to keep
    # looking for alternatives that do not exist.
    var prop_noun: String = _group_noun_phrase(prop_cat, target, false)
    var subject_id: Dictionary = {"cat": int(a["id_cat"]), "star": subject_star}
    var dist_ch: Dictionary = {"cat": Category.DISTANCE, "star": target, "ref": subject_star}
    _note_rendered_term("H", hop)
    var text: String = "%s is %d %s from %s." % [_characteristic_label(subject_id), hop, _hop_word(hop), prop_noun]
    # prop_noun is a raw custom string (color/pitch description), never
    # built via _characteristic_label — only subject_id's label discloses
    # anything Sequence-relevant, and only if subject_cat happens to be it.
    var solver_facts: Array = _seq_fact_for_label(subject_id)
    return {
        "chars": [subject_id, dist_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": subject_cat, "val_b": int(a["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
        # The clue's ACTUAL claim. Without this its only scoreable content
        # was _seq_fact_for_label's ordinal_exact — a fact derived from the
        # clue merely MENTIONING a Sequence descriptor, not from anything it
        # asserts. Distance is ternary so it fits no cell, and value_facts
        # (not solver_facts) is the right home: the Sequence uniqueness CSP
        # has no use for hops.
        #
        # ref_cat/target_cat (CACHE_VERSION 7) are what make this a claim
        # about DESCRIPTORS rather than about two solution star indices.
        # The text names neither star: it says "<hidden label> is N hops
        # from <group noun phrase>", so what the player is told is "the
        # star this descriptor denotes is N hops from SOME star in that
        # group". Recording the categories lets the engine reconstruct both
        # groups from the player's own knowledge, which is both the only
        # sound reading and the only one that can eliminate anything.
        # Without them the deduction side has nothing but ref/target — raw
        # solution indices it must not reason from directly.
        "value_facts": [{
            "kind": "distance_hop",
            "ref": subject_star, "target": target, "hops": hop,
            "ref_cat": int(a["id_cat"]), "target_cat": prop_cat,
        }],
    }


func _build_form_distance_extreme(chain: Dictionary) -> Dictionary:
    # ref_star: free-choice identity establishment (Form 15's pattern),
    # displayed via ref_cat itself (preserving the original's label
    # convention here, rather than the paired id_cat side other migrated
    # Forms display through — both sides are equally valid/true labels for
    # the same star; this Form just happened to use the other one).
    var ref_cat: int = _non_distance_category()
    var r: Dictionary = _sample_identity_axis_cell(ref_cat, chain, -1)
    if r.is_empty():
        return {}
    var ref_star: int = int(r["star"])
    # ref_cat plays the AXIS role inside _sample_identity_axis_cell, which
    # only guards the PAIRED id_cat side's uniqueness — ref_cat itself is
    # used directly as ref_ch2's label below, so its own group size for
    # THIS star still needs checking (unlike Form 15, which labels via
    # a["id_cat"] instead of the axis category, and so doesn't need this).
    if not _category_uniquely_labels(ref_cat, ref_star):
        return {}
    var best_star: int = -1
    var best_d: int = -1
    var want_closest: bool = _rng.randf() < 0.5
    for s in star_count:
        if s == ref_star:
            continue
        var d: int = _distances[ref_star][s]
        if d == -1:
            continue
        if best_star == -1 or (want_closest and d < best_d) or (not want_closest and d > best_d):
            best_star = s
            best_d = d
    if best_star == -1:
        return {}
    for s2 in star_count:
        if s2 == ref_star or s2 == best_star:
            continue
        if _distances[ref_star][s2] == best_d:
            return {}
    # target: a specific, predetermined star (the extreme-distance winner),
    # same Form 7/12/14 pattern. Minor behavior note: its identity category
    # is now guaranteed different from ref_cat (a side effect of reusing
    # _identity_cell_for_known_star's id_cat != axis_cat guard) rather than
    # being a fully free random pick that could coincidentally match —
    # arguably an improvement (avoids "the yellow star is farthest from the
    # red star"-style redundancy), flagging since it's still a behavior change.
    var t: Dictionary = _identity_cell_for_known_star(best_star, ref_cat)
    if t.is_empty():
        return {}
    var ref_ch2: Dictionary = {"cat": ref_cat, "star": ref_star}
    var target_dist_ch: Dictionary = {"cat": Category.DISTANCE, "star": best_star, "ref": ref_star}
    var target_id: Dictionary = {"cat": int(t["id_cat"]), "star": best_star}
    # Both ends can independently land on Color/Pitch — reject only when
    # NEITHER side touches a hidden axis (see _is_hidden_category), same
    # "at least one labeled star must be genuinely unknown" rule as
    # Form 15/19.
    if not _is_hidden_category(ref_cat) and not _is_hidden_category(int(t["id_cat"])):
        return {}
    var word: String = "closest" if want_closest else "farthest"
    var text: String = "%s is the %s star to %s." % [_characteristic_label(target_id), word, _characteristic_label(ref_ch2)]
    # Both labels are rendered; no Sequence-relational content either way —
    # closest/farthest is a hop-distance fact, unrelated to Sequence order.
    var solver_facts: Array = _seq_fact_for_label(ref_ch2) + _seq_fact_for_label(target_id)
    return {
        "chars": [ref_ch2, target_id, target_dist_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(r["id_cat"]), "val_a": int(r["id_val"]), "cat_b": ref_cat, "val_b": int(r["axis_val"]), "is_true": true},
            {"cat_a": int(t["id_cat"]), "val_a": int(t["id_val"]), "cat_b": ref_cat, "val_b": int(t["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


func _build_form_non_adjacency(chain: Dictionary) -> Dictionary:
    # subject: free-choice identity establishment (Form 15's pattern). value:
    # a star that must be neither subject_star nor one of its map-neighbors
    # — a whole-set exclusion _sample_identity_axis_cell doesn't support
    # (single exclude_star only), so this needs its own inline candidate
    # loop, same reason Forms 9/17 needed one. value_cat now restricted to
    # the four bijective categories (was _random_other_category, which could
    # land on Distance) — the old Distance branch of
    # _unused_characteristics_for always returned empty without a
    # reference star, so roughly 1/4 of attempts silently auto-failed;
    # removing that dead branch outright rather than replicating the waste.
    var subject_cat: int = _non_distance_category()
    var a: Dictionary = _sample_identity_axis_cell(subject_cat, chain, -1)
    if a.is_empty():
        return {}
    var subject_star: int = int(a["star"])
    # subject_id below is labeled via subject_cat directly (not a["id_cat"]),
    # so — like Form 16's ref_ch2 — subject_cat's own uniqueness for this
    # star needs its own check; _sample_identity_axis_cell only guarded
    # a["id_cat"]'s side.
    if not _category_uniquely_labels(subject_cat, subject_star):
        return {}
    var neighbor_set: Dictionary = {}
    for n in proximity[subject_star]:
        neighbor_set[int(n)] = true
    var value_cat: int = _non_distance_category()
    while value_cat == subject_cat:
        value_cat = _non_distance_category()
    # Same "at least one labeled star must be genuinely unknown" rule as
    # Form 15/16 — reject before the expensive candidate search below if
    # both ends would land on Color/Pitch.
    if not _is_hidden_category(subject_cat) and not _is_hidden_category(value_cat):
        return {}
    var id_cat2: int = _non_distance_category()
    while id_cat2 == value_cat:
        id_cat2 = _non_distance_category()
    var candidates: Array = []
    for s in star_count:
        if s == subject_star or neighbor_set.has(s) or not _category_uniquely_labels(value_cat, s):
            continue
        var id_val2: int = int(_cat_star_to_value[id_cat2][s])
        var val_val2: int = int(_cat_star_to_value[value_cat][s])
        if not bool(_matrix_cell(id_cat2, id_val2, value_cat, val_val2)["used"]):
            candidates.append(s)
    if candidates.is_empty():
        return {}
    var value_star: int = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
    var value_ch: Dictionary = {"cat": value_cat, "star": value_star}
    var subject_id: Dictionary = {"cat": subject_cat, "star": subject_star}
    var text: String = "%s is not connected to %s." % [_characteristic_label(subject_id), _characteristic_label(value_ch)]
    # Map-adjacency, not Sequence-adjacency — no relational Sequence content;
    # only the two rendered labels can disclose anything Sequence-relevant.
    var solver_facts: Array = _seq_fact_for_label(subject_id) + _seq_fact_for_label(value_ch)
    return {
        "chars": [subject_id, value_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": subject_cat, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": id_cat2, "val_a": int(_cat_star_to_value[id_cat2][value_star]), "cat_b": value_cat, "val_b": int(_cat_star_to_value[value_cat][value_star]), "is_true": true},
        ],
        "solver_facts": solver_facts,
        # "Not connected" IS a distance claim: not 1 hop. Same disclosure
        # kind as Form 15, negated — see this file's Form 15 note for why
        # the clue otherwise had no scoreable content of its own. Form 16
        # (Distance Extreme) deliberately gets NO distance_hop: its claim is
        # an extremum over a whole distance row ("the closest star to X is
        # Y"), not a fixed hop count, so it needs its own kind rather than
        # a misleading exact-hop stand-in.
        # target_cat's group is a SINGLETON here, guaranteed by the
        # _category_uniquely_labels(value_cat, s) filter on the candidate
        # search above — so the same existential representation Form 15
        # uses ("some star in the group") collapses to Form 19's definite
        # reference without needing a second shape for it.
        "value_facts": [{
            "kind": "distance_hop",
            "ref": subject_star, "target": value_star, "hops": 1, "negated": true,
            "ref_cat": subject_cat, "target_cat": value_cat,
        }],
    }


func _build_form_betweenness(chain: Dictionary) -> Dictionary:
    # Three stars, all freely chosen among remaining candidates (none is
    # predetermined the way Form 7/12/14/16's targets are). s1/s2 reuse
    # _sample_identity_axis_cell; s3 needs its own inline pick since that
    # helper only supports a single exclude_star and this needs to exclude
    # both s1 and s2 at once.
    var axis: int = Category.SEQUENCE if _rng.randf() < 0.7 else Category.PITCH
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var s1: int = int(a["star"])
    var b: Dictionary = _sample_identity_axis_cell(axis, {}, s1)   # only one node chains per Step 9
    if b.is_empty():
        return {}
    var s2: int = int(b["star"])
    var id_cat3: int = _non_distance_category()
    while id_cat3 == axis:
        id_cat3 = _non_distance_category()
    var candidates3: Array = []
    for s in star_count:
        if s == s1 or s == s2 or not _category_uniquely_labels(id_cat3, s):
            continue
        var id_val3: int = int(_cat_star_to_value[id_cat3][s])
        var axis_val3: int = int(_cat_star_to_value[axis][s])
        if not bool(_matrix_cell(id_cat3, id_val3, axis, axis_val3)["used"]):
            candidates3.append(s)
    if candidates3.is_empty():
        return {}
    var s3: int = int(candidates3[_rng.randi_range(0, candidates3.size() - 1)])
    var c: Dictionary = {"id_cat": id_cat3, "id_val": int(_cat_star_to_value[id_cat3][s3]), "axis_val": int(_cat_star_to_value[axis][s3]), "star": s3}

    if _order_value(axis, s1) == _order_value(axis, s2) or _order_value(axis, s2) == _order_value(axis, s3) or _order_value(axis, s1) == _order_value(axis, s3):
        return {}   # Pitch ranks can genuinely tie (unlike Sequence, which never does) —
                     # a tied pair can't support a strict betweenness claim.

    var stars_info: Dictionary = {s1: a, s2: b, s3: c}
    var ranked: Array = [s1, s2, s3]
    ranked.sort_custom(func(x, y): return _order_value(axis, x) < _order_value(axis, y))
    var lo: int = int(ranked[0])
    var mid: int = int(ranked[1])
    var hi: int = int(ranked[2])
    var lo_info: Dictionary = stars_info[lo]
    var mid_info: Dictionary = stars_info[mid]
    var hi_info: Dictionary = stars_info[hi]
    var lo_id: Dictionary = {"cat": int(lo_info["id_cat"]), "star": lo}
    var mid_id: Dictionary = {"cat": int(mid_info["id_cat"]), "star": mid}
    var hi_id: Dictionary = {"cat": int(hi_info["id_cat"]), "star": hi}
    var axis_lo: Dictionary = {"cat": axis, "star": lo}
    var axis_mid: Dictionary = {"cat": axis, "star": mid}
    var axis_hi: Dictionary = {"cat": axis, "star": hi}
    var verb: String = _order_verb(axis)
    var text: String
    match _rng.randi() % 3:
        0:
            text = "%s %s between %s and %s." % [_characteristic_label(mid_id), verb, _characteristic_label(lo_id), _characteristic_label(hi_id)]
        1:
            text = "%s %s %s %s, which %s %s %s." % [
                _characteristic_label(lo_id), verb, _order_chain_word(axis, false), _characteristic_label(mid_id),
                verb, _order_chain_word(axis, false), _characteristic_label(hi_id)]
        _:
            text = "%s %s %s %s, which %s %s %s." % [
                _characteristic_label(hi_id), verb, _order_chain_word(axis, true), _characteristic_label(mid_id),
                verb, _order_chain_word(axis, true), _characteristic_label(lo_id)]
    var solver_facts: Array = _seq_fact_for_label(lo_id) + _seq_fact_for_label(mid_id) + _seq_fact_for_label(hi_id)
    if axis == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_chain", "a": lo, "mid": mid, "b": hi})
    return {
        "chars": [lo_id, mid_id, hi_id, axis_lo, axis_mid, axis_hi],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": int(b["axis_val"]), "is_true": true},
            {"cat_a": int(c["id_cat"]), "val_a": int(c["id_val"]), "cat_b": axis, "val_b": int(c["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


# ── Form 20: Cross-Domain Bridge — first pass ────────────────────────────

func _build_form_cross_domain_bridge(chain: Dictionary) -> Dictionary:
    # Group derivation stays downstream (Form 9/13's pattern): sample a TRUE
    # cell pairing group_cat against some other category, group falls out
    # as "every star sharing that raw value." extreme_star is then fully
    # determined (the group's Sequence-extreme member), so d2's TRUE cell
    # is a direct (d1, d2) pairing for that already-known star, not a fresh
    # identity establishment. Also cleaned up d2's selection: the old
    # fallback ("if d2 lands on Distance, silently swap to Name") only
    # worked by coincidence (Name never equals group_cat/d1 here); using
    # _non_distance_category() directly removes the coincidence dependency.
    var group_cat: int = Category.COLOR if _rng.randf() < 0.5 else Category.PITCH
    var g: Dictionary = _sample_identity_axis_cell(group_cat, chain, -1)
    if g.is_empty():
        return {}
    var def_star: int = int(g["star"])
    var raw_of: Callable = func(s): return star_colors[s] if group_cat == Category.COLOR else star_pitch_index[s]
    var raw_val = raw_of.call(def_star)
    var group_stars: Array = []
    for s in star_count:
        if raw_of.call(s) == raw_val:
            group_stars.append(s)
    if group_stars.size() < 2:
        return {}
    var d1: int = Category.SEQUENCE
    var want_lowest: bool = _rng.randf() < 0.5
    var extreme_star: int = int(group_stars[0])
    for gs in group_stars:
        var v: int = _order_value(d1, int(gs))
        var cur: int = _order_value(d1, extreme_star)
        if (want_lowest and v < cur) or (not want_lowest and v > cur):
            extreme_star = int(gs)
    var d2: int = _non_distance_category()
    while d2 == group_cat or d2 == d1 or not _category_uniquely_labels(d2, extreme_star):
        d2 = _non_distance_category()
    var d1_val: int = int(_cat_star_to_value[d1][extreme_star])
    var d2_val: int = int(_cat_star_to_value[d2][extreme_star])
    if bool(_matrix_cell(d1, d1_val, d2, d2_val)["used"]):
        return {}
    var d2_ch: Dictionary = {"cat": d2, "star": extreme_star}
    var d1_ch: Dictionary = {"cat": d1, "star": extreme_star}
    var group_def_ch: Dictionary = {"cat": group_cat, "star": def_star}
    _note_group_value_term(group_cat, def_star)
    var group_phrase: String = ("the %s stars" % COLOR_NAMES[star_colors[def_star]].to_lower()) if group_cat == Category.COLOR else ("the stars that play %s" % note_name_for_freq(_freq_for_star(def_star)))
    var extreme_word: String = "earliest-firing" if want_lowest else "latest-firing"
    var text: String = "Among %s, the %s one is %s." % [group_phrase, extreme_word, _characteristic_label(d2_ch)]
    # group_phrase is a raw custom string, never through _characteristic_
    # label; d1_ch (the Sequence node) is bookkeeping only, never rendered
    # either — "earliest/latest-firing among the group" discloses only a
    # RELATIVE extreme fact (like Forms 9/11/14), never extreme_star's
    # absolute rank, so this needs ordinal_extreme, not ordinal_exact.
    var extreme_neighbors: Array = []
    for gs4 in group_stars:
        if int(gs4) != extreme_star:
            extreme_neighbors.append(int(gs4))
    var solver_facts: Array = _seq_fact_for_label(d2_ch)
    solver_facts.append({"kind": "ordinal_extreme", "s": extreme_star, "want_lowest": want_lowest, "neighbors": extreme_neighbors})
    # NAME closure (Phase 2, eleventh slice): d2_ch IS rendered — it is the
    # clue's subject, "...the earliest-firing one is X" — so when d2 lands
    # on Name this clue discloses two separate things about that name, and
    # both are emitted. Membership reuses the existing kind unchanged;
    # the extremum is the new one and is the valuable half, since it
    # resolves to a single position (a PIN). Both emitters no-op unless
    # d2 == NAME and group_cat is Colour/Pitch, so the ~25% of draws where
    # d2 lands on Pitch cost nothing. group_def_ch is disclosed by VALUE
    # via group_phrase/_note_group_value_term, never as an identity label
    # — same shape Group Membership already relies on.
    var value_facts: Array = _name_group_facts(d2_ch, group_def_ch, true)
    value_facts.append_array(_name_extreme_in_group_facts(d2_ch, group_def_ch, want_lowest))
    return {
        "chars": [group_def_ch, d1_ch, d2_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(g["id_cat"]), "val_a": int(g["id_val"]), "cat_b": group_cat, "val_b": int(g["axis_val"]), "is_true": true},
            {"cat_a": d1, "val_a": d1_val, "cat_b": d2, "val_b": d2_val, "is_true": true},
        ],
        "solver_facts": solver_facts,
        "value_facts": value_facts,
    }


# ── Form 23: Group Membership — the bare case Cross-Domain Bridge (20) and
# Group Order (9) both build ON TOP of but never state directly: "X is
# [not] one of the [colour/pitch] stars." No extremum, no ordering, just
# membership — found missing by a matrix-up review of negative-exclusion
# coverage (2026-08-16): Colour is never a legal IDENTIFIER anywhere in
# this file (its group size is never 1 — see MUTEX_AXIS_WEIGHTS' note), so
# every Form that needs to pin ONE star's colour is structurally blind to
# it; only Forms describing a GROUP by raw value (via _group_noun_phrase's
# approach, bypassing the uniqueness gate entirely) can touch it at all,
# and until now both of those wrapped it in something extra. This is the
# unwrapped version, and specifically the NEGATIVE half is the point: a
# single "not one of the blue stars" is weak alone, but is available for
# roughly 3 of 4 stars (vs. Cross-Domain Bridge's single per-group extreme
# member), and several such facts about the SAME name compound by
# elimination — the classic zebra-puzzle technique this Form set had no
# way to produce before. ──────────────────────────────────────────────────

func _build_form_group_membership(chain: Dictionary) -> Dictionary:
    var group_cat: int = Category.COLOR if _rng.randf() < 0.5 else Category.PITCH
    var g: Dictionary = _sample_identity_axis_cell(group_cat, chain, -1)
    if g.is_empty():
        return {}
    var def_star: int = int(g["star"])
    var raw_of: Callable = func(s): return star_colors[s] if group_cat == Category.COLOR else star_pitch_index[s]
    var raw_val = raw_of.call(def_star)
    var group_stars: Array = []
    for s in star_count:
        if raw_of.call(s) == raw_val:
            group_stars.append(s)
    # A singleton "group" makes "one of" degenerate — same guard
    # Cross-Domain Bridge uses (group_stars.size() < 2).
    if group_stars.size() < 2:
        return {}

    var want_positive: bool = _rng.randf() < 0.5
    var pool: Array = []
    if want_positive:
        # A genuine, DISTINCT member — excludes def_star itself, which
        # would otherwise make the clue "X is one of the group X defines."
        for gs in group_stars:
            if int(gs) != def_star:
                pool.append(gs)
    else:
        for s2 in star_count:
            if not group_stars.has(s2):
                pool.append(s2)
    _shuffle_array(pool)

    var subject_star: int = -1
    var subj_id_cat: int = -1
    for cand in pool:
        # NAME/SEQUENCE only — NOT _non_distance_category() excluding just
        # group_cat, which would also allow PITCH here whenever
        # group_cat==COLOR. That pairing is purely observational on BOTH
        # sides (map colour + a listened pitch) with no Name/Sequence
        # content anywhere in the clue — caught live by
        # test_clue_has_hidden_content.gd: "The star that plays C#5 is one
        # of the blue stars." is fully readable off the map, zero
        # deduction, same failure class as the F5/E5 bug fixed earlier
        # this session. Cross-Domain Bridge avoids this because its
        # "earliest/latest-firing" framing is ALWAYS genuine Sequence-
        # relational content even when its d2 lands on Pitch; this Form
        # has no such mandatory content, so the identifying side must BE
        # the hidden content instead.
        # Was a plain 0.5 coinflip; now shares CLOSURE_NAME_BIAS_WEIGHT
        # with the other closure-feeding Forms' draws (NAME:SEQUENCE
        # weighted 2:1 = 2/3), one tunable constant instead of a second,
        # independently-drifting magic number.
        var idc: int = Category.NAME if _rng.randf() < (CLOSURE_NAME_BIAS_WEIGHT / (CLOSURE_NAME_BIAS_WEIGHT + 1.0)) else Category.SEQUENCE
        if not _category_uniquely_labels(idc, int(cand)):
            continue
        var idv: int = int(_cat_star_to_value[idc][cand])
        var axv: int = int(_cat_star_to_value[group_cat][cand])
        if bool(_matrix_cell(idc, idv, group_cat, axv)["used"]):
            continue
        subject_star = int(cand)
        subj_id_cat = idc
        break
    if subject_star == -1:
        return {}

    var subj_id_val: int = int(_cat_star_to_value[subj_id_cat][subject_star])
    var subj_axis_val: int = int(_cat_star_to_value[group_cat][subject_star])
    var subject_id: Dictionary = {"cat": subj_id_cat, "star": subject_star}
    var group_def_ch: Dictionary = {"cat": group_cat, "star": def_star}
    _note_group_value_term(group_cat, def_star)
    var group_phrase: String = ("the %s stars" % COLOR_NAMES[star_colors[def_star]].to_lower()) if group_cat == Category.COLOR else ("the stars that play %s" % note_name_for_freq(_freq_for_star(def_star)))
    var word: String = "one of" if want_positive else "not one of"
    var text: String = "%s is %s %s." % [_characteristic_label(subject_id), word, group_phrase]
    # Both grid_updates entries below are TAUTOLOGICAL self-identity
    # markers (def_star's own group_cat slot; subject_star's own group_cat
    # slot) — always is_true:true regardless of want_positive, same
    # pattern as Cross-Domain Bridge's d1xd2 cell. The actual membership
    # claim (does subject_star's RAW group_cat value equal def_star's) is
    # NOT representable as a matrix cell at all: Colour/Pitch are
    # sub-ranked there, so a cell only ever means "same star," never "same
    # raw value, different star." That claim lives in value_facts instead,
    # same as Cross-Domain Bridge's own group membership.
    var solver_facts: Array = _seq_fact_for_label(subject_id)
    var value_facts: Array = _name_group_facts(subject_id, group_def_ch, want_positive)
    return {
        "chars": [subject_id, group_def_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(g["id_cat"]), "val_a": int(g["id_val"]), "cat_b": group_cat, "val_b": int(g["axis_val"]), "is_true": true},
            {"cat_a": subj_id_cat, "val_a": subj_id_val, "cat_b": group_cat, "val_b": subj_axis_val, "is_true": true},
        ],
        "solver_facts": solver_facts,
        "value_facts": value_facts,
    }


# ── Forms 21, 22: Pseudo-True Pair — read directly off two stars' actual
# ground-truth values, presented as a domain restriction. ────────────────

func _build_form_pseudo_true_pair_aligned(chain: Dictionary) -> Dictionary:
    # Two freely-chosen stars, same shape as Forms 5/6.
    var axis: int = Category.SEQUENCE if _rng.randf() < 0.6 else Category.PITCH
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var s1: int = int(a["star"])
    var b: Dictionary = _sample_identity_axis_cell(axis, {}, s1)   # only one node chains per Step 9
    if b.is_empty():
        return {}
    var s2: int = int(b["star"])
    # v1_ch/v2_ch below label s1/s2 via the AXIS category directly (not the
    # paired id_cat side _sample_identity_axis_cell already guards) — same
    # special case as Form 16/19/20's direct-axis labeling, needed here
    # because axis can be Pitch, where a shared-note group would otherwise
    # render an unverifiable "marked B" sub-rank letter.
    if not _category_uniquely_labels(axis, s1) or not _category_uniquely_labels(axis, s2):
        return {}
    var id1: Dictionary = {"cat": int(a["id_cat"]), "star": s1}
    var id2: Dictionary = {"cat": int(b["id_cat"]), "star": s2}
    var v1_ch: Dictionary = {"cat": axis, "star": s1}
    var v2_ch: Dictionary = {"cat": axis, "star": s2}
    var text: String = "%s and %s can only be %s or %s." % [_characteristic_label(id1), _characteristic_label(id2), _characteristic_label(v1_ch), _characteristic_label(v2_ch)]
    # v1_ch/v2_ch are each star's OWN true value (never a decoy, unlike Form
    # 22) — when axis is Sequence, a Sequence label is always unambiguous
    # (alldiff), so this "can only be X or Y" phrasing discloses both stars'
    # exact ranks directly via their labels, same as any other rendered
    # Sequence label; no separate relational fact is needed or would add
    # anything beyond what the four label-facts already capture.
    var solver_facts: Array = _seq_fact_for_label(id1) + _seq_fact_for_label(id2) + _seq_fact_for_label(v1_ch) + _seq_fact_for_label(v2_ch)
    return {
        "chars": [id1, id2, v1_ch, v2_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": int(a["id_cat"]), "val_a": int(a["id_val"]), "cat_b": axis, "val_b": int(a["axis_val"]), "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": int(b["axis_val"]), "is_true": true},
        ],
        "solver_facts": solver_facts,
    }


func _build_form_pseudo_true_pair_staggered(chain: Dictionary) -> Dictionary:
    # s_x/s_y: two freely-chosen stars (Forms 5/6/21's pattern). decoy: a
    # FALSE cell in s_x's own row (same axis, different column) — same
    # shape as Form 4's Disjunction decoy, just also excluded from
    # matching s_y's actual value so the two "either/or" pairs genuinely
    # stagger (share exactly one option) rather than coincidentally align.
    var axis: int = Category.SEQUENCE if _rng.randf() < 0.6 else Category.PITCH
    var a: Dictionary = _sample_identity_axis_cell(axis, chain, -1)
    if a.is_empty():
        return {}
    var s_x: int = int(a["star"])
    var b: Dictionary = _sample_identity_axis_cell(axis, {}, s_x)   # only one node chains per Step 9
    if b.is_empty():
        return {}
    var s_y: int = int(b["star"])
    # vx_ch/vy_ch/decoy_ch below all label their star via the AXIS category
    # directly — same special case as Form 21 above; s_x/s_y need checking
    # here, and the decoy candidate (a third, genuinely different star)
    # needs the same check in the loop below.
    if not _category_uniquely_labels(axis, s_x) or not _category_uniquely_labels(axis, s_y):
        return {}
    # This Form's tail clause is a strict comparison ("...and X is lower
    # than Y"), so it needs the same tie guard as Pairwise Order: s_y is
    # only sampled to differ from s_x, and two distinct stars can share a
    # Pitch rank. Checked here rather than at the _order_word call so the
    # decoy search below isn't done for a sample that cannot be used.
    if _order_value(axis, s_x) == _order_value(axis, s_y):
        return {}
    var id_cat_a: int = int(a["id_cat"])
    var id_val_a: int = int(a["id_val"])
    var true_axis_val: int = int(a["axis_val"])
    var y_axis_val: int = int(_cat_star_to_value[axis][s_y])
    var decoy_candidates: Array = []
    for v in star_count:
        if v == true_axis_val or v == y_axis_val:
            continue
        if not bool(_matrix_cell(id_cat_a, id_val_a, axis, v)["used"]) and _category_uniquely_labels(axis, int(_cat_value_to_star[axis][v])):
            decoy_candidates.append(v)
    if decoy_candidates.is_empty():
        return {}
    var decoy_val: int = int(decoy_candidates[_rng.randi_range(0, decoy_candidates.size() - 1)])
    var decoy_ch: Dictionary = {"cat": axis, "star": int(_cat_value_to_star[axis][decoy_val])}
    var id_x: Dictionary = {"cat": id_cat_a, "star": s_x}
    var id_y: Dictionary = {"cat": int(b["id_cat"]), "star": s_y}
    var vx_ch: Dictionary = {"cat": axis, "star": s_x}
    var vy_ch: Dictionary = {"cat": axis, "star": s_y}
    var order_word: String = _order_word(axis, _order_value(axis, s_x) > _order_value(axis, s_y))
    var verb: String = _order_verb(axis)
    var text: String = "%s can be %s or %s, %s can be %s or %s, and %s %s %s than %s." % [
        _characteristic_label(id_x), _characteristic_label(vx_ch), _characteristic_label(decoy_ch),
        _characteristic_label(id_y), _characteristic_label(decoy_ch), _characteristic_label(vy_ch),
        _characteristic_label(id_x), verb, order_word, _characteristic_label(id_y)]
    # vx_ch/vy_ch are s_x's/s_y's OWN true values; decoy_ch is a third,
    # genuinely different star's own true value — every one of these labels
    # discloses an exact rank on its own star when axis is Sequence (a
    # Sequence label is never ambiguous), regardless of the "can be X or Y"
    # framing built around them. The trailing comparison is a real,
    # independent fact too (redundant with the exact facts when axis is
    # Sequence, but sound to include either way).
    var solver_facts: Array = _seq_fact_for_label(id_x) + _seq_fact_for_label(id_y) \
        + _seq_fact_for_label(vx_ch) + _seq_fact_for_label(vy_ch) + _seq_fact_for_label(decoy_ch)
    if axis == Category.SEQUENCE:
        solver_facts.append({"kind": "ordinal_cmp", "a": s_x, "b": s_y, "a_gt_b": _order_value(axis, s_x) > _order_value(axis, s_y)})
    return {
        "chars": [id_x, id_y, vx_ch, vy_ch, decoy_ch],
        "text": text,
        "grid_updates": [
            {"cat_a": id_cat_a, "val_a": id_val_a, "cat_b": axis, "val_b": true_axis_val, "is_true": true},
            {"cat_a": int(b["id_cat"]), "val_a": int(b["id_val"]), "cat_b": axis, "val_b": y_axis_val, "is_true": true},
            {"cat_a": id_cat_a, "val_a": id_val_a, "cat_b": axis, "val_b": decoy_val, "is_true": false},
        ],
        "solver_facts": solver_facts,
    }


# ==================================================
# ZEBRATUTOR PASS — retired, 2026-07-22: this Sequence-only standalone
# tracker was mathematically redundant with the matrix's own Name x
# Sequence pair the moment every Form started producing grid_updates.
# Name's bijection is a trivial identity mapping (_cat_value_to_star
# [Category.NAME][i] == i), so the Name x Sequence matrix grid IS the same
# star x rank grid this used to maintain separately — same shape, same
# semantics, same algorithms (_apply_exact_clues-equivalent cascade +
# _naked_subset_pass), just duplicated across two data structures instead
# of one. Removed rather than "extended to more Forms," since extending it
# would have meant keeping two parallel trackers for the identical fact —
# the same class of redundancy already corrected twice this session (the
# ten possibility grids, then the separate cell-used dict).
#
# UPDATED 2026-08-18: this used to say Sequence derivability "now flows
# through _grid_zebratutor_pass". That pass has been REMOVED (see the note
# where it lived) — it inferred derivability from a `used` bit that cannot
# distinguish disclosed-True from disclosed-False from merely-touched, and
# patched the gap by reading ground truth. Nothing replaces it: the
# generator no longer tries to avoid stating derivable facts at all, and
# measured strictly better for it. The real uniqueness proofs are _solve()
# for Sequence and _solve_name_closure() for Name, both of which reason
# from DISCLOSED facts rather than from matrix Used-state.


# ==================================================
# FORM TIERS — Perception axis (target clueset composition) vs. Engine
# Execution axis (proportional-fair scheduling with opportunistic fallback)
# ==================================================
# Tier 1 (Entry Anchors), Tier 2 (Relational Workhorses), Tier 3 (Systemic
# Constraints) are a PERCEPTION classification — how a clue reads/scans to
# a player during simultaneous-reveal, co-solving play — not a mechanical
# hit-rate ranking. Several Tier 1/2/3 forms actually have very different
# real construction success rates (e.g. Betweenness needs 3 True cells,
# Distance Existential needs 1), which is exactly why a separate execution
# strategy (below) exists rather than folding hit-rate into the tiers
# themselves. Six forms (4, 5, 8, 12, 16, 19) weren't in the user's
# original breakdown — placed by matching the experiential character of
# forms already assigned to each tier; flagged for adjustment, especially
# Non-Adjacency (19), the least confident placement.
const FORM_TIER := {
    1: 1, 2: 1, 4: 1, 6: 1, 8: 1, 10: 1, 11: 1,             # Entry Anchors
    5: 2, 7: 2, 12: 2, 15: 2, 16: 2, 17: 2, 19: 2, 21: 2, 22: 2, 23: 2,  # Relational Workhorses
    3: 3, 9: 3, 13: 3, 14: 3, 20: 3,                        # Systemic Constraints
}
# Single target composition for the finished clueset (collapsed from the
# three phase-based ratios via simple averaging — a starting point, not a
# measured result; easy to retune once real generation output is visible).
const TIER_TARGET_RATIO := {1: 0.25, 2: 0.45, 3: 0.30}
const TIER_OPPORTUNISTIC_ATTEMPTS := 4


# ==================================================
# DIFFICULTY PROFILES
# ==================================================
# MEASURED BASELINE (2026-08-12, 6 seeds, constellation 0) — what today's
# settings actually produce, which is NOT what the constants suggest:
#   ~44.5 clues/puzzle
#   tier mix 17% / 68% / 15%  (against a 25/45/30 target it never reaches)
#   two Forms are 55% of every puzzle: Equality Pair (12.7/puzzle) and
#     Distance Existential (11.7/puzzle)
#   92% of asserted cells are TRUE — the grid is not negation-heavy
#   Exact Identity, the most direct clue in the game, appears 0.2/puzzle
#
# So the current difficulty does NOT come from clue scarcity (there is no
# trim pass; generation runs until the matrix pool is exhausted) nor from
# negation. It comes from having almost no direct footholds, buried in a
# 44-clue wall dominated by two repetitive relational Forms.
#
# That diagnosis sets the Easy levers. In rough order of expected impact:
#   opening_anchors — build the most direct Forms FIRST, before the cascade
#     consumes the True cells they need. This is why Exact Identity is
#     currently near-absent: it needs an unused True cell, and True cells
#     are scarce (one per row/column) and get marked used early by every
#     other Form's own cascade. Nothing else on this list matters as much.
#   form_caps — break the Equality Pair / Distance Existential duopoly so
#     the clueset reads as varied rather than as two sentences repeated.
#   excluded_forms — drop the Forms that need the most cross-referencing
#     to act on at all.
#   tier_ratio — steer the scheduler's preference. Listed last on purpose:
#     the scheduler already misses its target by a wide margin, so this is
#     the weakest of the four until that is understood.
#
# "hard" is EXACTLY today's behaviour — empty overrides, same constants —
# so this mechanism is inert until a profile is selected. Difficulty is
# not yet wired to anything player-facing; `difficulty` is set directly by
# tests for now, and where it should ultimately come from (per
# constellation? per Age? a player setting?) is an open design question.
const DIFFICULTY_PROFILES := {
    "hard": {
        "tier_ratio": TIER_TARGET_RATIO,
        "excluded_forms": [],
        "form_caps": {},
        "opening_anchors": [],
    },
    "easy": {
        # Heavily weighted to Entry Anchors. Tier 3 is not banned outright
        # (a Systemic clue is a nice occasional payoff) but is rare.
        "tier_ratio": {1: 0.55, 2: 0.38, 3: 0.07},
        # Dual Negation (3): two exclusions at once, nothing positive.
        # Group Order (9) / Group Comparison (14): require holding a whole
        #   group's membership in mind before the clue says anything.
        # Cross-Domain Bridge (20): two categories away from any anchor.
        # Pseudo-True Pairs (21/22): deliberately near-miss phrasing whose
        #   whole point is to be misread — actively hostile at Easy.
        "excluded_forms": [3, 9, 14, 20, 21, 22],
        # Measured at 12.7 and 11.7 per puzzle respectively; capped to a
        # presence rather than a dominance.
        "form_caps": {12: 4, 15: 4},
        # Built before the main loop, in this order, while True cells are
        # still unconsumed. Exact Identity ("X is Y") is the strongest
        # foothold in the game; Extreme and Range are the next most direct.
        "opening_anchors": [1, 1, 1, 11, 8, 1],
    },
}

## Which profile generation uses. Defaults to today's exact behaviour.
var difficulty: String = "hard"

## Restricts cell sampling to TRUE cells. Set ONLY for the duration of the
## opening-anchor pass, and false everywhere else — the main loop's
## unbiased landing is deliberate (grammar says "is"/"is not" as a
## CONSEQUENCE of where it landed, never as an input the sampler aimed
## for), and biasing it globally would distort every Form.
##
## Needed because ordering alone could not fix Exact Identity. Measured
## 2026-08-12: running it first barely moved it (0.2 -> 0.3 per puzzle),
## because it samples a random cell and bails unless that cell is True —
## and only star_count of star_count^2 cells are True, so it is ~7% per
## attempt no matter WHEN it runs. Range and Extreme jumped (0.2 -> 2.8,
## 0.7 -> 2.3) on ordering alone precisely because they don't need a True
## cell. The fix is to read the True cells off the matrix directly rather
## than hope to land on one — the same matrix-native-over-guess-and-reject
## correction applied to Form 13 earlier.
var _prefer_true_cells: bool = false


func _profile() -> Dictionary:
    return DIFFICULTY_PROFILES.get(difficulty, DIFFICULTY_PROFILES["hard"])
# Per-tier attempts before falling through to the next-most-underrepresented
# tier, rather than exhausting the whole stall budget hammering one tier
# that's currently out of constructible cells.


func _tiers_by_underrepresentation(tier_counts: Dictionary) -> Array:
    var total: int = 0
    for t in tier_counts.values():
        total += int(t)
    var ratio: Dictionary = _profile()["tier_ratio"]
    var tiers: Array = [1, 2, 3]
    tiers.sort_custom(func(a, b):
        var actual_a: float = (float(tier_counts[a]) / float(total)) if total > 0 else 0.0
        var actual_b: float = (float(tier_counts[b]) / float(total)) if total > 0 else 0.0
        var gap_a: float = float(ratio[a]) - actual_a
        var gap_b: float = float(ratio[b]) - actual_b
        return gap_a > gap_b)
    return tiers


## Forms in `tier` that this difficulty permits AND that have not already
## hit their per-Form cap this attempt. Caps exist because two Forms
## (Equality Pair, Distance Existential) otherwise supply 55% of every
## clueset — see DIFFICULTY_PROFILES.
func _forms_in_tier(tier: int, form_counts: Dictionary = {}) -> Array:
    var profile: Dictionary = _profile()
    var excluded: Array = profile["excluded_forms"]
    var caps: Dictionary = profile["form_caps"]
    var out: Array = []
    for form_id in AUTOMATED_FORM_IDS:
        if int(FORM_TIER.get(int(form_id), 2)) != tier:
            continue
        if excluded.has(int(form_id)):
            continue
        if caps.has(int(form_id)) and int(form_counts.get(int(form_id), 0)) >= int(caps[int(form_id)]):
            continue
        out.append(form_id)
    return out


# ==================================================
# GENERATION PIPELINE
# ==================================================

var chosen_form_clues: Array[Dictionary] = []

const MAX_GENERATION_ATTEMPTS := 5
# A failed uniqueness gate (see _generate_clues_forms_attempt's return)
# means this specific random draw's clue set didn't happen to pin down
# Sequence and Name — not that the constellation itself is unsolvable.
# Retrying with a fresh draw (the _rng stream has already advanced, so a
# retry is a genuinely different attempt, not a repeat) resolves it in
# all but the most structurally constrained cases; 5 attempts matches the
# same bounded-retry pattern already used elsewhere (TIER_OPPORTUNISTIC_
# ATTEMPTS, MAX_BACKTRACK_NODES) rather than looping indefinitely.
func generate_clues_forms() -> void:
    var result: Dictionary = {}
    var attempt: int = 0
    while attempt < MAX_GENERATION_ATTEMPTS:
        attempt += 1
        result = await _generate_clues_forms_attempt()
        if bool(result["seq_unique"]) and bool(result["name_unique"]):
            break
        # Yield a frame before the next attempt instead of blocking straight
        # through up to MAX_GENERATION_ATTEMPTS in one go — see the header
        # comment above generation_complete for why. No-op (old synchronous
        # behavior) if no host was set at setup() time.
        if _host:
            await _host.get_tree().process_frame
    if not (bool(result["seq_unique"]) and bool(result["name_unique"])):
        push_error("ConstellationLogicPuzzle [%d]: STILL NOT UNIQUE after %d generation attempts (sequence_solutions=%d, all_names_revealed=%s) — puzzle unsolvable as configured." % [
            constellation_id, MAX_GENERATION_ATTEMPTS, int(result["seq_solutions_count"]), str(result["name_unique"])])
    _generation_complete = true


## Builds `form_id` once and, if it produced a non-duplicate clue, commits
## it — matrix cells, characteristics, solver facts, name-reveal tracking,
## tier/form tallies, chain node. Returns whether it committed.
##
## Extracted from the main generation loop 2026-08-12 so the difficulty
## system's opening-anchor pass can commit clues through the SAME path
## rather than carrying a second copy of ~55 lines of commit bookkeeping —
## the duplication shape that has repeatedly cost this project bugs when
## one copy got a fix the other didn't. The accumulator arguments are
## Arrays/Dictionaries, which GDScript passes by reference, so they mutate
## in the caller exactly as the inline version did.
func _try_build_and_commit(form_id: int, sequence_solver_facts: Array,
        name_revealed: Array, tier_counts: Dictionary, form_counts: Dictionary) -> bool:
    var chain: Dictionary = _pick_chain_characteristic()
    # Cleared per ATTEMPT, not per committed clue: a Form that renders
    # labels and then bails still dirtied the accumulator, and those terms
    # belong to no clue.
    _rendered_terms = {}
    var result: Dictionary = _build_form(form_id, chain)
    if result.is_empty():
        return false
    # Most Forms' templates start with a rendered star label ("the white
    # star...", "a star that plays..."), which is correct mid-sentence but
    # needs sentence-initial capitalization here — a handful of Forms
    # (3, 10, 20) already start with a literal capitalized word
    # ("Neither", "Exactly", "Among"), for which this is a harmless no-op.
    var text: String = _capitalize_first(str(result.get("text", "")))
    for c in chosen_form_clues:
        if str(c.get("text", "")) == text:
            return false
    var chars: Array = result["chars"]
    _commit_characteristics(chars)
    chosen_form_clues.append({
        "form_id": form_id,
        "form_name": str(FORM_NAMES.get(form_id, "")),
        "text": text,
        "characteristics": _clue_characteristics(chars),
        # Raw node list (see CACHE_VERSION 3's comment) — each entry
        # {cat:int, star:int[, ref:int]}, already plain/JSON-safe, no
        # transformation needed before caching. Duplicated defensively
        # since `chars` is a shared local several Forms mutate further up.
        "chars": chars.duplicate(true),
        # What the clue actually ASSERTS, not merely mentions — see
        # CACHE_VERSION 4's comment and _cells_for_cache().
        "cells": _cells_for_cache(_coerce_array(result.get("grid_updates"), [])),
        # What the clue's text VISIBLY states — see CACHE_VERSION 5 and
        # _characteristic_label().
        "search_terms": _rendered_terms.keys(),
        # What the clue DISCLOSES, as evaluable constraints — see
        # CACHE_VERSION 6. solver_facts is the CSP's own input, so the
        # Sequence half can never drift from what the puzzle was proven
        # unique against; value_facts carries the Colour/Pitch content the
        # CSP has no use for.
        "disclosures": (_coerce_array(result.get("solver_facts"), []) + _coerce_array(result.get("value_facts"), [])).duplicate(true),
    })
    if result.has("solver_facts"):
        for f in result["solver_facts"]:
            sequence_solver_facts.append(f)
    # A Name node only reveals its star if THIS SAME clue also has a
    # different-category node describing the SAME star — not merely "some
    # other node exists somewhere in chars" (the old check), which wrongly
    # credited a reveal even when the other node described a DIFFERENT
    # star entirely (e.g. Dual Negation with id_cat1==id_cat2==Name: id1
    # names s1, id2 names s2, and neither co-occurs with any other
    # characteristic of ITS OWN star in that clue).
    var stars_with_name: Dictionary = {}
    var stars_with_other: Dictionary = {}
    for ch2 in chars:
        var ch2_star: int = int(ch2["star"])
        if int(ch2["cat"]) == Category.NAME:
            stars_with_name[ch2_star] = true
        else:
            stars_with_other[ch2_star] = true
    for named_star in stars_with_name.keys():
        if stars_with_other.has(named_star):
            name_revealed[int(named_star)] = true
    if result.has("grid_updates"):
        for gu in result["grid_updates"]:
            var g: Dictionary = gu
            _apply_grid_cell_result(int(g["cat_a"]), int(g["val_a"]), int(g["cat_b"]), int(g["val_b"]), bool(g["is_true"]))
    _last_clue_nodes = chars
    var tier: int = int(FORM_TIER.get(form_id, 2))
    tier_counts[tier] = int(tier_counts.get(tier, 0)) + 1
    form_counts[form_id] = int(form_counts.get(form_id, 0)) + 1
    return true


## Difficulty's opening-anchor pass: build the most DIRECT Forms first,
## before the main loop's cascade consumes the True cells they depend on.
##
## This is the single highest-impact Easy lever, and the reason is
## measured, not assumed: Exact Identity ("X is Y") appears only ~0.2
## times per puzzle today, because it needs an UNUSED True cell, True
## cells are scarce (exactly one per row and per column of each grid), and
## every committed clue's cascade marks a whole row and column used. Run
## first, the same Form succeeds readily. Each entry is attempted a few
## times and simply skipped if the matrix cannot supply it — no retry
## storm, and an Easy puzzle on an awkward constellation degrades to the
## normal loop rather than failing.
func _build_opening_anchors(sequence_solver_facts: Array, name_revealed: Array,
        tier_counts: Dictionary, form_counts: Dictionary) -> void:
    var anchors: Array = _profile()["opening_anchors"]
    if anchors.is_empty():
        return
    # Anchors are direct, positive footholds by definition, so the sampler
    # is pointed at True cells for this pass only. A negation Form listed
    # here would be self-defeating — it needs a False cell and would find
    # none. Always restored, including on the empty-list early return above.
    _prefer_true_cells = true
    for form_id in anchors:
        var tries: int = 0
        while tries < 3:
            tries += 1
            if _try_build_and_commit(int(form_id), sequence_solver_facts,
                    name_revealed, tier_counts, form_counts):
                break
    _prefer_true_cells = false


func _generate_clues_forms_attempt() -> Dictionary:
    _build_record_array()
    _build_matrix()
    _used_characteristics = {}
    _last_clue_nodes = []
    chosen_form_clues = []
    # Phase C — uniqueness verification inputs, accumulated alongside the
    # clue set itself (not persisted to cache; only needed transiently
    # here). sequence_solver_facts feeds the already-correct, already-
    # ported _solve() (shown-clues-only CSP, never ground truth) to prove
    # Sequence has exactly one consistent solution. name_revealed tracks,
    # per star, whether any committed clue's Name node co-occurred with a
    # DIFFERENT-category node describing that SAME star — sufficient once
    # Sequence-uniqueness holds, since every other category is then either
    # directly observable (Color/Pitch/Distance) or itself derivable
    # (Sequence, by the very uniqueness just proven) — see the header note
    # above _seq_fact_for_label for why this can't be approximated from
    # matrix Used-state directly.
    var sequence_solver_facts: Array[Dictionary] = []
    var name_revealed: Array[bool] = []
    for _s in star_count:
        name_revealed.append(false)
    var tier_counts: Dictionary = {1: 0, 2: 0, 3: 0}
    # Per-Form tally, for DIFFICULTY_PROFILES' form_caps. Counted here
    # rather than derived from chosen_form_clues on each lookup — this is
    # read once per tier per outer-loop pass.
    var form_counts: Dictionary = {}
    var stall_count: int = 0
    # Step 13's termination target grew a lot (every real matrix cell, not
    # the old coarse per-Characteristic count) — the old flat stall budget
    # was sized against the smaller number and would almost certainly cut
    # generation short well before the pool was actually exhausted.
    var max_stall: int = maxi(400, _unused_pool_size() * 2)
    # Yields a frame every YIELD_INTERVAL passes through this outer loop —
    # see the FIXED 2026-07-27 note above generation_complete. This is the
    # loop that can run into the hundreds of iterations building up a
    # single attempt; without this, a single attempt could still block one
    # frame for its entire duration even with the between-attempts yield in
    # generate_clues_forms(). Local state (tier_counts, chosen_form_clues,
    # stall_count, etc.) survives the pause untouched — awaiting mid-loop
    # suspends this exact call, it doesn't restart it — so this naturally
    # spreads one attempt's work across as many frames as it needs.
    #
    # TUNED 2026-07-27 — 20 still let each yielded chunk do up to
    # 20 * TIER_OPPORTUNISTIC_ATTEMPTS(4) * 4-tiers = ~320 _build_form-class
    # calls before yielding, enough to cause visible input/animation lag
    # (e.g. Archon face-tracking stutter) even after the earlier full-stop
    # freeze was fixed. Dropped to 3 (~48 calls/chunk) — there's a whole
    # prestige cycle's worth of real time to finish in, so trading more
    # total frames for a smaller per-frame chunk costs nothing.
    const YIELD_INTERVAL: int = 3
    var _since_yield: int = 0

    # BEFORE the main loop — see _build_opening_anchors for why ordering is
    # the whole point. No-op on "hard" (empty anchor list).
    _build_opening_anchors(sequence_solver_facts, name_revealed, tier_counts, form_counts)

    while _unused_pool_size() > 0 and stall_count < max_stall:
        var tier_order: Array = _tiers_by_underrepresentation(tier_counts)
        var committed: bool = false
        for tier in tier_order:
            var tier_forms: Array = _forms_in_tier(int(tier), form_counts)
            if tier_forms.is_empty():
                continue
            _shuffle_array(tier_forms)
            var tier_attempts: int = 0
            var succeeded: bool = false
            while tier_attempts < TIER_OPPORTUNISTIC_ATTEMPTS and not succeeded:
                tier_attempts += 1
                var form_id: int = int(tier_forms[tier_attempts % tier_forms.size()])
                succeeded = _try_build_and_commit(form_id, sequence_solver_facts,
                    name_revealed, tier_counts, form_counts)
            if succeeded:
                committed = true
                break
        if committed:
            stall_count = 0
        else:
            stall_count += 1
        _since_yield += 1
        if _host and _since_yield >= YIELD_INTERVAL:
            _since_yield = 0
            await _host.get_tree().process_frame

    # Phase C — uniqueness gate for THIS attempt. Whether a failure here
    # gets retried with a fresh draw (rather than shipped as-is) is decided
    # by the caller, generate_clues_forms().
    for f in sequence_solver_facts:
        var violation: String = _validate_sequence_fact(f)
        if violation != "":
            push_error("ConstellationLogicPuzzle [%d]: INCONSISTENT SEQUENCE FACT — %s" % [constellation_id, violation])
    var seq_solutions: Array = _solve(sequence_solver_facts, 2)
    var seq_unique: bool = seq_solutions.size() == 1
    var name_unique: bool = true
    for revealed in name_revealed:
        if not revealed:
            name_unique = false
            break
    # NAME CLOSURE (Phase 2 of the position-axis migration, first slice,
    # 2026-08-16) — a genuine uniqueness PROOF over POSITION x NAME,
    # replacing the mention-coverage flag above wherever it eventually
    # takes over. NOT the live gate yet: only Exact Identity and Single
    # Negation are wired to emit name_group facts so far, and BOTH are
    # structurally unable to carry Colour — the shared cell sampler
    # requires _category_uniquely_labels on both sides, and Colour's group
    # size is never 1 (measured). So this is a KNOWN undercount, reported
    # for measurement (see probe_scratch.gd), not enforced. Swapping it in
    # as the real gate before more Forms are wired would starve
    # generation, since almost no puzzle would close on Sequence+Pitch
    # facts alone.
    var name_unique_closure: bool = false
    var name_solutions_count: int = -1   # -1 = not attempted (seq not unique yet)
    if seq_unique:
        var name_solutions: Array = _solve_name_closure(seq_solutions)
        name_unique_closure = name_solutions.size() == 1
        name_solutions_count = name_solutions.size()
    return {
        "seq_unique": seq_unique,
        "name_unique": name_unique,
        "name_unique_closure": name_unique_closure,
        "name_solutions_count": name_solutions_count,
        "seq_solutions_count": seq_solutions.size(),
        # The solutions themselves, not just the count — already computed
        # above, so carrying the reference costs nothing. Lets a probe
        # re-run _solve_name_closure() at a higher cap to learn the TRUE
        # surviving-solution count, which name_solutions_count cannot
        # report (it is capped at 2; see _solve_name_closure's header).
        "seq_solutions": seq_solutions,
        "tier_counts": tier_counts,
    }


## `cap` is _solve()'s solution-count ceiling, NOT a count — the solver
## stops as soon as it has that many, so the default 2 answers "unique or
## not" as cheaply as possible and can never report a number above 2. That
## is correct for the gate and misleading for diagnosis: a probe reading
## name_solutions_count off the default will see every non-closing puzzle
## report exactly 2 and can mistake a capped read for a real 2-fold
## symmetry (nearly reported as a finding 2026-08-18). Raise it only for
## measurement; every production caller wants the default.
func _solve_name_closure(seq_solutions: Array, cap: int = 2) -> Array:
    # possible[name_star][candidate_position] — same shape _solve() already
    # uses for possible[star][candidate_rank]. Meaningless before Sequence
    # is unique: a Sequence-anchored name_group fact only resolves to a
    # single position via the one true Sequence solution, so the caller
    # gates this on seq_unique first.
    if seq_solutions.size() != 1:
        return []
    var rank_to_star: Array = []
    rank_to_star.resize(star_count)
    var seq_sol: Array = seq_solutions[0]
    for st in star_count:
        rank_to_star[int(seq_sol[st])] = st
    var name_clues: Array[Dictionary] = []
    var same_group_pairs: Array = []
    for clue in chosen_form_clues:
        for f in (clue.get("disclosures", []) as Array):
            if not (f is Dictionary):
                continue
            var fd: Dictionary = f
            var kind: String = str(fd.get("kind", ""))
            if kind == "name_group" or kind == "name_group_neg":
                var violation: String = _validate_name_group_fact(fd)
                if violation != "":
                    push_error("ConstellationLogicPuzzle [%d]: INCONSISTENT NAME FACT — %s" % [constellation_id, violation])
                var name_star: int = int(fd["name_star"])
                var obs_cat: int = int(fd["cat"])
                var group_key: int = int(fd["group_key"])
                var members: Array = []
                if obs_cat == Category.SEQUENCE:
                    members = [int(rank_to_star[group_key])]
                else:
                    for s2 in star_count:
                        if _name_group_key(obs_cat, s2) == group_key:
                            members.append(s2)
                if kind == "name_group":
                    name_clues.append({"kind": "value_in_set", "s": name_star, "allowed": members})
                else:
                    name_clues.append({"kind": "value_out_set", "s": name_star, "excluded": members})
            elif kind == "name_precedes_group" or kind == "name_follows_group":
                var violation2: String = _validate_name_order_vs_group_fact(fd)
                if violation2 != "":
                    push_error("ConstellationLogicPuzzle [%d]: INCONSISTENT NAME-ORDER FACT — %s" % [constellation_id, violation2])
                var name_star2: int = int(fd["name_star"])
                var obs_cat2: int = int(fd["cat"])
                var group_key2: int = int(fd["group_key"])
                # Rank range comes from seq_sol (the closure's OWN resolved
                # solution), not pitch_rank_solution directly — equal
                # whenever seq_unique holds (required to reach this point
                # at all), but reading through seq_sol keeps this
                # consistent with how the SEQUENCE-anchored branch above
                # already resolves positions, rather than reaching past it
                # to ground truth for no reason.
                var min_rank: int = -1
                var max_rank: int = -1
                for m in star_count:
                    if _name_group_key(obs_cat2, m) != group_key2:
                        continue
                    var r: int = int(seq_sol[m])
                    if min_rank == -1 or r < min_rank:
                        min_rank = r
                    if max_rank == -1 or r > max_rank:
                        max_rank = r
                var allowed2: Array = []
                for p in star_count:
                    var pr: int = int(seq_sol[p])
                    if kind == "name_precedes_group" and pr < min_rank:
                        allowed2.append(p)
                    elif kind == "name_follows_group" and pr > max_rank:
                        allowed2.append(p)
                name_clues.append({"kind": "value_in_set", "s": name_star2, "allowed": allowed2})
            elif kind == "name_extreme_in_group":
                var violation4: String = _validate_name_extreme_in_group_fact(fd)
                if violation4 != "":
                    push_error("ConstellationLogicPuzzle [%d]: INCONSISTENT NAME-EXTREME FACT — %s" % [constellation_id, violation4])
                var name_star3: int = int(fd["name_star"])
                var obs_cat3: int = int(fd["cat"])
                var group_key3: int = int(fd["group_key"])
                var want_lowest3: bool = bool(fd["want_lowest"])
                # A group's Sequence-extreme member is exactly ONE position
                # once Sequence is resolved, so this collapses to a
                # single-element value_in_set — a PIN, not a narrowing.
                # Ranks read through seq_sol (the closure's own resolved
                # solution) rather than pitch_rank_solution directly, same
                # reasoning as the order branch above.
                var extreme_pos: int = -1
                for p2 in star_count:
                    if _name_group_key(obs_cat3, p2) != group_key3:
                        continue
                    if extreme_pos == -1:
                        extreme_pos = p2
                        continue
                    var pr2: int = int(seq_sol[p2])
                    var cur2: int = int(seq_sol[extreme_pos])
                    if (want_lowest3 and pr2 < cur2) or (not want_lowest3 and pr2 > cur2):
                        extreme_pos = p2
                if extreme_pos != -1:
                    name_clues.append({"kind": "value_in_set", "s": name_star3, "allowed": [extreme_pos]})
            elif kind == "distance_hop":
                # Only a NAME-anchored hop says anything about which
                # position a name occupies; a Sequence/Pitch-anchored one
                # constrains a descriptor the closure is not solving for.
                if int(fd.get("ref_cat", -1)) != Category.NAME:
                    continue
                var dh_target_cat: int = int(fd["target_cat"])
                var dh_key: int = _name_group_key(dh_target_cat, int(fd["target"]))
                if dh_key == -1:
                    continue   # Name/Distance target — no reconstructable group
                var violation5: String = _validate_distance_hop_name_fact(fd)
                if violation5 != "":
                    push_error("ConstellationLogicPuzzle [%d]: INCONSISTENT DISTANCE FACT — %s" % [constellation_id, violation5])
                var dh_negated: bool = bool(fd.get("negated", false))
                var dh_group: Array = []
                for q3 in star_count:
                    if _name_group_key(dh_target_cat, q3) == dh_key:
                        dh_group.append(q3)
                # See _validate_distance_hop_name_fact: the negated reading
                # is only unambiguous for a singleton group. Skipping is
                # safe — it under-constrains, and this gate only ever errs
                # toward claiming LESS uniqueness.
                if dh_negated and dh_group.size() != 1:
                    continue
                var dh_hops: int = int(fd["hops"])
                var dh_allowed: Array = []
                for p3 in star_count:
                    var reach: bool = false
                    for q4 in dh_group:
                        if int(_distances[p3][int(q4)]) == dh_hops:
                            reach = true
                            break
                    if reach != dh_negated:
                        dh_allowed.append(p3)
                name_clues.append({"kind": "value_in_set", "s": int(fd["ref"]), "allowed": dh_allowed})
            elif kind == "name_same_group":
                var violation3: String = _validate_name_same_group_fact(fd)
                if violation3 != "":
                    push_error("ConstellationLogicPuzzle [%d]: INCONSISTENT NAME-SAME-GROUP FACT — %s" % [constellation_id, violation3])
                same_group_pairs.append({
                    "a": int(fd["name_star_a"]), "b": int(fd["name_star_b"]), "cat": int(fd["cat"]),
                })

    # Same-group pairs (Equality Pair's both-sides-NAME case) can't be
    # expressed as a per-row value_in_set/value_out_set restriction — see
    # _propagate_same_group's header. Pre-narrow a grid with the ordinary
    # per-row facts applied first (so same-group pruning benefits from
    # whatever they already established), THEN run same-group to a
    # fixpoint, and hand the result to _solve() as rank_restriction — its
    # OWN clue application/propagation/backtracking then runs as normal on
    # top, name_clues passed again is a harmless no-op re-narrowing.
    if same_group_pairs.is_empty():
        return _solve(name_clues, cap)
    var pre: Array = _init_possibility_grid()
    if not _apply_range_clues(pre, name_clues):
        return []
    if not _apply_negative_clues(pre, name_clues):
        return []
    if not _propagate_same_group(pre, same_group_pairs):
        return []
    return _solve(name_clues, cap, pre)


func get_form_clue_texts() -> Array[String]:
    var texts: Array[String] = []
    for c in chosen_form_clues:
        texts.append(str(c.get("text", "")))
    return texts
